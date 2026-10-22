package com.example.captura_mobile.ar

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.File
import java.io.FileOutputStream

/**
 * Writes `frames/NNNNNN.jpg` (JPEG quality 80 of the CPU camera image, converted from YUV_420_888
 * through NV21), `depth/NNNNNN.png` (16-bit, millimetres) and `confidence/NNNNNN.png` (8-bit).
 * The images keep ARCore's sensor orientation and resolution; their intrinsics go in the manifest.
 */
class AndroidKeyframeEncoder : KeyframeEncoder {
    override fun write(dir: File, index: Int, payload: KeyframePayload): WrittenFiles {
        val name = "%06d".format(index)
        val image = "frames/$name.jpg"
        val raw = payload.image
        val nv21 = YuvConverter.toNv21(raw)
        file(dir, image).outputStream().use { out ->
            val ok = YuvImage(nv21, ImageFormat.NV21, raw.width, raw.height, null)
                .compressToJpeg(Rect(0, 0, raw.width, raw.height), JPEG_QUALITY, out)
            if (!ok) throw java.io.IOException("JPEG compression failed")
        }
        val depthPath = payload.depth?.let {
            "depth/$name.png".also { path ->
                FileOutputStream(file(dir, path)).use { out -> out.write(PngEncoder.gray16(it.width, it.height, it.samples)) }
            }
        }
        val confidencePath = if (depthPath != null) {
            payload.confidence?.let {
                "confidence/$name.png".also { path ->
                    FileOutputStream(file(dir, path)).use { out -> out.write(PngEncoder.gray8(it.width, it.height, it.samples)) }
                }
            }
        } else {
            null
        }
        return WrittenFiles(image, depthPath, confidencePath)
    }

    private fun file(dir: File, relative: String): File = File(dir, relative).also { it.parentFile?.mkdirs() }

    companion object {
        const val JPEG_QUALITY = 80
    }
}
