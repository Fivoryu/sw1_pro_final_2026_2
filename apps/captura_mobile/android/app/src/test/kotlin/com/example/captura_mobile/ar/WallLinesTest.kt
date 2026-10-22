package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.tan

class WallLinesTest {

    private val floorY = -1.4

    private fun p(x: Double, z: Double) = Vec3(x, floorY, z)

    private fun wall(ax: Double, az: Double, bx: Double, bz: Double) = p(ax, az) to p(bx, bz)

    private fun assertCorners(expected: List<Pair<Double, Double>>, result: WallCornersResult) {
        assertTrue("expected corners, got $result", result is WallCornersResult.Corners)
        val corners = (result as WallCornersResult.Corners).corners
        assertEquals(expected.size, corners.size)
        expected.forEachIndexed { index, (x, z) ->
            assertEquals("corner $index x", x, corners[index].x, 1e-9)
            assertEquals("corner $index z", z, corners[index].z, 1e-9)
            assertEquals("corner $index y", floorY, corners[index].y, 1e-9)
        }
    }

    /** 4 x 3 rectangle; no marked point is at a corner. */
    private val rectangleWalls = listOf(
        wall(1.0, 0.0, 3.0, 0.0),
        wall(4.0, 0.5, 4.0, 2.5),
        wall(3.0, 3.0, 0.8, 3.0),
        wall(0.0, 2.2, 0.0, 0.7),
    )

    @Test
    fun rectangleFromPointsAwayFromCornersGivesExactCorners() {
        assertCorners(
            listOf(4.0 to 0.0, 4.0 to 3.0, 0.0 to 3.0, 0.0 to 0.0),
            WallLines.cornersFromWallLines(rectangleWalls),
        )
    }

    @Test
    fun pointsMayBeGivenInEitherDirectionAlongAWall() {
        val reversed = rectangleWalls.mapIndexed { index, (a, b) -> if (index % 2 == 0) b to a else a to b }
        assertCorners(
            listOf(4.0 to 0.0, 4.0 to 3.0, 0.0 to 3.0, 0.0 to 0.0),
            WallLines.cornersFromWallLines(reversed),
        )
    }

    @Test
    fun lShapedSixWallRoom() {
        val walls = listOf(
            wall(0.5, 0.0, 5.0, 0.0),
            wall(6.0, 0.4, 6.0, 1.5),
            wall(5.5, 2.0, 3.6, 2.0),
            wall(3.0, 2.6, 3.0, 4.4),
            wall(2.5, 5.0, 0.6, 5.0),
            wall(0.0, 4.0, 0.0, 1.0),
        )
        assertCorners(
            listOf(6.0 to 0.0, 6.0 to 2.0, 3.0 to 2.0, 3.0 to 5.0, 0.0 to 5.0, 0.0 to 0.0),
            WallLines.cornersFromWallLines(walls),
        )
    }

    @Test
    fun wrapAroundCornerJoinsLastAndFirstWall() {
        // Triangle (0,0), (4,0), (0,3): the last corner comes from wall 3 and wall 1.
        val walls = listOf(
            wall(1.0, 0.0, 3.0, 0.0),
            wall(3.2, 0.6, 0.8, 2.4),
            wall(0.0, 2.0, 0.0, 1.0),
        )
        val result = WallLines.cornersFromWallLines(walls) as WallCornersResult.Corners
        assertEquals(0.0, result.corners.last().x, 1e-9)
        assertEquals(0.0, result.corners.last().z, 1e-9)
        assertCorners(listOf(4.0 to 0.0, 0.0 to 3.0, 0.0 to 0.0), result)
    }

    @Test
    fun nearlyParallelConsecutiveWallsFailWithTheirIndices() {
        val tilt = tan(Math.toRadians(10.0))
        val walls = listOf(
            wall(1.0, 0.0, 3.0, 0.0),
            wall(4.0, 0.5, 4.0, 2.5),
            // Wall 3 is only 10 degrees away from wall 2.
            wall(4.5, 3.0, 4.5 + tilt, 4.0),
            wall(0.0, 2.2, 0.0, 0.7),
        )
        val result = WallLines.cornersFromWallLines(walls)
        assertEquals(WallCornersResult.NearlyParallel(firstWall = 2, secondWall = 3), result)
        assertEquals(
            "Las paredes 2 y 3 son casi paralelas: marcá otra pared entre ellas o revisá el orden.",
            (result as WallCornersResult.Failure).message,
        )
    }

    @Test
    fun nearlyParallelWrapAroundPairNamesLastAndFirstWall() {
        val walls = listOf(
            wall(1.0, 0.0, 3.0, 0.0),
            wall(4.0, 0.5, 4.0, 2.5),
            wall(3.5, 3.5, 1.5, 4.5),
            // Wall 4 runs almost parallel to wall 1 (5 degrees) but not to wall 3.
            wall(0.0, 1.0, 2.0, 1.0 + 2.0 * tan(Math.toRadians(5.0))),
        )
        val result = WallLines.cornersFromWallLines(walls)
        assertEquals(WallCornersResult.NearlyParallel(firstWall = 4, secondWall = 1), result)
        assertEquals(
            "Las paredes 4 y 1 son casi paralelas: marcá otra pared entre ellas o revisá el orden.",
            (result as WallCornersResult.Failure).message,
        )
    }

    @Test
    fun angleOfFifteenDegreesOrMoreIsAccepted() {
        val walls = listOf(
            wall(0.0, 0.0, 2.0, 0.0),
            wall(3.0, 0.0 + 3.0 * tan(Math.toRadians(16.0)), 4.0, 4.0 * tan(Math.toRadians(16.0))),
            wall(1.0, 3.0, 1.0, 2.0),
        )
        assertTrue(WallLines.cornersFromWallLines(walls) is WallCornersResult.Corners)
    }

    @Test
    fun fewerThanThreeWallsFail() {
        val result = WallLines.cornersFromWallLines(rectangleWalls.take(2))
        assertEquals(WallCornersResult.TooFewWalls(count = 2), result)
        assertEquals(
            "Marcá al menos 3 paredes para calcular las esquinas.",
            (result as WallCornersResult.Failure).message,
        )
        assertEquals(WallCornersResult.TooFewWalls(count = 0), WallLines.cornersFromWallLines(emptyList()))
    }

    @Test
    fun intersectionFarFromTheWallsIsDegenerate() {
        // Wall 2 is 16 degrees from wall 1 but 6 m away from it: they meet about 21 m away.
        val slope = tan(Math.toRadians(16.0))
        val walls = listOf(
            wall(0.0, 0.0, 1.0, 0.0),
            wall(0.0, 6.0, 1.0, 6.0 + slope),
            wall(5.0, 1.0, 5.0, 3.0),
        )
        val result = WallLines.cornersFromWallLines(walls)
        assertEquals(WallCornersResult.Degenerate(firstWall = 1, secondWall = 2), result)
        assertTrue((result as WallCornersResult.Failure).message.contains("paredes 1 y 2"))
    }

    @Test
    fun wallWithCoincidentPointsIsDegenerate() {
        val walls = listOf(
            wall(1.0, 0.0, 1.0, 0.0),
            wall(4.0, 0.5, 4.0, 2.5),
            wall(3.0, 3.0, 0.8, 3.0),
        )
        val result = WallLines.cornersFromWallLines(walls)
        assertEquals(WallCornersResult.ZeroLengthWall(wall = 1), result)
        assertTrue((result as WallCornersResult.Failure).message.contains("pared 1"))
    }
}
