package com.example.captura_mobile.ar

/**
 * Tracking state as the buttons should show it. ARCore can flip between TRACKING and
 * PAUSED several times per second while it starts or on poor texture; mirroring that
 * makes the buttons blink. The shown state changes only after the raw state held for a
 * while. Actions still check the real per-frame state when they run, so this never lets
 * a measurement through without tracking.
 */
class TrackingDebouncer(
    private val enableAfterMs: Long = 500,
    private val disableAfterMs: Long = 700,
) {
    private var shown = false
    private var candidate = false
    private var candidateSinceMs = 0L

    fun update(tracking: Boolean, nowMs: Long): Boolean {
        if (tracking != candidate) {
            candidate = tracking
            candidateSinceMs = nowMs
        }
        if (candidate != shown) {
            val holdMs = if (candidate) enableAfterMs else disableAfterMs
            if (nowMs - candidateSinceMs >= holdMs) shown = candidate
        }
        return shown
    }
}
