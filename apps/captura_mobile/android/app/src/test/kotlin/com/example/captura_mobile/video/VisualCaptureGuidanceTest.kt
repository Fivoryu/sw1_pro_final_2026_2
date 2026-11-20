package com.example.captura_mobile.video

import org.junit.Assert.*
import org.junit.Test
import java.util.Random

class VisualCaptureGuidanceTest {
    private val w = 128
    private val h = 96
    private fun color(v: Int) = (255 shl 24) or (v shl 16) or (v shl 8) or v
    private fun texture(seed: Long = 7): IntArray {
        val random = Random(seed)
        return IntArray(w * h) { color(50 + random.nextInt(180)) }
    }
    private fun movingViews(): List<IntArray> {
        val random = Random(42)
        val sourceWidth = w + 32
        val source = IntArray(sourceWidth * h) { color(50 + random.nextInt(180)) }
        return listOf(0, 4, 8, 12).map { offset ->
            IntArray(w * h) { i -> source[(i / w) * sourceWidth + i % w + offset] }
        }
    }

    @Test fun hybridGuideUsesTrackedChangesWithoutInferringAnAdjacentWall() {
        val engine = VisualCaptureGuidance()
        val progress = GuidedCaptureProgress().apply { reset(firstRoom = false); confirm(revision) }
        movingViews().forEachIndexed { i, pixels ->
            progress.observe(engine.analyze(pixels, w, h, 1000L + i * 1000, progress.step))
        }
        assertEquals(3, progress.step)
        assertEquals(1, progress.manualSteps)
        assertEquals("Veo esquina y pared contigua", progress.confirmation())
        assertTrue(progress.summary().contains("Sin paredes ni esquinas detectadas"))
    }

    @Test fun hybridGuideWithStaticPixelsOnlyAdvancesImageStabilization() {
        val engine = VisualCaptureGuidance()
        val progress = GuidedCaptureProgress().apply { reset(wantsReference = false) }
        repeat(8) { i ->
            progress.observe(engine.analyze(texture(), w, h, 1000L + i * 1000, progress.step))
        }
        assertEquals(1, progress.step)
        progress.confirm(progress.revision)
        repeat(8) { i ->
            progress.observe(engine.analyze(texture(), w, h, 9000L + i * 1000, progress.step))
        }
        assertEquals(2, progress.step)
        assertEquals(1, progress.manualSteps)
    }

    @Test fun staticTextureWithoutObjectCannotAutomaticallyFinishReferenceFraming() {
        val engine = VisualCaptureGuidance()
        val progress = GuidedCaptureProgress()
        repeat(8) { i ->
            progress.observe(engine.analyze(texture(), w, h, 1000L + i * 1000, progress.step),
                referenceCandidate = false)
        }
        assertTrue(progress.stableFraming)
        assertTrue(progress.visualContinuity)
        assertFalse(progress.referenceCandidate)
        assertEquals(0, progress.step)
        assertEquals(0, progress.manualSteps)
    }

    @Test fun slowAnalysisThenThreeSecondSamplingStillEvaluatesRealImageChanges() {
        val policy = GuidanceSamplingPolicy()
        val engine = VisualCaptureGuidance()
        val frames = movingViews()
        engine.analyze(frames[0], w, h, 1000, 2, policy.delayMs)
        policy.completed(251)
        assertEquals(3000L, policy.delayMs)
        var result: VisualFeedback? = null
        frames.drop(1).forEachIndexed { i, frame ->
            result = engine.analyze(frame, w, h, 4000L + i * 3000, 2, policy.delayMs)
            policy.completed(400)
            assertTrue(checkNotNull(result).localMatching)
        }
        assertTrue(checkNotNull(result).changedComparisons > 0)
        assertEquals(VisualState.NOT_VERIFIABLE, checkNotNull(result).state)
    }

    @Test fun slowStaticSamplesNeverBecomeNewViews() {
        val engine = VisualCaptureGuidance()
        repeat(4) { i ->
            val result = engine.analyze(texture(), w, h, 1000L + i * 3000, 2, 3000)
            assertEquals(0, result.changedComparisons)
            assertFalse(result.imageChanged)
            if (i > 0) assertEquals(VisualState.STABLE, result.state)
        }
    }

    @Test fun cadenceTransitionDoesNotAddProcessingTimeToTheNextInterval() {
        val policy = GuidanceSamplingPolicy()
        policy.completed(1800)
        assertEquals(1200L, policy.remainingDelayMs(1800))
        assertEquals(0L, policy.remainingDelayMs(3500))
        repeat(3) { policy.completed(100) }
        assertEquals(900L, policy.remainingDelayMs(100))
    }

    @Test fun threeFastSamplesRecoverNormalCadenceWithoutOscillating() {
        val policy = GuidanceSamplingPolicy()
        policy.completed(400)
        repeat(2) { policy.completed(100); assertEquals(3000L, policy.delayMs) }
        policy.completed(100)
        assertEquals(1000L, policy.delayMs)
        val engine = VisualCaptureGuidance()
        engine.analyze(texture(), w, h, 1000, 1, 3000)
        assertTrue(engine.analyze(texture(), w, h, 4000, 1, 3000).localMatching)
        assertTrue(engine.analyze(texture(), w, h, 5000, 1, policy.delayMs).localMatching)
        policy.completed(400)
        policy.reset()
        assertEquals(1000L, policy.delayMs)
    }

    @Test fun genuinelyStaleSlowSamplesRestartContinuityAndCanRecover() {
        val engine = VisualCaptureGuidance()
        engine.analyze(texture(), w, h, 1000, 1, 3000)
        assertTrue(engine.analyze(texture(), w, h, 5500, 1, 3000).localMatching)
        val stale = engine.analyze(texture(), w, h, 10001, 1, 3000)
        assertEquals(VisualState.PENDING, stale.state)
        assertFalse(stale.localMatching)
        assertEquals(0, stale.matches)
        assertTrue(engine.analyze(texture(), w, h, 13001, 1, 3000).localMatching)
        // Normal cadence retains the original 2500 ms limit.
        assertFalse(engine.analyze(texture(), w, h, 16001, 1).localMatching)
    }

    @Test fun stalePairIsNotCountedButAnIsolatedRecoveredPairIs() {
        val engine = VisualCaptureGuidance()
        val frames = movingViews()
        engine.analyze(frames[0], w, h, 1000, 2, 3000)
        engine.analyze(frames[1], w, h, 4000, 2, 3000)
        val stale = engine.analyze(frames[2], w, h, 9000, 2, 3000)
        assertFalse(stale.localMatching)
        assertEquals(1, stale.changedComparisons)
        val recovered = engine.analyze(frames[3], w, h, 12000, 2, 3000)
        assertTrue(recovered.localMatching)
        assertEquals(2, recovered.changedComparisons)
    }

    @Test fun oddPixelDisplacementsAreTrackedWithoutRelaxingMatchQuality() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        engine.analyze(image, w, h, 1000, 2)
        val shifted = IntArray(w * h) { i -> image[(i / w) * w + (i % w + 5) % w] }
        val result = engine.analyze(shifted, w, h, 2000, 2)
        assertTrue(result.matches >= result.requiredMatches)
        assertTrue(result.localMatching)
        assertTrue(result.imageChanged)
        assertEquals(VisualIssue.NONE, result.issue)
        assertEquals(1, result.changedComparisons)
        assertEquals(1000L, result.gapMs)
        assertTrue(result.luma >= VisualCaptureGuidance.MIN_LUMA)
        assertTrue(result.sharpness >= VisualCaptureGuidance.MIN_SHARPNESS)
        assertEquals(VisualState.NOT_VERIFIABLE, result.state)
    }

    @Test fun outOfOrderSamplesCannotReplaceANewerBaseline() {
        val engine = VisualCaptureGuidance()
        engine.analyze(texture(), w, h, 4000, 1)
        for (time in listOf(3000L, 4000L)) {
            val stale = engine.analyze(texture(19), w, h, time, 1)
            assertEquals(VisualState.PENDING, stale.state)
            assertEquals(1, stale.samples)
            assertFalse(stale.localMatching)
        }
        assertTrue(engine.analyze(texture(), w, h, 5000, 1).localMatching)
    }

    @Test fun roomTransitionAndResumeDoNotReuseSlowComparisonHistory() {
        val rooms = RoomVisualGuidance("Sala")
        rooms.analyze(texture(), w, h, 1000, 1, 3000)
        assertTrue(rooms.analyze(texture(), w, h, 4000, 1, 3000).localMatching)
        rooms.beginRoom("room-2", "Dormitorio")
        val first = rooms.analyze(texture(), w, h, 7000, 1, 3000)
        assertEquals(VisualState.PENDING, first.state)
        assertEquals(1, first.samples)
        assertTrue(rooms.analyze(texture(), w, h, 10000, 1, 3000).localMatching)
        rooms.resetComparison()
        val resumed = rooms.analyze(texture(), w, h, 11000, 1)
        assertFalse(resumed.localMatching)
        assertEquals(3, resumed.samples)
        assertTrue(rooms.summary().contains("Sala: 2 muestras"))
    }

    @Test fun darkAndBlankImagesNeverProducePositiveFeedback() {
        for (value in listOf(5, 150)) {
            val engine = VisualCaptureGuidance()
            val image = IntArray(w * h) { color(value) }
            repeat(4) {
                val result = engine.analyze(image, w, h, 1000L * (it + 1), 1)
                assertEquals(VisualState.NEEDS_IMPROVEMENT, result.state)
                assertEquals(0, result.changedComparisons)
                assertFalse(result.imageChanged)
            }
        }
    }

    @Test fun identicalTexturedFramesAreStableButNeverNewViewsOrCaptureProgress() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        assertEquals(VisualState.PENDING, engine.analyze(image, w, h, 1000, 1).state)
        repeat(8) {
            val result = engine.analyze(image, w, h, 2000L + it * 1000, 1)
            assertEquals(VisualState.STABLE, result.state)
            assertEquals(true, result.imageStable)
            assertTrue(result.localMatching)
            assertTrue(result.matches >= VisualCaptureGuidance.MIN_MATCHES)
            assertFalse(result.imageChanged)
            assertEquals(0, result.changedComparisons)
        }
        assertTrue(engine.summary().contains("0 comparaciones con cambio 2D"))
        assertTrue(engine.summary().contains("cobertura 3D no verificables"))
    }

    @Test fun movingMatchedImagesReportOnlyImageChangeNeverVerifiedParallax() {
        val engine = VisualCaptureGuidance()
        var result: VisualFeedback? = null
        movingViews().forEachIndexed { i, image -> result = engine.analyze(image, w, h, 1000L * (i + 1), 2) }
        val last = checkNotNull(result)
        assertTrue(last.localMatching)
        assertTrue(last.imageChanged)
        assertEquals(false, last.imageStable)
        assertTrue(last.changedComparisons > 0)
        // The same flow can be caused by rotation or a moving object: no translation claim.
        assertEquals(VisualState.NOT_VERIFIABLE, last.state)
        assertTrue(last.message.contains("paralaje no son verificables"))
    }

    @Test fun aStaticPauseDoesNotInflateEarlierImageChangeCounts() {
        val engine = VisualCaptureGuidance()
        val frames = movingViews()
        var count = 0
        frames.forEachIndexed { i, frame -> count = engine.analyze(frame, w, h, 1000L * (i + 1), 2).changedComparisons }
        assertTrue(count > 0)
        repeat(5) {
            val result = engine.analyze(frames.last(), w, h, 5000L + it * 1000, 2)
            assertEquals(count, result.changedComparisons)
            assertEquals(VisualState.STABLE, result.state)
        }
    }

    @Test fun advancingManualWallAndCornerInstructionsDoesNotDetectGeometry() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        repeat(6) { step ->
            val result = engine.analyze(image, w, h, 1000L * (step + 1), step)
            assertEquals(0, result.changedComparisons)
            assertFalse(result.imageChanged)
        }
        assertTrue(engine.summary().contains("Instrucciones mostradas (no detecciones)"))
        assertTrue(engine.summary().contains("Paredes, esquinas, nuevas perspectivas y cobertura 3D no verificables"))
    }

    @Test fun roomTransitionStartsFreshWithoutDiscardingThePreviousRoomSummary() {
        val rooms = RoomVisualGuidance("Sala")
        val frames = movingViews()
        frames.forEachIndexed { i, image -> rooms.analyze(image, w, h, 1000L * (i + 1), 2) }
        val previousSummary = rooms.summary()
        assertTrue(previousSummary.contains("Sala: 4 muestras analizadas"))
        rooms.beginRoom("room-2", "Dormitorio")
        val result = rooms.analyze(frames.last(), w, h, 5000, 1)
        assertEquals(VisualState.PENDING, result.state)
        assertEquals(0, result.matches)
        assertEquals(0, result.changedComparisons)
        assertEquals(1, result.samples)
        assertTrue(rooms.summary().startsWith(previousSummary))
        assertTrue(rooms.summary().contains("Dormitorio: 1 muestras analizadas; 0 comparaciones"))
        // Repeating notification of the same actual room is not another transition/reset.
        rooms.beginRoom("room-2", "Dormitorio")
        assertEquals(2, rooms.analyze(frames.last(), w, h, 6000, 1).samples)
    }

    @Test fun unrelatedFramesAndLongSamplingGapsDoNotProveOverlap() {
        val engine = VisualCaptureGuidance()
        engine.analyze(texture(), w, h, 1000, 3)
        assertEquals(0, engine.analyze(texture(19), w, h, 2000, 3).changedComparisons)
        val late = engine.analyze(texture(19), w, h, 9000, 3)
        assertEquals(VisualState.PENDING, late.state)
        assertFalse(late.localMatching)
        assertEquals(0, late.changedComparisons)
    }

    @Test fun repeatedPatternsAreAmbiguousRatherThanEvidenceOfCoverage() {
        val engine = VisualCaptureGuidance()
        val image = IntArray(w * h) { i -> color(if ((i % w / 4 + i / w / 4) % 2 == 0) 40 else 220) }
        repeat(4) {
            val result = engine.analyze(image, w, h, 1000L * (it + 1), 3)
            assertFalse(result.localMatching)
            assertEquals(0, result.changedComparisons)
        }
    }

    @Test fun movingRepeatedPatternsDoNotTurnAmbiguousPatchesIntoProgress() {
        val engine = VisualCaptureGuidance()
        repeat(6) { offset ->
            val image = IntArray(w * h) { i ->
                color(if (((i % w + offset * 2) / 4 + i / w / 4) % 2 == 0) 40 else 220)
            }
            val result = engine.analyze(image, w, h, 1000L * (offset + 1), 2)
            assertFalse(result.localMatching)
            assertFalse(result.imageChanged)
            assertEquals(0, result.changedComparisons)
        }
    }

    @Test fun trackerGridJitterDoesNotCountAsNewImageProgression() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        repeat(8) { index ->
            val offset = if (index % 2 == 0) 0 else 2
            val frame = IntArray(w * h) { i -> image[(i / w) * w + (i % w + offset) % w] }
            val result = engine.analyze(frame, w, h, 1000L * (index + 1), 2)
            assertFalse(result.imageChanged)
            assertEquals(0, result.changedComparisons)
        }
    }

    @Test fun resetDoesNotReuseEvidenceFromPreviousRecording() {
        val engine = VisualCaptureGuidance()
        val frames = movingViews()
        frames.forEachIndexed { i, frame -> engine.analyze(frame, w, h, 1000L * (i + 1), 1) }
        engine.reset()
        val result = engine.analyze(frames.last(), w, h, 5000, 1)
        assertEquals(VisualState.PENDING, result.state)
        assertEquals(0, result.changedComparisons)
        assertEquals(1, result.samples)
    }

    @Test fun abruptImageShiftRequestsSlowerMovement() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        engine.analyze(image, w, h, 1000, 2)
        val moved = IntArray(w * h) { i -> image[(i / w) * w + (i % w - 16 + w) % w] }
        val result = engine.analyze(moved, w, h, 2000, 2)
        assertEquals(VisualState.NEEDS_IMPROVEMENT, result.state)
        assertTrue(result.message.contains("despacio"))
    }

    @Test fun lossOfLightClearsPositiveStreak() {
        val engine = VisualCaptureGuidance()
        val image = texture()
        repeat(4) { engine.analyze(image, w, h, 1000L * (it + 1), 1) }
        val result = engine.analyze(IntArray(w * h) { color(0) }, w, h, 5000, 1)
        assertEquals(VisualState.NEEDS_IMPROVEMENT, result.state)
        assertTrue(result.message.contains("luz"))
        assertEquals(0, engine.analyze(image, w, h, 6000, 1).changedComparisons)
    }

    @Test fun measured27cmRectangleIsNotChangedToStandardA4Size() {
        val quad = listOf(ReferencePoint(0.1, 0.1), ReferencePoint(0.9, 0.1),
            ReferencePoint(0.9, 0.8), ReferencePoint(0.1, 0.8))
        val rect = ReferenceRect.create(0.27, 0.21, quad, ReferenceRectSource.ADJUSTED)
        val mark = ReferenceMark.create(1000, quad[0], quad[1], 0.27, "Hoja medida", ReferenceSurface.WALL, rect)
        assertEquals(0.27, mark.toMap()["lengthM"])
        assertEquals("user_confirmed", mark.toMap()["dimensionsSource"])
        assertEquals(0.27, rect.toMap()["widthM"])
    }
}
