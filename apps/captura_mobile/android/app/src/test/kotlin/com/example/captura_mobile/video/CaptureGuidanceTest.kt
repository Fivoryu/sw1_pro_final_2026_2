package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CaptureGuidanceTest {

    private val sec = 1_000_000_000L

    /** Feeds a constant gyro rate [wz] (rad/s about the gravity axis) for [seconds] at 100 Hz; returns the last timestamp. */
    private fun CaptureGuidance.spin(fromNs: Long, seconds: Double, wz: Float): Long {
        var t = fromNs
        repeat((seconds * 100).toInt()) {
            t += 10_000_000L
            onGyro(t, 0f, 0f, wz)
        }
        return t
    }

    private fun guidance() = CaptureGuidance().also { it.onGravity(0f, 0f, 9.81f) }

    @Test
    fun `calm recording has no hint`() {
        val g = guidance()
        val end = g.spin(0, 5.0, 0.1f)
        assertNull(g.current(end))
    }

    @Test
    fun `sustained fast turning asks to slow down`() {
        val g = guidance()
        val end = g.spin(0, 3.0, GuidanceThresholds.FAST_TURN_RAD_S + 0.3f)
        assertEquals(GuidanceHint.SLOW_DOWN, g.current(end))
    }

    @Test
    fun `an abrupt movement outranks a fast turn`() {
        val g = guidance()
        val end = g.spin(0, 2.0, GuidanceThresholds.ABRUPT_RAD_S + 1f)
        assertEquals(GuidanceHint.ABRUPT_MOVEMENT, g.current(end))
    }

    @Test
    fun `a hint is held after the condition ends and then clears`() {
        val g = guidance()
        val end = g.spin(0, 2.0, GuidanceThresholds.ABRUPT_RAD_S + 1f)
        val abruptEnd = end
        g.spin(end, 10.0, 0.05f)
        assertEquals(GuidanceHint.ABRUPT_MOVEMENT, g.current(abruptEnd + GuidanceThresholds.HOLD_NS / 2))
        assertNull(g.current(abruptEnd + 10 * sec))
    }

    @Test
    fun `high ISO for several consecutive captures means low light`() {
        val g = guidance()
        var t = 0L
        repeat(GuidanceThresholds.LOW_LIGHT_CAPTURES) {
            t += 33_000_000L
            g.onExposure(t, GuidanceThresholds.LOW_LIGHT_ISO)
        }
        assertEquals(GuidanceHint.LOW_LIGHT, g.current(t))
        assertNull(g.current(t + 2 * GuidanceThresholds.HOLD_NS))
    }

    @Test
    fun `one dark capture is not enough and a bright capture resets the count`() {
        val g = guidance()
        var t = 0L
        repeat(GuidanceThresholds.LOW_LIGHT_CAPTURES - 1) {
            t += 33_000_000L
            g.onExposure(t, GuidanceThresholds.LOW_LIGHT_ISO)
        }
        t += 33_000_000L
        g.onExposure(t, 100)
        t += 33_000_000L
        g.onExposure(t, GuidanceThresholds.LOW_LIGHT_ISO)
        assertNull(g.current(t))
    }

    @Test
    fun `turning a full circle after enough time suggests closing the loop`() {
        val g = guidance()
        // 0.5 rad/s for 2*pi/0.5 s is one whole turn, preceded by 60 s of standing still.
        val still = g.spin(0, 60.0, 0f)
        val end = g.spin(still, 2 * Math.PI / 0.5, 0.5f)
        assertEquals(GuidanceHint.CLOSE_LOOP, g.current(end))
    }

    @Test
    fun `no loop suggestion before the minimum elapsed time`() {
        val g = guidance()
        val end = g.spin(0, 2 * Math.PI / 0.5, 0.5f)
        assertNull(g.current(end))
    }

    @Test
    fun `a half turn is not a closed loop`() {
        val g = guidance()
        val still = g.spin(0, 60.0, 0f)
        val end = g.spin(still, Math.PI / 0.5, 0.5f)
        assertNull(g.current(end))
    }

    @Test
    fun `rotation about a horizontal axis does not count as heading change`() {
        val g = guidance()
        var t = 0L
        repeat(8000) {
            t += 10_000_000L
            g.onGyro(t, 0.5f, 0f, 0f)
        }
        assertNull(g.current(t))
    }

    @Test
    fun `without gravity the gyro is ignored instead of guessing`() {
        val g = CaptureGuidance()
        val end = g.spin(0, 3.0, 5f)
        assertNull(g.current(end))
    }
}
