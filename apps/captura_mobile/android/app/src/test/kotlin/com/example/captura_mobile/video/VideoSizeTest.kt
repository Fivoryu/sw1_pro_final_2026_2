package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoSizeTest {
    private val s1440 = VideoSize(1440, 1080)
    private val s1280x960 = VideoSize(1280, 960)
    private val s720p = VideoSize(1280, 720)

    @Test
    fun `the 4 to 3 size wins over 16 to 9`() {
        assertEquals(s1440, VideoSpec.chooseVideoSize(listOf(s720p, s1440, VideoSize(1920, 1080))))
    }

    @Test
    fun `the preference order is 1440x1080, then 1280x960, then 1280x720`() {
        assertEquals(s1440, VideoSpec.chooseVideoSize(listOf(s720p, s1280x960, s1440)))
        assertEquals(s1280x960, VideoSpec.chooseVideoSize(listOf(s720p, s1280x960)))
        assertEquals(s720p, VideoSpec.chooseVideoSize(listOf(s720p, VideoSize(1920, 1080))))
    }

    @Test
    fun `sizes outside the list are never chosen and nothing available gives null`() {
        assertNull(VideoSpec.chooseVideoSize(listOf(VideoSize(1920, 1440), VideoSize(640, 480))))
        assertNull(VideoSpec.chooseVideoSize(emptyList()))
        assertEquals("La cámara no graba en 1280x720.", VideoSpec.unsupportedSizeMessage())
    }

    @Test
    fun `every preferred size is at most 30 fps friendly and the list ends on the 1280x720 fallback`() {
        assertEquals(30, VideoSpec.FPS)
        assertEquals(s720p, VideoSpec.FALLBACK_SIZE)
        assertEquals(listOf(s1440, s1280x960, s720p), VideoSpec.PREFERRED_SIZES)
    }

    @Test
    fun `the bitrate of 1440x1080 is the named 3_5 Mbps constant`() {
        assertEquals(3_500_000, VideoSpec.BITRATE_BPS)
        assertEquals(VideoSpec.BITRATE_BPS, VideoSpec.bitrateFor(s1440))
    }

    @Test
    fun `smaller sizes scale down but never below the 3 Mbps floor`() {
        assertEquals(3_000_000, VideoSpec.bitrateFor(s1280x960))
        assertEquals(3_000_000, VideoSpec.bitrateFor(s720p))
        assertEquals(3_000_000, VideoSpec.bitrateFor(VideoSize(320, 240)))
    }

    @Test
    fun `bigger sizes are capped so five minutes stay under the package limit`() {
        val capped = VideoSpec.bitrateFor(VideoSize(3840, 2880))
        assertEquals(VideoSpec.BITRATE_BPS, capped)
        val fiveMinutesBytes = capped.toLong() * 300 / 8
        assertTrue(fiveMinutesBytes < VideoCaptureLimits.MAX_PACKAGE_BYTES * 90 / 100)
    }
}
