package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class KeyframeSelectorTest {

    private fun yaw(deg: Double): DoubleArray {
        val half = Math.toRadians(deg) / 2
        return doubleArrayOf(0.0, sin(half), 0.0, cos(half))
    }

    private fun pose(x: Double = 0.0, z: Double = 0.0, yawDeg: Double = 0.0, y: Double = 0.0): CameraPose {
        val q = yaw(yawDeg)
        return CameraPose(x, y, z, q[0], q[1], q[2], q[3])
    }

    @Test
    fun firstTrackedSampleIsAKeyframe() {
        val selector = KeyframeSelector()
        assertTrue(selector.offer(1_000, tracking = true, pose = pose()))
        assertEquals(1, selector.count)
    }

    @Test
    fun nothingIsSelectedWithoutTracking() {
        val selector = KeyframeSelector()
        assertFalse(selector.offer(1_000, tracking = false, pose = pose()))
        assertEquals(0, selector.count)
        // A rejected untracked sample must not become the reference for the next one.
        assertTrue(selector.offer(1_100, tracking = true, pose = pose()))
    }

    @Test
    fun needsHalfASecondAndEnoughMovement() {
        val selector = KeyframeSelector()
        assertTrue(selector.offer(0, true, pose()))
        // Moved far enough but too soon.
        assertFalse(selector.offer(499, true, pose(x = 1.0)))
        // Late enough but barely moved.
        assertFalse(selector.offer(600, true, pose(x = 0.2)))
        // Both conditions: 0.25 m exactly counts.
        assertTrue(selector.offer(600, true, pose(x = 0.25)))
        assertEquals(2, selector.count)
    }

    @Test
    fun movementCountsAllThreeAxes() {
        val selector = KeyframeSelector()
        assertTrue(selector.offer(0, true, pose()))
        assertTrue(selector.offer(500, true, pose(y = 0.25)))
    }

    @Test
    fun rotationOfFifteenDegreesIsEnoughWithoutMoving() {
        val selector = KeyframeSelector()
        assertTrue(selector.offer(0, true, pose()))
        assertFalse(selector.offer(600, true, pose(yawDeg = 14.0)))
        assertTrue(selector.offer(700, true, pose(yawDeg = 15.0)))
    }

    @Test
    fun rotationIsMeasuredAgainstTheLastKeyframeNotTheLastSample() {
        val selector = KeyframeSelector()
        assertTrue(selector.offer(0, true, pose()))
        assertFalse(selector.offer(600, true, pose(yawDeg = 10.0)))
        // 10 deg then 20 deg: the reference is still the keyframe at 0 deg.
        assertTrue(selector.offer(700, true, pose(yawDeg = 20.0)))
    }

    @Test
    fun oppositeQuaternionSignsAreTheSameRotation() {
        val selector = KeyframeSelector()
        val q = yaw(0.0)
        assertTrue(selector.offer(0, true, CameraPose(0.0, 0.0, 0.0, q[0], q[1], q[2], q[3])))
        assertFalse(selector.offer(600, true, CameraPose(0.0, 0.0, 0.0, -q[0], -q[1], -q[2], -q[3])))
    }

    @Test
    fun neverMoreThanSixHundredKeyframes() {
        val selector = KeyframeSelector()
        var accepted = 0
        for (i in 0 until 700) {
            if (selector.offer(i * 1_000L, true, pose(x = i * 1.0))) accepted++
        }
        assertEquals(600, accepted)
        assertEquals(600, selector.count)
    }
}
