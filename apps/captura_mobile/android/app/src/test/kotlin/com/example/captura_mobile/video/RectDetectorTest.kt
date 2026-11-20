package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Synthetic scenes only: they prove the geometry code on clean, deterministic input. They say nothing
 * about accuracy on real frames (lighting, texture, clutter), which is not measured.
 */
class RectDetectorTest {
    private val w = 640
    private val h = 360
    private val a4Ratio = 297.0 / 210.0

    private class Pt(val x: Double, val y: Double)

    private fun scene(seed: Long = 1, background: Int = 40, noise: Int = 4): IntArray {
        val rnd = Random(seed)
        return IntArray(w * h) { gray(background + rnd.nextInt(2 * noise + 1) - noise) }
    }

    private fun gray(v: Int): Int {
        val c = v.coerceIn(0, 255)
        return (0xFF shl 24) or (c shl 16) or (c shl 8) or c
    }

    /** Fills a convex polygon (any winding) with [value], per-pixel centre test. */
    private fun fill(img: IntArray, poly: List<Pt>, value: Int) {
        for (y in 0 until h) for (x in 0 until w) {
            val px = x + 0.5
            val py = y + 0.5
            var pos = false
            var neg = false
            for (i in poly.indices) {
                val a = poly[i]
                val b = poly[(i + 1) % poly.size]
                val cr = (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)
                if (cr > 0) pos = true else if (cr < 0) neg = true
            }
            if (!(pos && neg)) img[y * w + x] = gray(value)
        }
    }

    private fun rotatedRect(cx: Double, cy: Double, rw: Double, rh: Double, deg: Double): List<Pt> {
        val t = Math.toRadians(deg)
        val c = cos(t)
        val s = sin(t)
        return listOf(-1 to -1, 1 to -1, 1 to 1, -1 to 1).map { (sx, sy) ->
            val dx = sx * rw / 2
            val dy = sy * rh / 2
            Pt(cx + dx * c - dy * s, cy + dx * s + dy * c)
        }
    }

    /** Max distance (px) from each expected corner to its nearest detected corner. */
    private fun maxCornerError(found: List<ReferencePoint>, expected: List<Pt>): Double =
        expected.maxOf { e -> found.minOf { hypot(it.x * w - e.x, it.y * h - e.y) } }

    // Tolerance 4 px of 640 (0.6 %): the detector refines on full-resolution edges and the synthetic
    // edges are exact, so a coarser value would only hide a regression. It is a test threshold, not a spec.
    private val cornerTolerancePx = 4.0

    @Test fun findsAxisAlignedRectangle() {
        val img = scene()
        val rect = rotatedRect(320.0, 180.0, 210.0, 148.0, 0.0)
        fill(img, rect, 220)
        val found = RectDetector.detect(img, w, h, a4Ratio)
        assertNotNull(found)
        assertEquals(4, found!!.size)
        assertTrue(maxCornerError(found, rect) <= cornerTolerancePx)
    }

    @Test fun findsRectangleRotated15Degrees() {
        val img = scene()
        val rect = rotatedRect(300.0, 190.0, 220.0, 156.0, 15.0)
        fill(img, rect, 215)
        val found = RectDetector.detect(img, w, h, a4Ratio)
        assertNotNull(found)
        assertTrue(maxCornerError(found!!, rect) <= cornerTolerancePx)
    }

    @Test fun findsDarkRectangleOnBrightBackground() {
        val img = scene(background = 210)
        val rect = rotatedRect(320.0, 180.0, 210.0, 148.0, -10.0)
        fill(img, rect, 35)
        val found = RectDetector.detect(img, w, h, a4Ratio)
        assertNotNull(found)
        assertTrue(maxCornerError(found!!, rect) <= cornerTolerancePx)
    }

    @Test fun findsRectangleWithMildPerspective() {
        val img = scene()
        // A trapezoid: the far (top) side is 8 % shorter, as when a sheet is seen from a slight angle.
        val quad = listOf(Pt(215.0, 110.0), Pt(425.0 - 17.0, 110.0), Pt(430.0, 255.0), Pt(210.0, 255.0))
        fill(img, quad, 220)
        val found = RectDetector.detect(img, w, h, null)
        assertNotNull(found)
        assertTrue(maxCornerError(found!!, quad) <= cornerTolerancePx * 1.5)
    }

    @Test fun cornersAreNormalisedAndConsecutive() {
        val img = scene()
        fill(img, rotatedRect(320.0, 180.0, 210.0, 148.0, 0.0), 220)
        val found = RectDetector.detect(img, w, h, a4Ratio)!!
        assertTrue(found.all { it.x in 0.0..1.0 && it.y in 0.0..1.0 })
        // consecutive: the diagonal is longer than every side
        val sides = (0..3).map { hypot((found[(it + 1) % 4].x - found[it].x) * w, (found[(it + 1) % 4].y - found[it].y) * h) }
        val diag = hypot((found[2].x - found[0].x) * w, (found[2].y - found[0].y) * h)
        assertTrue(sides.all { it < diag })
    }

    @Test fun emptySceneGivesNull() {
        assertNull(RectDetector.detect(scene(), w, h, a4Ratio))
    }

    @Test fun uniformNoiseGivesNull() {
        val rnd = Random(7)
        val img = IntArray(w * h) { gray(rnd.nextInt(256)) }
        assertNull(RectDetector.detect(img, w, h, a4Ratio))
    }

    @Test fun squareDoesNotMatchAnA4Preset() {
        val img = scene()
        fill(img, rotatedRect(320.0, 180.0, 150.0, 150.0, 0.0), 220)
        assertNull(RectDetector.detect(img, w, h, a4Ratio))
    }

    @Test fun roundBlobIsNotARectangle() {
        val img = scene()
        for (y in 0 until h) for (x in 0 until w) {
            if (hypot(x - 320.0, y - 180.0) < 80.0) img[y * w + x] = gray(220)
        }
        assertNull(RectDetector.detect(img, w, h, a4Ratio))
    }

    @Test fun tooSmallObjectGivesNull() {
        val img = scene()
        fill(img, rotatedRect(320.0, 180.0, 60.0, 42.0, 0.0), 220)
        assertNull(RectDetector.detect(img, w, h, a4Ratio))
    }

    @Test fun twoCandidatesTheOneMatchingThePresetRatioWins() {
        val img = scene()
        val a4 = rotatedRect(160.0, 180.0, 200.0, 141.0, 0.0)
        val strip = rotatedRect(470.0, 180.0, 240.0, 96.0, 0.0)
        fill(img, a4, 220)
        fill(img, strip, 220)
        val forA4 = RectDetector.detect(img, w, h, a4Ratio)!!
        assertTrue(maxCornerError(forA4, a4) <= cornerTolerancePx)
        val forStrip = RectDetector.detect(img, w, h, 2.5)!!
        assertTrue(maxCornerError(forStrip, strip) <= cornerTolerancePx)
    }

    @Test fun findsRectangleOnAFullSizeFrame() {
        // The phone hands over 1280x720: nearest-neighbour 2x of the scene exercises the downscale path (factor 4).
        val img = scene()
        val rect = rotatedRect(300.0, 190.0, 220.0, 156.0, 8.0)
        fill(img, rect, 215)
        val big = IntArray(w * 2 * h * 2) { i -> img[(i / (w * 2) / 2) * w + (i % (w * 2)) / 2] }
        val found = RectDetector.detect(big, w * 2, h * 2, a4Ratio)
        assertNotNull(found)
        assertTrue(maxCornerError(found!!, rect) <= cornerTolerancePx)
    }

    @Test fun findsASheetWithDarkTextLinesOnIt() {
        val img = scene()
        val rect = rotatedRect(320.0, 180.0, 220.0, 156.0, 5.0)
        fill(img, rect, 225)
        for (row in 0 until 8) {
            val y = 125.0 + row * 14.0
            fill(img, rotatedRect(320.0, y + 6.0, 150.0, 5.0, 5.0), 60)
        }
        val found = RectDetector.detect(img, w, h, a4Ratio)
        assertNotNull(found)
        assertTrue(maxCornerError(found!!, rect) <= cornerTolerancePx * 1.5)
    }

    @Test fun ratioToleranceIsNamed() {
        assertTrue(abs(RectDetector.RATIO_TOLERANCE - 0.20) < 1e-9)
    }
}
