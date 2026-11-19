package com.example.captura_mobile.video

import kotlin.math.abs
import kotlin.math.hypot

/** Preview-only evidence, never a pose, distance, wall detector or metric reference. */
enum class VisualState { PENDING, NEEDS_IMPROVEMENT, STABLE, NOT_VERIFIABLE }
enum class VisualIssue { NONE, WARMUP, STALE, LOW_LIGHT, LOW_TEXTURE, BLUR, FAST_MOTION, LOW_MATCHES }

data class VisualFeedback(
    val state: VisualState,
    val message: String,
    val features: Int = 0,
    val matches: Int = 0,
    val changedComparisons: Int = 0,
    val samples: Int = 0,
    val imageStable: Boolean? = null,
    val localMatching: Boolean = false,
    val imageChanged: Boolean = false,
    val issue: VisualIssue = VisualIssue.WARMUP,
    val requiredMatches: Int = 0,
    val gapMs: Long = 0,
    val luma: Double = 0.0,
    val sharpness: Double = 0.0,
    val motionFraction: Double? = null,
)

/** Bounded patch tracking on <=192x192 grayscale previews, independent of a gyroscope.
 * Thresholds are conservative operational heuristics, not calibrated physical accuracy.
 * Ambiguous/repeated patterns never count as overlap. No image is persisted here.
 */
class VisualCaptureGuidance {
    companion object {
        const val MIN_FEATURES = 12
        const val MIN_MATCHES = 8
        const val MIN_MATCH_FRACTION = 0.35
        const val MIN_LUMA = 45.0
        const val MIN_SHARPNESS = 30.0
        const val MAX_MOTION = 0.10
        // Larger than the 2-pixel tracker grid/jitter. This is an image change, NOT parallax.
        const val MIN_IMAGE_CHANGE = 0.02
    }
    private data class Feature(val x: Int, val y: Int)
    private var previous: IntArray? = null
    private var previousWidth = 0
    private var previousHeight = 0
    private var previousAtMs = 0L
    private var features = emptyList<Feature>()
    private var changedComparisons = 0
    private var samples = 0
    private val issues = IntArray(VisualIssue.entries.size)
    private val seen = IntArray(6)

    fun reset() {
        resetComparison(); changedComparisons = 0; samples = 0
        seen.fill(0)
        issues.fill(0)
    }

    fun resetComparison() { previous = null; features = emptyList() }

    fun summary(): String {
        val selected = seen.indices.filter { seen[it] > 0 }.joinToString { (it + 1).toString() }.ifEmpty { "ninguna" }
        return "$samples muestras analizadas; $changedComparisons comparaciones con cambio 2D y coincidencias locales. " +
            "Instrucciones mostradas (no detecciones): $selected. " +
            "Paredes, esquinas, nuevas perspectivas y cobertura 3D no verificables en el teléfono. " +
            "Diagnóstico: " + VisualIssue.entries.filter { issues[it.ordinal] > 0 }
                .joinToString { "${it.name}=${issues[it.ordinal]}" }
    }

    fun analyze(pixels: IntArray, width: Int, height: Int, nowMs: Long, step: Int,
                cadenceMs: Long = GuidanceSamplingPolicy.NORMAL_MS): VisualFeedback {
        require(width in 16..192 && height in 16..192 && pixels.size == width * height)
        val maximumGap = GuidanceSamplingPolicy.maximumGapMs(cadenceMs)
        // A delayed/out-of-order sample must not replace a newer comparison baseline.
        if (previous != null && nowMs <= previousAtMs) return VisualFeedback(
            VisualState.PENDING, "Muestra antigua; esperando una imagen actual.",
            changedComparisons = changedComparisons, samples = samples,
            issue = VisualIssue.STALE,
        )
        val luma = IntArray(pixels.size) { i ->
            val p = pixels[i]
            (77 * ((p shr 16) and 255) + 150 * ((p shr 8) and 255) + 29 * (p and 255)) shr 8
        }
        samples++; seen[step.coerceIn(0, 5)]++
        val mean = luma.average()
        var lap2 = 0.0
        var lapSum = 0.0
        for (y in 1 until height - 1) for (x in 1 until width - 1) {
            val i = y * width + x
            val lap = 4 * luma[i] - luma[i - 1] - luma[i + 1] - luma[i - width] - luma[i + width]
            lap2 += lap.toDouble() * lap; lapSum += lap
        }
        val count = (width - 2) * (height - 2)
        val sharpness = lap2 / count - (lapSum / count) * (lapSum / count)
        val currentFeatures = findFeatures(luma, width, height)
        val old = previous
        val previousAtMsForComparison = previousAtMs
        val comparable = old != null && previousWidth == width && previousHeight == height &&
            nowMs - previousAtMs in 300..maximumGap
        val shifts = if (comparable) track(old!!, luma, width, height, features) else emptyList()
        val requiredMatches = maxOf(MIN_MATCHES, kotlin.math.ceil(features.size * MIN_MATCH_FRACTION).toInt())
        val motion = if (shifts.isEmpty()) null else shifts.sorted()[shifts.size / 2] / hypot(width.toDouble(), height.toDouble())
        previous = luma; previousWidth = width; previousHeight = height; previousAtMs = nowMs
        features = currentFeatures
        val issue = when {
            mean < MIN_LUMA || luma.count { it <= 20 } > luma.size * 0.6 -> VisualIssue.LOW_LIGHT
            currentFeatures.size < MIN_FEATURES -> VisualIssue.LOW_TEXTURE
            sharpness < MIN_SHARPNESS -> VisualIssue.BLUR
            motion != null && motion >= MAX_MOTION -> VisualIssue.FAST_MOTION
            !comparable -> if (old == null) VisualIssue.WARMUP else VisualIssue.STALE
            shifts.size < requiredMatches -> VisualIssue.LOW_MATCHES
            else -> VisualIssue.NONE
        }
        issues[issue.ordinal]++
        val problem = when (issue) {
            VisualIssue.NONE -> null
            VisualIssue.WARMUP -> "Detectando continuidad visual… Mantené la cámara estable."
            VisualIssue.STALE -> "Muestreo interrumpido; retomando continuidad visual."
            VisualIssue.LOW_LIGHT -> "Falta luz: iluminá la habitación."
            VisualIssue.LOW_TEXTURE -> "Falta textura: incluí marcos, zócalos y objetos con detalles."
            VisualIssue.BLUR -> "Mantené la cámara estable; falta nitidez."
            VisualIssue.FAST_MOTION -> "Mové el teléfono más despacio."
            VisualIssue.LOW_MATCHES -> "Falta continuidad: volvé un poco y conservá parte de la vista anterior."
        }
        // Report matching independently of image quality/motion warnings. A matched patch
        // can also belong to a fast pan or rotation; it is not a usable 3D observation.
        val matched = comparable && shifts.size >= requiredMatches
        val changed = matched && motion != null && motion >= MIN_IMAGE_CHANGE
        val stable = if (matched && motion != null) motion < MIN_IMAGE_CHANGE else null
        // Only an observable change in the image is counted. Pure rotation, object motion and
        // camera translation cannot be distinguished here; none verifies a new 3D viewpoint.
        // Count each qualified pair, including isolated pairs; requiring two consecutive
        // successes hid genuine comparisons whenever another pair lost tracking.
        if (changed && problem == null) changedComparisons++
        val state = when {
            issue == VisualIssue.WARMUP || issue == VisualIssue.STALE -> VisualState.PENDING
            problem != null -> VisualState.NEEDS_IMPROVEMENT
            stable == true -> VisualState.STABLE
            else -> VisualState.NOT_VERIFIABLE
        }
        val message = problem ?: if (stable == true) {
            "Imagen estable con coincidencias locales, sin cambio de vista observable. Esto no suma nuevas vistas."
        } else "Coincidencias locales con cambio 2D. La traslación y el paralaje no son verificables aquí; no acredita recorrido 3D."
        return VisualFeedback(
            state, message, currentFeatures.size, shifts.size, changedComparisons, samples,
            stable, matched, changed, issue, requiredMatches,
            if (old == null) 0 else nowMs - previousAtMsForComparison,
            mean, sharpness, motion,
        )
    }

    private fun findFeatures(a: IntArray, w: Int, h: Int): List<Feature> {
        val result = mutableListOf<Feature>()
        // One two-direction corner per grid cell; at most 48 patches.
        for (gy in 0 until 6) for (gx in 0 until 8) {
            var best = 80.0
            var point: Feature? = null
            for (y in maxOf(5, gy * h / 6) until minOf(h - 5, (gy + 1) * h / 6)) {
                for (x in maxOf(5, gx * w / 8) until minOf(w - 5, (gx + 1) * w / 8)) {
                    var xx = 0.0; var yy = 0.0; var xy = 0.0
                    for (dy in -1..1) for (dx in -1..1) {
                        val i = (y + dy) * w + x + dx
                        val u = a[i + 1] - a[i - 1]; val v = a[i + w] - a[i - w]
                        xx += u * u; yy += v * v; xy += u * v
                    }
                    val score = (xx * yy - xy * xy) / (xx + yy + 1)
                    if (score > best) { best = score; point = Feature(x, y) }
                }
            }
            if (point != null) result.add(point)
        }
        return result
    }

    private fun track(old: IntArray, current: IntArray, w: Int, h: Int, points: List<Feature>): List<Double> {
        val shifts = mutableListOf<Double>()
        val used = mutableListOf<Feature>()
        for (p in points) {
            // Evaluate every displacement: the old 2-pixel grid could not match odd
            // translations at all, even on an otherwise identical textured patch.
            val errors = IntArray(33 * 33) { Int.MAX_VALUE }
            var bestError = Int.MAX_VALUE
            var best = p
            for (dy in -16..16) for (dx in -16..16) {
                val x = p.x + dx; val y = p.y + dy
                if (x < 2 || x >= w - 2 || y < 2 || y >= h - 2) continue
                var error = 0
                for (py in -2..2) for (px in -2..2) {
                    error += abs(old[(p.y + py) * w + p.x + px] - current[(y + py) * w + x + px])
                }
                errors[(dy + 16) * 33 + dx + 16] = error
                if (error < bestError) { bestError = error; best = Feature(x, y) }
            }
            var second = Int.MAX_VALUE
            for (i in errors.indices) {
                if (abs(p.x + i % 33 - 16 - best.x) + abs(p.y + i / 33 - 16 - best.y) >= 4 && errors[i] < second) {
                    second = errors[i]
                }
            }
            if (bestError > 25 * 18 || bestError >= second * 0.65 ||
                used.any { abs(it.x - best.x) + abs(it.y - best.y) < 4 }) continue
            used.add(best)
            shifts.add(hypot((p.x - best.x).toDouble(), (p.y - best.y).toDouble()))
        }
        return shifts
    }
}

/** Keep only one room's pixel history. Closed rooms retain text summaries, never image buffers.
 * Room identity comes from the actual RoomTimeline transition, not from a manually chosen step.
 */
internal class RoomVisualGuidance(firstName: String = "Ambiente 1") {
    private var roomId = "room-1"
    private var roomName = firstName
    private var current = VisualCaptureGuidance()
    private val closedSummaries = linkedMapOf<String, String>()

    fun beginRoom(id: String, name: String) {
        if (id == roomId) return
        closedSummaries[roomId] = "$roomName: ${current.summary()}"
        roomId = id
        roomName = name
        current = VisualCaptureGuidance()
    }

    fun resetComparison() = current.resetComparison()

    fun analyze(pixels: IntArray, width: Int, height: Int, nowMs: Long, step: Int,
                cadenceMs: Long = GuidanceSamplingPolicy.NORMAL_MS): VisualFeedback =
        current.analyze(pixels, width, height, nowMs, step, cadenceMs)

    fun summary(): String = (closedSummaries.values + "$roomName: ${current.summary()}").joinToString("\n\n")
}
