package com.example.captura_mobile.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class KeyframeRecorderTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val pose = CameraPose(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
    private val payload = KeyframePayload(RawYuv(2, 2, ByteArray(4), 2, ByteArray(1), ByteArray(1), 1, 1), null, null)

    private class FakeEncoder(
        private val started: CountDownLatch = CountDownLatch(0),
        private val gate: CountDownLatch = CountDownLatch(0),
        private val failOn: Int? = null,
    ) : KeyframeEncoder {
        override fun write(dir: File, index: Int, payload: KeyframePayload): WrittenFiles {
            started.countDown()
            gate.await(5, TimeUnit.SECONDS)
            if (index == failOn) throw java.io.IOException("disk full")
            val name = "frames/%06d.jpg".format(index)
            File(dir, name).apply { parentFile.mkdirs() }.writeBytes(byteArrayOf(1))
            return WrittenFiles(name, null, null)
        }
    }

    @Test
    fun framesAreWrittenOffTheCallingThreadInOrder() {
        val dir = tmp.newFolder("work")
        val recorder = KeyframeRecorder(dir, FakeEncoder(), queueCapacity = 4)
        for (i in 1..3) assertTrue(recorder.submit(i * 1_000L, "room-1", pose) { payload })
        val result = recorder.finish(5_000)
        assertEquals(listOf(1, 2, 3), result.keyframes.map { it.index })
        assertEquals(listOf("room-1", "room-1", "room-1"), result.keyframes.map { it.roomId })
        assertEquals(0, result.dropped)
        assertTrue(File(dir, "frames/000001.jpg").exists())
    }

    @Test
    fun aFullQueueDropsTheKeyframeInsteadOfBlockingAndCountsIt() {
        val dir = tmp.newFolder("work")
        val started = CountDownLatch(1)
        val gate = CountDownLatch(1)
        val recorder = KeyframeRecorder(dir, FakeEncoder(started, gate), queueCapacity = 1)
        assertTrue(recorder.submit(1, "room-1", pose) { payload })
        assertTrue(started.await(5, TimeUnit.SECONDS)) // the worker is busy with frame 1
        assertTrue(recorder.submit(2, "room-1", pose) { payload }) // fills the queue
        var captured = false
        assertFalse(recorder.submit(3, "room-1", pose) { captured = true; payload })
        assertFalse("the image must not be copied when the frame is dropped", captured)
        assertEquals(1, recorder.dropped)
        gate.countDown()
        val result = recorder.finish(5_000)
        assertEquals(listOf(1, 2), result.keyframes.map { it.index })
        assertEquals(1, result.dropped)
    }

    @Test
    fun anUnavailableImageIsNotAKeyframe() {
        val recorder = KeyframeRecorder(tmp.newFolder("work"), FakeEncoder(), queueCapacity = 2)
        assertFalse(recorder.submit(1, "room-1", pose) { null })
        assertTrue(recorder.submit(2, "room-1", pose) { payload })
        val result = recorder.finish(5_000)
        assertEquals(listOf(1), result.keyframes.map { it.index })
    }

    @Test
    fun aFailedWriteIsCountedAndDoesNotStopTheRest() {
        val recorder = KeyframeRecorder(tmp.newFolder("work"), FakeEncoder(failOn = 1), queueCapacity = 4)
        assertTrue(recorder.submit(1, "room-1", pose) { payload })
        assertTrue(recorder.submit(2, "room-1", pose) { payload })
        val result = recorder.finish(5_000)
        assertEquals(listOf(2), result.keyframes.map { it.index })
        assertEquals(1, result.failed)
    }

    @Test
    fun abortRemovesTheWorkDirectory() {
        val dir = tmp.newFolder("work")
        val recorder = KeyframeRecorder(dir, FakeEncoder(), queueCapacity = 2)
        recorder.submit(1, "room-1", pose) { payload }
        recorder.abort()
        assertFalse(dir.exists())
    }
}
