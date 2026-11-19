package com.example.captura_mobile.video

import android.content.Context
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.view.Surface
import java.io.File

/**
 * Camera2 + MediaRecorder + sensors for the video walkthrough (F07, schema 2). This is the only
 * class that touches camera and sensor hardware, so none of it is JVM-testable: everything with
 * logic lives in VideoPackage.kt. Frame timestamps are Camera2's SENSOR_TIMESTAMP, the same
 * `elapsedRealtimeNanos` clock as the sensor events when the camera reports the realtime source.
 *
 * Recording has no audio track (privacy) and no rotation hint: `video.mp4` holds the raw sensor frames
 * in the negotiated size (4:3 preferred) and the reference points are normalised on that same frame.
 */
class VideoRecorder(
    private val context: Context,
    private val workDir: File,
    private val listener: Listener,
) {
    interface Listener {
        /** The preview is running (called on the camera thread). */
        fun onPreviewReady()

        /** The size of the stored frame was negotiated (called on the camera thread, before the preview starts). */
        fun onVideoSize(size: VideoSize)

        /** The size of the preview buffer (same aspect as the video when the camera offers one); the stage follows its aspect. */
        fun onPreviewSize(size: VideoSize) = Unit

        /** The recorder started; [startedAtNs] precedes every logged frame. */
        fun onRecordingStarted(startedAtNs: Long)

        fun onFailure(message: String)
    }

    /** The negotiated recording size; the preview buffer, crop, encoder and manifest all use it. */
    @Volatile
    var videoSize: VideoSize = VideoSpec.FALLBACK_SIZE
        private set

    var frames = FrameLog()
        private set
    val sensors = SensorLog()

    /** Live hints (S8) computed from the same sensor and capture data; never written to the package. */
    val guidance = CaptureGuidance()

    /** Sensor timestamp of the latest recording frame; 0 until one arrives. */
    @Volatile
    var lastFrameNs: Long = 0L
        private set

    @Volatile
    var timestampSource: String = TimestampSource.UNKNOWN
        private set

    /** Camera2 SENSOR_ORIENTATION of the back camera in use; the frames are stored unrotated. */
    @Volatile
    var sensorOrientation: Int = 0
        private set

    @Volatile
    private var recording = false

    private val cameraThread = HandlerThread("video-camera").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private val sensorThread = HandlerThread("video-sensors").apply { start() }
    private val sensorHandler = Handler(sensorThread.looper)

    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var characteristics: CameraCharacteristics? = null
    private var previewTexture: SurfaceTexture? = null
    private var previewSurface: Surface? = null
    private var mediaRecorder: MediaRecorder? = null
    private var released = false
    private var lensCorrectionEnabled = true
    private var recordingSession: CameraCaptureSession? = null
    private var recordingSequenceId: Int? = null
    private var stopCallback: ((Boolean) -> Unit)? = null
    private val stopTimeout = Runnable {
        Log.e(TAG, "Camera sequence did not drain; raw recording preserved")
        finishRecordingStop(false)
    }

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val kind = when (event.sensor.type) {
                Sensor.TYPE_GYROSCOPE -> SensorKind.GYRO
                Sensor.TYPE_ACCELEROMETER -> SensorKind.ACCEL
                Sensor.TYPE_GRAVITY -> SensorKind.GRAVITY
                Sensor.TYPE_MAGNETIC_FIELD -> SensorKind.MAG
                else -> return
            }
            if (event.values.size >= 3) feedGuidance(kind, event)
            if (event.values.size >= 3) sensors.add(event.timestamp, kind, event.values[0], event.values[1], event.values[2])
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit
    }

    private fun feedGuidance(kind: SensorKind, event: SensorEvent) {
        when (kind) {
            SensorKind.GYRO -> guidance.onGyro(event.timestamp, event.values[0], event.values[1], event.values[2])
            SensorKind.GRAVITY -> guidance.onGravity(event.values[0], event.values[1], event.values[2])
            else -> Unit
        }
    }

    private val frameCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureStarted(
            session: CameraCaptureSession,
            request: CaptureRequest,
            timestamp: Long,
            frameNumber: Long,
        ) {
            // Preview callbacks can still arrive after switching sessions. Record callbacks
            // remain relevant after stopRepeating() until the sequence has drained.
            if (session === recordingSession) {
                lastFrameNs = timestamp
                frames.add(timestamp)
            }
        }

        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            if (!recording || session !== recordingSession) return
            val iso = result.get(CaptureResult.SENSOR_SENSITIVITY) ?: return
            guidance.onExposure(result.get(CaptureResult.SENSOR_TIMESTAMP) ?: lastFrameNs, iso)
        }

        override fun onCaptureSequenceCompleted(session: CameraCaptureSession, sequenceId: Int, frameNumber: Long) {
            if (session === recordingSession && sequenceId == recordingSequenceId && stopCallback != null) {
                finishRecordingStop(true)
            }
        }

        override fun onCaptureSequenceAborted(session: CameraCaptureSession, sequenceId: Int) {
            if (session === recordingSession && sequenceId == recordingSequenceId && stopCallback != null) {
                finishRecordingStop(false)
            }
        }
    }

    // region preview

    @Suppress("MissingPermission")
    fun openPreview(texture: SurfaceTexture) {
        cameraHandler.post {
            try {
                val manager = context.getSystemService(CameraManager::class.java)
                val id = manager.cameraIdList.firstOrNull {
                    manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                } ?: return@post fail("Este teléfono no tiene cámara trasera.")
                val chars = manager.getCameraCharacteristics(id)
                val map: StreamConfigurationMap? = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val offered = map?.getOutputSizes(MediaRecorder::class.java).orEmpty().map { VideoSize(it.width, it.height) }
                Log.i(TAG, "MediaRecorder sizes offered: ${offered.joinToString(" ") { "${it.width}x${it.height}" }}")
                val size = VideoSpec.chooseVideoSize(offered) ?: return@post fail(VideoSpec.unsupportedSizeMessage())
                Log.i(TAG, "Chosen video size: ${size.width}x${size.height}")
                videoSize = size
                listener.onVideoSize(size)
                characteristics = chars
                sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
                timestampSource = TimestampSource.fromCamera(chars.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE))
                previewTexture = texture
                val previewOffered = map?.getOutputSizes(SurfaceTexture::class.java).orEmpty().map { VideoSize(it.width, it.height) }
                val previewSize = choosePreviewSize(size, previewOffered) ?: size
                Log.i(TAG, "Preview size: ${previewSize.width}x${previewSize.height} (offered ${previewOffered.joinToString(" ") { "${it.width}x${it.height}" }})")
                listener.onPreviewSize(previewSize)
                texture.setDefaultBufferSize(previewSize.width, previewSize.height)
                previewSurface = Surface(texture)
                manager.openCamera(id, object : CameraDevice.StateCallback() {
                    override fun onOpened(device: CameraDevice) {
                        if (released) {
                            device.close()
                            return
                        }
                        camera = device
                        createSession(listOfNotNull(previewSurface), CameraDevice.TEMPLATE_PREVIEW) { listener.onPreviewReady() }
                    }

                    override fun onDisconnected(device: CameraDevice) {
                        device.close()
                        camera = null
                        fail("Se perdió la conexión con la cámara.")
                    }

                    override fun onError(device: CameraDevice, error: Int) {
                        device.close()
                        camera = null
                        fail("La cámara no está disponible. Cerrá otras apps que la usen.")
                    }
                }, cameraHandler)
            } catch (e: CameraAccessException) {
                Log.e(TAG, "Camera access failed", e)
                fail("No se pudo abrir la cámara.")
            } catch (e: Exception) {
                Log.e(TAG, "Preview failed", e)
                fail("No se pudo iniciar la vista previa.")
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun createSession(
        surfaces: List<Surface>,
        template: Int,
        beforeRepeating: () -> Unit = {},
        onConfigured: (CameraCaptureSession) -> Unit,
    ) {
        val device = camera ?: return fail("La c?mara todav?a no est? lista. Reintent?.")
        try {
            device.createCaptureSession(
                surfaces,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(configured: CameraCaptureSession) {
                        if (released) {
                            configured.close()
                            return
                        }
                        session = configured
                        try {
                            beforeRepeating()
                            val sequenceId = try {
                                configured.setRepeatingRequest(buildRequest(device, template, surfaces), frameCallback, cameraHandler)
                            } catch (e: Exception) {
                                // T18: if the HAL rejects the lens-correction request, retry once without it.
                                if (!lensCorrectionEnabled) throw e
                                Log.w(TAG, "Request with lens correction rejected, retrying without it", e)
                                lensCorrectionEnabled = false
                                configured.setRepeatingRequest(buildRequest(device, template, surfaces), frameCallback, cameraHandler)
                            }
                            if (template == CameraDevice.TEMPLATE_RECORD) {
                                recordingSession = configured
                                recordingSequenceId = sequenceId
                            }
                            onConfigured(configured)
                        } catch (e: Exception) {
                            Log.e(TAG, "Repeating request failed", e)
                            fail("No se pudo iniciar la cámara.")
                        }
                    }

                    override fun onConfigureFailed(failed: CameraCaptureSession) {
                        fail("No se pudo configurar la cámara.")
                    }
                },
                cameraHandler,
            )
        } catch (e: Exception) {
            Log.e(TAG, "createCaptureSession failed", e)
            fail("No se pudo configurar la cámara.")
        }
    }

    private fun buildRequest(device: CameraDevice, template: Int, surfaces: List<Surface>): CaptureRequest {
        val builder = device.createCaptureRequest(template)
        surfaces.forEach(builder::addTarget)
        val chars = characteristics
        builder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
        val afModes = chars?.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
        if (afModes?.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO) == true) {
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
        }
        // S9: electronic stabilisation off when the device allows it (it warps frames and breaks the SfM).
        val stabilisation = chars?.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES)
        if (stabilisation?.contains(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF) == true) {
            builder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
        }
        // T17: ask for the crop of the sensor that has the stream's aspect explicitly: the whole array for a 4:3 stream,
        // the centred 16:9 band for the fallback. Without it the HAL may squeeze the array into the stream (anamorphic).
        cropRegionFor(chars)?.let { builder.set(CaptureRequest.SCALER_CROP_REGION, it) }
        if (lensCorrectionEnabled) applyLensCorrection(builder, chars)
        val fpsRanges = chars?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
        if (fpsRanges?.contains(Range(VideoSpec.FPS, VideoSpec.FPS)) == true) {
            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(VideoSpec.FPS, VideoSpec.FPS))
        }
        return builder.build()
    }

    /**
     * T18: ask for the best lens distortion correction the device lists, so the preview and the video look like the
     * vendor camera (straight lines stay straight). Only public API: standard key, or the Samsung vendor key found by
     * name among the advertised request keys. Missing keys or errors leave the request untouched.
     */
    @Suppress("UNCHECKED_CAST")
    private fun applyLensCorrection(builder: CaptureRequest.Builder, chars: CameraCharacteristics?) {
        if (chars == null) return
        try {
            val standard = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                chars.get(CameraCharacteristics.DISTORTION_CORRECTION_AVAILABLE_MODES)?.toList()
            } else {
                null
            }
            val vendorRequestKey = chars.availableCaptureRequestKeys.firstOrNull { it.name == LensCorrection.VENDOR_REQUEST_KEY }
            val vendorModes = chars.keys.firstOrNull { it.name == LensCorrection.VENDOR_MODES_KEY }
                ?.let { (chars.get(it as CameraCharacteristics.Key<Any>) as? IntArray)?.toList() }
            val support = LensCorrectionSupport(Build.VERSION.SDK_INT, standard, vendorRequestKey != null, vendorModes)
            Log.i(TAG, "Lens correction support: $support")
            when (val choice = LensCorrection.choose(support)) {
                is LensCorrectionChoice.Standard ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        builder.set(CaptureRequest.DISTORTION_CORRECTION_MODE, choice.mode)
                    }
                is LensCorrectionChoice.Vendor ->
                    if (vendorRequestKey != null) {
                        builder.set(vendorRequestKey as CaptureRequest.Key<Int>, choice.mode)
                    }
                null -> Unit
            }
        } catch (e: Exception) {
            Log.w(TAG, "Lens correction unavailable, keeping the default request", e)
        }
    }

    private fun cropRegionFor(chars: CameraCharacteristics?): Rect? {
        val array = chars?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return null
        val zoom = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        // CENTER_ONLY and FREEFORM both accept a centred region, so the cropping type does not change the result.
        val crop = CaptureCrop.centered(array.width(), array.height(), videoSize.width, videoSize.height, zoom) ?: return null
        return Rect(array.left + crop.left, array.top + crop.top, array.left + crop.right, array.top + crop.bottom)
    }

    // endregion

    // region recording

    /** Swaps the preview-only session for one that also feeds the encoder, then starts it. */
    fun startRecording() {
        cameraHandler.post {
            try {
                val preview = previewSurface ?: return@post fail("La vista previa no está lista.")
                session?.close()
                session = null
                val recorder = newMediaRecorder().also { mediaRecorder = it }
                recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
                recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                recorder.setOutputFile(File(workDir, VideoSpec.VIDEO_FILE).absolutePath)
                recorder.setVideoEncodingBitRate(VideoSpec.bitrateFor(videoSize))
                recorder.setVideoFrameRate(VideoSpec.FPS)
                recorder.setVideoSize(videoSize.width, videoSize.height)
                recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                // No audio source on purpose: the package has no audio track.
                recorder.prepare()
                var startedAtNs = 0L
                createSession(listOf(preview, recorder.surface), CameraDevice.TEMPLATE_RECORD,
                    beforeRepeating = {
                        registerSensors()
                        startedAtNs = SystemClock.elapsedRealtimeNanos()
                        // Start accepting buffers before submitting requests targeting the encoder.
                        recorder.start()
                    }) {
                    recording = true
                    listener.onRecordingStarted(startedAtNs)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Recording could not start", e)
                fail("No se pudo iniciar la grabación.")
            }
        }
    }

    /** Stops frames, sensors and the encoder; [onStopped] says whether `video.mp4` is usable. */
    fun stopRecording(onStopped: (Boolean) -> Unit) {
        cameraHandler.post {
            check(stopCallback == null) { "Recording stop already pending" }
            stopCallback = onStopped
            recording = false
            try {
                // Do not abort/close or block this handler in MediaRecorder.stop(): in-flight
                // frame callbacks must be delivered before validating the finalized MP4.
                checkNotNull(recordingSession).stopRepeating()
                cameraHandler.postDelayed(stopTimeout, 10_000L)
            } catch (e: Exception) {
                Log.w(TAG, "Stopping the request failed", e)
                finishRecordingStop(false)
            }
        }
    }

    private fun finishRecordingStop(sequenceDrained: Boolean) {
        val onStopped = stopCallback ?: return
        stopCallback = null
        cameraHandler.removeCallbacks(stopTimeout)
        recordingSession = null
        recordingSequenceId = null
        unregisterSensors()
        var ok = sequenceDrained
        session?.close()
        session = null
        try {
            mediaRecorder?.stop()
        } catch (e: RuntimeException) {
            // MediaRecorder.stop throws when it received no frames: the file is not valid.
            Log.e(TAG, "MediaRecorder.stop failed", e)
            ok = false
        }
        mediaRecorder?.release()
        mediaRecorder = null
        // Keep the complete callback evidence even when only a subset was encoded.
        try {
            CaptureRecovery.checkpoint(File(workDir, "camera_frames.jsonl"), frames.lines().joinToString("\n", postfix = "\n"))
        } catch (e: Exception) {
            Log.e(TAG, "Camera timeline checkpoint failed; raw recording preserved", e)
            ok = false
        }
        if (ok) {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(File(workDir, VideoSpec.VIDEO_FILE).absolutePath)
                val track = (0 until extractor.trackCount).first { extractor.getTrackFormat(it)
                    .getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                extractor.selectTrack(track)
                val encoded = mutableListOf<Long>()
                while (extractor.sampleTime >= 0) {
                    require(encoded.size < 20_000) { "MP4 frame limit exceeded" }
                    encoded.add(extractor.sampleTime)
                    if (!extractor.advance()) break
                }
                CaptureRecovery.checkpoint(File(workDir, "encoded_pts.jsonl"),
                    encoded.mapIndexed { i, t -> """{"sample":$i,"ptsUs":$t}""" }.joinToString("\n", postfix = "\n"))
                // Extractor order may be decode order (B frames); frames.jsonl is presentation order.
                Log.i(TAG, "Timeline samples: Camera2=${frames.count}, MP4=${encoded.size}")
                val matched = FrameTiming.match(frames.timestamps(), encoded.sorted())
                frames = FrameLog().also { log -> matched.forEach { log.add(it) } }
                lastFrameNs = matched.last()
            } catch (e: Exception) {
                Log.e(TAG, "MP4/camera timeline validation failed; raw recording preserved", e)
                ok = false
            } finally { extractor.release() }
        }
        try {
            CaptureRecovery.checkpoint(File(workDir, VideoSpec.FRAMES_FILE), frames.lines().joinToString("\n", postfix = "\n"))
            CaptureRecovery.checkpoint(File(workDir, VideoSpec.SENSORS_FILE), sensors.lines().joinToString("\n", postfix = "\n"))
        } catch (e: Exception) {
            Log.e(TAG, "Timeline checkpoint failed; raw recording preserved", e)
            ok = false
        }
        onStopped(ok)
    }

    private fun newMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

    private fun registerSensors() {
        val manager = context.getSystemService(SensorManager::class.java)
        val periodUs = 1_000_000 / VideoSpec.SENSOR_RATE_HZ
        for (type in intArrayOf(Sensor.TYPE_GYROSCOPE, Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GRAVITY, Sensor.TYPE_MAGNETIC_FIELD)) {
            // A missing sensor (for example no gravity or magnetometer) just yields no lines of that type.
            val sensor = manager.getDefaultSensor(type) ?: continue
            manager.registerListener(sensorListener, sensor, periodUs, sensorHandler)
        }
    }

    private fun unregisterSensors() {
        context.getSystemService(SensorManager::class.java).unregisterListener(sensorListener)
    }

    // endregion

    private fun fail(message: String) {
        listener.onFailure(message)
    }

    fun release() {
        released = true
        recording = false
        unregisterSensors()
        cameraHandler.post {
            try {
                session?.close()
                camera?.close()
                mediaRecorder?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Release failed", e)
            }
            session = null
            camera = null
            mediaRecorder = null
            previewSurface?.release()
            previewSurface = null
            cameraThread.quitSafely()
            sensorThread.quitSafely()
        }
    }

    companion object {
        private const val TAG = "RoomForgeVideo"

        /** SENSOR_ORIENTATION of the back camera (needs no permission); 90 when it cannot be read. */
        fun backCameraSensorOrientation(context: Context): Int = try {
            val manager = context.getSystemService(CameraManager::class.java)
            manager.cameraIdList
                .map { manager.getCameraCharacteristics(it) }
                .firstOrNull { it.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
                ?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: DEFAULT_SENSOR_ORIENTATION
        } catch (e: Exception) {
            DEFAULT_SENSOR_ORIENTATION
        }

        private const val DEFAULT_SENSOR_ORIENTATION = 90
    }
}
