package com.example.captura_mobile.video

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Finds the best rectangular object (a sheet, a card, a screen) on one frame, fully offline and in pure
 * Kotlin: no Android classes, no OpenCV, no ML model. Input is ARGB pixels; output is four consecutive
 * corners normalised to 0..1 on that frame, or null.
 *
 * Pipeline: luma, box downscale to [DETECTION_WIDTH], 3x3 blur, then for every threshold of a sweep and both
 * polarities (bright or dark object) a connected-component pass. A component is a candidate when its area is
 * plausible, it does not touch the image border, it fills its convex hull ([MIN_FILL]), and the hull reduces
 * to a quadrilateral that contains it tightly ([MIN_QUAD_FIT]) with corner angles near a right angle. The
 * candidates are scored by fill, quad fit and closeness of the side ratio to the target ratio; the winner's
 * edges are then refined on the full-resolution luma (gradient peak along each edge normal, line fit) and
 * its corners are the intersections of the fitted lines.
 *
 * Every threshold below is an unmeasured assumption chosen for the synthetic tests, not a measured accuracy.
 */
object RectDetector {
    const val DETECTION_WIDTH = 320

    /** Plausible area of the object relative to the frame. */
    const val MIN_AREA_FRACTION = 0.05
    const val MAX_AREA_FRACTION = 0.90

    /** Component pixels over convex-hull area: below this the shape is ragged or hollow. */
    const val MIN_FILL = 0.75

    /** Hull area over the area of the quadrilateral that contains it: below this the shape is not a quad. */
    const val MIN_QUAD_FIT = 0.90

    /** Allowed relative difference between the quad's side ratio and the preset ratio (assumption). */
    const val RATIO_TOLERANCE = 0.20

    /** Interior angles outside this range are not a rectangle seen with mild perspective (assumption). */
    const val MIN_CORNER_ANGLE_DEG = 55.0
    const val MAX_CORNER_ANGLE_DEG = 125.0

    /** Spacing of the luma threshold sweep. */
    const val THRESHOLD_STEP = 12

    /** A refined edge needs a luma step at least this large (0..255) or the unrefined edge is kept. */
    const val MIN_EDGE_CONTRAST = 8.0

    const val REFINE_SAMPLES = 24
    private const val MIN_REFINE_POINTS = 8

    private class Pt(val x: Double, val y: Double)

    private class Candidate(val quad: List<Pt>, val score: Double, val brightObject: Boolean)

    /**
     * @param targetRatio long side over short side of the expected object (for example 297/210); null
     * accepts any ratio.
     */
    fun detect(pixels: IntArray, width: Int, height: Int, targetRatio: Double? = null): List<ReferencePoint>? {
        require(width > 0 && height > 0 && pixels.size >= width * height) { "Invalid frame size" }
        val luma = FloatArray(width * height) { i ->
            val p = pixels[i]
            0.299f * ((p shr 16) and 0xFF) + 0.587f * ((p shr 8) and 0xFF) + 0.114f * (p and 0xFF)
        }
        val dw = min(DETECTION_WIDTH, width)
        val dh = max(1, (height.toDouble() * dw / width).roundToInt())
        val small = blur(downscale(luma, width, height, dw, dh), dw, dh)
        val sx = width.toDouble() / dw
        val sy = height.toDouble() / dh
        val target = targetRatio?.takeIf { it.isFinite() && it > 0.0 }?.let { if (it < 1.0) 1.0 / it else it }

        var best: Candidate? = null
        val mask = BooleanArray(dw * dh)
        val visited = BooleanArray(dw * dh)
        val queue = IntArray(dw * dh)
        for (brightObject in booleanArrayOf(true, false)) {
            var t = THRESHOLD_STEP
            while (t < 256 - THRESHOLD_STEP) {
                for (i in mask.indices) mask[i] = if (brightObject) small[i] > t else small[i] < t
                visited.fill(false)
                val found = bestInMask(mask, visited, queue, dw, dh, target, brightObject)
                if (found != null && (best == null || found.score > best.score)) best = found
                t += THRESHOLD_STEP
            }
        }
        val winner = best ?: return null
        val full = winner.quad.map { Pt(it.x * sx, it.y * sy) }
        val refined = refine(luma, width, height, full, winner.brightObject, max(sx, sy))
        return refined.map {
            ReferencePoint((it.x / width).coerceIn(0.0, 1.0), (it.y / height).coerceIn(0.0, 1.0))
        }
    }

    // region segmentation

    private fun bestInMask(
        mask: BooleanArray,
        visited: BooleanArray,
        queue: IntArray,
        w: Int,
        h: Int,
        target: Double?,
        brightObject: Boolean,
    ): Candidate? {
        val minArea = MIN_AREA_FRACTION * w * h
        val maxArea = MAX_AREA_FRACTION * w * h
        var best: Candidate? = null
        for (start in mask.indices) {
            if (!mask[start] || visited[start]) continue
            var head = 0
            var tail = 0
            queue[tail++] = start
            visited[start] = true
            var touchesBorder = false
            while (head < tail) {
                val p = queue[head++]
                val x = p % w
                val y = p / w
                if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesBorder = true
                if (x > 0 && mask[p - 1] && !visited[p - 1]) { visited[p - 1] = true; queue[tail++] = p - 1 }
                if (x < w - 1 && mask[p + 1] && !visited[p + 1]) { visited[p + 1] = true; queue[tail++] = p + 1 }
                if (y > 0 && mask[p - w] && !visited[p - w]) { visited[p - w] = true; queue[tail++] = p - w }
                if (y < h - 1 && mask[p + w] && !visited[p + w]) { visited[p + w] = true; queue[tail++] = p + w }
            }
            if (touchesBorder || tail < minArea || tail > maxArea) continue
            val candidate = evaluate(queue, tail, w, h, target, brightObject) ?: continue
            if (best == null || candidate.score > best.score) best = candidate
        }
        return best
    }

    private fun evaluate(queue: IntArray, count: Int, w: Int, h: Int, target: Double?, brightObject: Boolean): Candidate? {
        val rowMin = IntArray(h) { Int.MAX_VALUE }
        val rowMax = IntArray(h) { -1 }
        for (k in 0 until count) {
            val p = queue[k]
            val x = p % w
            val y = p / w
            if (x < rowMin[y]) rowMin[y] = x
            if (x > rowMax[y]) rowMax[y] = x
        }
        val points = ArrayList<Pt>()
        for (y in 0 until h) {
            if (rowMax[y] < 0) continue
            val l = rowMin[y].toDouble()
            val r = rowMax[y] + 1.0
            points.add(Pt(l, y.toDouble())); points.add(Pt(l, y + 1.0))
            points.add(Pt(r, y.toDouble())); points.add(Pt(r, y + 1.0))
        }
        val hull = convexHull(points)
        if (hull.size < 4) return null
        val hullArea = area(hull)
        if (hullArea <= 0.0) return null
        val fill = count / hullArea
        if (fill < MIN_FILL) return null
        val quad = reduceToQuad(hull) ?: return null
        val quadArea = area(quad)
        if (quadArea <= 0.0) return null
        val quadFit = hullArea / quadArea
        if (quadFit < MIN_QUAD_FIT) return null
        if (!anglesPlausible(quad)) return null
        var deviation = 0.0
        if (target != null) {
            val a = (dist(quad[0], quad[1]) + dist(quad[2], quad[3])) / 2.0
            val b = (dist(quad[1], quad[2]) + dist(quad[3], quad[0])) / 2.0
            if (min(a, b) <= 0.0) return null
            deviation = abs(max(a, b) / min(a, b) / target - 1.0)
            if (deviation > RATIO_TOLERANCE) return null
        }
        val score = min(fill, 1.0) * quadFit * (1.0 - 0.5 * deviation / RATIO_TOLERANCE)
        return Candidate(clockwiseFromTopLeft(quad), score, brightObject)
    }

    // endregion

    // region geometry

    private fun dist(a: Pt, b: Pt) = hypot(a.x - b.x, a.y - b.y)

    private fun cross(ax: Double, ay: Double, bx: Double, by: Double) = ax * by - ay * bx

    /** Signed shoelace area; positive for clockwise on screen (y down). */
    private fun signedArea(poly: List<Pt>): Double {
        var s = 0.0
        for (i in poly.indices) {
            val a = poly[i]
            val b = poly[(i + 1) % poly.size]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2.0
    }

    private fun area(poly: List<Pt>) = abs(signedArea(poly))

    /** Andrew's monotone chain. */
    private fun convexHull(input: List<Pt>): List<Pt> {
        val pts = input.sortedWith(compareBy({ it.x }, { it.y })).distinctBy { it.x to it.y }
        if (pts.size < 3) return pts
        val hull = ArrayList<Pt>()
        for (pass in 0..1) {
            val start = hull.size
            val seq = if (pass == 0) pts else pts.asReversed()
            for (p in seq) {
                while (hull.size >= start + 2) {
                    val a = hull[hull.size - 2]
                    val b = hull[hull.size - 1]
                    if (cross(b.x - a.x, b.y - a.y, p.x - b.x, p.y - b.y) <= 0.0) hull.removeAt(hull.size - 1) else break
                }
                hull.add(p)
            }
            hull.removeAt(hull.size - 1)
        }
        return hull
    }

    /**
     * Reduces a convex polygon to four vertices by repeatedly removing the edge whose neighbours, extended,
     * add the least area. Null when no edge can be removed (parallel neighbours).
     */
    private fun reduceToQuad(hull: List<Pt>): List<Pt>? {
        val poly = hull.toMutableList()
        while (poly.size > 4) {
            val n = poly.size
            var bestIdx = -1
            var bestArea = Double.MAX_VALUE
            var bestPt: Pt? = null
            for (i in 0 until n) {
                val prev = poly[(i + n - 1) % n]
                val a = poly[i]
                val b = poly[(i + 1) % n]
                val next = poly[(i + 2) % n]
                val d1x = a.x - prev.x
                val d1y = a.y - prev.y
                val d2x = next.x - b.x
                val d2y = next.y - b.y
                val denom = cross(d1x, d1y, d2x, d2y)
                if (abs(denom) < 1e-9) continue
                val t = cross(b.x - prev.x, b.y - prev.y, d2x, d2y) / denom
                val u = cross(b.x - prev.x, b.y - prev.y, d1x, d1y) / denom
                if (t <= 1.0 || u >= 0.0) continue
                val p = Pt(prev.x + t * d1x, prev.y + t * d1y)
                val added = abs(cross(p.x - a.x, p.y - a.y, b.x - a.x, b.y - a.y)) / 2.0
                if (added < bestArea) { bestArea = added; bestIdx = i; bestPt = p }
            }
            val p = bestPt ?: return null
            val j = (bestIdx + 1) % n
            poly[bestIdx] = p
            poly.removeAt(j)
        }
        return if (poly.size == 4) poly else null
    }

    private fun anglesPlausible(q: List<Pt>): Boolean {
        for (i in 0 until 4) {
            val p = q[(i + 3) % 4]
            val c = q[i]
            val n = q[(i + 1) % 4]
            val v1x = p.x - c.x
            val v1y = p.y - c.y
            val v2x = n.x - c.x
            val v2y = n.y - c.y
            val l = hypot(v1x, v1y) * hypot(v2x, v2y)
            if (l <= 0.0) return false
            val deg = Math.toDegrees(acos(((v1x * v2x + v1y * v2y) / l).coerceIn(-1.0, 1.0)))
            if (deg < MIN_CORNER_ANGLE_DEG || deg > MAX_CORNER_ANGLE_DEG) return false
        }
        return true
    }

    private fun clockwiseFromTopLeft(q: List<Pt>): List<Pt> {
        val ring = if (signedArea(q) >= 0.0) q else q.reversed()
        val start = ring.indices.minByOrNull { ring[it].x + ring[it].y } ?: 0
        return List(4) { ring[(start + it) % 4] }
    }

    // endregion

    // region image helpers

    private fun downscale(src: FloatArray, w: Int, h: Int, dw: Int, dh: Int): FloatArray {
        val out = FloatArray(dw * dh)
        for (dy in 0 until dh) {
            val y0 = dy * h / dh
            val y1 = max(y0 + 1, (dy + 1) * h / dh)
            for (dx in 0 until dw) {
                val x0 = dx * w / dw
                val x1 = max(x0 + 1, (dx + 1) * w / dw)
                var sum = 0.0f
                for (y in y0 until y1) for (x in x0 until x1) sum += src[y * w + x]
                out[dy * dw + dx] = sum / ((y1 - y0) * (x1 - x0))
            }
        }
        return out
    }

    private fun blur(src: FloatArray, w: Int, h: Int): FloatArray {
        val out = FloatArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            var sum = 0.0f
            var n = 0
            for (yy in max(0, y - 1)..min(h - 1, y + 1)) for (xx in max(0, x - 1)..min(w - 1, x + 1)) {
                sum += src[yy * w + xx]; n++
            }
            out[y * w + x] = sum / n
        }
        return out
    }

    // endregion

    // region refinement

    private class Line(val px: Double, val py: Double, val dx: Double, val dy: Double)

    private fun sampleLuma(luma: FloatArray, w: Int, h: Int, x: Double, y: Double): Double {
        val fx = (x - 0.5).coerceIn(0.0, w - 1.0)
        val fy = (y - 0.5).coerceIn(0.0, h - 1.0)
        val x0 = fx.toInt()
        val y0 = fy.toInt()
        val x1 = min(x0 + 1, w - 1)
        val y1 = min(y0 + 1, h - 1)
        val tx = fx - x0
        val ty = fy - y0
        val top = luma[y0 * w + x0] * (1 - tx) + luma[y0 * w + x1] * tx
        val bot = luma[y1 * w + x0] * (1 - tx) + luma[y1 * w + x1] * tx
        return top * (1 - ty) + bot * ty
    }

    /** Re-fits each edge to the strongest luma step near it; keeps the unrefined edge/corner when unsure. */
    private fun refine(luma: FloatArray, w: Int, h: Int, quad: List<Pt>, brightObject: Boolean, scale: Double): List<Pt> {
        val cx = quad.sumOf { it.x } / 4.0
        val cy = quad.sumOf { it.y } / 4.0
        val reach = max(3.0, 2.5 * scale)
        val half = max(1.0, 0.5 * scale)
        val step = 0.5
        val lines = (0 until 4).map { k ->
            val a = quad[k]
            val b = quad[(k + 1) % 4]
            val len = hypot(b.x - a.x, b.y - a.y)
            val fallback = Line(a.x, a.y, (b.x - a.x) / len, (b.y - a.y) / len)
            var nx = fallback.dy
            var ny = -fallback.dx
            if (nx * ((a.x + b.x) / 2 - cx) + ny * ((a.y + b.y) / 2 - cy) < 0) { nx = -nx; ny = -ny }
            val sign = if (brightObject) 1.0 else -1.0
            val points = ArrayList<Pt>()
            for (s in 0 until REFINE_SAMPLES) {
                val f = 0.12 + 0.76 * s / (REFINE_SAMPLES - 1)
                val bx = a.x + (b.x - a.x) * f
                val by = a.y + (b.y - a.y) * f
                val n = (2 * reach / step).toInt() + 1
                val d = DoubleArray(n) { i ->
                    val t = -reach + i * step
                    sign * (sampleLuma(luma, w, h, bx + (t - half) * nx, by + (t - half) * ny) -
                        sampleLuma(luma, w, h, bx + (t + half) * nx, by + (t + half) * ny))
                }
                val peak = d.indices.maxByOrNull { d[it] } ?: continue
                if (d[peak] < MIN_EDGE_CONTRAST) continue
                // Centroid of the contiguous part above half the peak: centred on a step edge whatever its blur.
                var lo = peak
                while (lo > 0 && d[lo - 1] >= 0.5 * d[peak]) lo--
                var hi = peak
                while (hi < n - 1 && d[hi + 1] >= 0.5 * d[peak]) hi++
                var sw = 0.0
                var st = 0.0
                for (i in lo..hi) { sw += d[i]; st += d[i] * (-reach + i * step) }
                val t = st / sw
                points.add(Pt(bx + t * nx, by + t * ny))
            }
            fitLine(points, half) ?: fallback
        }
        return List(4) { k ->
            val l1 = lines[(k + 3) % 4]
            val l2 = lines[k]
            val denom = cross(l1.dx, l1.dy, l2.dx, l2.dy)
            val original = quad[k]
            if (abs(denom) < 1e-6) return@List original
            val t = cross(l2.px - l1.px, l2.py - l1.py, l2.dx, l2.dy) / denom
            val p = Pt(l1.px + t * l1.dx, l1.py + t * l1.dy)
            if (dist(p, original) > 3.0 * reach) original else p
        }
    }

    /** Total-least-squares line with one outlier pass; null with too few points. */
    private fun fitLine(points: List<Pt>, tolerance: Double): Line? {
        var pts = points
        repeat(2) { pass ->
            if (pts.size < MIN_REFINE_POINTS) return null
            val mx = pts.sumOf { it.x } / pts.size
            val my = pts.sumOf { it.y } / pts.size
            var sxx = 0.0; var syy = 0.0; var sxy = 0.0
            for (p in pts) { sxx += (p.x - mx) * (p.x - mx); syy += (p.y - my) * (p.y - my); sxy += (p.x - mx) * (p.y - my) }
            val ang = 0.5 * atan2(2 * sxy, sxx - syy)
            val line = Line(mx, my, cos(ang), sin(ang))
            if (pass == 1) return line
            val kept = pts.filter { abs(cross(it.x - mx, it.y - my, line.dx, line.dy)) <= 2.0 * tolerance }
            if (kept.size == pts.size) return line
            pts = kept
        }
        return null
    }

    // endregion
}
