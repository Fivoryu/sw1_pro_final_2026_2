package com.example.captura_mobile.video

import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import com.example.captura_mobile.ar.JsonReader
import com.example.captura_mobile.ar.JsonWriter
import com.example.captura_mobile.ar.PackageZip

/** Files survive interruptions; only an explicit discard may remove the raw recording. */
internal object CaptureRecovery {
    enum class StopAction { FINALIZE, PACKAGE_FINALIZED, PRESERVE }

    fun onBackground(recording: Boolean, marking: Boolean, packageReady: Boolean): StopAction = when {
        marking && packageReady -> StopAction.PACKAGE_FINALIZED
        recording -> StopAction.FINALIZE
        else -> StopAction.PRESERVE
    }

    @Synchronized
    fun checkpoint(file: File, json: String) {
        file.parentFile?.mkdirs()
        val temporary = File(file.path + ".tmp")
        FileOutputStream(temporary).use { stream ->
            stream.write(json.toByteArray(Charsets.UTF_8))
            stream.fd.sync()
        }
        if (System.getProperty("os.name").orEmpty().startsWith("Windows", ignoreCase = true)) {
            replaceWindowsCheckpoint(temporary, file)
        } else {
            // Android (minSdk 24) and other POSIX hosts use same-directory rename.
            // Never delete the previous record to make a replacement succeed.
            check(temporary.renameTo(file)) { "Could not persist capture recovery checkpoint" }
        }
    }

    @Suppress("NewApi") // Desktop Windows only; Android API 24/25 never enters this method.
    private fun replaceWindowsCheckpoint(temporary: File, file: File) {
        java.nio.file.Files.move(temporary.toPath(), file.toPath(),
            java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        // If atomic replacement is unsupported or fails, propagate the error, retaining
        // the original and the synced temporary file. No non-atomic copy/delete fallback.
    }

    /** Only finalized, timeline-validated recordings are automatically packaged.
     * An abruptly killed, unfinalized encoder is preserved for explicit rescue. */
    @Synchronized
    fun recoverFinalized(filesDir: File, owner: String) {
        File(filesDir, "video_recovery").listFiles().orEmpty()
            .filter { it.name.endsWith(".finalized.json") }.forEach { checkpoint ->
                try {
                    val saved = JsonReader.parse(checkpoint.readText()) as? Map<*, *> ?: return@forEach
                    if (saved["ownerId"] != owner || saved["timelineValidated"] != true) return@forEach
                    val id = saved["captureId"] as? String ?: return@forEach
                    if (!Regex("^[A-Za-z0-9_-]{1,64}$").matches(id)) return@forEach
                    val journal = File(filesDir, "capture_packages/$id.json")
                    if (journal.isFile) return@forEach
                    val raw = File(filesDir, "video_work/$id")
                    if (!listOf(VideoSpec.VIDEO_FILE, VideoSpec.MANIFEST_FILE, VideoSpec.FRAMES_FILE,
                            VideoSpec.SENSORS_FILE).all { File(raw, it).isFile }) return@forEach
                    val zip = File(filesDir, "capture_packages/$id.zip")
                    zip.parentFile?.mkdirs()
                    PackageZip.zipDirectory(raw, zip)
                    if (zip.length() > VideoCaptureLimits.MAX_PACKAGE_BYTES) {
                        zip.delete() // Raw recording and recovery metadata are retained.
                        return@forEach
                    }
                    verifyAndSyncZip(zip)
                    val prototype = saved["result"] as? Map<*, *> ?: return@forEach
                    val result = prototype.entries.associate { it.key.toString() to it.value }.toMutableMap()
                    val packageInfo = (prototype["capturePackage"] as? Map<*, *>)
                        ?.entries?.associate { it.key.toString() to it.value }?.toMutableMap() ?: return@forEach
                    packageInfo["sizeBytes"] = zip.length()
                    packageInfo["sha256"] = sha256(zip)
                    result["capturePackage"] = packageInfo
                    checkpoint(journal, JsonWriter.write(mapOf("ownerId" to owner,
                        "listingId" to saved["listingId"], "result" to result)))
                    raw.deleteRecursively()
                    checkpoint.delete()
                    File(filesDir, "video_recovery/$id.json").delete()
                } catch (_: Exception) { /* Preserve all bytes for retry; never acknowledge failed recovery. */ }
            }
    }

    fun sha256(file: File): String = file.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(1024 * 1024)
        while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun verifyAndSyncZip(file: File) {
        val names = mutableSetOf<String>()
        ZipInputStream(file.inputStream().buffered()).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val entry = input.nextEntry ?: break
                check(names.add(entry.name)) { "Duplicate capture ZIP entry" }
                while (input.read(buffer) >= 0) { /* ZipInputStream verifies CRC at EOF. */ }
                input.closeEntry()
            }
        }
        check(names.containsAll(listOf(VideoSpec.VIDEO_FILE, VideoSpec.MANIFEST_FILE,
            VideoSpec.FRAMES_FILE, VideoSpec.SENSORS_FILE))) { "Incomplete capture ZIP" }
        FileOutputStream(file, true).use { it.fd.sync() }
    }
}
