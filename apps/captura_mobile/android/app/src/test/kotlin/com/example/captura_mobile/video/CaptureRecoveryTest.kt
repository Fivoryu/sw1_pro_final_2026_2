package com.example.captura_mobile.video

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import com.example.captura_mobile.ar.JsonWriter
import com.example.captura_mobile.ar.JsonReader

class CaptureRecoveryTest {
    @Test fun recordingBackgroundFinalizesInsteadOfDiscarding() {
        assertEquals(CaptureRecovery.StopAction.FINALIZE, CaptureRecovery.onBackground(true, false, false))
    }
    @Test fun markingBackgroundPackagesAlreadyFinalizedRecording() {
        assertEquals(CaptureRecovery.StopAction.PACKAGE_FINALIZED, CaptureRecovery.onBackground(false, true, true))
    }
    @Test fun finishingAndProcessRecoveryPreserveFiles() {
        assertEquals(CaptureRecovery.StopAction.PRESERVE, CaptureRecovery.onBackground(false, false, false))
        val root = Files.createTempDirectory("capture-recovery").toFile()
        try {
            val raw = root.resolve("video.mp4").also { it.writeText("original") }
            val journal = root.resolve("recovery.json")
            CaptureRecovery.checkpoint(journal, "{\"state\":\"recording\"}")
            CaptureRecovery.checkpoint(journal, "{\"state\":\"interrupted\"}")
            assertEquals("{\"state\":\"interrupted\"}", journal.readText())
            assertEquals("original", raw.readText())
            assertFalse(root.resolve("recovery.json.tmp").exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun finalizedMarkingRecoversAfterRestartOnlyForItsOwner() {
        val root = Files.createTempDirectory("capture-finalized").toFile()
        try {
            val raw = root.resolve("video_work/cap-1").also { it.mkdirs() }
            for (name in listOf(VideoSpec.VIDEO_FILE, VideoSpec.MANIFEST_FILE, VideoSpec.FRAMES_FILE, VideoSpec.SENSORS_FILE)) {
                raw.resolve(name).writeText("fixture") // File persistence test, not a native MP4 claim.
            }
            raw.resolve("reference-draft.json").writeText("{\"confirmed\":false}")
            val result = VideoCaptureResult.captured(root.resolve("capture_packages/cap-1.zip").absolutePath,
                "cap-1", 0, 5, listOf(VideoRoom("room-1", "Room", 1, 2)), false, 1, false, "realtime")
            CaptureRecovery.checkpoint(root.resolve("video_recovery/cap-1.finalized.json"), JsonWriter.write(mapOf(
                "ownerId" to "agent-1", "captureId" to "cap-1", "listingId" to "listing-1",
                "timelineValidated" to true, "result" to result)))
            CaptureRecovery.recoverFinalized(root, "agent-2")
            assertTrue(raw.resolve(VideoSpec.VIDEO_FILE).isFile)
            assertFalse(root.resolve("capture_packages/cap-1.zip").exists())
            CaptureRecovery.recoverFinalized(root, "agent-1")
            val journal = JsonReader.parse(root.resolve("capture_packages/cap-1.json").readText()) as Map<*, *>
            assertEquals("agent-1", journal["ownerId"])
            val recovered = journal["result"] as Map<*, *>
            val pkg = recovered["capturePackage"] as Map<*, *>
            assertEquals(CaptureRecovery.sha256(root.resolve("capture_packages/cap-1.zip")), pkg["sha256"])
            assertFalse(raw.exists())
            assertFalse(recovered["hasReference"] as Boolean)
            java.util.zip.ZipFile(root.resolve("capture_packages/cap-1.zip")).use { zip ->
                assertEquals("{\"confirmed\":false}", zip.getInputStream(zip.getEntry("reference-draft.json")).reader().readText())
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun repeatedCheckpointReplacementKeepsTheLatestCompleteRecordAndRawEvidence() {
        val root = Files.createTempDirectory("capture-replace").toFile()
        try {
            val raw = root.resolve("video.mp4").also { it.writeText("original") }
            val journal = root.resolve("recovery.json")
            repeat(20) { version ->
                val expected = JsonWriter.write(mapOf("version" to version, "state" to "recording"))
                CaptureRecovery.checkpoint(journal, expected)
                assertEquals(expected, journal.readText())
                assertFalse(root.resolve("recovery.json.tmp").exists())
            }
            assertEquals("original", raw.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun failedTemporaryWritePreservesThePreviousCheckpointAndRawEvidence() {
        val root = Files.createTempDirectory("capture-write-failure").toFile()
        try {
            val journal = root.resolve("recovery.json")
            CaptureRecovery.checkpoint(journal, "original checkpoint")
            val raw = root.resolve("video.mp4").also { it.writeText("original video") }
            // A directory blocks FileOutputStream portably, even with administrator permissions.
            root.resolve("recovery.json.tmp").mkdir()
            try {
                CaptureRecovery.checkpoint(journal, "replacement")
                fail("A failed write must not be acknowledged")
            } catch (_: java.io.IOException) { }
            assertEquals("original checkpoint", journal.readText())
            assertEquals("original video", raw.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun failedAtomicReplacementPreservesExistingDataAndSyncedTemporaryRecord() {
        val root = Files.createTempDirectory("capture-rename-failure").toFile()
        try {
            val journal = root.resolve("recovery.json").also { it.mkdir() }
            val evidence = journal.resolve("original.json").also { it.writeText("previous data") }
            try {
                CaptureRecovery.checkpoint(journal, "replacement")
                fail("A failed replacement must not be acknowledged")
            } catch (_: java.io.IOException) {
            } catch (_: IllegalStateException) { }
            assertEquals("previous data", evidence.readText())
            assertEquals("replacement", root.resolve("recovery.json.tmp").readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun unfinalizedProcessDeathIsPreservedWithoutClaimingRecovery() {
        val root = Files.createTempDirectory("capture-unfinalized").toFile()
        try {
            val raw = root.resolve("video_work/cap-1").also { it.mkdirs() }
            raw.resolve(VideoSpec.VIDEO_FILE).writeText("unfinalized encoder output")
            CaptureRecovery.checkpoint(root.resolve("video_recovery/cap-1.json"), "{\"state\":\"recording\"}")
            CaptureRecovery.recoverFinalized(root, "agent-1")
            assertTrue(raw.resolve(VideoSpec.VIDEO_FILE).isFile)
            assertFalse(root.resolve("capture_packages/cap-1.json").exists())
        } finally { root.deleteRecursively() }
    }
}
