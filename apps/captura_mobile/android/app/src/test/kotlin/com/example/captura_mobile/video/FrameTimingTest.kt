package com.example.captura_mobile.video

import org.junit.Test
import org.junit.Assert.assertThrows
import org.junit.Assert.assertEquals

class FrameTimingTest {
    @Test fun matchingTimelinesMayHaveDifferentEpochs() {
        FrameTiming.validate(listOf(1_000_000_000, 1_033_333_000, 1_066_666_000), listOf(0, 33_333, 66_666))
    }
    @Test fun missingEncodedFramesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.validate(listOf(1L, 2L), listOf(0L))
        }
    }
    @Test fun shiftedFrameOrDriftIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.validate(listOf(0L, 33_333_000L, 66_666_000L), listOf(0L, 66_666L, 99_999L))
        }
    }
    @Test fun nonMonotonicEncoderPtsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.validate(listOf(0L, 33_333_000L), listOf(0L, 0L))
        }
    }

    @Test fun replayKeepsTheOriginalCameraTimestamps() {
        val camera = listOf(1_000_000_000L, 1_033_333_000L, 1_066_666_000L)
        assertEquals(camera, FrameTiming.match(camera, listOf(5_000L, 38_333L, 71_666L)))
    }

    @Test fun droppedEncoderFrameKeepsTheRealTimestampGap() {
        val camera = listOf(0L, 33_000_000L, 71_000_000L, 104_000_000L, 140_000_000L)
        assertEquals(listOf(camera[0], camera[1], camera[3], camera[4]),
            FrameTiming.match(camera, listOf(0L, 33_000L, 104_000L, 140_000L)))
    }

    @Test fun startupShutdownAndInteriorOmissionsRequireAUniqueAlignment() {
        val camera = listOf(1_000_000_000L, 1_033_000_000L, 1_071_000_000L,
            1_104_000_000L, 1_140_000_000L, 1_181_000_000L)
        assertEquals(listOf(camera[1], camera[2], camera[4]),
            FrameTiming.match(camera, listOf(9_000L, 47_000L, 116_000L)))
    }

    @Test fun constantCadenceCannotIdentifyWhichBoundaryFrameWasDropped() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.match(listOf(0L, 33_000_000L, 66_000_000L), listOf(0L, 33_000L))
        }
    }

    @Test fun encodedSampleWithoutCameraEvidenceIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.match(listOf(0L, 33_000_000L), listOf(0L, 33_000L, 66_000L))
        }
    }

    @Test fun matchingDoesNotRelaxTheExistingDriftTolerance() {
        assertThrows(IllegalArgumentException::class.java) {
            FrameTiming.match(listOf(0L, 33_000_000L, 66_000_000L), listOf(0L, 33_000L, 69_001L))
        }
    }
}
