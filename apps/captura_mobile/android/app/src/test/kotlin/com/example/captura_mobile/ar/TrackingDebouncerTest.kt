package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Test

class TrackingDebouncerTest {

    @Test
    fun startsWithoutTracking() {
        val debouncer = TrackingDebouncer()
        assertEquals(false, debouncer.update(tracking = false, nowMs = 0))
    }

    @Test
    fun enablesOnlyAfterTrackingHoldsSteady() {
        val debouncer = TrackingDebouncer()
        assertEquals(false, debouncer.update(tracking = true, nowMs = 0))
        assertEquals(false, debouncer.update(tracking = true, nowMs = 400))
        assertEquals(true, debouncer.update(tracking = true, nowMs = 500))
    }

    @Test
    fun flickeringTrackingNeverTogglesTheButtons() {
        val debouncer = TrackingDebouncer()
        var now = 0L
        val shown = mutableListOf<Boolean>()
        repeat(40) { index ->
            shown += debouncer.update(tracking = index % 2 == 0, nowMs = now)
            now += 100
        }
        assertEquals(setOf(false), shown.toSet())
    }

    @Test
    fun aBriefLossKeepsTheButtonsEnabled() {
        val debouncer = TrackingDebouncer()
        debouncer.update(tracking = true, nowMs = 0)
        assertEquals(true, debouncer.update(tracking = true, nowMs = 600))
        assertEquals(true, debouncer.update(tracking = false, nowMs = 700))
        assertEquals(true, debouncer.update(tracking = false, nowMs = 1300))
        assertEquals(true, debouncer.update(tracking = true, nowMs = 1350))
        assertEquals(true, debouncer.update(tracking = false, nowMs = 1400))
    }

    @Test
    fun aSustainedLossDisablesTheButtons() {
        val debouncer = TrackingDebouncer()
        debouncer.update(tracking = true, nowMs = 0)
        debouncer.update(tracking = true, nowMs = 600)
        debouncer.update(tracking = false, nowMs = 700)
        assertEquals(false, debouncer.update(tracking = false, nowMs = 1400))
    }
}
