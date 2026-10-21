package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureResultTest {

    private fun sampleCaptured(): Map<String, Any?> = CaptureResult.captured(
        corners = listOf(Corner2(0.0, 0.0), Corner2(3.25, 0.0), Corner2(3.25, 4.0)),
        height = RoomHeight(2.6, RoomHeight.SOURCE_CEILING_PLANE),
        boxes = listOf(
            CapturedBox(listOf(Corner2(1.0, 1.0), Corner2(1.8, 1.5)), 0.75, CapturedBox.SOURCE_DEPTH, 0.5),
            CapturedBox(listOf(Corner2(2.0, 2.0), Corner2(2.5, 2.5)), null, null, null),
        ),
        metrics = CaptureMetrics(
            durationMs = 61234L,
            trackingLossCount = 1,
            depthSupported = true,
            cornerHitDistances = listOf(1.2, 1.5, 2.0),
            floorY = -1.4,
        ),
    )

    @Test
    fun capturedResultHasContractShape() {
        val result = sampleCaptured()
        assertEquals(listOf("outcome", "corners", "height", "boxes", "metrics"), result.keys.toList())
        assertEquals("captured", result["outcome"])
        assertEquals(listOf(mapOf("x" to 0.0, "z" to 0.0), mapOf("x" to 3.25, "z" to 0.0), mapOf("x" to 3.25, "z" to 4.0)), result["corners"])
        assertEquals(mapOf("value" to 2.6, "source" to "ceiling_plane"), result["height"])
        val boxes = result["boxes"] as List<*>
        assertEquals(
            mapOf(
                "corners" to listOf(mapOf("x" to 1.0, "z" to 1.0), mapOf("x" to 1.8, "z" to 1.5)),
                "height" to 0.75,
                "heightSource" to "depth",
                "confidence" to 0.5,
            ),
            boxes[0],
        )
        val manual = boxes[1] as Map<*, *>
        assertTrue(manual.containsKey("height") && manual["height"] == null)
        assertTrue(manual.containsKey("heightSource") && manual["heightSource"] == null)
        assertTrue(manual.containsKey("confidence") && manual["confidence"] == null)
        assertEquals(
            mapOf(
                "durationMs" to 61234L,
                "trackingLossCount" to 1,
                "depthSupported" to true,
                "cornerHitDistances" to listOf(1.2, 1.5, 2.0),
                "floorY" to -1.4,
            ),
            result["metrics"],
        )
    }

    @Test
    fun capturedResultWithoutHeightKeepsExplicitNull() {
        val result = CaptureResult.captured(
            corners = listOf(Corner2(0.0, 0.0), Corner2(1.0, 0.0), Corner2(1.0, 1.0)),
            height = null,
            boxes = emptyList(),
            metrics = CaptureMetrics(1L, 0, false, listOf(1.0, 1.0, 1.0), 0.0),
        )
        assertTrue(result.containsKey("height"))
        assertNull(result["height"])
        assertEquals(emptyList<Any>(), result["boxes"])
    }

    @Test
    fun wallPointHeightSourceIsSerialised() {
        assertEquals("wall_point", RoomHeight(2.4, RoomHeight.SOURCE_WALL_POINT).toMap()["source"])
    }

    @Test
    fun cancelledAndErrorResults() {
        assertEquals(mapOf("outcome" to "cancelled"), CaptureResult.cancelled())
        assertEquals(
            mapOf("outcome" to "error", "code" to "camera_permission_denied", "message" to "Sin cámara"),
            CaptureResult.error(CaptureResult.ERROR_CAMERA_PERMISSION_DENIED, "Sin cámara"),
        )
        assertEquals("arcore_unavailable", CaptureResult.ERROR_ARCORE_UNAVAILABLE)
        assertEquals("arcore_install_declined", CaptureResult.ERROR_ARCORE_INSTALL_DECLINED)
        assertEquals("session_failed", CaptureResult.ERROR_SESSION_FAILED)
    }

    @Test
    fun jsonWriterProducesValidJsonWithDecimalPointsForDoubles() {
        val json = JsonWriter.write(mapOf("a" to 2.0, "b" to 3, "c" to null, "d" to listOf(true, "x\"y"), "e" to 7L))
        assertEquals("{\"a\":2.0,\"b\":3,\"c\":null,\"d\":[true,\"x\\\"y\"],\"e\":7}", json)
    }

    @Test(expected = IllegalArgumentException::class)
    fun jsonWriterRejectsNonFiniteNumbers() {
        JsonWriter.write(mapOf("a" to Double.NaN))
    }

    @Test
    fun jsonRoundTripKeepsCodecFriendlyTypes() {
        val parsed = JsonReader.parse(JsonWriter.write(sampleCaptured())) as Map<*, *>
        assertEquals("captured", parsed["outcome"])
        val height = parsed["height"] as Map<*, *>
        assertTrue(height["value"] is Double)
        assertEquals(2.6, height["value"] as Double, 1e-12)
        val metrics = parsed["metrics"] as Map<*, *>
        assertEquals(61234, (metrics["durationMs"] as Number).toInt())
        assertTrue(metrics["durationMs"] is Int || metrics["durationMs"] is Long)
        assertEquals(true, metrics["depthSupported"])
        assertTrue(metrics["floorY"] is Double)
        val boxes = parsed["boxes"] as List<*>
        val manual = boxes[1] as Map<*, *>
        assertTrue(manual.containsKey("height"))
        assertNull(manual["height"])
        val corners = parsed["corners"] as List<*>
        val first = corners[0] as Map<*, *>
        assertTrue("whole-number coordinate must stay a Double", first["x"] is Double)
    }

    @Test
    fun wallLinesMethodIsAppendedToMetrics() {
        val metrics = CaptureMetrics(
            durationMs = 10L,
            trackingLossCount = 0,
            depthSupported = false,
            cornerHitDistances = listOf(1.0, 1.1, 1.2, 1.3, 1.4, 1.5),
            floorY = -1.3,
            method = CaptureMetrics.METHOD_WALL_LINES,
        ).toMap()
        assertEquals(
            listOf("durationMs", "trackingLossCount", "depthSupported", "cornerHitDistances", "floorY", "method"),
            metrics.keys.toList(),
        )
        assertEquals("wall_lines", metrics["method"])
    }
}
