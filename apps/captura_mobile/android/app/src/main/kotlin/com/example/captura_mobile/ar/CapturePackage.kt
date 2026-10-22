package com.example.captura_mobile.ar

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/*
 * Pure parts of the F07 capture package (docs/api/f07-capture-package.md): manifest, rooms, image
 * conversions and the ZIP. Nothing here depends on Android so everything is JVM-tested.
 */

/** Pinhole intrinsics of one image resolution, in pixels. */
data class Intrinsics(val width: Int, val height: Int, val fx: Double, val fy: Double, val cx: Double, val cy: Double) {
    /**
     * The same camera at another resolution of the same field of view: focal length and principal
     * point scale with the width and height ratios. ARCore's depth image covers the camera image's
     * field of view, so the depth intrinsics are the image intrinsics scaled to the depth size.
     */
    fun scaledTo(newWidth: Int, newHeight: Int): Intrinsics {
        val sx = newWidth.toDouble() / width
        val sy = newHeight.toDouble() / height
        return Intrinsics(newWidth, newHeight, fx * sx, fy * sy, cx * sx, cy * sy)
    }

    fun toMap(): Map<String, Any?> = linkedMapOf(
        "width" to width, "height" to height, "fx" to fx, "fy" to fy, "cx" to cx, "cy" to cy,
    )
}

data class PackageRoom(val id: String, val name: String)

/** Rooms of one session. The first takes the name the agent typed; the next ones are «Ambiente N». */
class RoomSequence(firstName: String) {
    private val all = mutableListOf(PackageRoom("room-1", firstName.trim().ifEmpty { "Ambiente 1" }))

    val rooms: List<PackageRoom> get() = all.toList()
    val currentId: String get() = all.last().id

    fun next(): PackageRoom {
        val number = all.size + 1
        return PackageRoom("room-$number", "Ambiente $number").also { all.add(it) }
    }
}

enum class PlaneKind(val wireName: String) { FLOOR("floor"), WALL("wall"), CEILING("ceiling") }

/** A tracked plane at the end of the session: pose in world, polygon in the plane's local x/z. */
data class PackagePlane(val id: String, val kind: PlaneKind, val pose: CameraPose, val polygon: List<Pair<Double, Double>>)

/** `[t_ms, x, z, roomId]`. */
data class TrajectorySample(val tMs: Long, val x: Double, val z: Double, val roomId: String)

data class PackageKeyframe(
    val index: Int,
    val timestampNs: Long,
    val roomId: String,
    val pose: CameraPose,
    val image: String,
    val depth: String?,
    val confidence: String?,
)

data class ManifestInput(
    val captureId: String,
    val listingId: String?,
    val capturedAt: String,
    val deviceModel: String,
    val arcoreVersion: String,
    val depthSupported: Boolean,
    val image: Intrinsics,
    val depth: Intrinsics?,
    val floorY: Double?,
    val rooms: List<PackageRoom>,
    val planes: List<PackagePlane>,
    val trajectory: List<TrajectorySample>,
    val keyframes: List<PackageKeyframe>,
)

object ManifestBuilder {
    const val SCHEMA_VERSION = 1

    fun build(input: ManifestInput): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to SCHEMA_VERSION,
        "captureId" to input.captureId,
        "listingId" to input.listingId,
        "capturedAt" to input.capturedAt,
        "device" to linkedMapOf(
            "model" to input.deviceModel,
            "arcoreVersion" to input.arcoreVersion,
            "depthSupported" to input.depthSupported,
        ),
        "image" to input.image.toMap(),
        "depth" to input.depth?.toMap(),
        "floorY" to input.floorY,
        "rooms" to input.rooms.map { linkedMapOf("id" to it.id, "name" to it.name) },
        "planes" to input.planes.map {
            linkedMapOf(
                "id" to it.id,
                "type" to it.kind.wireName,
                "pose" to it.pose.toList(),
                "polygon" to it.polygon.map { (x, z) -> listOf(x, z) },
            )
        },
        "trajectory" to input.trajectory.map { listOf(it.tMs, it.x, it.z, it.roomId) },
        "keyframes" to input.keyframes.map {
            linkedMapOf(
                "index" to it.index,
                "timestampNs" to it.timestampNs,
                "roomId" to it.roomId,
                "pose" to it.pose.toList(),
                "image" to it.image,
                "depth" to it.depth,
                "confidence" to it.confidence,
            )
        },
        // The scale reference is not taken on the phone yet; the agent corrects scale afterwards.
        "reference" to null,
    )
}

/** What the channel returns about the finished package (additive key `capturePackage`). */
data class CapturePackageResult(
    val zipPath: String,
    val captureId: String,
    val sizeBytes: Long,
    val keyframeCount: Int,
    val droppedKeyframes: Int,
    val failedKeyframes: Int,
    val rooms: List<PackageRoom>,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "zipPath" to zipPath,
        "captureId" to captureId,
        "sizeBytes" to sizeBytes,
        "keyframeCount" to keyframeCount,
        "droppedKeyframes" to droppedKeyframes,
        "failedKeyframes" to failedKeyframes,
        "rooms" to rooms.map { linkedMapOf("id" to it.id, "name" to it.name) },
    )
}

/** Raw planes of ARCore's YUV_420_888 camera image, copied off the Image so it can be closed at once. */
class RawYuv(
    val width: Int,
    val height: Int,
    val y: ByteArray,
    val yRowStride: Int,
    val u: ByteArray,
    val v: ByteArray,
    val uvRowStride: Int,
    val uvPixelStride: Int,
)

/** A single-channel image of non-negative integers (millimetres, or 0..255 confidence). */
class GraySamples(val width: Int, val height: Int, val samples: IntArray)

object YuvConverter {
    /**
     * YUV_420_888 to NV21 (full Y plane, then interleaved V/U at half resolution), honouring the
     * row and pixel strides of each plane. A chroma byte missing at the end of a padded buffer
     * (Android may omit the last padding bytes) becomes the neutral value 128.
     */
    fun toNv21(raw: RawYuv): ByteArray {
        val w = raw.width
        val h = raw.height
        val out = ByteArray(w * h + 2 * ((w + 1) / 2) * ((h + 1) / 2))
        for (row in 0 until h) {
            System.arraycopy(raw.y, row * raw.yRowStride, out, row * w, w)
        }
        var o = w * h
        for (row in 0 until (h + 1) / 2) {
            for (col in 0 until (w + 1) / 2) {
                val i = row * raw.uvRowStride + col * raw.uvPixelStride
                out[o++] = raw.v.getOrElse(i) { 128.toByte() }
                out[o++] = raw.u.getOrElse(i) { 128.toByte() }
            }
        }
        return out
    }
}

object DepthDecoder {
    private const val DEPTH_RANGE_MASK = 0x1FFF

    /**
     * ARCore's 16-bit depth is Android DEPTH16: little-endian, depth in millimetres in the low 13
     * bits (the high 3 bits are a confidence code, not part of the distance), so values are masked.
     * 0 means no depth at that pixel.
     */
    fun millimetres(buffer: ByteArray, width: Int, height: Int, rowStrideBytes: Int): GraySamples {
        val samples = IntArray(width * height)
        for (row in 0 until height) {
            for (col in 0 until width) {
                val i = row * rowStrideBytes + col * 2
                val value = (buffer[i].toInt() and 0xFF) or ((buffer[i + 1].toInt() and 0xFF) shl 8)
                samples[row * width + col] = value and DEPTH_RANGE_MASK
            }
        }
        return GraySamples(width, height, samples)
    }

    /** 8-bit plane (raw depth confidence, 0..255) with a row stride. */
    fun gray8(buffer: ByteArray, width: Int, height: Int, rowStrideBytes: Int): GraySamples {
        val samples = IntArray(width * height)
        for (row in 0 until height) {
            for (col in 0 until width) {
                samples[row * width + col] = buffer[row * rowStrideBytes + col].toInt() and 0xFF
            }
        }
        return GraySamples(width, height, samples)
    }
}

/** Minimal grayscale PNG writer: Android's Bitmap cannot write 16-bit PNGs. */
object PngEncoder {
    private val SIGNATURE = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

    fun gray16(width: Int, height: Int, samples: IntArray): ByteArray = encode(width, height, 16, samples)

    fun gray8(width: Int, height: Int, samples: IntArray): ByteArray = encode(width, height, 8, samples)

    private fun encode(width: Int, height: Int, bitDepth: Int, samples: IntArray): ByteArray {
        require(samples.size == width * height) { "Expected ${width * height} samples, got ${samples.size}" }
        val bytesPerSample = bitDepth / 8
        val raw = ByteArrayOutputStream(height * (1 + width * bytesPerSample))
        for (row in 0 until height) {
            raw.write(0) // filter type: none
            for (col in 0 until width) {
                val value = samples[row * width + col]
                if (bitDepth == 16) raw.write((value shr 8) and 0xFF)
                raw.write(value and 0xFF)
            }
        }
        val compressed = ByteArrayOutputStream()
        DeflaterOutputStream(compressed, Deflater(Deflater.DEFAULT_COMPRESSION)).use { it.write(raw.toByteArray()) }

        val out = ByteArrayOutputStream()
        out.write(SIGNATURE)
        val header = ByteArrayOutputStream()
        DataOutputStream(header).apply {
            writeInt(width)
            writeInt(height)
            writeByte(bitDepth)
            writeByte(0) // colour type: grayscale
            writeByte(0) // compression
            writeByte(0) // filter
            writeByte(0) // no interlace
        }
        chunk(out, "IHDR", header.toByteArray())
        chunk(out, "IDAT", compressed.toByteArray())
        chunk(out, "IEND", ByteArray(0))
        return out.toByteArray()
    }

    private fun chunk(out: ByteArrayOutputStream, type: String, data: ByteArray) {
        val data32 = DataOutputStream(out)
        data32.writeInt(data.size)
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        out.write(typeBytes)
        out.write(data)
        val crc = CRC32()
        crc.update(typeBytes)
        crc.update(data)
        data32.writeInt(crc.value.toInt())
    }
}

object PackageZip {
    /** `manifest.json` first, then every other file by relative path with `/` separators. */
    fun zipDirectory(dir: File, target: File) {
        val files = dir.walkTopDown().filter { it.isFile }.map { it.relativeTo(dir).invariantSeparatorsPath }.toList()
        val ordered = files.filter { it == "manifest.json" } + files.filter { it != "manifest.json" }.sorted()
        val temporary = File(target.path + ".tmp")
        try {
            ZipOutputStream(FileOutputStream(temporary)).use { zip ->
                for (name in ordered) {
                    // JPEG and PNG are already compressed: store them quickly, deflate only the manifest.
                    zip.setLevel(if (name.endsWith(".json")) Deflater.DEFAULT_COMPRESSION else Deflater.NO_COMPRESSION)
                    zip.putNextEntry(ZipEntry(name))
                    File(dir, name).inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                }
            }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temporary.delete()
        }
    }
}
