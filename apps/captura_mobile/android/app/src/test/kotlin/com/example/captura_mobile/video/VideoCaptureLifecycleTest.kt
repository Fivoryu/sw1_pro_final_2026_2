package com.example.captura_mobile.video

import org.junit.Assert.*
import org.junit.Test

/** Tests the production lifecycle gate; Android/Camera2 callback dispatch still needs device QA. */
class VideoCaptureLifecycleTest {
    @Test fun previewBackgroundReturnThenRecordingStillAllowsReferenceConfirmation() {
        val state = VideoCaptureForeground()
        state.resume()
        assertTrue(state.canGuide(true, true))
        state.pause()
        state.stop(recording = false)
        assertFalse(state.canGuide(true, true))
        assertFalse(state.canConfirmReference)
        state.resume()
        assertTrue(state.canGuide(true, true))
        state.recordingStarted()
        assertTrue(state.canConfirmReference)
    }

    @Test fun uninterruptedRecordingKeepsTheExistingReferenceFlow() {
        val state = VideoCaptureForeground()
        state.resume()
        state.recordingStarted()
        assertTrue(state.canConfirmReference)
    }

    @Test fun backgroundDuringRecordingFinalizesWithoutReopeningReferenceAfterReturn() {
        val state = VideoCaptureForeground()
        state.resume()
        state.recordingStarted()
        state.pause()
        state.stop(recording = true)
        assertEquals(CaptureRecovery.StopAction.FINALIZE, CaptureRecovery.onBackground(true, false, false))
        assertFalse(state.canConfirmReference)
        state.resume() // Encoder stop may still be completing.
        assertFalse(state.canConfirmReference)
        assertFalse(state.canGuide(true, false)) // FINISHING is not a preview/recording phase.
    }

    @Test fun pauseAloneBlocksAsyncReferenceUiBeforeOnStop() {
        val state = VideoCaptureForeground()
        state.resume()
        state.recordingStarted()
        state.pause()
        assertFalse(state.canConfirmReference)
        assertFalse(state.canGuide(true, true))
    }

    @Test fun previewReadyWhilePausedCanBeUsedOnResumeWithoutAnotherCameraCallback() {
        val state = VideoCaptureForeground()
        state.resume()
        assertFalse(state.canGuide(false, true))
        state.pause()
        assertFalse(state.canGuide(true, true))
        state.resume()
        assertTrue(state.canGuide(true, true))
        assertFalse(state.canGuide(true, false)) // MARKING, FINISHING and DONE.
    }

    @Test fun delayedRecordingStartInBackgroundRetainsInterruptedStatusAfterReturn() {
        val state = VideoCaptureForeground()
        state.resume()
        state.stop(recording = false) // Start callback was still pending in PREVIEW.
        state.recordingStarted()
        assertFalse(state.canConfirmReference)
        state.resume()
        assertFalse(state.canConfirmReference)
    }

    @Test fun markingInBackgroundRetainsTheExistingPackageRecoveryDecision() {
        val state = VideoCaptureForeground()
        state.resume()
        state.recordingStarted()
        state.pause()
        state.stop(recording = false)
        assertFalse(state.canConfirmReference)
        assertEquals(CaptureRecovery.StopAction.PACKAGE_FINALIZED, CaptureRecovery.onBackground(false, true, true))
        assertEquals(CaptureRecovery.StopAction.PRESERVE, CaptureRecovery.onBackground(false, true, false))
    }
}
