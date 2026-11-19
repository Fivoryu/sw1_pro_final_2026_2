package com.example.captura_mobile.video

/**
 * Pure geometry of the recorder screen (F07, T17); nothing here touches Android, so it is JVM-testable.
 *
 * The stored frame (`video.mp4`) is the raw sensor image, unrotated, in the negotiated size (4:3, or 16:9 as a fallback). The preview shows that same
 * buffer upright for whatever way the phone is held. Every coordinate that reaches the package (reference
 * points, rectangle corners) is normalised on the STORED frame; [displayToStored] converts the points the
 * agent sees and taps on the rotated display.
 */
internal object PreviewGeometry {
    /** Clockwise rotation (0, 90, 180, 270) to apply to the sensor buffer so it looks upright on the display. */
    fun imageRotation(sensorOrientation: Int, displayRotationDegrees: Int): Int =
        (((sensorOrientation - displayRotationDegrees) % 360) + 360) % 360

    fun isQuarterTurn(rotation: Int): Boolean = rotation == 90 || rotation == 270

    /**
     * Clockwise rotation (0, 90, 180, 270) that the platform already applies to the buffer when it renders the
     * TextureView, read from SurfaceTexture.getTransformMatrix (column-major 4x4). The vertical flip that GL textures
     * carry is ignored, and so are the crop scale and translate terms: only the direction of the first column of the
     * 2x2 block counts. Identity with the flip gives 0, the ROT_90 matrix (0,-1,-1,0) gives 90.
     */
    fun hintRotationDegrees(matrix: FloatArray): Int {
        if (matrix.size < 6) return 0
        val a = matrix[0].toDouble()
        val b = matrix[1].toDouble()
        if (Math.hypot(a, b) < 1e-6) return 0
        val degrees = Math.toDegrees(Math.atan2(-b, a))
        return ((Math.round(degrees / 90.0).toInt() * 90) % 360 + 360) % 360
    }

    /** Extra clockwise rotation the view must apply on top of what the platform already did (the hint). */
    fun remainderRotation(sensorOrientation: Int, displayRotationDegrees: Int, hint: Int): Int =
        (((imageRotation(sensorOrientation, displayRotationDegrees) - hint) % 360) + 360) % 360

    /**
     * Guards the sign convention of a measured quarter-turn hint: a pre-rotated buffer must show the hint equal to the
     * upright rotation, so a measured quarter turn that equals its opposite is the same thing read the other way round.
     */
    fun effectiveHint(measured: Int, sensorOrientation: Int, displayRotationDegrees: Int): Int {
        val up = imageRotation(sensorOrientation, displayRotationDegrees)
        return if (isQuarterTurn(up) && measured == (360 - up) % 360) up else measured
    }

    /** What the screen needs for one posture: the real geometry (independent of the hint) and the view remainder. */
    data class Plan(val uprightRotation: Int, val hint: Int, val remainder: Int)

    fun plan(sensorOrientation: Int, displayRotationDegrees: Int, measuredHint: Int): Plan {
        val hint = effectiveHint(measuredHint, sensorOrientation, displayRotationDegrees)
        return Plan(
            uprightRotation = imageRotation(sensorOrientation, displayRotationDegrees),
            hint = hint,
            remainder = remainderRotation(sensorOrientation, displayRotationDegrees, hint),
        )
    }

    /** Width and height of the upright image (the buffer swaps its sides for a quarter turn). */
    fun displayedSize(rotation: Int, bufferWidth: Int, bufferHeight: Int): Pair<Int, Int> =
        if (isQuarterTurn(rotation)) bufferHeight to bufferWidth else bufferWidth to bufferHeight

    /**
     * Size of the stage (the upright image) inside a window of [availableWidth] x [availableHeight]: the whole image
     * always fits (letterbox), never cropped and never stretched. The free space is left to the controls.
     */
    fun stageSize(
        rotation: Int,
        bufferWidth: Int,
        bufferHeight: Int,
        availableWidth: Int,
        availableHeight: Int,
    ): Pair<Int, Int> {
        val (w, h) = displayedSize(rotation, bufferWidth, bufferHeight)
        val widthLimited = availableWidth.toLong() * h <= availableHeight.toLong() * w
        return if (widthLimited) {
            availableWidth to (availableWidth.toLong() * h / w).toInt()
        } else {
            (availableHeight.toLong() * w / h).toInt() to availableHeight
        }
    }

    /** Where a point of the sensor buffer lands on the upright image, both normalised to 0..1. */
    fun storedToDisplay(rotation: Int, x: Double, y: Double): Pair<Double, Double> = when (rotation) {
        90 -> (1.0 - y) to x
        180 -> (1.0 - x) to (1.0 - y)
        270 -> y to (1.0 - x)
        else -> x to y
    }

    /** Inverse of [storedToDisplay]: a point on the upright image to the stored (unrotated) frame. */
    fun displayToStored(rotation: Int, x: Double, y: Double): Pair<Double, Double> = when (rotation) {
        90 -> y to (1.0 - x)
        180 -> (1.0 - x) to (1.0 - y)
        270 -> (1.0 - y) to x
        else -> x to y
    }

    /**
     * The 3x3 matrix (row-major, the layout of android.graphics.Matrix.setValues) for TextureView.setTransform on a
     * view of [viewWidth] x [viewHeight]. A TextureView stretches the buffer over its whole rectangle, so for a view
     * that has the upright image's aspect this matrix both rotates the image and cancels that stretch: it never
     * scales the two axes differently on the picture.
     */
    fun bufferToView(rotation: Int, viewWidth: Float, viewHeight: Float): FloatArray {
        val (ox, oy) = storedToDisplay(rotation, 0.0, 0.0)
        val (xx, xy) = storedToDisplay(rotation, 1.0, 0.0)
        val (yx, yy) = storedToDisplay(rotation, 0.0, 1.0)
        return floatArrayOf(
            (xx - ox).toFloat(), (viewWidth / viewHeight * (yx - ox)).toFloat(), (viewWidth * ox).toFloat(),
            (viewHeight / viewWidth * (xy - oy)).toFloat(), (yy - oy).toFloat(), (viewHeight * oy).toFloat(),
            0f, 0f, 1f,
        )
    }
}

/** Integer rectangle of the sensor array (android.graphics.Rect without the Android dependency). */
internal data class CropRect(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

/**
 * SCALER_CROP_REGION for a stream of the given aspect: the centred sub-rectangle of the active array with that
 * aspect, so the camera crops the field of view instead of squeezing it into the stream (F07, T17). A 4:3 stream on a
 * 4:3 array gets the whole array (no crop); a 16:9 fallback gets the centred 16:9 band.
 */
internal object CaptureCrop {
    /** SCALER_CROPPING_TYPE values from Camera2. */
    const val CENTER_ONLY = 0
    const val FREEFORM = 1

    /**
     * Largest centred rectangle of aspect [targetWidth]:[targetHeight] inside the [arrayWidth] x [arrayHeight] array,
     * with even sides (odd sides break some HALs). Null when the inputs are not usable. Zoom stays 1.0, so the region
     * is only widened when it would be smaller than the array divided by [maxDigitalZoom].
     * Both cropping types accept a centred region.
     */
    fun centered(
        arrayWidth: Int,
        arrayHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        maxDigitalZoom: Float = 10f,
    ): CropRect? {
        if (arrayWidth <= 0 || arrayHeight <= 0 || targetWidth <= 0 || targetHeight <= 0) return null
        val wider = arrayWidth.toLong() * targetHeight > arrayHeight.toLong() * targetWidth
        var w: Int
        var h: Int
        if (wider) {
            h = arrayHeight - arrayHeight % 2
            w = evenUp(h.toLong() * targetWidth / targetHeight, arrayWidth)
        } else {
            w = arrayWidth - arrayWidth % 2
            h = evenUp(w.toLong() * targetHeight / targetWidth, arrayHeight)
        }
        val zoom = if (maxDigitalZoom.isFinite() && maxDigitalZoom >= 1f) maxDigitalZoom else 1f
        w = maxOf(w, minOf(arrayWidth, Math.ceil(arrayWidth / zoom.toDouble()).toInt()))
        h = maxOf(h, minOf(arrayHeight, Math.ceil(arrayHeight / zoom.toDouble()).toInt()))
        val left = (arrayWidth - w) / 2
        val top = (arrayHeight - h) / 2
        return CropRect(left, top, left + w, top + h)
    }

    private fun evenUp(value: Long, limit: Int): Int {
        val even = if (value % 2 == 0L) value else value + 1
        return minOf(even, limit.toLong()).toInt()
    }
}
