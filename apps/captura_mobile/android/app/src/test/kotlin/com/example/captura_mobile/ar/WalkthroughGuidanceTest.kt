package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WalkthroughGuidanceTest {

    private fun wall(x1: Double, z1: Double, x2: Double, z2: Double) =
        WallSegment(Corner2(x1, z1), Corner2(x2, z2), area = 1.0, minY = 0.0, maxY = 2.5)

    /** Four walls of a 4 x 4 room centred at the origin. */
    private val squareRoom = listOf(
        wall(-2.0, -2.0, 2.0, -2.0),
        wall(2.0, -2.0, 2.0, 2.0),
        wall(2.0, 2.0, -2.0, 2.0),
        wall(-2.0, 2.0, -2.0, -2.0),
    )

    private val centre = Corner2(0.0, 0.0)

    private fun input(
        trackingState: String = "TRACKING",
        failureReason: String = "NONE",
        recording: Boolean = true,
        floorFound: Boolean = true,
        speed: Double? = 0.3,
        yawRate: Double? = 10.0,
        light: Double? = 0.5,
        coverage: Coverage = Coverage.EMPTY,
        heading: Double = 0.0,
    ) = GuidanceInput(trackingState, failureReason, recording, floorFound, speed, yawRate, light, coverage, heading)

    // region Coverage

    @Test
    fun `a closed room covers every sector`() {
        val coverage = WalkthroughCoverage.compute(squareRoom, centre)
        assertEquals(1.0, coverage.fraction, 1e-9)
        assertTrue(coverage.sectors.all { it })
    }

    @Test
    fun `no walls means no coverage`() {
        val coverage = WalkthroughCoverage.compute(emptyList(), centre)
        assertEquals(0.0, coverage.fraction, 1e-9)
    }

    @Test
    fun `one wall covers only the sectors it faces`() {
        // Wall in front of +x: bearings between -45 and +45 degrees.
        val coverage = WalkthroughCoverage.compute(listOf(wall(2.0, -2.0, 2.0, 2.0)), centre)
        assertEquals(3.0 / WalkthroughCoverage.SECTOR_COUNT, coverage.fraction, 1e-9)
        assertTrue(coverage.sectors[0])
        assertFalse(coverage.sectors[6])
    }

    @Test
    fun `a wall across the bearing wrap still covers its sectors`() {
        // Wall on -x spans bearings 135..225 degrees, crossing +180.
        val coverage = WalkthroughCoverage.compute(listOf(wall(-2.0, 2.0, -2.0, -2.0)), centre)
        assertEquals(3.0 / WalkthroughCoverage.SECTOR_COUNT, coverage.fraction, 1e-9)
        assertTrue(coverage.sectors[6])
    }

    @Test
    fun `missing side is reported relative to the camera heading`() {
        // Only the +x wall is seen. Facing -z (bearing -90), the gap is right in front of the user.
        val coverage = WalkthroughCoverage.compute(listOf(wall(2.0, -2.0, 2.0, 2.0)), centre)
        val headingMinusZ = Math.toRadians(-90.0)
        assertEquals(MissingSide.AHEAD, WalkthroughCoverage.missingSide(coverage, headingMinusZ))
        // Facing +x the covered wall is ahead; the nearest gap is beside the user, not behind.
        val side = WalkthroughCoverage.missingSide(coverage, 0.0)
        assertTrue(side == MissingSide.LEFT || side == MissingSide.RIGHT)
    }

    @Test
    fun `relative side follows ARCore axes`() {
        // ARCore: +x is right of a camera looking down -z.
        val headingMinusZ = Math.toRadians(-90.0)
        assertEquals(MissingSide.RIGHT, WalkthroughCoverage.sideOf(0.0, headingMinusZ))
        assertEquals(MissingSide.LEFT, WalkthroughCoverage.sideOf(Math.PI, headingMinusZ))
        assertEquals(MissingSide.BEHIND, WalkthroughCoverage.sideOf(Math.toRadians(90.0), headingMinusZ))
        assertEquals(MissingSide.AHEAD, WalkthroughCoverage.sideOf(Math.toRadians(-90.0), headingMinusZ))
    }

    @Test
    fun `full coverage has no missing side`() {
        val coverage = WalkthroughCoverage.compute(squareRoom, centre)
        assertNull(WalkthroughCoverage.missingSide(coverage, 0.0))
    }

    // endregion

    // region Cues

    @Test
    fun `stopped tracking wins over everything`() {
        val guidance = WalkthroughGuidance.evaluate(input(trackingState = "STOPPED", speed = 3.0))
        assertEquals(GuidanceCue.STOPPED, guidance.cue)
    }

    @Test
    fun `lost tracking keeps what was captured`() {
        val guidance = WalkthroughGuidance.evaluate(input(trackingState = "PAUSED", failureReason = "NONE"))
        assertEquals(GuidanceCue.TRACKING_LOST, guidance.cue)
        assertTrue(guidance.message.contains("se conserva"))
    }

    @Test
    fun `paused tracking names its cause`() {
        assertEquals(
            GuidanceCue.LOW_LIGHT,
            WalkthroughGuidance.evaluate(input(trackingState = "PAUSED", failureReason = "INSUFFICIENT_LIGHT")).cue,
        )
        assertEquals(
            GuidanceCue.TOO_FAST,
            WalkthroughGuidance.evaluate(input(trackingState = "PAUSED", failureReason = "EXCESSIVE_MOTION")).cue,
        )
        assertEquals(
            GuidanceCue.LOW_TEXTURE,
            WalkthroughGuidance.evaluate(input(trackingState = "PAUSED", failureReason = "INSUFFICIENT_FEATURES")).cue,
        )
    }

    @Test
    fun `before recording without floor asks to point at the floor`() {
        val guidance = WalkthroughGuidance.evaluate(input(recording = false, floorFound = false))
        assertEquals(GuidanceCue.NO_FLOOR, guidance.cue)
    }

    @Test
    fun `before recording with floor invites to start`() {
        val guidance = WalkthroughGuidance.evaluate(input(recording = false, floorFound = true))
        assertEquals(GuidanceCue.READY, guidance.cue)
    }

    @Test
    fun `walking or turning too fast slows the user down`() {
        assertEquals(GuidanceCue.TOO_FAST, WalkthroughGuidance.evaluate(input(speed = 1.5)).cue)
        assertEquals(GuidanceCue.TOO_FAST, WalkthroughGuidance.evaluate(input(yawRate = 150.0)).cue)
        assertEquals(GuidanceCue.MISSING_SIDE, WalkthroughGuidance.evaluate(input(speed = null, yawRate = null)).cue)
    }

    @Test
    fun `dim light warns before tracking fails`() {
        assertEquals(GuidanceCue.LOW_LIGHT, WalkthroughGuidance.evaluate(input(light = 0.05)).cue)
        assertEquals(GuidanceCue.MISSING_SIDE, WalkthroughGuidance.evaluate(input(light = null)).cue)
    }

    @Test
    fun `missing coverage points to the gap`() {
        val coverage = WalkthroughCoverage.compute(listOf(wall(2.0, -2.0, 2.0, 2.0)), centre)
        val guidance = WalkthroughGuidance.evaluate(input(coverage = coverage, heading = Math.toRadians(-90.0)))
        assertEquals(GuidanceCue.MISSING_SIDE, guidance.cue)
        assertTrue(guidance.message.contains("adelante"))
    }

    @Test
    fun `full coverage invites to finish`() {
        val coverage = WalkthroughCoverage.compute(squareRoom, centre)
        val guidance = WalkthroughGuidance.evaluate(input(coverage = coverage))
        assertEquals(GuidanceCue.COMPLETE, guidance.cue)
        assertTrue(guidance.message.contains("Terminar recorrido"))
    }

    // endregion

    // region Motion

    @Test
    fun `motion meter reports speed and yaw rate over its window`() {
        val meter = MotionMeter(windowMs = 500)
        assertNull(meter.offer(0L, 0.0, 0.0, 0.0))
        val sample = meter.offer(500L, 0.5, 0.0, Math.toRadians(45.0))!!
        assertEquals(1.0, sample.speed, 1e-9)
        assertEquals(90.0, sample.yawRateDeg, 1e-9)
    }

    @Test
    fun `motion meter handles yaw wrap`() {
        val meter = MotionMeter(windowMs = 500)
        meter.offer(0L, 0.0, 0.0, Math.toRadians(179.0))
        val sample = meter.offer(500L, 0.0, 0.0, Math.toRadians(-179.0))!!
        assertEquals(4.0, sample.yawRateDeg, 1e-6)
    }

    // endregion

    // region Announcer

    @Test
    fun `a cue is announced once it is stable`() {
        val announcer = GuidanceAnnouncer(stableMs = 1000, repeatMs = 8000)
        assertNull(announcer.offer(GuidanceCue.TOO_FAST, 0L))
        assertNull(announcer.offer(GuidanceCue.TOO_FAST, 500L))
        assertEquals(GuidanceCue.TOO_FAST, announcer.offer(GuidanceCue.TOO_FAST, 1000L))
        assertNull(announcer.offer(GuidanceCue.TOO_FAST, 2000L))
    }

    @Test
    fun `a flickering cue is not announced`() {
        val announcer = GuidanceAnnouncer(stableMs = 1000, repeatMs = 8000)
        announcer.offer(GuidanceCue.TOO_FAST, 0L)
        announcer.offer(GuidanceCue.MISSING_SIDE, 600L)
        assertNull(announcer.offer(GuidanceCue.TOO_FAST, 1200L))
    }

    @Test
    fun `a persisting cue repeats after the repeat interval`() {
        val announcer = GuidanceAnnouncer(stableMs = 1000, repeatMs = 8000)
        announcer.offer(GuidanceCue.LOW_LIGHT, 0L)
        assertEquals(GuidanceCue.LOW_LIGHT, announcer.offer(GuidanceCue.LOW_LIGHT, 1000L))
        assertNull(announcer.offer(GuidanceCue.LOW_LIGHT, 8000L))
        assertEquals(GuidanceCue.LOW_LIGHT, announcer.offer(GuidanceCue.LOW_LIGHT, 9000L))
    }

    @Test
    fun `quiet cues are never spoken`() {
        val announcer = GuidanceAnnouncer(stableMs = 0, repeatMs = 8000)
        assertNull(announcer.offer(GuidanceCue.READY, 0L))
        assertNull(announcer.offer(GuidanceCue.READY, 5000L))
    }

    // endregion

    // region Minimap

    @Test
    fun `minimap fits the room inside the box keeping proportions`() {
        val points = listOf(Corner2(-2.0, -1.0), Corner2(2.0, 1.0))
        val projection = MinimapProjection.fit(points, sizePx = 100f, paddingPx = 10f)!!
        val a = projection.map(Corner2(-2.0, -1.0))
        val b = projection.map(Corner2(2.0, 1.0))
        assertEquals(10f, a.x, 1e-4f)
        assertEquals(90f, b.x, 1e-4f)
        // 4 m wide and 2 m deep: the depth uses half the width, centred vertically.
        assertEquals(40f, b.y - a.y, 1e-4f)
        assertEquals(50f, (a.y + b.y) / 2f, 1e-4f)
    }

    @Test
    fun `minimap needs at least one point`() {
        assertNull(MinimapProjection.fit(emptyList(), sizePx = 100f, paddingPx = 10f))
    }

    // endregion
}
