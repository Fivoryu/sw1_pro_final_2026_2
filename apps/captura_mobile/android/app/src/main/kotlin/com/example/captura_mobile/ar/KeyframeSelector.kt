package com.example.captura_mobile.ar

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.min
import kotlin.math.sqrt

/** Camera (or plane) to world pose, `[tx, ty, tz, qx, qy, qz, qw]`, ARCore convention. */
data class CameraPose(
    val tx: Double,
    val ty: Double,
    val tz: Double,
    val qx: Double,
    val qy: Double,
    val qz: Double,
    val qw: Double,
) {
    fun toList(): List<Double> = listOf(tx, ty, tz, qx, qy, qz, qw)

    fun distanceTo(other: CameraPose): Double {
        val dx = tx - other.tx
        val dy = ty - other.ty
        val dz = tz - other.tz
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /** Smallest rotation between the two orientations, in degrees (q and -q are the same rotation). */
    fun angleToDegrees(other: CameraPose): Double {
        val dot = abs(qx * other.qx + qy * other.qy + qz * other.qz + qw * other.qw)
        val normA = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
        val normB = sqrt(other.qx * other.qx + other.qy * other.qy + other.qz * other.qz + other.qw * other.qw)
        if (normA == 0.0 || normB == 0.0) return 0.0
        return Math.toDegrees(2 * acos(min(1.0, dot / (normA * normB))))
    }
}

/**
 * The keyframe rule of `docs/api/f07-capture-package.md`: only while TRACKING; a new keyframe once
 * at least [MIN_INTERVAL_MS] passed since the last one AND the camera moved at least [MIN_MOVE_M]
 * or rotated at least [MIN_ROTATION_DEG]; never more than [MAX_KEYFRAMES].
 */
class KeyframeSelector {
    private var last: CameraPose? = null
    private var lastAtMs = 0L

    var count = 0
        private set

    /** Returns true when this sample is a keyframe. Rejected samples leave the reference untouched. */
    fun offer(timestampMs: Long, tracking: Boolean, pose: CameraPose): Boolean {
        if (!tracking || count >= MAX_KEYFRAMES) return false
        val reference = last
        if (reference != null) {
            if (timestampMs - lastAtMs < MIN_INTERVAL_MS) return false
            val moved = pose.distanceTo(reference) >= MIN_MOVE_M - EPSILON
            val rotated = pose.angleToDegrees(reference) >= MIN_ROTATION_DEG - ANGLE_EPSILON
            if (!moved && !rotated) return false
        }
        last = pose
        lastAtMs = timestampMs
        count++
        return true
    }

    companion object {
        const val MIN_INTERVAL_MS = 500L
        const val MIN_MOVE_M = 0.25
        const val MIN_ROTATION_DEG = 15.0
        const val MAX_KEYFRAMES = 600
        private const val EPSILON = 1e-9
        private const val ANGLE_EPSILON = 1e-6
    }
}
