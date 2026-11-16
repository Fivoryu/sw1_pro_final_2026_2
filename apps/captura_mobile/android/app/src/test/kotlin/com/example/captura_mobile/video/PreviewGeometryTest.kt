package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun <T : Any> assertNotNull(value: T?): T = checkNotNull(value)

private fun assertEquals(expected: Double, actual: Double, delta: Double, message: String) =
    org.junit.Assert.assertEquals(message, expected, actual, delta)

class CaptureCropTest {
    @Test
    fun `the 4 to 3 array of the S23 FE gets the centred 16 to 9 band`() {
        assertEquals(CropRect(0, 382, 4080, 2678), CaptureCrop.centered(4080, 3060, 1280, 720, 10f))
    }

    @Test
    fun `an array that is already 16 to 9 is left whole`() {
        assertEquals(CropRect(0, 0, 3840, 2160), CaptureCrop.centered(3840, 2160, 1280, 720))
    }

    @Test
    fun `a wider array is cropped on the sides`() {
        // 21:9 array: keep the full height, 4032 wide band centred.
        val crop = assertNotNull(CaptureCrop.centered(5040, 2268, 1280, 720))
        assertEquals(2268, crop.height)
        assertEquals(4032, crop.width)
        assertEquals((5040 - 4032) / 2, crop.left)
        assertEquals(0, crop.top)
    }

    @Test
    fun `an odd sized array yields an even sized centred region that fits`() {
        val crop = assertNotNull(CaptureCrop.centered(4001, 3001, 1280, 720))
        assertEquals(0, crop.width % 2)
        assertEquals(0, crop.height % 2)
        assertTrue(crop.left >= 0 && crop.top >= 0 && crop.right <= 4001 && crop.bottom <= 3001)
        assertTrue(Math.abs(crop.left - (4001 - crop.right)) <= 1)
        assertTrue(Math.abs(crop.top - (3001 - crop.bottom)) <= 1)
        // Aspect stays 16:9 within one even step.
        assertTrue(Math.abs(crop.width.toDouble() / crop.height - 16.0 / 9.0) < 0.002)
    }

    @Test
    fun `the region keeps the aspect of the stream for several arrays`() {
        for ((w, h) in listOf(4000 to 3000, 4608 to 3456, 2592 to 1944, 1920 to 1080, 4160 to 3120)) {
            val crop = assertNotNull(CaptureCrop.centered(w, h, 1280, 720, 8f))
            assertTrue(Math.abs(crop.width.toDouble() / crop.height - 16.0 / 9.0) < 0.002)
            assertTrue(Math.abs(crop.left - (w - crop.right)) <= 1)
        }
    }

    @Test
    fun `a small max zoom never shrinks the region below the zoom floor`() {
        // Zoom 1.0 with an array that is 4:3: the band is never narrower than the array.
        val crop = assertNotNull(CaptureCrop.centered(4080, 3060, 1280, 720, 1f))
        assertEquals(4080, crop.width)
        // A max zoom below the crop ratio widens the short side back to the zoom floor (here 2x: >= 1530 high).
        val floor = assertNotNull(CaptureCrop.centered(4080, 3060, 1280, 720, 2f))
        assertTrue(floor.height >= 1530 && floor.width >= 2040)
    }

    @Test
    fun `unusable inputs give null`() {
        assertNull(CaptureCrop.centered(0, 3060, 1280, 720))
        assertNull(CaptureCrop.centered(4080, 3060, 1280, 0))
    }
}

class PreviewGeometryTest {
    private val rotations = listOf(0, 90, 180, 270)

    @Test
    fun `image rotation follows sensor minus display rotation`() {
        assertEquals(90, PreviewGeometry.imageRotation(90, 0))
        assertEquals(0, PreviewGeometry.imageRotation(90, 90))
        assertEquals(270, PreviewGeometry.imageRotation(90, 180))
        assertEquals(180, PreviewGeometry.imageRotation(90, 270))
        assertEquals(270, PreviewGeometry.imageRotation(0, 90))
        assertEquals(90, PreviewGeometry.imageRotation(270, 180))
        for (s in listOf(0, 90, 180, 270)) for (d in rotations) {
            assertTrue(PreviewGeometry.imageRotation(s, d) in rotations)
        }
    }

    @Test
    fun `the stage is 9 to 16 for a quarter turn and 16 to 9 otherwise`() {
        assertEquals(720 to 1280, PreviewGeometry.displayedSize(90, 1280, 720))
        assertEquals(720 to 1280, PreviewGeometry.displayedSize(270, 1280, 720))
        assertEquals(1280 to 720, PreviewGeometry.displayedSize(0, 1280, 720))
        assertEquals(1280 to 720, PreviewGeometry.displayedSize(180, 1280, 720))
    }

    @Test
    fun `cover stage fills a portrait window without stretching`() {
        val (w, h) = PreviewGeometry.stageSize(90, 1280, 720, 1080, 2340, cover = true)
        assertTrue(w >= 1080 && h >= 2340)
        assertEquals(2340, h)
        assertTrue(Math.abs(w.toDouble() / h - 720.0 / 1280.0) < 0.001)
    }

    @Test
    fun `cover stage fills a landscape window without stretching`() {
        val (w, h) = PreviewGeometry.stageSize(0, 1280, 720, 2340, 1080, cover = true)
        assertEquals(2340, w)
        assertTrue(h >= 1080)
        assertTrue(Math.abs(w.toDouble() / h - 16.0 / 9.0) < 0.001)
    }

    @Test
    fun `fit stage stays inside the window and keeps the aspect`() {
        val (w, h) = PreviewGeometry.stageSize(90, 1280, 720, 1080, 1200, cover = false)
        assertTrue(w <= 1080 && h <= 1200)
        assertEquals(1200, h)
        assertTrue(Math.abs(w.toDouble() / h - 720.0 / 1280.0) < 0.001)
        val (w2, h2) = PreviewGeometry.stageSize(0, 1280, 720, 1000, 2000, cover = false)
        assertEquals(1000, w2)
        assertEquals(562, h2)
    }

    @Test
    fun `stored and display mappings are inverse for every rotation`() {
        val points = listOf(0.0 to 0.0, 1.0 to 0.0, 0.0 to 1.0, 0.31 to 0.8, 0.5 to 0.5, 0.9 to 0.123)
        for (rotation in rotations) for ((x, y) in points) {
            val (dx, dy) = PreviewGeometry.storedToDisplay(rotation, x, y)
            val (sx, sy) = PreviewGeometry.displayToStored(rotation, dx, dy)
            assertEquals(x, sx, 1e-9, "x for $rotation")
            assertEquals(y, sy, 1e-9, "y for $rotation")
            val (rx, ry) = PreviewGeometry.displayToStored(rotation, x, y)
            val (bx, by) = PreviewGeometry.storedToDisplay(rotation, rx, ry)
            assertEquals(x, bx, 1e-9)
            assertEquals(y, by, 1e-9)
        }
    }

    @Test
    fun `a tap on the rotated display lands on the right stored coordinate`() {
        // Display rotated 90 cw: the stored top-left corner shows at the display top-right.
        assertEquals(0.0 to 0.0, PreviewGeometry.displayToStored(90, 1.0, 0.0))
        // The display top-left is the stored bottom-left for 90 and the stored top-right for 270.
        assertEquals(0.0 to 1.0, PreviewGeometry.displayToStored(90, 0.0, 0.0))
        assertEquals(1.0 to 0.0, PreviewGeometry.displayToStored(270, 0.0, 0.0))
        // 180 flips both axes.
        assertEquals(0.75 to 0.6, PreviewGeometry.displayToStored(180, 0.25, 0.4).let { (a, b) -> Math.round(a * 100) / 100.0 to Math.round(b * 100) / 100.0 })
        // 0 is the identity.
        assertEquals(0.3 to 0.7, PreviewGeometry.displayToStored(0, 0.3, 0.7))
    }

    @Test
    fun `a portrait tap keeps real distances on the stored frame`() {
        // Portrait S=90, R=0: rotation 90. A vertical drag of 0.5 of the display height (1280 stage px of a 9:16
        // image) is a horizontal 0.5 of the stored width: 640 px in both frames, so the metric length survives.
        val (ax, ay) = PreviewGeometry.displayToStored(90, 0.5, 0.25)
        val (bx, by) = PreviewGeometry.displayToStored(90, 0.5, 0.75)
        assertEquals(0.5, Math.abs(bx - ax), 1e-9)
        assertEquals(0.0, Math.abs(by - ay), 1e-9)
        val storedLengthPx = Math.abs(bx - ax) * VideoSpec.WIDTH
        val displayedLengthPx = 0.5 * 1280
        assertEquals(displayedLengthPx, storedLengthPx, 1e-9)
    }

    private fun apply(m: FloatArray, x: Double, y: Double) =
        (m[0] * x + m[1] * y + m[2]) to (m[3] * x + m[4] * y + m[5])

    @Test
    fun `the view matrix sends each buffer corner to its upright position for all rotations and view sizes`() {
        val views = listOf(1316f to 2340f, 720f to 1280f, 2340f to 1316f, 1280f to 720f)
        for (rotation in rotations) {
            val view = if (PreviewGeometry.isQuarterTurn(rotation)) views[0] else views[2]
            val (vw, vh) = view
            val m = PreviewGeometry.bufferToView(rotation, vw, vh)
            // The texture stretches the buffer over the view: buffer corner (bx, by) sits at (bx*vw, by*vh).
            for ((bx, by) in listOf(0.0 to 0.0, 1.0 to 0.0, 0.0 to 1.0, 1.0 to 1.0, 0.3 to 0.6)) {
                val (px, py) = apply(m, bx * vw, by * vh)
                val (dx, dy) = PreviewGeometry.storedToDisplay(rotation, bx, by)
                assertEquals(dx * vw, px, 1e-3, "x r=$rotation")
                assertEquals(dy * vh, py, 1e-3, "y r=$rotation")
            }
        }
    }

    @Test
    fun `the view matrix does not stretch the picture for any rotation`() {
        // Scale of the rendered buffer along its own axes, in view pixels per buffer pixel.
        for (rotation in rotations) {
            val (dw, dh) = PreviewGeometry.displayedSize(rotation, VideoSpec.WIDTH, VideoSpec.HEIGHT)
            val scale = 1.7
            val vw = dw * scale
            val vh = dh * scale
            val m = PreviewGeometry.bufferToView(rotation, vw.toFloat(), vh.toFloat())
            val (x0, y0) = apply(m, 0.0, 0.0)
            val (xx, xy) = apply(m, vw, 0.0) // buffer's right edge (vw px wide as stretched)
            val (yx, yy) = apply(m, 0.0, vh)
            val bufferWidthOnScreen = Math.hypot(xx - x0, xy - y0)
            val bufferHeightOnScreen = Math.hypot(yx - x0, yy - y0)
            val perPixelX = bufferWidthOnScreen / VideoSpec.WIDTH
            val perPixelY = bufferHeightOnScreen / VideoSpec.HEIGHT
            assertEquals(perPixelX, perPixelY, 1e-3, "uniform scale at r=$rotation")
            assertEquals(scale, perPixelX, 1e-3)
        }
    }

    @Test
    fun `every display rotation by sensor orientation round trips`() {
        for (sensor in listOf(0, 90, 180, 270)) for (display in rotations) {
            val rotation = PreviewGeometry.imageRotation(sensor, display)
            val (sx, sy) = PreviewGeometry.displayToStored(rotation, 0.2, 0.9)
            val (dx, dy) = PreviewGeometry.storedToDisplay(rotation, sx, sy)
            assertEquals(0.2, dx, 1e-9)
            assertEquals(0.9, dy, 1e-9)
            assertTrue(sx in 0.0..1.0 && sy in 0.0..1.0)
        }
    }
}
