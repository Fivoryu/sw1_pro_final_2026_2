package com.example.captura_mobile.ar

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.min

/** Outcome of deriving room corners from marked wall lines. Wall numbers in failures are 1-based. */
sealed class WallCornersResult {
    /** Corner i is where wall i meets wall i + 1; the last one joins the last wall and the first. */
    data class Corners(val corners: List<Vec3>) : WallCornersResult()

    sealed class Failure : WallCornersResult() {
        abstract val message: String
    }

    data class TooFewWalls(val count: Int) : Failure() {
        override val message: String get() = "Marcá al menos 3 paredes para calcular las esquinas."
    }

    data class ZeroLengthWall(val wall: Int) : Failure() {
        override val message: String
            get() = "Los dos puntos de la pared $wall están en el mismo lugar: deshacé y volvé a marcarla."
    }

    data class NearlyParallel(val firstWall: Int, val secondWall: Int) : Failure() {
        override val message: String
            get() = "Las paredes $firstWall y $secondWall son casi paralelas: " +
                "marcá otra pared entre ellas o revisá el orden."
    }

    data class Degenerate(val firstWall: Int, val secondWall: Int) : Failure() {
        override val message: String
            get() = "Las paredes $firstWall y $secondWall se cruzan a más de 20 m de lo marcado: " +
                "revisá el orden o volvé a marcar esas paredes."
    }
}

/**
 * Room corners from wall lines marked on the floor. Corners are dark, textureless and often hidden
 * by furniture, so the agent marks two floor points anywhere along the base of each wall instead,
 * in order around the room; each corner is the x/z intersection of two consecutive wall lines.
 * Assumes straight walls. No Android dependencies.
 */
object WallLines {
    /** Consecutive walls closer than this angle cannot give a reliable corner. */
    const val MIN_WALL_ANGLE_DEG = 15.0

    /** A corner farther than this from the marked points of either wall is treated as degenerate. */
    const val MAX_CORNER_DISTANCE_M = 20.0

    private const val MIN_DIRECTION_M = 1e-6

    /**
     * Intersects wall i with wall i + 1 (wrapping last to first) on the floor plane. Each wall is
     * two points in either direction along it; corners take the y of the first marked point.
     */
    fun cornersFromWallLines(walls: List<Pair<Vec3, Vec3>>): WallCornersResult {
        if (walls.size < CaptureRules.MIN_CORNERS) return WallCornersResult.TooFewWalls(walls.size)
        walls.forEachIndexed { index, (a, b) ->
            if (hypot(b.x - a.x, b.z - a.z) < MIN_DIRECTION_M) return WallCornersResult.ZeroLengthWall(index + 1)
        }
        val floorY = walls.first().first.y
        val corners = ArrayList<Vec3>(walls.size)
        for (i in walls.indices) {
            val j = (i + 1) % walls.size
            val first = walls[i]
            val second = walls[j]
            if (angleBetweenDeg(first, second) < MIN_WALL_ANGLE_DEG) {
                return WallCornersResult.NearlyParallel(i + 1, j + 1)
            }
            val corner = intersect(first, second)
            if (distanceToWall(corner, first) > MAX_CORNER_DISTANCE_M ||
                distanceToWall(corner, second) > MAX_CORNER_DISTANCE_M
            ) {
                return WallCornersResult.Degenerate(i + 1, j + 1)
            }
            corners.add(Vec3(corner.first, floorY, corner.second))
        }
        return WallCornersResult.Corners(corners)
    }

    /** Unsigned angle between two undirected lines on x/z, in degrees (0..90). */
    private fun angleBetweenDeg(first: Pair<Vec3, Vec3>, second: Pair<Vec3, Vec3>): Double {
        val (dx1, dz1) = direction(first)
        val (dx2, dz2) = direction(second)
        val cos = abs(dx1 * dx2 + dz1 * dz2) / (hypot(dx1, dz1) * hypot(dx2, dz2))
        return Math.toDegrees(acos(cos.coerceIn(0.0, 1.0)))
    }

    /** Intersection (x, z) of two non-parallel lines. */
    private fun intersect(first: Pair<Vec3, Vec3>, second: Pair<Vec3, Vec3>): Pair<Double, Double> {
        val p = first.first
        val q = second.first
        val (dx, dz) = direction(first)
        val (ex, ez) = direction(second)
        val cross = dx * ez - dz * ex
        val t = ((q.x - p.x) * ez - (q.z - p.z) * ex) / cross
        return (p.x + t * dx) to (p.z + t * dz)
    }

    private fun distanceToWall(point: Pair<Double, Double>, wall: Pair<Vec3, Vec3>): Double = min(
        hypot(point.first - wall.first.x, point.second - wall.first.z),
        hypot(point.first - wall.second.x, point.second - wall.second.z),
    )

    private fun direction(wall: Pair<Vec3, Vec3>): Pair<Double, Double> =
        (wall.second.x - wall.first.x) to (wall.second.z - wall.first.z)
}
