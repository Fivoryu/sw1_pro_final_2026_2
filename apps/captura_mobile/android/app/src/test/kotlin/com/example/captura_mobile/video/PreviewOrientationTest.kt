package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Test

class PreviewOrientationTest {
    private val angles = listOf(0, 90, 180, 270)

    /** Column-major 4x4 like SurfaceTexture.getTransformMatrix. */
    private fun matrix(m0: Float, m1: Float, m4: Float, m5: Float, m12: Float, m13: Float) = floatArrayOf(
        m0, m1, 0f, 0f,
        m4, m5, 0f, 0f,
        0f, 0f, 1f, 0f,
        m12, m13, 0f, 1f,
    )

    private val identityFlip = matrix(1f, 0f, 0f, -1f, 0f, 1f)
    private val rot90 = matrix(0f, -1f, -1f, 0f, 1f, 1f)
    private val rot180 = matrix(-1f, 0f, 0f, 1f, 1f, 0f)
    private val rot270 = matrix(0f, 1f, 1f, 0f, 0f, 0f)

    @Test
    fun `the standard matrices give their hint rotation`() {
        assertEquals(0, PreviewGeometry.hintRotationDegrees(identityFlip))
        assertEquals(90, PreviewGeometry.hintRotationDegrees(rot90))
        assertEquals(180, PreviewGeometry.hintRotationDegrees(rot180))
        assertEquals(270, PreviewGeometry.hintRotationDegrees(rot270))
    }

    @Test
    fun `crop scale and translate terms do not change the hint`() {
        val noisy = listOf(
            matrix(0.9996f, 0f, 0f, -0.9996f, 0.0002f, 0.9998f),
            matrix(0f, -0.9996f, -0.9996f, 0f, 0.9998f, 0.9998f),
            matrix(-0.9992f, 0f, 0f, 0.9992f, 0.9996f, 0.0004f),
            matrix(0f, 0.9996f, 0.9996f, 0f, 0.0002f, 0.0002f),
            matrix(0.75f, 0f, 0f, -1f, 0.125f, 1f),
        )
        assertEquals(listOf(0, 90, 180, 270, 0), noisy.map { PreviewGeometry.hintRotationDegrees(it) })
    }

    @Test
    fun `a degenerate or short matrix gives 0`() {
        assertEquals(0, PreviewGeometry.hintRotationDegrees(FloatArray(16)))
        assertEquals(0, PreviewGeometry.hintRotationDegrees(FloatArray(4)))
    }

    @Test
    fun `remainder is sensor minus display minus hint`() {
        assertEquals(90, PreviewGeometry.remainderRotation(90, 0, 0))
        assertEquals(0, PreviewGeometry.remainderRotation(90, 0, 90))
        assertEquals(270, PreviewGeometry.remainderRotation(90, 180, 0))
        assertEquals(180, PreviewGeometry.remainderRotation(90, 0, 270))
        for (s in angles) for (r in angles) {
            // Raw buffer: the whole rotation is left; pre-rotated buffer (hint = S - R): nothing is left.
            assertEquals(PreviewGeometry.imageRotation(s, r), PreviewGeometry.remainderRotation(s, r, 0))
            assertEquals(0, PreviewGeometry.remainderRotation(s, r, PreviewGeometry.imageRotation(s, r)))
        }
    }

    @Test
    fun `the opposite sign of a quarter turn hint is read as the pre rotation`() {
        // S=90, R=0: up rotation 90. A measured 270 is the same pre-rotation read with the opposite sign convention.
        assertEquals(90, PreviewGeometry.effectiveHint(270, 90, 0))
        assertEquals(270, PreviewGeometry.effectiveHint(90, 90, 180))
        assertEquals(0, PreviewGeometry.effectiveHint(0, 90, 0))
        assertEquals(90, PreviewGeometry.effectiveHint(90, 90, 0))
        assertEquals(180, PreviewGeometry.effectiveHint(180, 0, 180))
        // Not the opposite of the up rotation: left as measured.
        assertEquals(180, PreviewGeometry.effectiveHint(180, 90, 0))
    }

    @Test
    fun `the stored to display mapping does not depend on the hint`() {
        for (s in angles) for (r in angles) {
            val reference = PreviewGeometry.plan(s, r, 0)
            for (hint in angles) {
                val plan = PreviewGeometry.plan(s, r, hint)
                assertEquals(reference.uprightRotation, plan.uprightRotation)
                assertEquals(PreviewGeometry.imageRotation(s, r), plan.uprightRotation)
                for ((x, y) in listOf(0.1 to 0.2, 0.9 to 0.4, 0.5 to 0.5)) {
                    assertEquals(
                        PreviewGeometry.storedToDisplay(reference.uprightRotation, x, y),
                        PreviewGeometry.storedToDisplay(plan.uprightRotation, x, y),
                    )
                }
            }
        }
    }

    private fun apply(m: FloatArray, x: Double, y: Double) =
        (m[0] * x + m[1] * y + m[2]) to (m[3] * x + m[4] * y + m[5])

    @Test
    fun `world up ends on the screen top whatever the buffer pre rotation when the remainder is applied on top`() {
        for (s in angles) for (r in angles) {
            val up = PreviewGeometry.imageRotation(s, r)
            // Raw buffer (hint 0) and a buffer the platform already rotated to the display (hint = up).
            for (hint in listOf(0, up)) {
                // World-up sits on this edge midpoint of the raw buffer (physics: R - S clockwise from the top edge).
                val (ux, uy) = when ((((r - s) % 360) + 360) % 360) {
                    0 -> 0.5 to 0.0
                    90 -> 1.0 to 0.5
                    180 -> 0.5 to 1.0
                    else -> 0.0 to 0.5
                }
                // The platform turns the buffer by the hint; its output is a normalised 0..1 image.
                val (hx, hy) = PreviewGeometry.storedToDisplay(hint, ux, uy)
                val plan = PreviewGeometry.plan(s, r, hint)
                assertEquals(PreviewGeometry.remainderRotation(s, r, hint), plan.remainder)
                val (vw, vh) = PreviewGeometry.displayedSize(up, 1440, 1080)
                // The view stretches that content over the stage rectangle; the matrix is applied on top of that.
                val m = PreviewGeometry.bufferToView(plan.remainder, vw.toFloat(), vh.toFloat())
                val (px, py) = apply(m, hx * vw, hy * vh)
                assertEquals("x s=$s r=$r hint=$hint", vw / 2.0, px, 1e-3)
                assertEquals("y s=$s r=$r hint=$hint", 0.0, py, 1e-3)
            }
        }
    }
}
