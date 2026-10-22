package com.example.captura_mobile.ar

import java.util.Locale
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** How the native screen captures a room; selected by the optional `mode` channel argument. */
enum class CaptureMode(val wireName: String) {
    /** Two floor points per wall, corners intersected natively (see [WallLines]). */
    WALLS("walls"),

    /** Continuous walk: tracked planes and the camera path are recorded; Dart proposes the corners. */
    WALKTHROUGH("walkthrough"),
    ;

    companion object {
        /** Unknown or missing values fall back to [WALLS]. */
        fun fromArgument(value: String?): CaptureMode = values().firstOrNull { it.wireName == value } ?: WALLS
    }
}

/** A vertical plane projected to the floor: a segment along its principal axis on x/z. */
data class WallSegment(
    val start: Corner2,
    val end: Corner2,
    /** Plane extent area (extentX * extentZ), m². */
    val area: Double,
    val minY: Double,
    val maxY: Double,
) {
    val length: Double get() = hypot(end.x - start.x, end.z - start.z)

    fun toMap(): Map<String, Any?> = linkedMapOf(
        "start" to start.toMap(),
        "end" to end.toMap(),
        "area" to area,
        "minY" to minY,
        "maxY" to maxY,
    )
}

/** What a walkthrough observed; serialised as the `observations` key of the `captured` result. */
data class WalkthroughObservations(
    val floorY: Double,
    val walls: List<WallSegment>,
    val floors: List<List<Corner2>>,
    val trajectory: List<Corner2>,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "floorY" to floorY,
        "walls" to walls.map { it.toMap() },
        "floors" to floors.map { polygon -> polygon.map { it.toMap() } },
        "trajectory" to trajectory.map { it.toMap() },
    )
}

/** Pure geometry of the walkthrough mode. No Android dependencies. */
object WalkthroughGeometry {
    /** Walls shorter than this on the floor are ignored (noise or a sliver of a plane). */
    const val MIN_WALL_LENGTH_M = 0.30

    /** Horizontal planes within this distance of the floor level count as floor. */
    const val FLOOR_PLANE_TOLERANCE_M = 0.10

    private const val EPSILON = 1e-9

    /**
     * Fits a floor segment to a vertical plane's polygon given in world coordinates: the x/z
     * points are projected on their principal axis (PCA) and the segment spans the min/max
     * projection. Returns null for walls shorter than [MIN_WALL_LENGTH_M].
     */
    fun fitWallSegment(worldPolygon: List<Vec3>, area: Double): WallSegment? {
        if (worldPolygon.size < 2) return null
        val meanX = worldPolygon.sumOf { it.x } / worldPolygon.size
        val meanZ = worldPolygon.sumOf { it.z } / worldPolygon.size
        var sxx = 0.0
        var szz = 0.0
        var sxz = 0.0
        for (p in worldPolygon) {
            val dx = p.x - meanX
            val dz = p.z - meanZ
            sxx += dx * dx
            szz += dz * dz
            sxz += dx * dz
        }
        // Major-axis angle of the 2x2 covariance matrix.
        val angle = 0.5 * atan2(2 * sxz, sxx - szz)
        val ux = cos(angle)
        val uz = sin(angle)
        var minT = Double.POSITIVE_INFINITY
        var maxT = Double.NEGATIVE_INFINITY
        for (p in worldPolygon) {
            val t = (p.x - meanX) * ux + (p.z - meanZ) * uz
            if (t < minT) minT = t
            if (t > maxT) maxT = t
        }
        if (maxT - minT < MIN_WALL_LENGTH_M - EPSILON) return null
        return WallSegment(
            start = Corner2(meanX + minT * ux, meanZ + minT * uz),
            end = Corner2(meanX + maxT * ux, meanZ + maxT * uz),
            area = area,
            minY = worldPolygon.minOf { it.y },
            maxY = worldPolygon.maxOf { it.y },
        )
    }

    fun isAtFloorHeight(planeY: Double, floorY: Double): Boolean =
        abs(planeY - floorY) <= FLOOR_PLANE_TOLERANCE_M + EPSILON

    /** The floor is the lowest upward-facing plane seen so far; it only ever moves down. */
    fun refineFloorY(current: Double?, upwardPlaneYs: List<Double>): Double? {
        val lowest = upwardPlaneYs.minOrNull() ?: return current
        return if (current == null || lowest < current) lowest else current
    }

    /** Unsigned polygon area on x/z (shoelace); 0 for fewer than three points. */
    fun polygonArea(points: List<Corner2>): Double {
        if (points.size < 3) return 0.0
        var sum = 0.0
        for (i in points.indices) {
            val a = points[i]
            val b = points[(i + 1) % points.size]
            sum += a.x * b.z - b.x * a.z
        }
        return abs(sum) / 2
    }

    /** "12,35 m²". */
    fun formatSquareMeters(value: Double): String =
        String.format(Locale.ROOT, "%.2f", value).replace('.', ',') + " m²"

    /** "8,3 m". */
    fun formatTrajectory(value: Double): String =
        String.format(Locale.ROOT, "%.1f", value).replace('.', ',') + " m"
}

/** Camera path on x/z: a point is kept only when it moved at least [minStep] from the last kept one. */
class TrajectorySampler(private val minStep: Double = MIN_STEP_M) {
    private val kept = mutableListOf<Corner2>()

    val points: List<Corner2> get() = kept.toList()

    /** Returns true when the point was kept. */
    fun offer(x: Double, z: Double): Boolean {
        val last = kept.lastOrNull()
        if (last != null && hypot(x - last.x, z - last.z) < minStep - 1e-9) return false
        kept.add(Corner2(x, z))
        return true
    }

    /** Length of the kept path, in metres. */
    fun length(): Double = kept.zipWithNext { a, b -> hypot(b.x - a.x, b.z - a.z) }.sum()

    companion object {
        const val MIN_STEP_M = 0.25
    }
}
