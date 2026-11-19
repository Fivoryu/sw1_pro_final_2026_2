package com.example.captura_mobile.video

/** Relative PTS agreement guard. 2 ms is a quantisation allowance, not measured accuracy. */
object FrameTiming {
    private const val TOLERANCE_NS = 2_000_000L

    fun validate(cameraNs: List<Long>, encodedUs: List<Long>) {
        require(cameraNs.isNotEmpty() && cameraNs.size == encodedUs.size) { "MP4/camera frame count differs" }
        require(cameraNs.zipWithNext().all { it.first < it.second }) { "Camera timestamps are not monotonic" }
        require(encodedUs.zipWithNext().all { it.first < it.second }) { "MP4 timestamps are not monotonic" }
        cameraNs.indices.forEach { i ->
            val delta = (encodedUs[i] - encodedUs[0]) * 1000 - (cameraNs[i] - cameraNs[0])
            require(kotlin.math.abs(delta) <= TOLERANCE_NS) { "MP4/camera timeline differs" }
        }
    }

    /** Match actual samples to an ordered subset of actual camera timestamps, never to FPS.
     * MediaRecorder may change the PTS epoch and omit frames. With no absolute MP4 epoch,
     * multiple possible alignments must fail rather than silently shift sensor synchronization.
     */
    fun match(cameraNs: List<Long>, encodedUs: List<Long>): List<Long> {
        require(encodedUs.isNotEmpty() && cameraNs.size >= encodedUs.size) { "MP4 samples lack camera timestamps" }
        require(cameraNs.zipWithNext().all { it.first < it.second }) { "Camera timestamps are not monotonic" }
        require(encodedUs.zipWithNext().all { it.first < it.second }) { "MP4 timestamps are not monotonic" }
        if (cameraNs.size == encodedUs.size) {
            validate(cameraNs, encodedUs)
            return cameraNs.toList()
        }
        var matched: List<Long>? = null
        for (first in 0..cameraNs.size - encodedUs.size) {
            if (cameraNs.last() - cameraNs[first] + TOLERANCE_NS <
                (encodedUs.last() - encodedUs[0]) * 1000) break
            val candidate = ArrayList<Long>(encodedUs.size)
            candidate.add(cameraNs[first])
            var cursor = first + 1
            for (i in 1 until encodedUs.size) {
                val relativeNs = (encodedUs[i] - encodedUs[0]) * 1000
                while (cursor < cameraNs.size &&
                    cameraNs[cursor] - cameraNs[first] < relativeNs - TOLERANCE_NS) cursor++
                if (cursor == cameraNs.size ||
                    kotlin.math.abs(cameraNs[cursor] - cameraNs[first] - relativeNs) > TOLERANCE_NS) break
                // Two camera frames within the same acceptance window cannot be distinguished.
                require(cursor + 1 == cameraNs.size ||
                    cameraNs[cursor + 1] - cameraNs[first] > relativeNs + TOLERANCE_NS) {
                    "MP4/camera frame mapping is ambiguous"
                }
                candidate.add(cameraNs[cursor++])
            }
            if (candidate.size != encodedUs.size) continue
            require(matched == null) { "MP4/camera timeline mapping is ambiguous" }
            matched = candidate
        }
        return requireNotNull(matched) { "MP4/camera timeline differs" }.also { validate(it, encodedUs) }
    }
}
