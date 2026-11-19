package com.example.captura_mobile.video

import org.junit.Assert.*
import org.junit.Test

class GuidanceCopyGateTest {
    @Test fun missingCallbackTimesOutAndAllowsOneBoundedRecoveryCopy() {
        val gate = GuidanceCopyGate()
        val stalled = checkNotNull(gate.begin(1000))
        assertTrue(gate.copying)
        assertNull(gate.begin(1500))
        assertFalse(gate.expire(stalled, 2999))
        assertTrue(gate.expire(stalled, 3000))
        assertFalse(gate.copying)
        assertTrue(gate.owns(stalled)) // Native destination must not be recycled on timeout.
        val recovery = checkNotNull(gate.begin(3000))
        assertEquals(2, gate.pendingCount)
        assertTrue(gate.finish(recovery, 3500))
        assertEquals(1, gate.pendingCount)
    }

    @Test fun lateCallbackCannotClearNewRequestOwnershipOrApplyExpiredPixels() {
        val gate = GuidanceCopyGate()
        val old = checkNotNull(gate.begin(0))
        assertTrue(gate.expire(old, 2000))
        val current = checkNotNull(gate.begin(2100))
        assertFalse(gate.finish(old, 2200))
        assertTrue(gate.copying)
        assertNull(gate.begin(2300))
        assertTrue(gate.finish(current, 2500))
        assertFalse(gate.copying)
        assertFalse(gate.owns(old))
        assertFalse(gate.finish(old, 2600)) // A duplicate completion has no ownership.
    }

    @Test fun twoPermanentStallsNeverAllocateUnboundedReplacementDestinations() {
        val gate = GuidanceCopyGate()
        val first = checkNotNull(gate.begin(0))
        gate.expire(first, 2000)
        val second = checkNotNull(gate.begin(2100))
        gate.expire(second, 4100)
        repeat(10) { assertNull(gate.begin(5000L + it * 1000)) }
        assertEquals(2, gate.pendingCount)
        assertFalse(gate.copying)
        assertFalse(gate.finish(first, 20000))
        assertNotNull(gate.begin(21000)) // A late native callback safely restores capacity.
    }

    @Test fun delayedWatchdogDoesNotMakeAnExpiredCallbackTimely() {
        val gate = GuidanceCopyGate()
        val ticket = checkNotNull(gate.begin(0))
        assertFalse(gate.finish(ticket, 2001))
        assertEquals(0, gate.pendingCount)
        assertNotNull(gate.begin(3000))
    }

    @Test fun closeRejectsFeedbackAndNewCopiesButRetainsLateCallbackCleanupOwnership() {
        val gate = GuidanceCopyGate()
        val ticket = checkNotNull(gate.begin(0))
        gate.close()
        assertNull(gate.begin(1))
        assertTrue(gate.owns(ticket))
        assertFalse(gate.finish(ticket, 100))
        assertEquals(0, gate.pendingCount)
    }
}
