package com.example.captura_mobile.ar

import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Raw data of one keyframe, copied on the GL thread so the ARCore images can be closed at once. */
class KeyframePayload(val image: RawYuv, val depth: GraySamples?, val confidence: GraySamples?)

/** Package-relative paths of the files written for one keyframe. */
data class WrittenFiles(val image: String, val depth: String?, val confidence: String?)

/** Encodes and writes the files of one keyframe under [dir]; runs on the recorder's worker thread. */
interface KeyframeEncoder {
    fun write(dir: File, index: Int, payload: KeyframePayload): WrittenFiles
}

data class RecordedKeyframe(
    val index: Int,
    val timestampNs: Long,
    val roomId: String,
    val pose: CameraPose,
    val files: WrittenFiles,
)

data class RecordingResult(val keyframes: List<RecordedKeyframe>, val dropped: Int, val failed: Int)

/**
 * Writes keyframes on a single background thread through a bounded queue. The GL thread never
 * waits: when the queue is full the keyframe is dropped and counted, and its image is not even
 * copied. Keyframe numbers are assigned on acceptance, so a failed write leaves a gap.
 */
class KeyframeRecorder(
    private val dir: File,
    private val encoder: KeyframeEncoder,
    queueCapacity: Int = DEFAULT_QUEUE_CAPACITY,
) {
    private val queue = ArrayBlockingQueue<Runnable>(queueCapacity)
    private val executor = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, queue) { runnable ->
        Thread(runnable, "keyframe-writer").apply { isDaemon = true }
    }
    private val written = ConcurrentLinkedQueue<RecordedKeyframe>()
    private val failures = AtomicInteger(0)
    private var accepted = 0
    private var droppedCount = 0

    /** Keyframes dropped because the writer could not keep up. Read on the submitting thread. */
    val dropped: Int get() = droppedCount

    /**
     * Offers a keyframe. [capture] copies the images and returns null when they are not available
     * yet; it only runs when there is room in the queue. Returns true when the keyframe was queued.
     */
    fun submit(timestampNs: Long, roomId: String, pose: CameraPose, capture: () -> KeyframePayload?): Boolean {
        if (queue.remainingCapacity() == 0) {
            droppedCount++
            return false
        }
        val payload = capture() ?: return false
        val index = accepted + 1
        val job = Runnable {
            try {
                val files = encoder.write(dir, index, payload)
                written.add(RecordedKeyframe(index, timestampNs, roomId, pose, files))
            } catch (e: Exception) {
                failures.incrementAndGet()
            }
        }
        return try {
            executor.execute(job)
            accepted = index
            true
        } catch (e: RejectedExecutionException) {
            droppedCount++
            false
        }
    }

    /** Waits for the queued writes (up to [timeoutMs]); frames still pending after that count as failed. */
    fun finish(timeoutMs: Long): RecordingResult {
        executor.shutdown()
        if (!executor.awaitTermination(timeoutMs, TimeUnit.MILLISECONDS)) {
            failures.addAndGet(executor.shutdownNow().size)
            executor.awaitTermination(1, TimeUnit.SECONDS)
        }
        return RecordingResult(written.sortedBy { it.index }, droppedCount, failures.get())
    }

    /** Stops without waiting and deletes everything written so far. */
    fun abort() {
        executor.shutdownNow()
        executor.awaitTermination(2, TimeUnit.SECONDS)
        dir.deleteRecursively()
    }

    companion object {
        const val DEFAULT_QUEUE_CAPACITY = 4
    }
}
