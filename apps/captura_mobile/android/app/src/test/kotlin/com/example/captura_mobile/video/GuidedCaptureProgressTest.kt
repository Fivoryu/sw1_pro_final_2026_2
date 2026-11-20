package com.example.captura_mobile.video

import org.junit.Assert.*
import org.junit.Test

class GuidedCaptureProgressTest {
    private fun observation(sample: Int, changes: Int = 0, stable: Boolean = false,
                            issue: VisualIssue = VisualIssue.NONE) = VisualFeedback(
        VisualState.NOT_VERIFIABLE, "quality warning", changedComparisons = changes,
        samples = sample, imageStable = stable, localMatching = issue == VisualIssue.NONE,
        imageChanged = !stable && changes > 0, issue = issue,
    )
    private fun wall() = GuidedCaptureProgress().apply { reset(firstRoom = false) }
    private fun moving() = wall().apply { confirm(revision) }

    @Test fun stableFramesOnlyCompleteImageStabilizationNotReferenceConfirmation() {
        val p = GuidedCaptureProgress()
        p.observe(observation(1, stable = true), referenceCandidate = true)
        assertEquals(0, p.step)
        p.observe(observation(2, stable = true), referenceCandidate = true)
        assertEquals(1, p.step)
        assertEquals(GuidanceProgressState.VISUALLY_SUFFICIENT, p.state)
        assertEquals(0, p.manualSteps)
        repeat(20) { p.observe(observation(it + 3, stable = true)) }
        assertEquals(1, p.step)
        assertTrue(p.summary().contains("no aplica escala"))
    }

    @Test fun missingReferenceNeverRequestsAnObjectOrCreatesACandidate() {
        val p = GuidedCaptureProgress().apply { reset(wantsReference = false) }
        assertFalse(p.instruction().contains("objeto"))
        p.observe(observation(1, stable = true), referenceCandidate = true)
        assertFalse(p.referenceCandidate)
        p.observe(observation(2, stable = true))
        assertEquals(1, p.step)
        assertTrue(p.summary().contains("Sin referencia solicitada"))
    }

    @Test fun stableTextureWithoutReferenceCandidateNeverAdvancesReferenceStep() {
        val p = GuidedCaptureProgress()
        repeat(20) { p.observe(observation(it + 1, stable = true)) }
        assertTrue(p.stableFraming)
        assertTrue(p.visualContinuity)
        assertFalse(p.referenceCandidate)
        assertEquals(0, p.step)
        assertEquals(0, p.manualSteps)
        assertNotEquals(GuidanceProgressState.VISUALLY_SUFFICIENT, p.state)
        assertTrue(p.instruction().contains("Sin candidato"))
    }

    @Test fun candidateMustBePresentInBothConsecutiveStableSamples() {
        val p = GuidedCaptureProgress()
        p.observe(observation(1, stable = true), referenceCandidate = true)
        p.observe(observation(2, stable = true), referenceCandidate = false)
        p.observe(observation(3, stable = true), referenceCandidate = true)
        assertEquals(0, p.step)
        p.observe(observation(4, stable = true), referenceCandidate = true)
        assertEquals(1, p.step)
        assertTrue(p.summary().contains("no confirmado en el MP4"))
    }

    @Test fun manualReferenceFallbackNeverConfirmsObjectOrDimensions() {
        val p = GuidedCaptureProgress()
        val revision = p.revision
        assertTrue(checkNotNull(p.confirmation()).contains("sin verificar"))
        p.confirm(revision); p.confirm(revision)
        assertEquals(1, p.step)
        assertEquals(1, p.manualSteps)
        assertTrue(p.referenceContinuedManually)
        assertFalse(p.referenceCandidate)
        assertFalse(p.visualContinuity)
        assertEquals("Declarado por vos · no verificado", p.state.label)
        repeat(3) { p.observe(observation(it + 1, stable = true)) }
        assertTrue(checkNotNull(p.qualityWarning()).contains("Referencia no verificada"))
        assertTrue(p.summary().contains("continuación manual"))
        assertTrue(p.summary().contains("no aplica escala"))
    }

    @Test fun sameWallMotionNeverConfirmsAWall() {
        val p = wall()
        repeat(12) { p.observe(observation(it + 1, it + 1)) }
        assertEquals(1, p.step)
        assertEquals(0, p.manualSteps)
    }

    @Test fun localChangeCompletesOnlyContinuityThenWaitsForHumanCornerConfirmation() {
        val p = moving()
        p.observe(observation(1, 1))
        assertEquals(2, p.step)
        p.observe(observation(2, 2))
        assertEquals(3, p.step)
        assertEquals(GuidanceProgressState.VISUALLY_SUFFICIENT, p.state)
        repeat(12) { p.observe(observation(it + 3, it + 3)) }
        assertEquals(3, p.step)
        assertEquals(1, p.manualSteps)
        assertEquals("Veo esquina y pared contigua", p.confirmation())
    }

    @Test fun rotationCannotConfirmCornerEvenWhenItProducesMatchedImageChanges() {
        val p = moving()
        repeat(12) { p.observe(observation(it + 1, it + 1)) }
        assertEquals(3, p.step)
        assertEquals(1, p.manualSteps)
        assertTrue(p.summary().contains("Sin paredes ni esquinas detectadas"))
    }

    @Test fun staticMatchingNeverCompletesMovement() {
        val p = moving()
        repeat(20) { p.observe(observation(it + 1, stable = true)) }
        assertEquals(2, p.step)
        assertNull(p.confirmation())
    }

    @Test fun repeatedFeedbackAndHistoricalCounterCannotSupplyTwoNewChanges() {
        val p = moving()
        repeat(20) { p.observe(observation(1, 100)) }
        assertEquals(2, p.step)
        p.observe(observation(2, 100))
        assertEquals(2, p.step)
        p.observe(observation(3, 101))
        assertEquals(2, p.step)
        p.observe(observation(4, 102))
        assertEquals(3, p.step)
    }

    @Test fun badQualityAndOcclusionBreakConsecutiveEvidence() {
        val p = moving()
        p.observe(observation(1, 1))
        p.observe(observation(2, 2, issue = VisualIssue.LOW_MATCHES))
        assertEquals(GuidanceProgressState.NEEDS_IMPROVEMENT, p.state)
        p.markHidden()
        p.observe(observation(3, 3))
        assertEquals(2, p.step)
        p.observe(observation(4, 4))
        assertEquals(3, p.step)
        assertEquals(1, p.hiddenAreas)
        assertTrue(checkNotNull(p.qualityWarning()).contains("Muebles"))
    }

    @Test fun blindConfirmationCannotCreateVisualEvidenceOrSkipAutomaticStep() {
        val p = wall()
        p.confirm(p.revision)
        assertEquals(GuidanceProgressState.MANUALLY_CONFIRMED, p.state)
        assertFalse(p.stableFraming)
        assertFalse(p.visualContinuity)
        assertEquals(2, p.step)
        repeat(10) { p.confirm(p.revision) }
        assertEquals(2, p.step)
        assertEquals(1, p.manualSteps)
        assertEquals(1, p.unverifiedDeclarations)
        assertTrue(checkNotNull(p.qualityWarning()).contains("sin imagen suficiente"))
        p.observe(observation(1, stable = true))
        assertTrue(checkNotNull(p.qualityWarning()).contains("sin imagen suficiente"))
        assertTrue(p.summary().contains("1 declaraciones sin imagen suficiente"))
    }

    @Test fun duplicateConfirmationAndOldRoomControlCannotAdvance() {
        val p = wall()
        val revision = p.revision
        p.confirm(revision)
        p.confirm(revision)
        assertEquals(2, p.step)
        p.reset(firstRoom = false)
        p.confirm(revision)
        assertEquals(1, p.step)
        assertEquals(0, p.manualSteps)
    }

    @Test fun roomTransitionClearsQualityMovementAndHiddenAreaState() {
        val p = moving()
        p.observe(observation(50, 50), referenceCandidate = true)
        p.markHidden()
        p.reset(firstRoom = false)
        assertEquals(GuidanceProgressState.PENDING, p.state)
        assertEquals(1, p.step)
        assertEquals(0, p.hiddenAreas)
        assertFalse(p.visualContinuity)
        assertFalse(p.referenceCandidate)
        assertEquals(0, p.unverifiedDeclarations)
        assertFalse(p.referenceContinuedManually)
        p.observe(observation(1, stable = true))
        assertTrue(p.stableFraming)
        assertEquals(1, p.step)
    }

    @Test fun pauseClearsCurrentEvidenceAndRequiresNewConsecutiveSamples() {
        val p = moving()
        p.observe(observation(1, 1))
        val oldRevision = p.revision
        p.invalidateObservation()
        assertEquals(GuidanceProgressState.PENDING, p.state)
        assertFalse(p.visualContinuity)
        p.confirm(oldRevision)
        p.observe(observation(2, 2))
        assertEquals(2, p.step)
        p.observe(observation(3, 3))
        assertEquals(3, p.step)
    }

    @Test fun staleSampleNeverRestoresSufficientQuality() {
        val p = wall()
        p.observe(observation(2, stable = true))
        p.observe(observation(1, stable = true, issue = VisualIssue.STALE))
        assertFalse(p.stableFraming)
        assertEquals(GuidanceProgressState.PENDING, p.state)
        p.observe(observation(2, stable = true))
        assertFalse(p.stableFraming)
    }

    @Test fun lowLightBlurAndFastMotionCannotAdvanceEitherAutomaticStep() {
        for (issue in listOf(VisualIssue.LOW_LIGHT, VisualIssue.BLUR, VisualIssue.FAST_MOTION)) {
            for (p in listOf(GuidedCaptureProgress(), moving())) {
                val step = p.step
                repeat(8) { p.observe(observation(it + 1, it + 1, issue = issue)) }
                assertEquals(step, p.step)
                assertEquals(GuidanceProgressState.NEEDS_IMPROVEMENT, p.state)
                assertEquals("quality warning", p.qualityWarning())
            }
        }
    }

    @Test fun completedHumanSequenceNeverClearsDeclaredOcclusionsOrClaims3D() {
        val p = moving()
        p.observe(observation(1, 1)); p.observe(observation(2, 2))
        p.markHidden()
        p.confirm(p.revision); p.confirm(p.revision)
        assertEquals(5, p.step)
        assertEquals(3, p.manualSteps)
        assertEquals(1, p.hiddenAreas)
        assertTrue(p.instruction().contains("captura manual"))
        assertTrue(p.summary().contains("Cobertura 3D pendiente"))
    }

    @Test fun staleOrDuplicateHiddenAreaActionsCannotAffectAnotherRoom() {
        val p = wall()
        val revision = p.revision
        p.markHidden(revision); p.markHidden(revision)
        assertEquals(1, p.hiddenAreas)
        p.reset(firstRoom = false)
        p.markHidden(revision)
        assertEquals(0, p.hiddenAreas)
    }

    @Test fun unavailablePixelCopyClearsOldSuccessAndKeepsManualFallback() {
        val p = GuidedCaptureProgress()
        p.observe(observation(1, stable = true), referenceCandidate = true)
        val revision = p.revision
        p.observe(VisualFeedback(VisualState.NOT_VERIFIABLE, "copy unavailable"))
        assertFalse(p.stableFraming)
        assertFalse(p.visualContinuity)
        assertFalse(p.referenceCandidate)
        assertEquals(GuidanceProgressState.PENDING, p.state)
        assertEquals("copy unavailable", p.qualityWarning())
        p.confirm(revision)
        assertEquals(0, p.step)
        p.observe(observation(2, stable = true), referenceCandidate = true)
        assertEquals(0, p.step)
        p.confirm(p.revision)
        assertEquals(1, p.step)
        assertTrue(p.referenceContinuedManually)
    }
}
