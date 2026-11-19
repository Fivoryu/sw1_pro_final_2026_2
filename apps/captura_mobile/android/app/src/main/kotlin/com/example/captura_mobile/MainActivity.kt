package com.example.captura_mobile

import java.io.File
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.captura_mobile.ar.ArCaptureActivity
import com.example.captura_mobile.ar.CaptureMode
import com.example.captura_mobile.ar.CaptureResult
import com.example.captura_mobile.ar.CaptureRules
import com.example.captura_mobile.ar.JsonReader
import com.example.captura_mobile.video.VideoCaptureActivity
import com.example.captura_mobile.video.VideoCaptureResult
import com.example.captura_mobile.video.CaptureRecovery
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "roomforge/ar_capture"
        const val CAPTURE_REQUEST = 7301
        const val VIDEO_CHANNEL = "roomforge/video_capture"
        const val VIDEO_REQUEST = 7302
        const val AVAILABILITY_RETRY_MS = 200L
        const val AVAILABILITY_MAX_ATTEMPTS = 25
        const val TAG = "RoomForgeArChannel"
    }

    private val handler = Handler(Looper.getMainLooper())

    /** Only one capture may be in flight. */
    private var pendingCapture: MethodChannel.Result? = null

    /** Only one video walkthrough may be in flight. */
    private var pendingVideo: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "roomforge/connectivity")
            .setStreamHandler(ConnectivityEvents(applicationContext))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailability" -> checkAvailability(result, attempt = 0)
                "captureRoom" -> startCapture(
                    roomName = call.argument<String>("roomName").orEmpty(),
                    mode = CaptureMode.fromArgument(call.argument<String>("mode")),
                    listingId = call.argument<String>("listingId"),
                    result = result,
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "recordVideo" -> startVideo(
                    listingId = call.argument<String>("listingId"),
                    ownerId = call.argument<String>("ownerId"),
                    firstRoomName = call.argument<String>("firstRoomName"),
                    result = result,
                )
                "recoverPackages" -> {
                    val owner = call.argument<String>("ownerId")
                    val mayRecover = pendingVideo == null
                    kotlin.concurrent.thread(name = "capture-recovery") {
                      if (owner != null && mayRecover) CaptureRecovery.recoverFinalized(filesDir, owner)
                      val entries = File(filesDir, "capture_packages").listFiles().orEmpty()
                        .filter { it.extension == "json" }.mapNotNull { file ->
                            try { (JsonReader.parse(file.readText()) as? Map<*, *>)?.takeIf { it["ownerId"] == owner && owner != null } }
                            catch (_: Exception) { null } // Keep unreadable journals and ZIPs intact.
                        }
                      handler.post { result.success(entries) }
                    }
                }
                "ackPackage" -> {
                    val id = call.argument<String>("captureId").orEmpty()
                    val owner = call.argument<String>("ownerId")
                    if (Regex("^[A-Za-z0-9_-]{1,64}$").matches(id)) {
                        val file = File(filesDir, "capture_packages/$id.json")
                        try {
                            val savedOwner = (if (file.isFile) JsonReader.parse(file.readText()) else null) as? Map<*, *>
                            if (savedOwner?.get("ownerId") == owner && owner != null && !file.delete()) {
                                result.error("journal_io", "No se pudo confirmar la cola local.", null)
                                return@setMethodCallHandler
                            }
                        } catch (_: Exception) {
                            result.error("journal_io", "El registro local se conserva para recuperacion.", null)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVideo(listingId: String?, ownerId: String?, firstRoomName: String?, result: MethodChannel.Result) {
        if (pendingVideo != null) {
            result.success(VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, "Ya hay una grabación en curso."))
            return
        }
        pendingVideo = result
        try {
            val intent = Intent(this, VideoCaptureActivity::class.java)
                .putExtra(VideoCaptureActivity.EXTRA_LISTING_ID, listingId)
                .putExtra(VideoCaptureActivity.EXTRA_FIRST_ROOM_NAME, firstRoomName)
                .putExtra("ownerId", ownerId)
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VIDEO_REQUEST)
        } catch (e: Exception) {
            Log.e(TAG, "Could not start the video capture", e)
            pendingVideo = null
            result.success(
                VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, "No se pudo abrir la grabación de video."),
            )
        }
    }

    private fun checkAvailability(result: MethodChannel.Result, attempt: Int) {
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(this)
        } catch (e: Exception) {
            Log.w(TAG, "ARCore availability check failed", e)
            result.success(mapOf("status" to "unknown"))
            return
        }
        // UNKNOWN_CHECKING is transient: ARCore queries the device profile in the background.
        if (availability.isTransient && attempt < AVAILABILITY_MAX_ATTEMPTS) {
            handler.postDelayed({ checkAvailability(result, attempt + 1) }, AVAILABILITY_RETRY_MS)
            return
        }
        result.success(mapOf("status" to CaptureRules.availabilityStatus(availability.name)))
    }

    private fun startCapture(roomName: String, mode: CaptureMode, listingId: String?, result: MethodChannel.Result) {
        if (pendingCapture != null) {
            result.success(CaptureResult.error(CaptureResult.ERROR_SESSION_FAILED, "Ya hay una captura en curso."))
            return
        }
        pendingCapture = result
        try {
            val intent = Intent(this, ArCaptureActivity::class.java)
                .putExtra(ArCaptureActivity.EXTRA_ROOM_NAME, roomName)
                .putExtra(ArCaptureActivity.EXTRA_MODE, mode.wireName)
                .putExtra(ArCaptureActivity.EXTRA_LISTING_ID, listingId)
            @Suppress("DEPRECATION")
            startActivityForResult(intent, CAPTURE_REQUEST)
        } catch (e: Exception) {
            Log.e(TAG, "Could not start the AR capture", e)
            pendingCapture = null
            result.success(
                CaptureResult.error(CaptureResult.ERROR_SESSION_FAILED, "No se pudo abrir la captura espacial."),
            )
        }
    }

    @Deprecated("Flutter's FlutterActivity still routes results through onActivityResult.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VIDEO_REQUEST) {
            val pending = pendingVideo ?: return
            pendingVideo = null
            val json = data?.getStringExtra(VideoCaptureActivity.EXTRA_RESULT_JSON)
            val reply: Any? = if (json == null) {
                VideoCaptureResult.cancelled()
            } else {
                try {
                    JsonReader.parse(json)
                } catch (e: Exception) {
                    Log.e(TAG, "Invalid video capture result", e)
                    VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, "La grabación devolvió un resultado inválido.")
                }
            }
            pending.success(reply)
            return
        }
        if (requestCode != CAPTURE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingCapture ?: return
        pendingCapture = null
        val json = data?.getStringExtra(ArCaptureActivity.EXTRA_RESULT_JSON)
        val reply: Any? = if (json == null) {
            CaptureResult.cancelled()
        } else {
            try {
                JsonReader.parse(json)
            } catch (e: Exception) {
                Log.e(TAG, "Invalid capture result", e)
                CaptureResult.error(CaptureResult.ERROR_SESSION_FAILED, "La captura devolvió un resultado inválido.")
            }
        }
        pending.success(reply)
    }
}
