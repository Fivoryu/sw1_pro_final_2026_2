package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PreviewSizeTest {
    private fun sizes(vararg s: Pair<Int, Int>) = s.map { VideoSize(it.first, it.second) }

    @Test
    fun `4 to 3 video prefers the largest 4 to 3 size not above it and never the square`() {
        val available = sizes(1088 to 1088, 1920 to 1440, 1440 to 1080, 960 to 720, 640 to 480, 1280 to 720)
        assertEquals(VideoSize(1440, 1080), PreviewSize.choose(VideoSize(1440, 1080), available))
        assertEquals(VideoSize(960, 720), PreviewSize.choose(VideoSize(1440, 1080), sizes(1088 to 1088, 960 to 720, 640 to 480)))
        assertEquals(VideoSize(640, 480), PreviewSize.choose(VideoSize(1440, 1080), sizes(1088 to 1088, 640 to 480)))
    }

    @Test
    fun `16 to 9 fallback picks the analogous 16 to 9 size`() {
        val available = sizes(1920 to 1080, 1280 to 720, 960 to 540, 1088 to 1088, 1440 to 1080)
        assertEquals(VideoSize(1280, 720), PreviewSize.choose(VideoSize(1280, 720), available))
        assertEquals(VideoSize(960, 540), PreviewSize.choose(VideoSize(1280, 720), sizes(1920 to 1080, 960 to 540)))
    }

    @Test
    fun `candidates are ordered from the largest and none when the aspect never matches`() {
        val c = PreviewSize.candidates(VideoSize(1440, 1080), sizes(640 to 480, 1440 to 1080, 960 to 720, 1280 to 720))
        assertEquals(sizes(1440 to 1080, 960 to 720, 640 to 480), c)
        assertNull(PreviewSize.choose(VideoSize(1440, 1080), sizes(1280 to 720, 1088 to 1088)))
        assertNull(PreviewSize.choose(VideoSize(1440, 1080), emptyList()))
    }
}
