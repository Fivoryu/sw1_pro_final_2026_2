package com.example.captura_mobile.video

import com.example.captura_mobile.ar.JsonWriter
import com.example.captura_mobile.ar.PackageZip
import java.io.File

/*
 * Pure parts of the F07 video capture package, schema 2 (docs/api/f07-capture-package.md):
 * manifest, frame and sensor logs, rooms, scale reference and the ZIP. Nothing here depends on
 * Android so everything is JVM-tested; the Camera2 and sensor code lives in VideoRecorder.kt.
 * Every value below is the frozen S9 contract of odd/tasks/f07-video-capture-reconstruction.md.
 */

object VideoSpec {
    const val SCHEMA_VERSION = 2
    const val VIDEO_FILE = "video.mp4"
    const val FRAMES_FILE = "frames.jsonl"
    const val SENSORS_FILE = "sensors.jsonl"
    const val MANIFEST_FILE = "manifest.json"
    const val FPS = 30
    const val SENSOR_RATE_HZ = 100

    /**
     * Recording sizes in order of preference (ASSUMPTION, unmeasured). Any 4:3 size wins over 16:9 because the
     * sensor is 4:3: the whole field of view is recorded and shown, nothing is cropped. 1280x720 stays as the
     * last-resort fallback so phones without a 4:3 option still record.
     */
    val PREFERRED_SIZES = listOf(VideoSize(1440, 1080), VideoSize(1280, 960), VideoSize(1280, 720))

    /** The last-resort size; it also names the failure message when the camera offers none of the sizes. */
    val FALLBACK_SIZE: VideoSize = PREFERRED_SIZES.last()

    /**
     * Bitrate of the largest preferred size (1440x1080). ASSUMPTION, unmeasured: 5 min x 3.5 Mbps is about 131 MB,
     * which keeps a full recording under the 150 MiB package limit with margin for the logs and the ZIP.
     */
    const val BITRATE_BPS = 3_500_000
    private const val REFERENCE_PIXELS = 1440L * 1080L

    /** The floor is the 3 Mbps the 1280x720 format had before; the cap keeps any size within the package limit. */
    private const val MIN_BITRATE_BPS = 3_000_000
    private const val MAX_BITRATE_BPS = BITRATE_BPS

    /** The first of [PREFERRED_SIZES] that the camera lists for MediaRecorder; null when none is available. */
    fun chooseVideoSize(available: Collection<VideoSize>): VideoSize? = PREFERRED_SIZES.firstOrNull { it in available }

    /** Bitrate proportional to the pixel count of [size] against 1440x1080, between the floor and the cap. */
    fun bitrateFor(size: VideoSize): Int {
        val scaled = BITRATE_BPS.toLong() * size.width.toLong() * size.height.toLong() / REFERENCE_PIXELS
        return scaled.coerceIn(MIN_BITRATE_BPS.toLong(), MAX_BITRATE_BPS.toLong()).toInt()
    }

    /** Message when the camera lists none of the preferred sizes. */
    fun unsupportedSizeMessage(): String = "La cámara no graba en ${FALLBACK_SIZE.width}x${FALLBACK_SIZE.height}."
}

/** A video size in pixels (the stored frame, unrotated). */
data class VideoSize(val width: Int, val height: Int)

object VideoCaptureLimits {
    const val MAX_DURATION_NS = 5L * 60L * 1_000_000_000L

    /** The server's `MAX_PACKAGE_BYTES`: 150 MiB. */
    const val MAX_PACKAGE_BYTES = 150L * 1024L * 1024L

    fun reachedTimeLimit(startedAtNs: Long, nowNs: Long): Boolean = nowNs - startedAtNs >= MAX_DURATION_NS

    fun exceedsSize(bytes: Long): Boolean = bytes > MAX_PACKAGE_BYTES
}

object TimestampSource {
    const val REALTIME = "realtime"
    const val UNKNOWN = "unknown"

    /** Camera2 `SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME`. */
    private const val CAMERA_SOURCE_REALTIME = 1

    /** `realtime` only when the camera reports the realtime source; otherwise `unknown`. */
    fun fromCamera(sensorInfoTimestampSource: Int?): String =
        if (sensorInfoTimestampSource == CAMERA_SOURCE_REALTIME) REALTIME else UNKNOWN
}

// region Scale reference (S5)

enum class ReferenceSurface(val wireName: String) { FLOOR("floor"), WALL("wall") }

/** A point on the frame, normalised to 0..1 with the origin at the top left. */
data class ReferencePoint(val x: Double, val y: Double) {
    fun toMap(): Map<String, Any?> = linkedMapOf("x" to x, "y" to y)

    companion object {
        /** Taps slightly outside the frame clamp to its edge. */
        fun fromPixels(px: Float, py: Float, width: Float, height: Float): ReferencePoint {
            require(width > 0f && height > 0f) { "Frame size must be positive" }
            return ReferencePoint(
                (px / width).toDouble().coerceIn(0.0, 1.0),
                (py / height).toDouble().coerceIn(0.0, 1.0),
            )
        }
    }
}

/** Where the corners of a [ReferenceRect] came from (docs/api/f07-capture-package.md, `reference.rect.source`). */
enum class ReferenceRectSource(val wireName: String) {
    /** Detected by the app and confirmed untouched. */
    AUTO("auto"),

    /** Detected, then corrected by hand. */
    ADJUSTED("adjusted"),

    /** The four corners were placed by hand without a detection. */
    MANUAL("manual"),
}

/**
 * A rectangle of known real sides on the reference frame (optional `reference.rect`). The invariants are
 * the frozen contract: `widthM >= heightM`, four corners in 0..1, and the ring starts on the long side
 * (`corners[0]`->`corners[1]` is `widthM`, `corners[1]`->`corners[2]` is `heightM`).
 */
class ReferenceRect private constructor(
    val widthM: Double,
    val heightM: Double,
    val corners: List<ReferencePoint>,
    val source: ReferenceRectSource,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "widthM" to widthM,
        "heightM" to heightM,
        "corners" to corners.map { it.toMap() },
        "source" to source.wireName,
    )

    companion object {
        /** @throws IllegalArgumentException when any contract invariant is broken. */
        fun create(widthM: Double, heightM: Double, corners: List<ReferencePoint>, source: ReferenceRectSource): ReferenceRect {
            require(widthM.isFinite() && widthM > 0.0) { "The rectangle width must be a positive number" }
            require(heightM.isFinite() && heightM > 0.0) { "The rectangle height must be a positive number" }
            require(widthM >= heightM) { "The rectangle width must be the long side" }
            require(corners.size == 4) { "A rectangle needs four corners" }
            require(corners.all { it.x.isFinite() && it.y.isFinite() && it.x in 0.0..1.0 && it.y in 0.0..1.0 }) {
                "The rectangle corners must lie inside the frame"
            }
            require(corners.toSet().size == 4) { "The rectangle corners must be four different points" }
            require(isConvexRing(corners)) { "The rectangle corners must form a convex ring" }
            return ReferenceRect(widthM, heightM, corners.toList(), source)
        }

        /** True when the four points, in order, turn the same way at every corner (no bow-tie, no dent). */
        fun isConvexRing(corners: List<ReferencePoint>): Boolean {
            if (corners.size != 4) return false
            var sign = 0
            for (i in 0 until 4) {
                val a = corners[i]
                val b = corners[(i + 1) % 4]
                val c = corners[(i + 2) % 4]
                val cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                val s = if (cross > 0.0) 1 else if (cross < 0.0) -1 else return false
                if (sign == 0) sign = s else if (sign != s) return false
            }
            return true
        }

        /**
         * Rotates the consecutive [quad] so that it starts on the pair of opposite sides that matches the long
         * side (the longer pair, measured in frame pixels, not in normalised units) and returns the corners in
         * contract order. The ratio of [widthM] to [heightM] cannot decide anything the longer pair does not:
         * both candidates are the same two lengths swapped.
         */
        fun orient(
            quad: List<ReferencePoint>,
            widthM: Double,
            heightM: Double,
            frameWidth: Int,
            frameHeight: Int,
        ): List<ReferencePoint> {
            require(quad.size == 4) { "A rectangle needs four corners" }
            require(widthM >= heightM) { "The rectangle width must be the long side" }
            fun side(a: ReferencePoint, b: ReferencePoint) =
                Math.hypot((a.x - b.x) * frameWidth, (a.y - b.y) * frameHeight)
            val first = side(quad[0], quad[1]) + side(quad[2], quad[3])
            val second = side(quad[1], quad[2]) + side(quad[3], quad[0])
            val shift = if (first >= second) 0 else 1
            return List(4) { quad[(shift + it) % 4] }
        }
    }
}

/** An object of known length the agent marked on frame [frameNs]. */
class ReferenceMark private constructor(
    val frameNs: Long,
    val p1: ReferencePoint,
    val p2: ReferencePoint,
    val lengthM: Double,
    val label: String,
    val surface: ReferenceSurface,
    val rect: ReferenceRect? = null,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf<String, Any?>(
        "kind" to "object",
        "label" to label,
        "lengthM" to lengthM,
        "surface" to surface.wireName,
        "frameNs" to frameNs,
        "p1" to p1.toMap(),
        "p2" to p2.toMap(),
    ).also { map -> rect?.let { map["rect"] = it.toMap() } }

    companion object {
        /** @throws IllegalArgumentException for a non-positive length or two identical ends. */
        fun create(
            frameNs: Long,
            p1: ReferencePoint,
            p2: ReferencePoint,
            lengthM: Double,
            label: String,
            surface: ReferenceSurface,
            rect: ReferenceRect? = null,
        ): ReferenceMark {
            require(lengthM.isFinite() && lengthM > 0.0) { "The reference length must be a positive number" }
            require(p1 != p2) { "The two ends of the reference must be different points" }
            if (rect != null) {
                require(rect.widthM == lengthM) { "The rectangle width must equal the reference length" }
                require(rect.corners[0] == p1 && rect.corners[1] == p2) { "The rectangle must start at p1 and p2" }
            }
            return ReferenceMark(frameNs, p1, p2, lengthM, label.trim().ifEmpty { "Objeto" }, surface, rect)
        }
    }
}

/**
 * Known sizes offered to the agent; the length stays editable and a free value is always allowed. [otherSideM] is the
 * short side of a rectangular object; without it the preset is 2-point manual only (a door, say).
 */
data class ReferencePreset(val label: String, val lengthM: Double, val surface: ReferenceSurface, val otherSideM: Double? = null)

object ReferencePresets {
    val ALL = listOf(
        ReferencePreset("Hoja A4 (lado largo)", 0.297, ReferenceSurface.WALL, otherSideM = 0.210),
        ReferencePreset("Tarjeta (lado largo)", 0.0856, ReferenceSurface.WALL, otherSideM = 0.05398),
        ReferencePreset("Puerta estándar (alto)", 2.0, ReferenceSurface.FLOOR),
    )
}

// endregion

// region Rooms (S6)

/** One room interval of the video, in `elapsedRealtimeNanos`: [fromNs, toNs). */
data class VideoRoom(val id: String, val name: String, val fromNs: Long, val toNs: Long)

/**
 * Rooms of one recording. The first takes the name the agent typed (or «Ambiente 1»); «Siguiente
 * ambiente» closes the current interval and opens the next at the same instant, so intervals
 * never overlap and always cover the recording.
 */
class RoomTimeline(firstName: String) {
    private class Open(val id: String, val name: String, val fromNs: Long)

    private val firstRoomName = firstName.trim().ifEmpty { "Ambiente 1" }
    private val closed = mutableListOf<VideoRoom>()
    private var current: Open? = null

    val currentId: String? get() = current?.id

    fun start(startNs: Long) {
        check(current == null) { "The timeline was already started" }
        current = Open("room-1", firstRoomName, startNs)
    }

    /** Opens the next room at [nowNs]; null (and no change) when no time has passed in the current one. */
    fun nextRoom(nowNs: Long): VideoRoom? {
        val open = checkNotNull(current) { "The timeline was not started" }
        if (nowNs <= open.fromNs) return null
        closed.add(VideoRoom(open.id, open.name, open.fromNs, nowNs))
        val number = closed.size + 1
        current = Open("room-$number", "Ambiente $number", nowNs)
        return VideoRoom("room-$number", "Ambiente $number", nowNs, nowNs)
    }

    /** Closes the last room at [endNs]. An empty trailing room is dropped unless it is the only one. */
    fun finish(endNs: Long): List<VideoRoom> {
        val open = checkNotNull(current) { "The timeline was not started" }
        current = null
        if (endNs > open.fromNs || closed.isEmpty()) {
            closed.add(VideoRoom(open.id, open.name, open.fromNs, maxOf(endNs, open.fromNs)))
        }
        return closed.toList()
    }
}

// endregion

// region frames.jsonl / sensors.jsonl

/** One entry per frame: `{"i":0,"t":<sensor timestamp ns>}`. */
class FrameLog {
    private val timestamps = ArrayList<Long>()

    val count: Int get() = timestamps.size
    val firstTimestampNs: Long? get() = timestamps.firstOrNull()

    @Synchronized
    fun contains(timestampNs: Long): Boolean = timestamps.contains(timestampNs)

    @Synchronized
    fun add(timestampNs: Long) {
        timestamps.add(timestampNs)
    }

    @Synchronized
    fun lines(): List<String> = timestamps.mapIndexed { i, t -> """{"i":$i,"t":$t}""" }
}

enum class SensorKind(val wireName: String) {
    GYRO("gyro"),
    ACCEL("accel"),
    GRAVITY("gravity"),
    MAG("mag"),
}

/** Sensor samples kept in memory (about 120k for 5 minutes) and written sorted by time. */
class SensorLog {
    private class Sample(val t: Long, val kind: SensorKind, val x: Float, val y: Float, val z: Float)

    private val samples = ArrayList<Sample>()

    /** Non-finite samples are dropped instead of written as fictitious values. */
    @Synchronized
    fun add(timestampNs: Long, kind: SensorKind, x: Float, y: Float, z: Float) {
        if (!x.isFinite() || !y.isFinite() || !z.isFinite()) return
        samples.add(Sample(timestampNs, kind, x, y, z))
    }

    @Synchronized
    fun lines(): List<String> = samples.sortedBy { it.t }.map {
        """{"t":${it.t},"type":"${it.kind.wireName}","x":${it.x.toDouble()},"y":${it.y.toDouble()},"z":${it.z.toDouble()}}"""
    }
}

// endregion

// region manifest, package, result

data class VideoManifestInput(
    val captureId: String,
    val listingId: String,
    val deviceModel: String,
    val osVersion: String,
    val startedAtNs: Long,
    val timestampSource: String,
    /** Camera2 SENSOR_ORIENTATION of the camera used (0, 90, 180 or 270); frames are stored unrotated. */
    val sensorOrientation: Int,
    val rooms: List<VideoRoom>,
    val reference: ReferenceMark?,
    /** The negotiated size of `video.mp4` (the stored frame). */
    val videoSize: VideoSize,
)

/** The worker rejects a reference whose frame is not in frames.jsonl or lies outside every room. */
object ReferenceCoverage {
    fun isCovered(reference: ReferenceMark, frames: FrameLog, rooms: List<VideoRoom>): Boolean =
        frames.contains(reference.frameNs) && rooms.any { reference.frameNs >= it.fromNs && reference.frameNs < it.toNs }
}

object VideoManifestBuilder {
    fun build(input: VideoManifestInput): Map<String, Any?> {
        require(input.listingId.isNotBlank()) { "A package needs a non-blank listingId" }
        require(input.rooms.isNotEmpty()) { "A package needs at least one room" }
        require(input.sensorOrientation in intArrayOf(0, 90, 180, 270)) { "Invalid sensor orientation" }
        require(input.videoSize.width > 0 && input.videoSize.height > 0) { "Invalid video size" }
        val manifest = linkedMapOf<String, Any?>(
            "schemaVersion" to VideoSpec.SCHEMA_VERSION,
            "captureId" to input.captureId,
            "listingId" to input.listingId,
            "device" to linkedMapOf("model" to input.deviceModel, "os" to "android", "osVersion" to input.osVersion),
            "video" to linkedMapOf(
                "file" to VideoSpec.VIDEO_FILE,
                "width" to input.videoSize.width,
                "height" to input.videoSize.height,
                "fps" to VideoSpec.FPS,
                "startedAtNs" to input.startedAtNs,
                "framesFile" to VideoSpec.FRAMES_FILE,
                "timestampSource" to input.timestampSource,
                "sensorOrientation" to input.sensorOrientation,
            ),
            "sensors" to linkedMapOf("file" to VideoSpec.SENSORS_FILE, "rateHz" to VideoSpec.SENSOR_RATE_HZ),
            "rooms" to input.rooms.map {
                linkedMapOf("id" to it.id, "name" to it.name, "fromNs" to it.fromNs, "toNs" to it.toNs)
            },
        )
        // The reference is optional: the key is absent when the agent skipped it.
        input.reference?.let { manifest["reference"] = it.toMap() }
        return manifest
    }
}

sealed class VideoPackageOutcome {
    data class Built(val sizeBytes: Long) : VideoPackageOutcome()

    /** The ZIP was above the limit and was removed. */
    data class TooLarge(val sizeBytes: Long) : VideoPackageOutcome()
}

object VideoPackageBuilder {
    /**
     * Writes manifest, frames and sensors next to the recorded `video.mp4` in [workDir] and zips the
     * directory into [target]. A ZIP above [maxBytes] is deleted and reported, never returned.
     */
    fun build(
        workDir: File,
        target: File,
        manifest: Map<String, Any?>,
        frames: FrameLog,
        sensors: SensorLog,
        maxBytes: Long = VideoCaptureLimits.MAX_PACKAGE_BYTES,
    ): VideoPackageOutcome {
        require(File(workDir, VideoSpec.VIDEO_FILE).isFile) { "${VideoSpec.VIDEO_FILE} is missing" }
        File(workDir, VideoSpec.MANIFEST_FILE).writeText(JsonWriter.write(manifest))
        writeLines(File(workDir, VideoSpec.FRAMES_FILE), frames.lines())
        writeLines(File(workDir, VideoSpec.SENSORS_FILE), sensors.lines())
        target.parentFile?.mkdirs()
        PackageZip.zipDirectory(workDir, target)
        val size = target.length()
        if (size > maxBytes) {
            target.delete()
            return VideoPackageOutcome.TooLarge(size)
        }
        return VideoPackageOutcome.Built(size)
    }

    private fun writeLines(file: File, lines: List<String>) {
        file.bufferedWriter().use { out -> lines.forEach { out.write(it); out.write("\n") } }
    }
}

/** What `roomforge/video_capture` returns to Dart (outcome `captured`, `cancelled` or `error`). */
object VideoCaptureResult {
    const val ERROR_CAMERA_PERMISSION_DENIED = "camera_permission_denied"
    const val ERROR_PACKAGE_TOO_LARGE = "package_too_large"
    const val ERROR_RECORDING_FAILED = "recording_failed"

    fun captured(
        zipPath: String,
        captureId: String,
        sizeBytes: Long,
        frameCount: Int,
        rooms: List<VideoRoom>,
        hasReference: Boolean,
        durationMs: Long,
        reachedTimeLimit: Boolean,
        timestampSource: String,
    ): Map<String, Any?> = linkedMapOf(
        "outcome" to "captured",
        "capturePackage" to linkedMapOf(
            "zipPath" to zipPath,
            "captureId" to captureId,
            "sizeBytes" to sizeBytes,
            "keyframeCount" to frameCount,
            "droppedKeyframes" to 0,
            "failedKeyframes" to 0,
            "rooms" to rooms.map { linkedMapOf("id" to it.id, "name" to it.name) },
        ),
        "hasReference" to hasReference,
        "durationMs" to durationMs,
        "reachedTimeLimit" to reachedTimeLimit,
        "timestampSource" to timestampSource,
    )

    fun cancelled(): Map<String, Any?> = linkedMapOf("outcome" to "cancelled")

    fun error(code: String, message: String): Map<String, Any?> =
        linkedMapOf("outcome" to "error", "code" to code, "message" to message)
}

// endregion
