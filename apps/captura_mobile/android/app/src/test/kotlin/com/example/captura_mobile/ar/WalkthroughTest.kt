package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

class WalkthroughTest {

    /** Rectangle of [length] x [thickness] on x/z, centred at (cx, cz), long axis rotated [deg] from +x. */
    private fun rotatedRectangle(cx: Double, cz: Double, length: Double, thickness: Double, deg: Double, y: Double): List<Vec3> {
        val a = Math.toRadians(deg)
        val ux = cos(a)
        val uz = sin(a)
        val vx = -uz
        val vz = ux
        val hl = length / 2
        val ht = thickness / 2
        return listOf(-hl to -ht, hl to -ht, hl to ht, -hl to ht).map { (s, t) ->
            Vec3(cx + s * ux + t * vx, y, cz + s * uz + t * vz)
        }
    }

    private fun assertPoint(expectedX: Double, expectedZ: Double, actual: Corner2) {
        assertEquals(expectedX, actual.x, 1e-9)
        assertEquals(expectedZ, actual.z, 1e-9)
    }

    @Test
    fun wallSegmentFollowsTheLongAxisOfARotatedPolygon() {
        val polygon = rotatedRectangle(1.0, 2.0, 3.0, 0.2, 30.0, y = 0.0) +
            rotatedRectangle(1.0, 2.0, 3.0, 0.2, 30.0, y = 2.4)
        val segment = WalkthroughGeometry.fitWallSegment(polygon, area = 7.2)
        assertNotNull(segment)
        segment!!
        val dx = 1.5 * cos(Math.toRadians(30.0))
        val dz = 1.5 * sin(Math.toRadians(30.0))
        val ends = listOf(segment.start, segment.end).sortedBy { it.x }
        assertPoint(1.0 - dx, 2.0 - dz, ends[0])
        assertPoint(1.0 + dx, 2.0 + dz, ends[1])
        assertEquals(3.0, segment.length, 1e-9)
        assertEquals(7.2, segment.area, 1e-12)
        assertEquals(0.0, segment.minY, 1e-12)
        assertEquals(2.4, segment.maxY, 1e-12)
    }

    @Test
    fun wallShorterThanThirtyCentimetresIsIgnored() {
        assertNull(WalkthroughGeometry.fitWallSegment(rotatedRectangle(0.0, 0.0, 0.25, 0.05, 10.0, 0.0), area = 0.1))
        assertNull(WalkthroughGeometry.fitWallSegment(listOf(Vec3(1.0, 0.0, 1.0)), area = 0.0))
        assertNull(WalkthroughGeometry.fitWallSegment(emptyList(), area = 0.0))
        assertNotNull(WalkthroughGeometry.fitWallSegment(rotatedRectangle(0.0, 0.0, 0.31, 0.0, 10.0, 0.0), area = 0.1))
    }

    @Test
    fun trajectorySamplerKeepsPointsAtLeastAQuarterMetreApart() {
        val sampler = TrajectorySampler()
        assertTrue(sampler.offer(0.0, 0.0))
        assertFalse(sampler.offer(0.1, 0.1))
        assertFalse(sampler.offer(0.2, 0.0))
        assertTrue(sampler.offer(0.25, 0.0))
        assertFalse(sampler.offer(0.4, 0.1))
        assertTrue(sampler.offer(0.25, 0.3))
        assertEquals(listOf(Corner2(0.0, 0.0), Corner2(0.25, 0.0), Corner2(0.25, 0.3)), sampler.points)
        assertEquals(0.55, sampler.length(), 1e-9)
    }

    @Test
    fun floorPlanesMustBeWithinTenCentimetresOfTheFloor() {
        assertTrue(WalkthroughGeometry.isAtFloorHeight(planeY = -1.30, floorY = -1.40))
        assertTrue(WalkthroughGeometry.isAtFloorHeight(planeY = -1.50, floorY = -1.40))
        assertFalse(WalkthroughGeometry.isAtFloorHeight(planeY = -1.25, floorY = -1.40))
        assertFalse(WalkthroughGeometry.isAtFloorHeight(planeY = -0.70, floorY = -1.40))
    }

    @Test
    fun floorLevelIsTheLowestUpwardPlaneSeen() {
        assertNull(WalkthroughGeometry.refineFloorY(null, emptyList()))
        assertEquals(-1.4, WalkthroughGeometry.refineFloorY(null, listOf(-0.7, -1.4))!!, 1e-12)
        assertEquals(-1.45, WalkthroughGeometry.refineFloorY(-1.4, listOf(-1.45, -0.7))!!, 1e-12)
        assertEquals(-1.4, WalkthroughGeometry.refineFloorY(-1.4, listOf(-0.7))!!, 1e-12)
    }

    @Test
    fun polygonAreaUsesTheShoelaceFormula() {
        val square = listOf(Corner2(0.0, 0.0), Corner2(2.0, 0.0), Corner2(2.0, 1.5), Corner2(0.0, 1.5))
        assertEquals(3.0, WalkthroughGeometry.polygonArea(square), 1e-12)
        assertEquals(3.0, WalkthroughGeometry.polygonArea(square.reversed()), 1e-12)
        assertEquals(0.0, WalkthroughGeometry.polygonArea(square.take(2)), 1e-12)
    }

    @Test
    fun walkthroughFinishNeedsAFloorAndThreeWalls() {
        val noFloor = CaptureRules.checkWalkthroughFinish(floorFound = false, wallCount = 5)
        assertTrue(noFloor is RuleCheck.Rejected)
        val twoWalls = CaptureRules.checkWalkthroughFinish(floorFound = true, wallCount = 2)
        assertEquals(
            RuleCheck.Rejected(
                "Detectamos 2 paredes; recorré las que faltan apuntando a su base, o usá el modo Marcar paredes.",
            ),
            twoWalls,
        )
        val none = CaptureRules.checkWalkthroughFinish(floorFound = true, wallCount = 0) as RuleCheck.Rejected
        assertTrue(none.message.contains("Detectamos 0 paredes"))
        assertEquals(RuleCheck.Ok, CaptureRules.checkWalkthroughFinish(floorFound = true, wallCount = 3))
    }

    @Test
    fun captureModeDefaultsToWalls() {
        assertEquals(CaptureMode.WALKTHROUGH, CaptureMode.fromArgument("walkthrough"))
        assertEquals(CaptureMode.WALLS, CaptureMode.fromArgument("walls"))
        assertEquals(CaptureMode.WALLS, CaptureMode.fromArgument(null))
        assertEquals(CaptureMode.WALLS, CaptureMode.fromArgument("corners"))
        assertEquals("walkthrough", CaptureMode.WALKTHROUGH.wireName)
        assertEquals("walls", CaptureMode.WALLS.wireName)
    }

    @Test
    fun walkthroughResultHasContractShape() {
        val walls = listOf(
            WallSegment(Corner2(0.0, 0.0), Corner2(3.0, 0.0), area = 6.0, minY = -1.4, maxY = 0.9),
            WallSegment(Corner2(3.0, 0.0), Corner2(3.0, 2.0), area = 4.0, minY = -1.35, maxY = 1.0),
            WallSegment(Corner2(3.0, 2.0), Corner2(0.0, 2.0), area = 5.5, minY = -1.4, maxY = 0.8),
        )
        val result = CaptureResult.captured(
            corners = emptyList(),
            height = RoomHeight(2.5, RoomHeight.SOURCE_CEILING_PLANE),
            boxes = emptyList(),
            metrics = CaptureMetrics(
                durationMs = 90000L,
                trackingLossCount = 2,
                depthSupported = true,
                cornerHitDistances = emptyList(),
                floorY = -1.4,
                method = CaptureMetrics.METHOD_WALKTHROUGH,
            ),
            observations = WalkthroughObservations(
                floorY = -1.4,
                walls = walls,
                floors = listOf(listOf(Corner2(0.0, 0.0), Corner2(2.0, 0.0), Corner2(2.0, 1.0))),
                trajectory = listOf(Corner2(1.0, 1.0), Corner2(1.5, 1.0)),
            ),
        )
        assertEquals(listOf("outcome", "corners", "height", "boxes", "metrics", "observations"), result.keys.toList())
        assertEquals("captured", result["outcome"])
        assertEquals(emptyList<Any>(), result["corners"])
        assertEquals(emptyList<Any>(), result["boxes"])
        val metrics = result["metrics"] as Map<*, *>
        assertEquals("walkthrough", metrics["method"])
        assertEquals(emptyList<Any>(), metrics["cornerHitDistances"])
        assertEquals(-1.4, metrics["floorY"])
        val observations = result["observations"] as Map<*, *>
        assertEquals(listOf("floorY", "walls", "floors", "trajectory"), observations.keys.toList())
        assertEquals(-1.4, observations["floorY"])
        assertEquals(
            mapOf(
                "start" to mapOf("x" to 0.0, "z" to 0.0),
                "end" to mapOf("x" to 3.0, "z" to 0.0),
                "area" to 6.0,
                "minY" to -1.4,
                "maxY" to 0.9,
            ),
            (observations["walls"] as List<*>)[0],
        )
        assertEquals(3, (observations["walls"] as List<*>).size)
        assertEquals(
            listOf(listOf(mapOf("x" to 0.0, "z" to 0.0), mapOf("x" to 2.0, "z" to 0.0), mapOf("x" to 2.0, "z" to 1.0))),
            observations["floors"],
        )
        assertEquals(listOf(mapOf("x" to 1.0, "z" to 1.0), mapOf("x" to 1.5, "z" to 1.0)), observations["trajectory"])

        // Every number survives the channel JSON as a double.
        val parsed = JsonReader.parse(JsonWriter.write(result)) as Map<*, *>
        val parsedObservations = parsed["observations"] as Map<*, *>
        val firstWall = (parsedObservations["walls"] as List<*>)[0] as Map<*, *>
        assertTrue((firstWall["start"] as Map<*, *>)["x"] is Double)
        assertTrue(firstWall["area"] is Double)
        assertTrue(parsedObservations["floorY"] is Double)
    }

    @Test
    fun wallsModeResultHasNoObservationsKey() {
        val result = CaptureResult.captured(
            corners = listOf(Corner2(0.0, 0.0), Corner2(1.0, 0.0), Corner2(1.0, 1.0)),
            height = null,
            boxes = emptyList(),
            metrics = CaptureMetrics(1L, 0, false, listOf(1.0), 0.0, CaptureMetrics.METHOD_WALL_LINES),
        )
        assertFalse(result.containsKey("observations"))
    }

    @Test
    fun formatsAreaAndTrajectoryWithDecimalComma() {
        assertEquals("12,35 m²", WalkthroughGeometry.formatSquareMeters(12.345))
        assertEquals("8,3 m", WalkthroughGeometry.formatTrajectory(8.26))
        assertEquals(5.0, hypot(3.0, 4.0), 0.0)
    }
}
