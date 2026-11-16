package com.example.captura_mobile.video

import com.example.captura_mobile.ar.JsonReader
import com.example.captura_mobile.ar.JsonWriter
import com.example.captura_mobile.ar.PackageZip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

@Suppress("UNCHECKED_CAST")
class VideoPackageTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun map(value: Any?) = value as Map<String, Any?>

    private fun manifest(reference: ReferenceMark?, rooms: List<VideoRoom> = listOf(VideoRoom("room-1", "Sala", 100L, 900L))) =
        VideoManifestBuilder.build(
            VideoManifestInput(
                captureId = "3f2b8c1e-0000-4000-8000-000000000001",
                listingId = "listing-1",
                deviceModel = "SM-S711B",
                osVersion = "14",
                startedAtNs = 100L,
                timestampSource = TimestampSource.REALTIME,
                sensorOrientation = 90,
                rooms = rooms,
                reference = reference,
            ),
        )

    // --- S9: manifest, schema 2 ---

    @Test
    fun manifestFollowsTheFrozenSchema2Shape() {
        val json = map(JsonReader.parse(JsonWriter.write(manifest(null))))

        assertEquals(2, json["schemaVersion"])
        assertEquals("3f2b8c1e-0000-4000-8000-000000000001", json["captureId"])
        assertEquals("listing-1", json["listingId"])
        assertEquals(mapOf("model" to "SM-S711B", "os" to "android", "osVersion" to "14"), map(json["device"]))
        assertEquals(
            mapOf(
                "file" to "video.mp4", "width" to 1280, "height" to 720, "fps" to 30,
                "startedAtNs" to 100, "framesFile" to "frames.jsonl", "timestampSource" to "realtime",
                "sensorOrientation" to 90,
            ),
            map(json["video"]),
        )
        assertEquals(mapOf("file" to "sensors.jsonl", "rateHz" to 100), map(json["sensors"]))
        assertEquals(
            listOf(mapOf("id" to "room-1", "name" to "Sala", "fromNs" to 100, "toNs" to 900)),
            json["rooms"],
        )
        assertFalse("reference is optional and omitted when skipped", json.containsKey("reference"))
    }

    @Test
    fun manifestCarriesTheReferenceWhenMarked() {
        val reference = ReferenceMark.create(
            frameNs = 150L,
            p1 = ReferencePoint(0.31, 0.80),
            p2 = ReferencePoint(0.33, 0.12),
            lengthM = 2.0,
            label = "Puerta",
            surface = ReferenceSurface.FLOOR,
        )
        val json = map(JsonReader.parse(JsonWriter.write(manifest(reference))))

        assertEquals(
            mapOf(
                "kind" to "object", "label" to "Puerta", "lengthM" to 2.0, "surface" to "floor", "frameNs" to 150,
                "p1" to mapOf("x" to 0.31, "y" to 0.80), "p2" to mapOf("x" to 0.33, "y" to 0.12),
            ),
            map(json["reference"]),
        )
    }

    @Test
    fun timestampSourceIsRealtimeOnlyWhenTheCameraSaysSo() {
        assertEquals("realtime", TimestampSource.fromCamera(1))
        assertEquals("unknown", TimestampSource.fromCamera(0))
        assertEquals("unknown", TimestampSource.fromCamera(null))
    }

    // --- frames.jsonl / sensors.jsonl ---

    @Test
    fun framesAreOneLinePerFrameWithSequentialIndex() {
        val log = FrameLog()
        log.add(1_000L)
        log.add(34_000L)

        assertEquals(listOf("""{"i":0,"t":1000}""", """{"i":1,"t":34000}"""), log.lines())
        assertEquals(2, log.count)
        assertEquals(1_000L, log.firstTimestampNs)
    }

    @Test
    fun sensorsAreWrittenSortedByTimeWithTheContractFields() {
        val log = SensorLog()
        log.add(30L, SensorKind.MAG, 21f, -3.5f, 40.25f)
        log.add(10L, SensorKind.GYRO, 0.5f, 0f, -1f)
        log.add(20L, SensorKind.ACCEL, 0.25f, 9.5f, 0f)
        log.add(20L, SensorKind.GRAVITY, 0f, 9.75f, 0f)

        val lines = log.lines()

        assertEquals(
            listOf(
                """{"t":10,"type":"gyro","x":0.5,"y":0.0,"z":-1.0}""",
                """{"t":20,"type":"accel","x":0.25,"y":9.5,"z":0.0}""",
                """{"t":20,"type":"gravity","x":0.0,"y":9.75,"z":0.0}""",
                """{"t":30,"type":"mag","x":21.0,"y":-3.5,"z":40.25}""",
            ),
            lines,
        )
        lines.forEach { map(JsonReader.parse(it)) }
    }

    @Test
    fun nonFiniteSensorSamplesAreDropped() {
        val log = SensorLog()
        log.add(1L, SensorKind.GYRO, Float.NaN, 0f, 0f)
        assertTrue(log.lines().isEmpty())
    }

    // --- S6: rooms ---

    @Test
    fun roomsAreContiguousNonOverlappingAndAtLeastOne() {
        val timeline = RoomTimeline("Sala")
        timeline.start(100L)
        assertEquals("room-2", timeline.nextRoom(400L)?.id)
        timeline.nextRoom(700L)

        val rooms = timeline.finish(1_000L)

        assertEquals(
            listOf(
                VideoRoom("room-1", "Sala", 100L, 400L),
                VideoRoom("room-2", "Ambiente 2", 400L, 700L),
                VideoRoom("room-3", "Ambiente 3", 700L, 1_000L),
            ),
            rooms,
        )
        rooms.zipWithNext().forEach { (a, b) -> assertTrue(a.toNs <= b.fromNs) }
    }

    @Test
    fun aSingleRoomWithoutMarksCoversTheWholeRecording() {
        val timeline = RoomTimeline("")
        timeline.start(5L)

        assertEquals(listOf(VideoRoom("room-1", "Ambiente 1", 5L, 50L)), timeline.finish(50L))
    }

    @Test
    fun nextRoomIsIgnoredWhenNoTimeHasPassed() {
        val timeline = RoomTimeline("Sala")
        timeline.start(100L)

        assertNull(timeline.nextRoom(100L))
        assertEquals(1, timeline.finish(200L).size)
    }

    @Test
    fun anEmptyTrailingRoomIsDroppedOnFinish() {
        val timeline = RoomTimeline("Sala")
        timeline.start(100L)
        timeline.nextRoom(500L)

        assertEquals(listOf(VideoRoom("room-1", "Sala", 100L, 500L)), timeline.finish(500L))
    }

    // --- S5: reference ---

    @Test
    fun pixelsNormaliseToZeroOneWithTopLeftOrigin() {
        val point = ReferencePoint.fromPixels(320f, 180f, 1280f, 720f)

        assertEquals(0.25, point.x, 1e-9)
        assertEquals(0.25, point.y, 1e-9)
        val outside = ReferencePoint.fromPixels(-5f, 900f, 1280f, 720f)
        assertEquals(0.0, outside.x, 0.0)
        assertEquals(1.0, outside.y, 0.0)
    }

    @Test
    fun referenceRejectsInvalidLengthsAndIdenticalPoints() {
        val a = ReferencePoint(0.1, 0.1)
        val b = ReferencePoint(0.9, 0.9)
        assertThrows(IllegalArgumentException::class.java) {
            ReferenceMark.create(1L, a, b, 0.0, "x", ReferenceSurface.WALL)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ReferenceMark.create(1L, a, b, Double.NaN, "x", ReferenceSurface.WALL)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ReferenceMark.create(1L, a, a, 1.0, "x", ReferenceSurface.WALL)
        }
    }

    @Test
    fun referencePresetsAreEditableDefaults() {
        assertTrue(ReferencePresets.ALL.any { it.label.contains("A4") })
        assertTrue(ReferencePresets.ALL.any { it.label.contains("puerta", ignoreCase = true) })
        assertTrue(ReferencePresets.ALL.all { it.lengthM > 0 })
    }

    @Test
    fun referenceFrameMustBeLoggedAndInsideARoom() {
        val frames = FrameLog().apply { add(120L); add(150L) }
        val rooms = listOf(VideoRoom("room-1", "Sala", 100L, 151L))
        fun ref(ns: Long) = ReferenceMark.create(
            ns, ReferencePoint(0.1, 0.1), ReferencePoint(0.2, 0.9), 1.0, "x", ReferenceSurface.WALL,
        )

        assertTrue(ReferenceCoverage.isCovered(ref(150L), frames, rooms))
        assertFalse("frame not in frames.jsonl", ReferenceCoverage.isCovered(ref(140L), frames, rooms))
        assertFalse("frame outside every room", ReferenceCoverage.isCovered(ref(150L), frames, listOf(VideoRoom("r", "S", 100L, 150L))))
    }

    @Test
    fun blankListingIdIsRejected() {
        listOf("", "  ").forEach { blank ->
            assertThrows(IllegalArgumentException::class.java) {
                VideoManifestBuilder.build(
                    VideoManifestInput("c", blank, "m", "14", 1L, "unknown", 90, listOf(VideoRoom("room-1", "S", 1L, 2L)), null),
                )
            }
        }
    }

    @Test
    fun invalidSensorOrientationIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoManifestBuilder.build(
                VideoManifestInput("c", "l", "m", "14", 1L, "unknown", 45, listOf(VideoRoom("room-1", "S", 1L, 2L)), null),
            )
        }
    }

    // --- limits ---

    @Test
    fun recordingStopsAtFiveMinutes() {
        val second = 1_000_000_000L
        assertFalse(VideoCaptureLimits.reachedTimeLimit(10L, 10L + 299 * second))
        assertTrue(VideoCaptureLimits.reachedTimeLimit(10L, 10L + 300 * second))
    }

    @Test
    fun packageLimitIs150MiBInclusive() {
        assertFalse(VideoCaptureLimits.exceedsSize(150L * 1024 * 1024))
        assertTrue(VideoCaptureLimits.exceedsSize(150L * 1024 * 1024 + 1))
    }

    // --- package ---

    @Test
    fun packageHasTheFourFilesAndTheManifestFirst() {
        val work = tmp.newFolder("work")
        work.resolve("video.mp4").writeBytes(ByteArray(64) { it.toByte() })
        val frames = FrameLog().apply { add(1L); add(2L) }
        val sensors = SensorLog().apply { add(1L, SensorKind.GYRO, 1f, 2f, 3f) }
        val target = tmp.newFile("out.zip")

        val outcome = VideoPackageBuilder.build(work, target, manifest(null), frames, sensors)

        assertTrue(outcome is VideoPackageOutcome.Built)
        assertEquals(target.length(), (outcome as VideoPackageOutcome.Built).sizeBytes)
        ZipFile(target).use { zip ->
            assertEquals(
                listOf("manifest.json", "frames.jsonl", "sensors.jsonl", "video.mp4"),
                zip.entries().toList().map(ZipEntry::getName),
            )
            assertEquals(
                frames.lines().joinToString("\n", postfix = "\n"),
                zip.getInputStream(zip.getEntry("frames.jsonl")).readBytes().decodeToString(),
            )
        }
    }

    @Test
    fun packageAboveTheLimitIsRefusedAndRemoved() {
        val work = tmp.newFolder("big")
        work.resolve("video.mp4").writeBytes(ByteArray(2048) { (it * 31).toByte() })
        val target = tmp.newFolder("out").resolve("big.zip")

        val outcome = VideoPackageBuilder.build(
            work, target, manifest(null), FrameLog(), SensorLog(), maxBytes = 1024,
        )

        assertTrue(outcome is VideoPackageOutcome.TooLarge)
        assertFalse(target.exists())
    }

    // --- channel result ---

    @Test
    fun resultsFollowTheChannelContract() {
        val captured = VideoCaptureResult.captured(
            zipPath = "/p/a.zip", captureId = "id", sizeBytes = 10L, frameCount = 3,
            rooms = listOf(VideoRoom("room-1", "Sala", 1L, 2L)),
            hasReference = false, durationMs = 5000L, reachedTimeLimit = true, timestampSource = "unknown",
        )
        assertEquals("captured", captured["outcome"])
        assertEquals(false, captured["hasReference"])
        assertEquals(true, captured["reachedTimeLimit"])
        val pkg = map(captured["capturePackage"])
        assertEquals(3, pkg["keyframeCount"])
        assertEquals(listOf(mapOf("id" to "room-1", "name" to "Sala")), pkg["rooms"])
        assertEquals("cancelled", VideoCaptureResult.cancelled()["outcome"])
        assertEquals("package_too_large", VideoCaptureResult.error("package_too_large", "m")["code"])
    }

    // --- existing behaviour: the schema 1 zip is unchanged ---

    @Test
    fun schema1ZipStillStoresPngAndDeflatesJson() {
        val dir = tmp.newFolder("v1")
        dir.resolve("manifest.json").writeText("{" + "\"a\":1,".repeat(200) + "\"b\":2}")
        dir.resolve("depth.png").writeBytes(ByteArray(300) { (it * 7).toByte() })
        val target = tmp.newFile("v1.zip")

        PackageZip.zipDirectory(dir, target)

        ZipFile(target).use { zip ->
            val manifestEntry = zip.getEntry("manifest.json")
            val png = zip.getEntry("depth.png")
            assertTrue(manifestEntry.compressedSize < manifestEntry.size)
            assertTrue(png.compressedSize >= png.size)
            assertEquals("manifest.json", zip.entries().toList().first().name)
        }
    }
}
