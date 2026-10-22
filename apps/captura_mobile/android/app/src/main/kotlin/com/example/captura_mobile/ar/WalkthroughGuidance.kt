package com.example.captura_mobile.ar

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max

/**
 * Live guidance for the continuous walkthrough. Pure rules with no Android dependencies: the activity feeds
 * ARCore state in and shows, speaks or vibrates what comes out. Thresholds are heuristics, not measured
 * tolerances.
 */
enum class GuidanceCue(val spoken: Boolean) {
    STOPPED(true),
    TRACKING_LOST(true),
    LOW_LIGHT(true),
    TOO_FAST(true),
    LOW_TEXTURE(true),
    NO_FLOOR(true),
    READY(false),
    MISSING_SIDE(true),
    COMPLETE(true),
}

enum class MissingSide(val phrase: String) {
    AHEAD("adelante tuyo"),
    LEFT("a tu izquierda"),
    RIGHT("a tu derecha"),
    BEHIND("detrás tuyo"),
}

/** Which bearing sectors around the walked area have an observed wall. */
data class Coverage(val sectors: List<Boolean>) {
    val fraction: Double get() = if (sectors.isEmpty()) 0.0 else sectors.count { it }.toDouble() / sectors.size

    companion object {
        val EMPTY = Coverage(List(WalkthroughCoverage.SECTOR_COUNT) { false })
    }
}

data class GuidanceInput(
    val trackingStateName: String,
    val failureReasonName: String,
    val recording: Boolean,
    val floorFound: Boolean,
    /** Metres per second over the motion window; null until measured. */
    val speed: Double?,
    /** Degrees per second of heading change; null until measured. */
    val yawRateDeg: Double?,
    /** ARCore ambient pixel intensity (0..1); null when unavailable. */
    val lightIntensity: Double?,
    val coverage: Coverage,
    /** Camera forward bearing on the floor plane, `atan2(z, x)` in radians. */
    val headingRad: Double,
)

data class Guidance(val cue: GuidanceCue, val message: String)

object WalkthroughCoverage {
    const val SECTOR_COUNT = 12
    private const val SECTOR_RAD = 2 * PI / SECTOR_COUNT

    /** Marks every sector whose centre bearing, seen from [centre], falls on a wall segment. */
    fun compute(walls: List<WallSegment>, centre: Corner2): Coverage {
        val sectors = BooleanArray(SECTOR_COUNT)
        for (wall in walls) {
            val a = bearing(centre, wall.start)
            val span = normalize(bearing(centre, wall.end) - a)
            // A straight wall that does not pass through the centre subtends less than half a turn.
            val from = if (span >= 0) a else a + span
            val width = abs(span)
            for (i in 0 until SECTOR_COUNT) {
                val offset = normalizePositive(i * SECTOR_RAD - from)
                if (offset <= width + 1e-9) sectors[i] = true
            }
        }
        return Coverage(sectors.toList())
    }

    /** The side of the nearest uncovered sector relative to [headingRad]; null when everything is covered. */
    fun missingSide(coverage: Coverage, headingRad: Double): MissingSide? {
        var best: Int? = null
        var bestDistance = Double.MAX_VALUE
        coverage.sectors.forEachIndexed { i, covered ->
            if (covered) return@forEachIndexed
            val distance = abs(normalize(i * SECTOR_RAD - headingRad))
            if (distance < bestDistance - 1e-9) {
                bestDistance = distance
                best = i
            }
        }
        return best?.let { sideOf(it * SECTOR_RAD, headingRad) }
    }

    /** ARCore axes: with the camera looking down -z, +x is to the right, so a positive turn is rightwards. */
    fun sideOf(targetRad: Double, headingRad: Double): MissingSide {
        val relative = Math.toDegrees(normalize(targetRad - headingRad))
        return when {
            abs(relative) <= 45.0 -> MissingSide.AHEAD
            abs(relative) >= 135.0 -> MissingSide.BEHIND
            relative > 0 -> MissingSide.RIGHT
            else -> MissingSide.LEFT
        }
    }

    private fun bearing(from: Corner2, to: Corner2): Double = atan2(to.z - from.z, to.x - from.x)

    /** Wraps to (-PI, PI]. */
    fun normalize(angle: Double): Double {
        var a = angle % (2 * PI)
        if (a <= -PI) a += 2 * PI
        if (a > PI) a -= 2 * PI
        return a
    }

    private fun normalizePositive(angle: Double): Double {
        val a = angle % (2 * PI)
        return if (a < 0) a + 2 * PI else a
    }
}

object WalkthroughGuidance {
    const val MAX_SPEED_MPS = 1.0
    const val MAX_YAW_RATE_DEG = 100.0
    const val MIN_LIGHT_INTENSITY = 0.1

    /** One sector may stay open, for example a doorway or a wall hidden behind furniture. */
    const val COMPLETE_FRACTION = (WalkthroughCoverage.SECTOR_COUNT - 1).toDouble() / WalkthroughCoverage.SECTOR_COUNT

    fun evaluate(input: GuidanceInput): Guidance {
        if (input.trackingStateName == "STOPPED") {
            return Guidance(GuidanceCue.STOPPED, "Seguimiento detenido. Terminá o cancelá el recorrido y volvé a abrir la captura.")
        }
        if (input.trackingStateName != "TRACKING") {
            return when (input.failureReasonName) {
                "INSUFFICIENT_LIGHT" -> lowLight()
                "EXCESSIVE_MOTION" -> tooFast()
                "INSUFFICIENT_FEATURES" -> Guidance(
                    GuidanceCue.LOW_TEXTURE,
                    "La superficie no tiene textura. Apuntá a un borde, un zócalo o un mueble junto a la pared.",
                )
                else -> Guidance(
                    GuidanceCue.TRACKING_LOST,
                    "Se perdió el seguimiento. Volvé a apuntar a donde estabas: lo capturado se conserva.",
                )
            }
        }
        if (!input.floorFound) {
            return Guidance(GuidanceCue.NO_FLOOR, "Apuntá al piso y mové el teléfono despacio de lado a lado.")
        }
        if (!input.recording) {
            return Guidance(
                GuidanceCue.READY,
                "Piso detectado. Tocá «Iniciar recorrido» con el teléfono a la altura del pecho.",
            )
        }
        if ((input.speed ?: 0.0) > MAX_SPEED_MPS || (input.yawRateDeg ?: 0.0) > MAX_YAW_RATE_DEG) return tooFast()
        if (input.lightIntensity != null && input.lightIntensity < MIN_LIGHT_INTENSITY) return lowLight()
        if (input.coverage.fraction >= COMPLETE_FRACTION) {
            return Guidance(GuidanceCue.COMPLETE, "Ambiente completo. Tocá «Terminar recorrido».")
        }
        val side = WalkthroughCoverage.missingSide(input.coverage, input.headingRad) ?: MissingSide.AHEAD
        return Guidance(
            GuidanceCue.MISSING_SIDE,
            "Faltan paredes ${side.phrase}. Caminá junto a ellas apuntando a la base.",
        )
    }

    private fun tooFast() = Guidance(GuidanceCue.TOO_FAST, "Más despacio. Caminá y girá con calma.")

    private fun lowLight() = Guidance(GuidanceCue.LOW_LIGHT, "Hay poca luz. Encendé las luces o abrí las cortinas.")
}

data class MotionSample(val speed: Double, val yawRateDeg: Double)

/** Speed and heading change measured between samples at least [windowMs] apart. */
class MotionMeter(private val windowMs: Long = 500) {
    private var anchorAtMs: Long? = null
    private var anchorX = 0.0
    private var anchorZ = 0.0
    private var anchorYaw = 0.0

    /** Returns a sample when a full window has elapsed since the previous anchor, otherwise null. */
    fun offer(nowMs: Long, x: Double, z: Double, yawRad: Double): MotionSample? {
        val since = anchorAtMs
        if (since == null) {
            anchor(nowMs, x, z, yawRad)
            return null
        }
        val elapsed = nowMs - since
        if (elapsed < windowMs) return null
        val seconds = elapsed / 1000.0
        val sample = MotionSample(
            speed = hypot(x - anchorX, z - anchorZ) / seconds,
            yawRateDeg = Math.toDegrees(abs(WalkthroughCoverage.normalize(yawRad - anchorYaw))) / seconds,
        )
        anchor(nowMs, x, z, yawRad)
        return sample
    }

    fun reset() {
        anchorAtMs = null
    }

    private fun anchor(nowMs: Long, x: Double, z: Double, yawRad: Double) {
        anchorAtMs = nowMs
        anchorX = x
        anchorZ = z
        anchorYaw = yawRad
    }
}

/** Decides when a cue is spoken: only after it is stable, and not again until [repeatMs] have passed. */
class GuidanceAnnouncer(private val stableMs: Long = 1200, private val repeatMs: Long = 8000) {
    private var candidate: GuidanceCue? = null
    private var candidateSinceMs = 0L
    private var lastSpoken: GuidanceCue? = null
    private var lastSpokenAtMs = 0L

    fun offer(cue: GuidanceCue, nowMs: Long): GuidanceCue? {
        if (cue != candidate) {
            candidate = cue
            candidateSinceMs = nowMs
            return null
        }
        if (!cue.spoken || nowMs - candidateSinceMs < stableMs) return null
        if (cue == lastSpoken && nowMs - lastSpokenAtMs < repeatMs) return null
        lastSpoken = cue
        lastSpokenAtMs = nowMs
        return cue
    }
}

/** Maps floor coordinates into a square minimap, keeping proportions and centring the shorter axis. */
class MinimapProjection private constructor(
    private val minX: Double,
    private val minZ: Double,
    private val scale: Double,
    private val offsetX: Double,
    private val offsetY: Double,
) {
    fun map(point: Corner2): ScreenPoint = ScreenPoint(
        (offsetX + (point.x - minX) * scale).toFloat(),
        (offsetY + (point.z - minZ) * scale).toFloat(),
    )

    companion object {
        /** Smallest span drawn, so a single point or a short wall does not fill the map. */
        private const val MIN_SPAN_M = 1.0

        fun fit(points: List<Corner2>, sizePx: Float, paddingPx: Float): MinimapProjection? {
            if (points.isEmpty()) return null
            val minX = points.minOf { it.x }
            val maxX = points.maxOf { it.x }
            val minZ = points.minOf { it.z }
            val maxZ = points.maxOf { it.z }
            val inner = (sizePx - 2 * paddingPx).toDouble()
            val span = max(max(maxX - minX, maxZ - minZ), MIN_SPAN_M)
            val scale = inner / span
            return MinimapProjection(
                minX = minX,
                minZ = minZ,
                scale = scale,
                offsetX = paddingPx + (inner - (maxX - minX) * scale) / 2,
                offsetY = paddingPx + (inner - (maxZ - minZ) * scale) / 2,
            )
        }
    }
}
