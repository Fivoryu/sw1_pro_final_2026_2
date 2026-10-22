package com.example.captura_mobile.ar

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.zip.CRC32
import java.util.zip.Inflater
import java.util.zip.ZipFile

class PackageIoTest {

    @get:Rule
    val tmp = TemporaryFolder()

    /** Decoded grayscale PNG: Android's unit-test classpath has no javax.imageio, so this checks the format by hand. */
    private class DecodedPng(val width: Int, val height: Int, val bitDepth: Int, val colorType: Int, val samples: IntArray)

    private fun decode(png: ByteArray): DecodedPng {
        assertArrayEquals(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A), png.copyOfRange(0, 8))
        val buffer = ByteBuffer.wrap(png).position(8) as ByteBuffer
        val idat = ByteArrayOutputStream()
        var width = 0
        var height = 0
        var depth = 0
        var colorType = -1
        val chunks = mutableListOf<String>()
        while (buffer.remaining() > 0) {
            val length = buffer.int
            val typeBytes = ByteArray(4).also { buffer.get(it) }
            val data = ByteArray(length).also { buffer.get(it) }
            val crc = CRC32().apply { update(typeBytes); update(data) }
            assertEquals("CRC of ${String(typeBytes)}", crc.value.toInt(), buffer.int)
            val type = String(typeBytes, Charsets.US_ASCII)
            chunks.add(type)
            when (type) {
                "IHDR" -> ByteBuffer.wrap(data).let {
                    width = it.int
                    height = it.int
                    depth = it.get().toInt()
                    colorType = it.get().toInt()
                }
                "IDAT" -> idat.write(data)
            }
        }
        assertEquals(listOf("IHDR", "IDAT", "IEND"), chunks)
        val bytesPerSample = depth / 8
        val raw = ByteArray(height * (1 + width * bytesPerSample))
        val inflater = Inflater().apply { setInput(idat.toByteArray()) }
        assertEquals(raw.size, inflater.inflate(raw))
        val samples = IntArray(width * height)
        for (y in 0 until height) {
            val row = y * (1 + width * bytesPerSample)
            assertEquals("filter type of row $y", 0, raw[row].toInt())
            for (x in 0 until width) {
                val i = row + 1 + x * bytesPerSample
                samples[y * width + x] = if (bytesPerSample == 2) {
                    ((raw[i].toInt() and 0xFF) shl 8) or (raw[i + 1].toInt() and 0xFF)
                } else {
                    raw[i].toInt() and 0xFF
                }
            }
        }
        return DecodedPng(width, height, depth, colorType, samples)
    }

    @Test
    fun png16RoundTripsEverySample() {
        val samples = intArrayOf(0, 1, 4000, 8191, 65535, 300)
        val image = decode(PngEncoder.gray16(3, 2, samples))
        assertEquals(3, image.width)
        assertEquals(2, image.height)
        assertEquals(16, image.bitDepth)
        assertEquals("grayscale", 0, image.colorType)
        assertArrayEquals(samples, image.samples)
    }

    @Test
    fun png8RoundTripsEverySample() {
        val samples = intArrayOf(0, 255, 17, 128)
        val image = decode(PngEncoder.gray8(2, 2, samples))
        assertEquals(8, image.bitDepth)
        assertArrayEquals(samples, image.samples)
    }

    @Test
    fun nv21FromInterleavedChromaWithRowPadding() {
        // 4x2 image: Y rows are padded to stride 6; chroma is interleaved (pixelStride 2), row stride 6.
        val y = byteArrayOf(1, 2, 3, 4, 9, 9, 5, 6, 7, 8, 9, 9)
        // One chroma row (height / 2): U0 V0 U1 V1 plus padding; V is the byte after U.
        val u = byteArrayOf(10, 99, 12, 99, 0, 0)
        val v = byteArrayOf(11, 99, 13, 99, 0, 0)
        val raw = RawYuv(4, 2, y, 6, u, v, 6, 2)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 11, 10, 13, 12), YuvConverter.toNv21(raw))
    }

    @Test
    fun nv21FromPlanarChroma() {
        val y = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        val u = byteArrayOf(10, 12)
        val v = byteArrayOf(11, 13)
        val raw = RawYuv(4, 2, y, 4, u, v, 2, 1)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 11, 10, 13, 12), YuvConverter.toNv21(raw))
    }

    @Test
    fun depthKeepsTheThirteenRangeBitsInMillimetres() {
        // Little-endian DEPTH16, width 2, row stride 6 bytes (2 bytes of padding per row).
        val buffer = byteArrayOf(
            0x10, 0x00, 0xFF.toByte(), 0xFF.toByte(), 0, 0,
            0x01, 0x20, 0x00, 0x00, 0, 0,
        )
        val depth = DepthDecoder.millimetres(buffer, width = 2, height = 2, rowStrideBytes = 6)
        assertEquals(2, depth.width)
        assertArrayEquals(intArrayOf(16, 8191, 0x2001 and 0x1FFF, 0), depth.samples)
    }

    @Test
    fun confidenceRespectsRowStride() {
        val bytes = byteArrayOf(1, 2, 0, 3, 4, 0)
        assertArrayEquals(intArrayOf(1, 2, 3, 4), DepthDecoder.gray8(bytes, 2, 2, rowStrideBytes = 3).samples)
    }

    @Test
    fun zipHasTheManifestFirstAndForwardSlashPaths() {
        val dir = tmp.newFolder("pkg")
        dir.resolve("frames").mkdirs()
        dir.resolve("depth").mkdirs()
        dir.resolve("frames/000002.jpg").writeBytes(byteArrayOf(2))
        dir.resolve("frames/000001.jpg").writeBytes(byteArrayOf(1))
        dir.resolve("depth/000001.png").writeBytes(byteArrayOf(3))
        dir.resolve("manifest.json").writeText("{}")
        val zip = tmp.newFile("out.zip")
        PackageZip.zipDirectory(dir, zip)
        ZipFile(zip).use { file ->
            assertEquals(
                listOf("manifest.json", "depth/000001.png", "frames/000001.jpg", "frames/000002.jpg"),
                file.entries().toList().map { it.name },
            )
            assertEquals("{}", file.getInputStream(file.getEntry("manifest.json")).readBytes().decodeToString())
            assertTrue(file.getInputStream(file.getEntry("frames/000001.jpg")).readBytes().contentEquals(byteArrayOf(1)))
        }
    }
}
