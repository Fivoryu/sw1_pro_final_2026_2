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
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import java.io.File

/**
 * Camera2 + MediaRecorder + sensors for the video walkthrough (F07, schema 2). This is the only
 * class that touches camera and sensor hardware, so none of it is JVM-testable: everything with
 * logic lives in VideoPackage.kt. Frame timestamps are Camera2's SENSOR_TIMESTAMP, the same
 * `elapsedRealtimeNanos` clock as the sensor events when the camera reports the realtime source.
 *
 * Recording has no audio track (privacy) and no rotation hint: `video.mp4` holds the raw 1280x720
 * sensor frames and the reference points are normalised on that same frame.
 */
class VideoRecorder(
    private val context: Context,
    private val workDir: File,
    private val listener: Listener,
) {
    interface Listener {
        /** The preview is running (called on the camera thread). */
        fun onPreviewReady()

        /** The recorder started; [startedAtNs] precedes every logged frame. */
        fun onRecordingStarted(startedAtNs: Long)

        fun onFailure(message: String)
    }

    val frames = FrameLog()
    val sensors = SensorLog()

    /** Live hints (S8) computed from the same sensor and capture data; never written to the package. */
    val guidance = CaptureGuidance()

    /** Sensor timestamp of the latest frame; 0 until one arrives. */
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
            lastFrameNs = timestamp
            if (recording) frames.add(timestamp)
        }

        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            if (!recording) return
            val iso = result.get(CaptureResult.SENSOR_SENSITIVITY) ?: return
            guidance.onExposure(result.get(CaptureResult.SENSOR_TIMESTAMP) ?: lastFrameNs, iso)
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
                val size = Size(VideoSpec.WIDTH, VideoSpec.HEIGHT)
                if (map?.getOutputSizes(MediaRecorder::class.java)?.contains(size) != true) {
                    return@post fail("La cámara no graba en ${VideoSpec.WIDTH}x${VideoSpec.HEIGHT}.")
                }
                characteristics = chars
                sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
                timestampSource = TimestampSource.fromCamera(chars.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE))
                previewTexture = texture
                texture.setDefaultBufferSize(VideoSpec.WIDTH, VideoSpec.HEIGHT)
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
    private fun createSession(surfaces: List<Surface>, template: Int, onConfigured: (CameraCaptureSession) -> Unit) {
        val device = camera ?: return
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
                            configured.setRepeatingRequest(buildRequest(device, template, surfaces), frameCallback, cameraHandler)
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
        // T17: ask for the centred 16:9 band of the sensor explicitly. Without it the HAL may squeeze the full 4:3
        // array into the 16:9 stream (anamorphic); with it, preview and recording share one undistorted field of view.
        cropRegionFor(chars)?.let { builder.set(CaptureRequest.SCALER_CROP_REGION, it) }
        val fpsRanges = chars?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
        if (fpsRanges?.contains(Range(VideoSpec.FPS, VideoSpec.FPS)) == true) {
            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(VideoSpec.FPS, VideoSpec.FPS))
        }
        return builder.build()
    }

    private fun cropRegionFor(chars: CameraCharacteristics?): Rect? {
        val array = chars?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return null
        val zoom = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        // CENTER_ONLY and FREEFORM both accept a centred region, so the cropping type does not change the result.
        val crop = CaptureCrop.centered(array.width(), array.height(), VideoSpec.WIDTH, VideoSpec.HEIGHT, zoom) ?: return null
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
                recorder.setVideoEncodingBitRate(VideoSpec.BITRATE_BPS)
                recorder.setVideoFrameRate(VideoSpec.FPS)
                recorder.setVideoSize(VideoSpec.WIDTH, VideoSpec.HEIGHT)
                recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                // No audio source on purpose: the package has no audio track.
                recorder.prepare()
                createSession(listOf(preview, recorder.surface), CameraDevice.TEMPLATE_RECORD) {
                    registerSensors()
                    val startedAtNs = SystemClock.elapsedRealtimeNanos()
                    recorder.start()
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
            recording = false
            unregisterSensors()
            var ok = true
            try {
                session?.stopRepeating()
                session?.abortCaptures()
            } catch (e: Exception) {
                Log.w(TAG, "Stopping the request failed", e)
            }
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
            onStopped(ok)
        }
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
