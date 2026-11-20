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
    fun `a 4 to 3 stream on the 4 to 3 array of the S23 FE gets the whole array`() {
        assertEquals(CropRect(0, 0, 4080, 3060), CaptureCrop.centered(4080, 3060, 1440, 1080, 10f))
        assertEquals(CropRect(0, 0, 4080, 3060), CaptureCrop.centered(4080, 3060, 1280, 960, 10f))
    }

    @Test
    fun `a 4 to 3 stream on a wider array is cropped on the sides only`() {
        val crop = assertNotNull(CaptureCrop.centered(4320, 2160, 1440, 1080, 10f))
        assertEquals(2160, crop.height)
        assertEquals(2880, crop.width)
    }

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
    // The preferred 4:3 stored frame (VideoSpec.PREFERRED_SIZES.first()).
    private val STORED_WIDTH = 1440
    private val STORED_HEIGHT = 1080
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
    fun `the stage is 3 to 4 for a quarter turn and 4 to 3 otherwise`() {
        assertEquals(1080 to 1440, PreviewGeometry.displayedSize(90, 1440, 1080))
        assertEquals(1080 to 1440, PreviewGeometry.displayedSize(270, 1440, 1080))
        assertEquals(1440 to 1080, PreviewGeometry.displayedSize(0, 1440, 1080))
        assertEquals(1440 to 1080, PreviewGeometry.displayedSize(180, 1440, 1080))
        assertEquals(720 to 1280, PreviewGeometry.displayedSize(90, 1280, 720))
    }

    @Test
    fun `a portrait window shows the whole 3 to 4 image full width with free height left`() {
        val (w, h) = PreviewGeometry.stageSize(90, 1440, 1080, 1080, 2340)
        assertEquals(1080, w)
        assertEquals(1440, h)
        assertTrue(2340 - h >= 900)
    }

    @Test
    fun `a landscape window shows the whole 4 to 3 image full height with free width left`() {
        val (w, h) = PreviewGeometry.stageSize(0, 1440, 1080, 2340, 1080)
        assertEquals(1440, w)
        assertEquals(1080, h)
        assertTrue(2340 - w >= 900)
    }

    @Test
    fun `the stage never exceeds the window and keeps the aspect in every case`() {
        for (rotation in rotations) for ((aw, ah) in listOf(1080 to 2340, 2340 to 1080, 1000 to 1000, 600 to 1500, 1500 to 600)) {
            for ((bw, bh) in listOf(1440 to 1080, 1280 to 720)) {
                val (w, h) = PreviewGeometry.stageSize(rotation, bw, bh, aw, ah)
                assertTrue("fits r=$rotation $aw x $ah", w <= aw && h <= ah)
                assertTrue(w == aw || h == ah)
                val (dw, dh) = PreviewGeometry.displayedSize(rotation, bw, bh)
                assertTrue(Math.abs(w.toDouble() / h - dw.toDouble() / dh) < 0.01)
            }
        }
    }

    @Test
    fun `fit stage of a 16 to 9 fallback stays inside the window`() {
        val (w, h) = PreviewGeometry.stageSize(90, 1280, 720, 1080, 1200)
        assertTrue(w <= 1080 && h <= 1200)
        assertEquals(1200, h)
        assertTrue(Math.abs(w.toDouble() / h - 720.0 / 1280.0) < 0.001)
        val (w2, h2) = PreviewGeometry.stageSize(0, 1280, 720, 1000, 2000)
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
        // Portrait S=90, R=0: rotation 90. A vertical drag of 0.5 of the display height (1440 stage px of a 3:4
        // image) is a horizontal 0.5 of the stored width: 720 px in both frames, so the metric length survives.
        val (ax, ay) = PreviewGeometry.displayToStored(90, 0.5, 0.25)
        val (bx, by) = PreviewGeometry.displayToStored(90, 0.5, 0.75)
        assertEquals(0.5, Math.abs(bx - ax), 1e-9)
        assertEquals(0.0, Math.abs(by - ay), 1e-9)
        val storedLengthPx = Math.abs(bx - ax) * STORED_WIDTH
        val displayedLengthPx = 0.5 * 1440
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
            val (dw, dh) = PreviewGeometry.displayedSize(rotation, STORED_WIDTH, STORED_HEIGHT)
            val scale = 1.7
            val vw = dw * scale
            val vh = dh * scale
            val m = PreviewGeometry.bufferToView(rotation, vw.toFloat(), vh.toFloat())
            val (x0, y0) = apply(m, 0.0, 0.0)
            val (xx, xy) = apply(m, vw, 0.0) // buffer's right edge (vw px wide as stretched)
            val (yx, yy) = apply(m, 0.0, vh)
            val bufferWidthOnScreen = Math.hypot(xx - x0, xy - y0)
            val bufferHeightOnScreen = Math.hypot(yx - x0, yy - y0)
            val perPixelX = bufferWidthOnScreen / STORED_WIDTH
            val perPixelY = bufferHeightOnScreen / STORED_HEIGHT
            assertEquals(perPixelX, perPixelY, 1e-3, "uniform scale at r=$rotation")
            assertEquals(scale, perPixelX, 1e-3)
        }
    }

    /**
     * Where, in buffer coordinates (0..1), the world-up direction sits for a sensor mounted at [sensorOrientation]
     * on a phone held in the posture of [displayRotation]. Derived from the physics, not from imageRotation:
     * natural up (device +y) lies on the buffer edge at -sensorOrientation degrees clockwise from the top edge, and
     * turning the phone by displayRotation (counterclockwise) moves world-up by +displayRotation clockwise relative
     * to the device. Returns the midpoint of that buffer edge.
     */
    private fun worldUpEdge(sensorOrientation: Int, displayRotation: Int): Pair<Double, Double> =
        when ((((displayRotation - sensorOrientation) % 360) + 360) % 360) {
            0 -> 0.5 to 0.0
            90 -> 1.0 to 0.5
            180 -> 0.5 to 1.0
            else -> 0.0 to 0.5
        }

    @Test
    fun `the buffer edge that holds world-up ends on the screen top for every sensor and display rotation`() {
        for (sensor in listOf(0, 90, 180, 270)) for (display in rotations) {
            val rotation = PreviewGeometry.imageRotation(sensor, display)
            val (vw, vh) = if (PreviewGeometry.isQuarterTurn(rotation)) 1080f to 1440f else 1440f to 1080f
            val m = PreviewGeometry.bufferToView(rotation, vw, vh)
            val (ux, uy) = worldUpEdge(sensor, display)
            val (px, py) = apply(m, ux * vw, uy * vh)
            assertEquals(vw / 2.0, px, 1e-3, "up edge x s=$sensor d=$display")
            assertEquals(0.0, py, 1e-3, "up edge y s=$sensor d=$display")
            // The opposite buffer edge (world-down) ends on the bottom.
            val (qx, qy) = apply(m, (1.0 - ux) * vw, (1.0 - uy) * vh)
            assertEquals(vw / 2.0, qx, 1e-3, "down edge x s=$sensor d=$display")
            assertEquals(vh.toDouble(), qy, 1e-3, "down edge y s=$sensor d=$display")
        }
    }

    @Test
    fun `all four buffer corners land inside the view for every rotation`() {
        for (rotation in rotations) {
            val (vw, vh) = if (PreviewGeometry.isQuarterTurn(rotation)) 1080f to 1440f else 1440f to 1080f
            val m = PreviewGeometry.bufferToView(rotation, vw, vh)
            for ((bx, by) in listOf(0.0 to 0.0, 1.0 to 0.0, 0.0 to 1.0, 1.0 to 1.0)) {
                val (px, py) = apply(m, bx * vw, by * vh)
                assertTrue("x r=$rotation", px >= -1e-3 && px <= vw + 1e-3)
                assertTrue("y r=$rotation", py >= -1e-3 && py <= vh + 1e-3)
            }
        }
    }

    @Test
    fun `S23 FE on the table - sensor 90, portrait screen, gravity on device +x, world-up shows on the screen right`() {
        // Measured on the phone (accelerometer x=+9.2, y=-0.5, z=+3.1 with the screen in portrait): the phone is held
        // on its side, so world-up is the device's right edge. With sensor 90 that is the buffer top edge, which the
        // 90 degree turn sends to the screen's right edge: the picture is sideways on the portrait screen, as it must be.
        val rotation = PreviewGeometry.imageRotation(90, 0)
        assertEquals(90, rotation)
        val m = PreviewGeometry.bufferToView(rotation, 1080f, 1440f)
        val (x, y) = apply(m, 0.5 * 1080, 0.0)
        assertEquals(1080.0, x, 1e-3, "world-up on the right edge")
        assertEquals(720.0, y, 1e-3, "world-up on the right edge")
    }

    @Test
    fun `phone held upright in portrait - sensor 90, display 0 - the device up edge ends on the screen top`() {
        // Device +y is up: natural up sits on the buffer's left edge for sensor 90.
        val rotation = PreviewGeometry.imageRotation(90, 0)
        val m = PreviewGeometry.bufferToView(rotation, 1080f, 1440f)
        val (x, y) = apply(m, 0.0, 0.5 * 1440)
        assertEquals(540.0, x, 1e-3, "x")
        assertEquals(0.0, y, 1e-3, "y")
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
