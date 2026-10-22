package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureRulesTest {

    @Test
    fun firstFloorPointIsAlwaysAccepted() {
        assertEquals(RuleCheck.Ok, CaptureRules.checkFloorPoint(floorY = null, hitY = -1.37))
    }

    @Test
    fun floorPointWithinToleranceIsAccepted() {
        assertEquals(RuleCheck.Ok, CaptureRules.checkFloorPoint(floorY = -1.40, hitY = -1.31))
        assertEquals(RuleCheck.Ok, CaptureRules.checkFloorPoint(floorY = -1.40, hitY = -1.50))
    }

    @Test
    fun floorPointOutsideToleranceIsRejectedWithMessage() {
        val check = CaptureRules.checkFloorPoint(floorY = -1.40, hitY = -1.20)
        assertTrue(check is RuleCheck.Rejected)
        assertTrue((check as RuleCheck.Rejected).message.contains("10 cm"))
    }

    @Test
    fun roomHeightInsideRangeIsAccepted() {
        assertEquals(RuleCheck.Ok, CaptureRules.checkRoomHeight(1.8))
        assertEquals(RuleCheck.Ok, CaptureRules.checkRoomHeight(2.6))
        assertEquals(RuleCheck.Ok, CaptureRules.checkRoomHeight(4.5))
    }

    @Test
    fun roomHeightOutsideRangeIsRejected() {
        assertTrue(CaptureRules.checkRoomHeight(1.79) is RuleCheck.Rejected)
        assertTrue(CaptureRules.checkRoomHeight(4.51) is RuleCheck.Rejected)
        assertTrue(CaptureRules.checkRoomHeight(Double.NaN) is RuleCheck.Rejected)
    }

    @Test
    fun boxHeightMustBeAboveTheFloor() {
        assertEquals(RuleCheck.Ok, CaptureRules.checkBoxHeight(0.75))
        assertTrue(CaptureRules.checkBoxHeight(0.01) is RuleCheck.Rejected)
        assertTrue(CaptureRules.checkBoxHeight(-0.3) is RuleCheck.Rejected)
        assertTrue(CaptureRules.checkBoxHeight(3.5) is RuleCheck.Rejected)
    }

    @Test
    fun finishRequiresThreeCorners() {
        assertTrue(CaptureRules.checkFinish(cornerCount = 2, allAnchorsTracking = true) is RuleCheck.Rejected)
        assertEquals(RuleCheck.Ok, CaptureRules.checkFinish(cornerCount = 3, allAnchorsTracking = true))
    }

    @Test
    fun finishRefusesWhenAnAnchorIsNotTracking() {
        val check = CaptureRules.checkFinish(cornerCount = 4, allAnchorsTracking = false)
        assertTrue(check is RuleCheck.Rejected)
    }

    @Test
    fun availabilityMapsArCoreNamesToContractStatuses() {
        assertEquals("supported", CaptureRules.availabilityStatus("SUPPORTED_INSTALLED"))
        assertEquals("supported_not_installed", CaptureRules.availabilityStatus("SUPPORTED_NOT_INSTALLED"))
        assertEquals("supported_not_installed", CaptureRules.availabilityStatus("SUPPORTED_APK_TOO_OLD"))
        assertEquals("unsupported", CaptureRules.availabilityStatus("UNSUPPORTED_DEVICE_NOT_CAPABLE"))
        assertEquals("unknown", CaptureRules.availabilityStatus("UNKNOWN_CHECKING"))
        assertEquals("unknown", CaptureRules.availabilityStatus("UNKNOWN_ERROR"))
        assertEquals("unknown", CaptureRules.availabilityStatus("UNKNOWN_TIMED_OUT"))
        assertEquals("unknown", CaptureRules.availabilityStatus("SOMETHING_NEW"))
    }

    @Test
    fun trackingGuidanceMapsFailureReasonsToSpanishMessages() {
        assertEquals("Seguimiento activo.", CaptureRules.trackingGuidance("TRACKING", "NONE"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "INSUFFICIENT_LIGHT").contains("luz"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "EXCESSIVE_MOTION").contains("despacio"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "INSUFFICIENT_FEATURES").contains("textura"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "CAMERA_UNAVAILABLE").contains("cámara"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "BAD_STATE").contains("reiniciá"))
        assertTrue(CaptureRules.trackingGuidance("PAUSED", "NONE").contains("Mové el teléfono despacio"))
        assertTrue(CaptureRules.trackingGuidance("STOPPED", "NONE").contains("detenido"))
    }

    @Test
    fun trackingLossCounterCountsOnlyTransitionsFromTracking() {
        val counter = TrackingLossCounter()
        counter.update(isTracking = false) // initial non-tracking state is not a loss
        counter.update(isTracking = true)
        counter.update(isTracking = false) // loss 1
        counter.update(isTracking = false)
        counter.update(isTracking = true)
        counter.update(isTracking = true)
        counter.update(isTracking = false) // loss 2
        assertEquals(2, counter.count)
    }

    @Test
    fun planeHitOutsideItsDetectedPolygonIsNotAMeasurement() {
        // ARCore also returns hits on the infinite extension of a plane: aiming at a
        // textureless wall 1 m away can "hit" the extended floor 10 m behind it.
        assertEquals(
            false,
            CaptureRules.isMeasurableHit(HitKind.PLANE, tracking = true, insidePolygon = false),
        )
        assertEquals(
            true,
            CaptureRules.isMeasurableHit(HitKind.PLANE, tracking = true, insidePolygon = true),
        )
    }

    @Test
    fun depthAndFeaturePointsCountOnlyWhileTracked() {
        assertEquals(true, CaptureRules.isMeasurableHit(HitKind.DEPTH_POINT, tracking = true, insidePolygon = false))
        assertEquals(true, CaptureRules.isMeasurableHit(HitKind.FEATURE_POINT, tracking = true, insidePolygon = false))
        assertEquals(false, CaptureRules.isMeasurableHit(HitKind.DEPTH_POINT, tracking = false, insidePolygon = false))
        assertEquals(false, CaptureRules.isMeasurableHit(HitKind.OTHER, tracking = true, insidePolygon = true))
    }

    @Test
    fun secondWallPointCloserThan30cmIsRejected() {
        val check = CaptureRules.checkWallPointSpacing(0.29)
        assertTrue(check is RuleCheck.Rejected)
        assertTrue((check as RuleCheck.Rejected).message.contains("30 cm"))
        assertEquals(RuleCheck.Ok, CaptureRules.checkWallPointSpacing(0.30))
        assertEquals(RuleCheck.Ok, CaptureRules.checkWallPointSpacing(1.2))
    }

    @Test
    fun wallFinishRequiresThreeCompleteWalls() {
        val check = CaptureRules.checkWallFinish(completeWalls = 2, pendingPoint = false, allAnchorsTracking = true)
        assertEquals(RuleCheck.Rejected("Marcá al menos 3 paredes antes de terminar."), check)
        assertEquals(
            RuleCheck.Ok,
            CaptureRules.checkWallFinish(completeWalls = 3, pendingPoint = false, allAnchorsTracking = true),
        )
    }

    @Test
    fun wallFinishRefusesAPendingHalfWall() {
        val check = CaptureRules.checkWallFinish(completeWalls = 4, pendingPoint = true, allAnchorsTracking = true)
        assertEquals(
            RuleCheck.Rejected("Falta el segundo punto de la última pared: marcalo o tocá «Deshacer»."),
            check,
        )
    }

    @Test
    fun wallFinishRefusesWhenAnAnchorIsNotTracking() {
        val check = CaptureRules.checkWallFinish(completeWalls = 4, pendingPoint = false, allAnchorsTracking = false)
        assertTrue(check is RuleCheck.Rejected)
        assertTrue((check as RuleCheck.Rejected).message.contains("seguimiento"))
    }
}
