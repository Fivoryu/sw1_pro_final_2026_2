package com.example.captura_mobile

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.captura_mobile.ar.ArCaptureActivity
import com.example.captura_mobile.ar.CaptureMode
import com.example.captura_mobile.ar.CaptureResult
import com.example.captura_mobile.ar.CaptureRules
import com.example.captura_mobile.ar.JsonReader
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "roomforge/ar_capture"
        const val CAPTURE_REQUEST = 7301
        const val AVAILABILITY_RETRY_MS = 200L
        const val AVAILABILITY_MAX_ATTEMPTS = 25
        const val TAG = "RoomForgeArChannel"
    }

    private val handler = Handler(Looper.getMainLooper())

    /** Only one capture may be in flight. */
    private var pendingCapture: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailability" -> checkAvailability(result, attempt = 0)
                "captureRoom" -> startCapture(
                    roomName = call.argument<String>("roomName").orEmpty(),
                    mode = CaptureMode.fromArgument(call.argument<String>("mode")),
                    result = result,
                )
                else -> result.notImplemented()
            }
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

    private fun startCapture(roomName: String, mode: CaptureMode, result: MethodChannel.Result) {
        if (pendingCapture != null) {
            result.success(CaptureResult.error(CaptureResult.ERROR_SESSION_FAILED, "Ya hay una captura en curso."))
            return
        }
        pendingCapture = result
        try {
            val intent = Intent(this, ArCaptureActivity::class.java)
                .putExtra(ArCaptureActivity.EXTRA_ROOM_NAME, roomName)
                .putExtra(ArCaptureActivity.EXTRA_MODE, mode.wireName)
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
