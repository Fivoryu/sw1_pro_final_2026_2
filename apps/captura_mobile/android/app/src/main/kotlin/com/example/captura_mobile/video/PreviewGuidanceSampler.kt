package com.example.captura_mobile.video

import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.PixelCopy
import android.view.Surface
import android.view.TextureView

/** Copies the existing preview asynchronously: no extra Camera2 stream or encoder changes.
 * One active tiny copy, <=1 Hz, one analysis thread. One expired native copy may be quarantined
 * while a recovery copy runs. A second stall disables copying until a callback frees a slot.
 * Neither pixels nor preview timestamps are used as encoded-frame/metric evidence.
 */
internal class PreviewGuidanceSampler(
    private val view: TextureView,
    private val main: Handler,
    private val onResult: (VisualFeedback, List<ReferencePoint>?) -> Unit,
) {
    private val thread = HandlerThread("video-visual-guide").apply { start() }
    private val worker = Handler(thread.looper)
    private var engine = RoomVisualGuidance()
    private val copies = GuidanceCopyGate()
    private var generation = 0
    private var closed = false
    private var active = false
    private var analysisBusy = false
    private var failures = 0
    private val sampling = GuidanceSamplingPolicy()
    private var lastSummary = "Guía visual pendiente; cobertura 3D no verificable."
    var step = 0
    var recording = false

    fun start() {
        if (!closed) {
            generation++; active = true; failures = 0; sampling.reset()
            worker.post { engine.resetComparison() }
            main.removeCallbacks(sample); main.post(sample)
        }
    }
    fun pause() { active = false; generation++; main.removeCallbacks(sample) }
    fun resetRecording(firstRoomName: String = "Ambiente 1") {
        generation++; recording = true; step = 0; sampling.reset()
        worker.post { engine = RoomVisualGuidance(firstRoomName) }
        lastSummary = "$firstRoomName: guía visual pendiente; cobertura 3D no verificable."
    }
    fun beginRoom(id: String, name: String) {
        generation++; step = 1; sampling.reset()
        lastSummary += "\n\n$name: análisis pendiente; no hereda muestras del ambiente anterior."
        val token = generation
        worker.post {
            engine.beginRoom(id, name)
            val summary = engine.summary()
            main.post { if (!closed && token == generation) lastSummary = summary }
        }
    }
    fun summary(): String = lastSummary
    fun close() {
        pause(); closed = true; copies.close()
        // Drain already queued work so its bitmap is recycled. Native copies cannot be
        // cancelled: late callbacks still own and release their isolated destinations.
        thread.quitSafely()
    }

    private fun unavailable() {
        onResult(VisualFeedback(VisualState.NOT_VERIFIABLE,
            "Guía visual no verificable. Podés grabar y guardar; recorré bases y esquinas lentamente."), null)
    }

    private val sample: Runnable = object : Runnable {
        override fun run() {
            if (!active || closed) return
            main.postDelayed(this, sampling.delayMs)
            if (analysisBusy || copies.copying) return
            if (Build.VERSION.SDK_INT < 24 || failures >= 3) { unavailable(); return }
            val texture = view.surfaceTexture ?: return
            if (!view.isAvailable) return
            val token = generation
            val area = step
            val isRecording = recording
            val cadenceMs = sampling.delayMs
            val started = SystemClock.elapsedRealtime()
            val ticket = copies.begin(started) ?: run { unavailable(); return }
            // Surface size is the raw preview buffer, not the rotated TextureView bounds.
            val size = bufferSize
            val bitmap = try {
                Bitmap.createBitmap(192, maxOf(16, 192 * size.height / size.width).coerceAtMost(192), Bitmap.Config.ARGB_8888)
            } catch (_: OutOfMemoryError) {
                copies.finish(ticket, SystemClock.elapsedRealtime()); failures = 3; unavailable(); return
            }
            val surface = try { Surface(texture) } catch (_: RuntimeException) {
                copies.finish(ticket, SystemClock.elapsedRealtime())
                bitmap.recycle(); failures++; unavailable(); return
            }
            val watchdog = Runnable {
                if (copies.expire(ticket, SystemClock.elapsedRealtime()) && !closed && active && token == generation) {
                    failures++
                    unavailable()
                    // Do not recycle/reuse bitmap or release surface while native code may
                    // still write. Gate permits at most one additional recovery request.
                }
            }
            fun completeCopy(status: Int) {
                if (!copies.owns(ticket)) return
                main.removeCallbacks(watchdog)
                val timely = copies.finish(ticket, SystemClock.elapsedRealtime())
                surface.release()
                if (status != PixelCopy.SUCCESS || !timely || closed || !active || token != generation) {
                    bitmap.recycle()
                    if ((!timely || status != PixelCopy.SUCCESS) && !closed && active && token == generation) {
                        if (timely) failures++
                        unavailable()
                    }
                    return
                }
                analysisBusy = true
                val posted = worker.post {
                    try {
                        val pixels = IntArray(bitmap.width * bitmap.height)
                        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                        val feedback = engine.analyze(pixels, bitmap.width, bitmap.height, started, area, cadenceMs)
                        if (isRecording) Log.d("F07Visual", "sample=${feedback.samples} gap=${feedback.gapMs} " +
                            "features=${feedback.features} matches=${feedback.matches}/${feedback.requiredMatches} " +
                            "motion=${feedback.motionFraction} luma=${feedback.luma} sharpness=${feedback.sharpness} " +
                            "issue=${feedback.issue} changes=${feedback.changedComparisons}")
                        // A candidate is not A4 recognition; real sizes are supplied by the user.
                        val quad = if (area == 0) RectDetector.detect(pixels, bitmap.width, bitmap.height) else null
                        val summary = engine.summary()
                        main.post {
                            analysisBusy = false
                            if (!closed && active && token == generation) {
                                failures = 0
                                val previousDelay = sampling.delayMs
                                val elapsed = SystemClock.elapsedRealtime() - started
                                sampling.completed(elapsed)
                                if (sampling.delayMs != previousDelay) {
                                    main.removeCallbacks(sample)
                                    main.postDelayed(sample, sampling.remainingDelayMs(elapsed))
                                }
                                lastSummary = summary
                                onResult(feedback, quad)
                            }
                        }
                    } catch (_: Exception) {
                        main.post { analysisBusy = false; if (!closed && active && token == generation) { failures++; unavailable() } }
                    } catch (_: OutOfMemoryError) {
                        main.post { analysisBusy = false; if (!closed && active && token == generation) { failures = 3; unavailable() } }
                    } finally { bitmap.recycle() }
                }
                if (!posted) { bitmap.recycle(); analysisBusy = false }
            }
            main.postDelayed(watchdog, copies.timeoutMs)
            try {
                PixelCopy.request(surface, bitmap, { status -> completeCopy(status) }, main)
            } catch (_: Exception) {
                completeCopy(PixelCopy.ERROR_UNKNOWN)
            }
        }
    }

    var bufferSize: VideoSize = VideoSpec.PREFERRED_SIZES.first()
}
