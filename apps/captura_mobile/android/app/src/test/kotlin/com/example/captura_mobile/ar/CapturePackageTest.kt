package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CapturePackageTest {

    private val identity = CameraPose(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)

    private fun input(
        depth: Intrinsics? = null,
        keyframes: List<PackageKeyframe> = emptyList(),
        floorY: Double? = -1.42,
    ) = ManifestInput(
        captureId = "cap-1",
        listingId = "listing-9",
        capturedAt = "2026-10-21T22:10:00Z",
        deviceModel = "SM-S711B",
        arcoreVersion = "1.57.0",
        depthSupported = depth != null,
        image = Intrinsics(640, 480, 500.0, 501.0, 320.0, 240.0),
        depth = depth,
        floorY = floorY,
        rooms = listOf(PackageRoom("room-1", "Dormitorio 1"), PackageRoom("room-2", "Ambiente 2")),
        planes = listOf(
            PackagePlane("p1", PlaneKind.FLOOR, identity, listOf(0.0 to 0.0, 1.0 to 0.0, 1.0 to 1.0)),
            PackagePlane("p2", PlaneKind.WALL, identity, listOf(0.0 to 0.0, 2.0 to 0.0, 2.0 to 1.0)),
        ),
        trajectory = listOf(TrajectorySample(0, 0.0, 0.0, "room-1"), TrajectorySample(1200, 0.5, 0.25, "room-2")),
        keyframes = keyframes,
    )

    @Suppress("UNCHECKED_CAST")
    private fun parse(map: Map<String, Any?>): Map<String, Any?> =
        JsonReader.parse(JsonWriter.write(map)) as Map<String, Any?>

    @Test
    fun manifestFollowsTheFrozenContract() {
        val manifest = parse(
            ManifestBuilder.build(
                input(
                    depth = Intrinsics(160, 120, 125.0, 125.25, 80.0, 60.0),
                    keyframes = listOf(
                        PackageKeyframe(1, 123_000_000, "room-1", identity, "frames/000001.jpg", "depth/000001.png", "confidence/000001.png"),
                    ),
                ),
            ),
        )
        assertEquals(1, manifest["schemaVersion"])
        assertEquals("cap-1", manifest["captureId"])
        assertEquals("listing-9", manifest["listingId"])
        assertEquals("2026-10-21T22:10:00Z", manifest["capturedAt"])
        assertEquals(
            mapOf("model" to "SM-S711B", "arcoreVersion" to "1.57.0", "depthSupported" to true),
            manifest["device"],
        )
        assertEquals(
            mapOf("width" to 640, "height" to 480, "fx" to 500.0, "fy" to 501.0, "cx" to 320.0, "cy" to 240.0),
            manifest["image"],
        )
        assertEquals(
            mapOf("width" to 160, "height" to 120, "fx" to 125.0, "fy" to 125.25, "cx" to 80.0, "cy" to 60.0),
            manifest["depth"],
        )
        assertEquals(-1.42, manifest["floorY"])
        assertEquals(
            listOf(mapOf("id" to "room-1", "name" to "Dormitorio 1"), mapOf("id" to "room-2", "name" to "Ambiente 2")),
            manifest["rooms"],
        )
        val planes = manifest["planes"] as List<*>
        val floor = planes[0] as Map<*, *>
        assertEquals("floor", floor["type"])
        assertEquals(listOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0), floor["pose"])
        assertEquals(listOf(listOf(0.0, 0.0), listOf(1.0, 0.0), listOf(1.0, 1.0)), floor["polygon"])
        assertEquals("wall", (planes[1] as Map<*, *>)["type"])
        assertEquals(
            listOf(listOf(0, 0.0, 0.0, "room-1"), listOf(1200, 0.5, 0.25, "room-2")),
            manifest["trajectory"],
        )
        val frame = (manifest["keyframes"] as List<*>)[0] as Map<*, *>
        assertEquals(1, frame["index"])
        assertEquals(123_000_000, frame["timestampNs"])
        assertEquals("room-1", frame["roomId"])
        assertEquals("frames/000001.jpg", frame["image"])
        assertEquals("depth/000001.png", frame["depth"])
        assertEquals("confidence/000001.png", frame["confidence"])
        assertTrue(manifest.containsKey("reference"))
        assertNull(manifest["reference"])
    }

    @Test
    fun withoutDepthSupportDepthFieldsAreNull() {
        val manifest = parse(
            ManifestBuilder.build(
                input(
                    keyframes = listOf(PackageKeyframe(1, 1, "room-1", identity, "frames/000001.jpg", null, null)),
                ),
            ),
        )
        assertTrue(manifest.containsKey("depth"))
        assertNull(manifest["depth"])
        val frame = (manifest["keyframes"] as List<*>)[0] as Map<*, *>
        assertTrue(frame.containsKey("depth"))
        assertNull(frame["depth"])
        assertNull(frame["confidence"])
        assertEquals(false, (manifest["device"] as Map<*, *>)["depthSupported"])
    }

    @Test
    fun missingFloorIsWrittenAsNullNotAGuess() {
        val manifest = parse(ManifestBuilder.build(input(floorY = null)))
        assertTrue(manifest.containsKey("floorY"))
        assertNull(manifest["floorY"])
    }

    @Test
    fun unknownListingIsNull() {
        val manifest = parse(ManifestBuilder.build(input().copy(listingId = null)))
        assertNull(manifest["listingId"])
    }

    @Test
    fun intrinsicsScaleWithTheResolution() {
        val image = Intrinsics(640, 480, 500.0, 500.0, 320.0, 240.0)
        val depth = image.scaledTo(160, 120)
        assertEquals(Intrinsics(160, 120, 125.0, 125.0, 80.0, 60.0), depth)
    }

    @Test
    fun roomSequenceNamesTheFirstRoomAndNumbersTheNext() {
        val rooms = RoomSequence("Dormitorio 1")
        assertEquals("room-1", rooms.currentId)
        assertEquals(listOf(PackageRoom("room-1", "Dormitorio 1")), rooms.rooms)
        assertEquals("room-2", rooms.next().id)
        assertEquals("Ambiente 2", rooms.rooms.last().name)
        assertEquals("room-2", rooms.currentId)
        assertEquals("room-3", rooms.next().id)
        assertEquals("Ambiente 3", rooms.rooms.last().name)
        assertEquals(3, rooms.rooms.map { it.id }.toSet().size)
    }

    @Test
    fun blankFirstRoomNameFallsBackToAmbiente1() {
        assertEquals("Ambiente 1", RoomSequence("  ").rooms.single().name)
    }
}
