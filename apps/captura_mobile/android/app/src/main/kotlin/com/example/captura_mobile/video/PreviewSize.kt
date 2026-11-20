package com.example.captura_mobile.video

/**
 * Preview stream size (F07). The HAL may hand the preview a different size than the default buffer size, for example a
 * square 1088x1088 one, which a 4:3 stage would stretch. We ask explicitly for a size with exactly the aspect of the
 * recorded video, so the preview shows the same field of view as the recording.
 */
internal object PreviewSize {
    /** Sizes with exactly the aspect of [video] and not larger than it, largest first. */
    fun candidates(video: VideoSize, available: Collection<VideoSize>): List<VideoSize> =
        available
            .filter { it.width > 0 && it.height > 0 }
            .filter { it.width.toLong() * video.height == it.height.toLong() * video.width }
            .filter { it.width <= video.width && it.height <= video.height }
            .distinct()
            .sortedByDescending { it.width.toLong() * it.height }

    fun choose(video: VideoSize, available: Collection<VideoSize>): VideoSize? = candidates(video, available).firstOrNull()
}

internal fun choosePreviewSize(videoSize: VideoSize, available: Collection<VideoSize>): VideoSize? =
    PreviewSize.choose(videoSize, available)
