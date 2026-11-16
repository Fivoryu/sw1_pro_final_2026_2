package com.example.captura_mobile.video

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.SurfaceTexture
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import com.example.captura_mobile.ar.JsonWriter
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Video walkthrough capture (F07, schema 2): preview, recording with «Siguiente ambiente», and the
 * optional scale reference marked on a frozen frame at the start. No ARCore. The hardware work is
 * in [VideoRecorder] and the package logic in VideoPackage.kt. Landscape only: the recorded frame
 * is 1280x720 and the preview and reference taps use that same orientation.
 */
class VideoCaptureActivity : Activity(), VideoRecorder.Listener {

    private enum class Phase { PREVIEW, RECORDING, MARKING, FINISHING, DONE }

    private val main = Handler(Looper.getMainLooper())
    private var phase = Phase.PREVIEW

    private lateinit var captureId: String
    private lateinit var workDir: File
    private var listingId: String? = null
    private lateinit var timeline: RoomTimeline
    private var recorder: VideoRecorder? = null
    private var texture: SurfaceTexture? = null
    private var permissionRequested = false

    private var startedAtNs = 0L
    private var reference: ReferenceMark? = null

    // views
    private lateinit var textureView: TextureView
    private lateinit var stage: AspectFrameLayout
    private lateinit var markView: ReferenceMarkView
    private lateinit var statusText: TextView
    private lateinit var warningText: TextView
    private lateinit var timerText: TextView
    private lateinit var recordButton: Button
    private lateinit var nextRoomButton: Button
    private lateinit var referenceButton: Button
    private lateinit var stopButton: Button
    private lateinit var controlsPanel: LinearLayout
    private lateinit var referencePanel: ScrollView
    private lateinit var presetSpinner: Spinner
    private lateinit var lengthInput: EditText
    private lateinit var labelInput: EditText
    private lateinit var surfaceGroup: RadioGroup

    private val tick = object : Runnable {
        override fun run() {
            if (phase != Phase.RECORDING && phase != Phase.MARKING) return
            val now = SystemClock.elapsedRealtimeNanos()
            val elapsedS = ((now - startedAtNs) / 1_000_000_000L).coerceAtLeast(0)
            timerText.text = String.format(Locale.ROOT, "%02d:%02d", elapsedS / 60, elapsedS % 60)
            if (VideoCaptureLimits.reachedTimeLimit(startedAtNs, now)) {
                finishRecording(reachedTimeLimit = true)
                return
            }
            main.postDelayed(this, TICK_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        captureId = UUID.randomUUID().toString()
        listingId = intent.getStringExtra(EXTRA_LISTING_ID)
        timeline = RoomTimeline(intent.getStringExtra(EXTRA_FIRST_ROOM_NAME).orEmpty())
        workDir = File(cacheDir, "video_work/$captureId").also { it.mkdirs() }
        buildUi()
        if (listingId.isNullOrBlank()) {
            finishWithResult(
                VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, "Falta la publicación del recorrido."),
            )
        }
    }

    // region UI

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun buildUi() {
        textureView = TextureView(this).apply {
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                    texture = surface
                    openPreviewWhenPermitted()
                }

                override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit
                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
            }
        }
        markView = ReferenceMarkView(this).apply { visibility = View.GONE }
        warningText = TextView(this).apply {
            text = "Sin referencia: el modelo quedará sin escala métrica."
            setTextColor(Color.BLACK)
            setBackgroundColor(Color.argb(220, 255, 193, 7))
            setPadding(dp(8), dp(4), dp(8), dp(4))
            visibility = View.GONE
        }
        timerText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(140, 0, 0, 0))
            setPadding(dp(8), dp(4), dp(8), dp(4))
            visibility = View.GONE
        }
        stage = AspectFrameLayout(this).apply {
            addView(textureView, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            addView(markView, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            addView(warningText, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.START))
            addView(timerText, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END))
        }

        statusText = TextView(this).apply {
            setTextColor(Color.WHITE)
            text = "Encuadrá un objeto de medida conocida (hoja A4, tarjeta, puerta) y tocá «Grabar». " +
                "Después marcá la referencia, o seguí sin ella."
        }
        recordButton = button("Grabar") { startRecording() }
        referenceButton = button("Marcar referencia") { beginReference() }.apply { visibility = View.GONE }
        nextRoomButton = button("Siguiente ambiente") { nextRoom() }.apply { visibility = View.GONE }
        stopButton = button("Detener y guardar") { finishRecording(reachedTimeLimit = false) }.apply { visibility = View.GONE }
        val cancelButton = button("Cancelar") { cancelCapture() }
        controlsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(statusText)
            addView(recordButton)
            addView(referenceButton)
            addView(nextRoomButton)
            addView(stopButton)
            addView(cancelButton)
        }
        referencePanel = buildReferencePanel().apply { visibility = View.GONE }

        val side = FrameLayout(this).apply {
            setPadding(dp(12), dp(12), dp(12), dp(12))
            addView(controlsPanel)
            addView(referencePanel)
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(Color.BLACK)
            addView(stage, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
            addView(side, LinearLayout.LayoutParams(dp(260), ViewGroup.LayoutParams.MATCH_PARENT))
        }
        setContentView(root)
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        minimumHeight = dp(48)
        setOnClickListener { onClick() }
    }

    private fun buildReferencePanel(): ScrollView {
        val presets = ReferencePresets.ALL
        presetSpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@VideoCaptureActivity,
                android.R.layout.simple_spinner_dropdown_item,
                presets.map { it.label } + "Otro (valor libre)",
            )
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    // A preset only fills the fields; the agent can edit the length and label afterwards.
                    val preset = presets.getOrNull(position) ?: return
                    lengthInput.setText(preset.lengthM.toString())
                    labelInput.setText(preset.label.substringBefore(" ("))
                    surfaceGroup.check(if (preset.surface == ReferenceSurface.FLOOR) SURFACE_FLOOR_ID else SURFACE_WALL_ID)
                }

                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            }
        }
        lengthInput = EditText(this).apply {
            hint = "Largo real entre los dos puntos (m)"
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
        }
        labelInput = EditText(this).apply {
            hint = "Objeto"
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
        }
        surfaceGroup = RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            addView(RadioButton(this@VideoCaptureActivity).apply { id = SURFACE_FLOOR_ID; text = "Apoyado en el piso"; setTextColor(Color.WHITE) })
            addView(RadioButton(this@VideoCaptureActivity).apply { id = SURFACE_WALL_ID; text = "Apoyado en la pared"; setTextColor(Color.WHITE) })
            check(SURFACE_WALL_ID)
        }
        val hint = TextView(this).apply {
            setTextColor(Color.WHITE)
            text = "Tocá los dos extremos del objeto sobre la imagen congelada. La grabación sigue."
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(hint)
            addView(presetSpinner)
            addView(lengthInput)
            addView(labelInput)
            addView(surfaceGroup)
            addView(button("Confirmar referencia") { confirmReference() })
            addView(button("Repetir puntos") { markView.clearPoints() })
            addView(button("Seguir sin referencia") { endReference() })
        }
        return ScrollView(this).apply { addView(panel) }
    }

    // endregion

    // region permission and preview

    private fun openPreviewWhenPermitted() {
        val surface = texture ?: return
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            if (!permissionRequested) {
                permissionRequested = true
                requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
            }
            return
        }
        if (recorder != null) return
        recorder = VideoRecorder(applicationContext, workDir, this).also { it.openPreview(surface) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            openPreviewWhenPermitted()
        } else {
            finishWithResult(
                VideoCaptureResult.error(
                    VideoCaptureResult.ERROR_CAMERA_PERMISSION_DENIED,
                    "Sin permiso de cámara no se puede grabar el recorrido.",
                ),
            )
        }
    }

    override fun onPreviewReady() {
        // Nothing to do: the Grabar button is always enabled once the activity is shown.
    }

    override fun onFailure(message: String) {
        main.post {
            if (phase == Phase.DONE) return@post
            finishWithResult(VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, message))
        }
    }

    // endregion

    // region recording

    private fun startRecording() {
        val active = recorder ?: run {
            toast("La cámara todavía no está lista.")
            return
        }
        recordButton.isEnabled = false
        active.startRecording()
    }

    override fun onRecordingStarted(startedAtNs: Long) {
        main.post {
            if (phase != Phase.PREVIEW) return@post
            this.startedAtNs = startedAtNs
            timeline.start(startedAtNs)
            phase = Phase.RECORDING
            recordButton.visibility = View.GONE
            referenceButton.visibility = View.VISIBLE
            nextRoomButton.visibility = View.VISIBLE
            stopButton.visibility = View.VISIBLE
            timerText.visibility = View.VISIBLE
            warningText.visibility = View.VISIBLE
            statusText.text = "Grabando. Marcá la referencia ahora si querés escala métrica; después recorré " +
                "el inmueble y tocá «Siguiente ambiente» al cambiar de ambiente."
            main.post(tick)
        }
    }

    private fun nextRoom() {
        if (phase != Phase.RECORDING) return
        val now = recorder?.lastFrameNs?.takeIf { it > 0 } ?: SystemClock.elapsedRealtimeNanos()
        val room = timeline.nextRoom(now)
        if (room != null) toast("${room.name} iniciado")
    }

    // endregion

    // region reference (S5)

    private fun beginReference() {
        val active = recorder ?: return
        if (phase != Phase.RECORDING) return
        val frameNs = active.lastFrameNs
        val frame: Bitmap? = textureView.bitmap
        if (frameNs <= 0L || frame == null) {
            toast("Todavía no hay una imagen para marcar. Probá de nuevo.")
            return
        }
        phase = Phase.MARKING
        markView.show(frame, frameNs)
        markView.visibility = View.VISIBLE
        controlsPanel.visibility = View.GONE
        referencePanel.visibility = View.VISIBLE
        presetSpinner.setSelection(0)
        lengthInput.setText(ReferencePresets.ALL[0].lengthM.toString())
        labelInput.setText(ReferencePresets.ALL[0].label.substringBefore(" ("))
    }

    private fun confirmReference() {
        val points = markView.points()
        if (points == null) {
            toast("Tocá los dos extremos del objeto sobre la imagen.")
            return
        }
        val length = lengthInput.text.toString().replace(',', '.').toDoubleOrNull()
        if (length == null || length <= 0.0) {
            toast("Ingresá el largo real del objeto en metros.")
            return
        }
        val surface = if (surfaceGroup.checkedRadioButtonId == SURFACE_FLOOR_ID) ReferenceSurface.FLOOR else ReferenceSurface.WALL
        try {
            reference = ReferenceMark.create(markView.frameNs, points.first, points.second, length, labelInput.text.toString(), surface)
        } catch (e: IllegalArgumentException) {
            toast("Los dos extremos tienen que ser puntos distintos.")
            return
        }
        warningText.visibility = View.GONE
        referenceButton.visibility = View.GONE
        endReference()
    }

    private fun endReference() {
        if (phase != Phase.MARKING) return
        phase = Phase.RECORDING
        markView.visibility = View.GONE
        markView.clear()
        referencePanel.visibility = View.GONE
        controlsPanel.visibility = View.VISIBLE
    }

    // endregion

    // region finishing

    private fun finishRecording(reachedTimeLimit: Boolean) {
        if (phase != Phase.RECORDING && phase != Phase.MARKING) return
        phase = Phase.FINISHING
        main.removeCallbacks(tick)
        statusText.text = "Guardando el recorrido…"
        controlsPanel.visibility = View.VISIBLE
        referencePanel.visibility = View.GONE
        markView.visibility = View.GONE
        listOf(referenceButton, nextRoomButton, stopButton).forEach { it.isEnabled = false }
        val active = recorder ?: return
        active.stopRecording { videoOk ->
            // Runs on the camera thread; packaging is slow, so it gets its own thread.
            thread(name = "video-package") {
                val result = buildPackage(active, videoOk, reachedTimeLimit)
                main.post { finishWithResult(result) }
            }
        }
    }

    private fun buildPackage(active: VideoRecorder, videoOk: Boolean, reachedTimeLimit: Boolean): Map<String, Any?> {
        if (!videoOk || active.frames.count == 0) {
            workDir.deleteRecursively()
            return VideoCaptureResult.error(
                VideoCaptureResult.ERROR_RECORDING_FAILED,
                "No se guardó video del recorrido. Probá de nuevo con buena luz.",
            )
        }
        return try {
            val firstFrameNs = active.frames.firstTimestampNs ?: startedAtNs
            // Rooms are [from, to): +1 keeps the last frame inside the last room.
            val endNs = maxOf(active.lastFrameNs, firstFrameNs) + 1
            val rooms = timeline.finish(endNs)
            // A reference whose frame is not logged or lies outside the rooms would make the worker reject the package.
            val usableReference = reference?.takeIf { ReferenceCoverage.isCovered(it, active.frames, rooms) }
            val manifest = VideoManifestBuilder.build(
                VideoManifestInput(
                    captureId = captureId,
                    listingId = checkNotNull(listingId),
                    deviceModel = Build.MODEL,
                    osVersion = Build.VERSION.RELEASE,
                    startedAtNs = firstFrameNs,
                    timestampSource = active.timestampSource,
                    sensorOrientation = active.sensorOrientation,
                    rooms = rooms,
                    reference = usableReference,
                ),
            )
            val zip = File(filesDir, "capture_packages/$captureId.zip")
            val outcome = VideoPackageBuilder.build(workDir, zip, manifest, active.frames, active.sensors)
            workDir.deleteRecursively()
            when (outcome) {
                is VideoPackageOutcome.TooLarge -> VideoCaptureResult.error(
                    VideoCaptureResult.ERROR_PACKAGE_TOO_LARGE,
                    "El recorrido pesa más de 150 MB y no se puede subir. Grabá un recorrido más corto.",
                )
                is VideoPackageOutcome.Built -> VideoCaptureResult.captured(
                    zipPath = zip.absolutePath,
                    captureId = captureId,
                    sizeBytes = outcome.sizeBytes,
                    frameCount = active.frames.count,
                    rooms = rooms,
                    hasReference = usableReference != null,
                    durationMs = (endNs - firstFrameNs) / 1_000_000L,
                    reachedTimeLimit = reachedTimeLimit,
                    timestampSource = active.timestampSource,
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Video package failed", e)
            workDir.deleteRecursively()
            VideoCaptureResult.error(
                VideoCaptureResult.ERROR_RECORDING_FAILED,
                "No pudimos armar el paquete del recorrido (¿poco espacio en el teléfono?).",
            )
        }
    }

    private fun cancelCapture() {
        if (phase == Phase.FINISHING || phase == Phase.DONE) return
        main.removeCallbacks(tick)
        workDir.deleteRecursively()
        finishWithResult(VideoCaptureResult.cancelled())
    }

    private fun finishWithResult(result: Map<String, Any?>) {
        if (phase == Phase.DONE) return
        phase = Phase.DONE
        main.removeCallbacks(tick)
        recorder?.release()
        recorder = null
        if (result["outcome"] != "captured") workDir.deleteRecursively()
        setResult(RESULT_OK, Intent().putExtra(EXTRA_RESULT_JSON, JsonWriter.write(result)))
        finish()
    }

    @Deprecated("Used below API 33 and when predictive back is not enabled.")
    override fun onBackPressed() {
        if (phase == Phase.MARKING) endReference() else cancelCapture()
    }

    override fun onStop() {
        super.onStop()
        // The camera and the sensors stop with the app in the background: the recording would have gaps.
        if (phase == Phase.RECORDING || phase == Phase.MARKING) {
            main.removeCallbacks(tick)
            workDir.deleteRecursively()
            finishWithResult(
                VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, "La grabación se interrumpió al salir de la app."),
            )
        }
    }

    override fun onDestroy() {
        if (phase != Phase.DONE) {
            main.removeCallbacks(tick)
            recorder?.release()
            recorder = null
            workDir.deleteRecursively()
        }
        super.onDestroy()
    }

    // endregion

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

    companion object {
        const val EXTRA_LISTING_ID = "listingId"
        const val EXTRA_FIRST_ROOM_NAME = "firstRoomName"
        const val EXTRA_RESULT_JSON = "resultJson"
        private const val CAMERA_PERMISSION_REQUEST = 4208
        private const val TICK_MS = 500L
        private const val SURFACE_FLOOR_ID = 9101
        private const val SURFACE_WALL_ID = 9102
        private const val TAG = "RoomForgeVideo"
    }
}

/** Keeps its children at the 16:9 of the recorded frame so normalised taps map onto it. */
internal class AspectFrameLayout(context: android.content.Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec)
        val maxH = MeasureSpec.getSize(heightMeasureSpec)
        val fitsByHeight = maxW * VideoSpec.HEIGHT > maxH * VideoSpec.WIDTH
        val w = if (fitsByHeight) maxH * VideoSpec.WIDTH / VideoSpec.HEIGHT else maxW
        val h = if (fitsByHeight) maxH else maxW * VideoSpec.HEIGHT / VideoSpec.WIDTH
        super.onMeasure(
            MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY),
        )
    }
}

/** A frozen frame on which the agent taps the two ends of the reference object. */
internal class ReferenceMarkView(context: android.content.Context) : View(context) {
    private var frame: Bitmap? = null
    var frameNs: Long = 0L
        private set
    private val taps = ArrayList<Pair<Float, Float>>(2)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 4f; color = Color.YELLOW }

    fun show(bitmap: Bitmap, frameNs: Long) {
        frame = bitmap
        this.frameNs = frameNs
        taps.clear()
        invalidate()
    }

    fun clear() {
        frame = null
        taps.clear()
    }

    fun clearPoints() {
        taps.clear()
        invalidate()
    }

    /** The two ends normalised to 0..1 on the frame, or null until both were tapped. */
    fun points(): Pair<ReferencePoint, ReferencePoint>? {
        if (taps.size < 2 || width <= 0 || height <= 0) return null
        val (a, b) = taps
        return ReferencePoint.fromPixels(a.first, a.second, width.toFloat(), height.toFloat()) to
            ReferencePoint.fromPixels(b.first, b.second, width.toFloat(), height.toFloat())
    }

    override fun onDraw(canvas: Canvas) {
        frame?.let { canvas.drawBitmap(it, null, android.graphics.Rect(0, 0, width, height), null) }
        taps.forEach { canvas.drawCircle(it.first, it.second, 14f, paint) }
        if (taps.size == 2) canvas.drawLine(taps[0].first, taps[0].second, taps[1].first, taps[1].second, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            if (taps.size == 2) taps.clear()
            taps.add(event.x to event.y)
            invalidate()
            return true
        }
        return true
    }
}
