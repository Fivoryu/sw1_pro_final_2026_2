package com.example.captura_mobile.video

/** Preview timing only; never changes MP4 timestamps or image matching thresholds. */
internal class GuidanceSamplingPolicy {
    companion object {
        const val NORMAL_MS = 1000L
        const val SLOW_MS = 3000L
        // Preserve the existing 1500 ms scheduling allowance at either cadence.
        fun maximumGapMs(cadenceMs: Long): Long {
            require(cadenceMs == NORMAL_MS || cadenceMs == SLOW_MS)
            return cadenceMs + 1500L
        }
    }

    var delayMs = NORMAL_MS
        private set
    private var fastSamples = 0

    fun reset() { delayMs = NORMAL_MS; fastSamples = 0 }

    // Cadence is measured from copy start, not from analysis completion.
    fun remainingDelayMs(elapsedMs: Long): Long = (delayMs - elapsedMs).coerceAtLeast(0)

    fun completed(elapsedMs: Long) {
        require(elapsedMs >= 0)
        if (elapsedMs > 250) {
            delayMs = SLOW_MS
            fastSamples = 0
        } else if (++fastSamples >= 3) {
            // Hysteresis avoids oscillating after a single fast copy/analysis.
            reset()
        }
    }
}
