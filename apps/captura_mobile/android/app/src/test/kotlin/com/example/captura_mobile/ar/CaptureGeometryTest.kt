package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class CaptureGeometryTest {

    @Test
    fun horizontalDistanceIgnoresHeight() {
        val a = Vec3(0.0, 0.0, 0.0)
        val b = Vec3(3.0, 5.0, 4.0)
        assertEquals(5.0, CaptureGeometry.horizontalDistance(a, b), 1e-9)
    }

    @Test
    fun edgeLengthsOpenPolylineHasOneEdgeLessThanPoints() {
        val points = listOf(Vec3(0.0, 0.0, 0.0), Vec3(2.0, 0.0, 0.0), Vec3(2.0, 0.0, 3.0))
        val lengths = CaptureGeometry.edgeLengths(points, closed = false)
        assertEquals(listOf(2.0, 3.0), lengths)
    }

    @Test
    fun edgeLengthsClosedPolygonAddsClosingEdge() {
        val points = listOf(Vec3(0.0, 0.0, 0.0), Vec3(2.0, 0.0, 0.0), Vec3(2.0, 0.0, 3.0), Vec3(0.0, 0.0, 3.0))
        val lengths = CaptureGeometry.edgeLengths(points, closed = true)
        assertEquals(listOf(2.0, 3.0, 2.0, 3.0), lengths)
    }

    @Test
    fun edgeLengthsClosedWithTwoPointsDoesNotDuplicateEdge() {
        val points = listOf(Vec3(0.0, 0.0, 0.0), Vec3(1.0, 0.0, 0.0))
        assertEquals(listOf(1.0), CaptureGeometry.edgeLengths(points, closed = true))
    }

    @Test
    fun edgeLengthsOfSinglePointIsEmpty() {
        assertEquals(emptyList<Double>(), CaptureGeometry.edgeLengths(listOf(Vec3(0.0, 0.0, 0.0)), closed = true))
    }

    @Test
    fun formatMetersUsesTwoDecimalsWithComma() {
        assertEquals("2,35 m", CaptureGeometry.formatMeters(2.3456))
        assertEquals("0,10 m", CaptureGeometry.formatMeters(0.1))
    }

    @Test
    fun projectToScreenMapsPointInFrontOfCameraToCentre() {
        // Identity view: camera at origin looking down -Z.
        val view = identity()
        val projection = perspective(near = 0.1f, far = 100f)
        val point = CaptureGeometry.projectToScreen(Vec3(0.0, 0.0, -2.0), view, projection, 1000, 2000)
        assertNotNull(point)
        assertEquals(500f, point!!.x, 1e-3f)
        assertEquals(1000f, point.y, 1e-3f)
    }

    @Test
    fun projectToScreenFlipsYAndScalesX() {
        val view = identity()
        val projection = perspective(near = 0.1f, far = 100f)
        // With a 90 degree fov and aspect 1, x = -z maps to the right edge, y = -z to the top edge.
        val right = CaptureGeometry.projectToScreen(Vec3(1.0, 0.0, -1.0), view, projection, 1000, 1000)!!
        assertEquals(1000f, right.x, 1e-3f)
        assertEquals(500f, right.y, 1e-3f)
        val top = CaptureGeometry.projectToScreen(Vec3(0.0, 1.0, -1.0), view, projection, 1000, 1000)!!
        assertEquals(500f, top.x, 1e-3f)
        assertEquals(0f, top.y, 1e-3f)
    }

    @Test
    fun projectToScreenAppliesViewMatrixTranslation() {
        // Camera moved to x = 1: the view matrix translates world by -1 on x.
        val view = identity().also { it[12] = -1f }
        val projection = perspective(near = 0.1f, far = 100f)
        val point = CaptureGeometry.projectToScreen(Vec3(1.0, 0.0, -3.0), view, projection, 800, 600)!!
        assertEquals(400f, point.x, 1e-3f)
        assertEquals(300f, point.y, 1e-3f)
    }

    @Test
    fun projectToScreenReturnsNullBehindCamera() {
        val point = CaptureGeometry.projectToScreen(Vec3(0.0, 0.0, 2.0), identity(), perspective(0.1f, 100f), 100, 100)
        assertNull(point)
    }

    private fun identity(): FloatArray = FloatArray(16).also {
        it[0] = 1f; it[5] = 1f; it[10] = 1f; it[15] = 1f
    }

    /** Column-major OpenGL perspective with 90 degree vertical fov and aspect 1. */
    private fun perspective(near: Float, far: Float): FloatArray {
        val m = FloatArray(16)
        m[0] = 1f
        m[5] = 1f
        m[10] = -(far + near) / (far - near)
        m[11] = -1f
        m[14] = -(2f * far * near) / (far - near)
        return m
    }
}
