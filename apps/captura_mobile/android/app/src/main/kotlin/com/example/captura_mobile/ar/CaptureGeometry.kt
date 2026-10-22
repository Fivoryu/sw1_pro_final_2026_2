package com.example.captura_mobile.ar

import java.util.Locale
import kotlin.math.hypot

/** A point in ARCore world space, in metres (y is up). */
data class Vec3(val x: Double, val y: Double, val z: Double)

/** A point in view pixels (origin top-left). */
data class ScreenPoint(val x: Float, val y: Float)

/** Pure geometry helpers shared by the AR overlay and the capture result. No Android dependencies. */
object CaptureGeometry {

    /** Distance projected on the floor plane (x/z), ignoring height differences. */
    fun horizontalDistance(a: Vec3, b: Vec3): Double = hypot(b.x - a.x, b.z - a.z)

    /**
     * Horizontal lengths of consecutive edges. When [closed] and there are at least three points,
     * the closing edge (last to first) is appended.
     */
    fun edgeLengths(points: List<Vec3>, closed: Boolean): List<Double> {
        if (points.size < 2) return emptyList()
        val lengths = points.zipWithNext { a, b -> horizontalDistance(a, b) }.toMutableList()
        if (closed && points.size >= 3) {
            lengths.add(horizontalDistance(points.last(), points.first()))
        }
        return lengths
    }

    /** Formats a length in metres with two decimals and a decimal comma, e.g. "2,35 m". */
    fun formatMeters(value: Double): String =
        String.format(Locale.ROOT, "%.2f", value).replace('.', ',') + " m"

    /**
     * Projects a world point to view pixels using column-major (OpenGL/ARCore) view and projection
     * matrices. Returns null when the point is behind the camera.
     */
    fun projectToScreen(
        point: Vec3,
        view: FloatArray,
        projection: FloatArray,
        width: Int,
        height: Int,
    ): ScreenPoint? {
        val world = doubleArrayOf(point.x, point.y, point.z, 1.0)
        val eye = multiply(view, world)
        val clip = multiply(projection, eye)
        val w = clip[3]
        if (w <= 1e-6) return null
        val ndcX = clip[0] / w
        val ndcY = clip[1] / w
        val screenX = (ndcX + 1.0) / 2.0 * width
        val screenY = (1.0 - ndcY) / 2.0 * height
        return ScreenPoint(screenX.toFloat(), screenY.toFloat())
    }

    private fun multiply(matrix: FloatArray, vector: DoubleArray): DoubleArray {
        val out = DoubleArray(4)
        for (row in 0 until 4) {
            var sum = 0.0
            for (col in 0 until 4) {
                sum += matrix[col * 4 + row] * vector[col]
            }
            out[row] = sum
        }
        return out
    }
}
