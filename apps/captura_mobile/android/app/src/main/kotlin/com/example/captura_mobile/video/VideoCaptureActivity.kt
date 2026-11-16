package com.example.captura_mobile.video

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import com.example.captura_mobile.R
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
    private lateinit var hintText: TextView
    private lateinit var timerText: TextView
    private lateinit var recordButton: View
    private lateinit var nextRoomButton: View
    private lateinit var referenceButton: View
    private lateinit var stopButton: View
    private lateinit var timerChip: View
    private lateinit var rail: FrameLayout
    private lateinit var chipsLayer: FrameLayout
    private var cancelDialog: AlertDialog? = null
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
            showGuidance(now)
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

    private fun rounded(color: Int, radiusDp: Int, strokeColor: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
        if (strokeColor != null) setStroke(dp(2), strokeColor)
    }

    /** Rounded chip over the preview used by the instruction and the banners. */
    private fun chip(textView: TextView, background: Int, horizontalDp: Int = 12, verticalDp: Int = 6) = textView.apply {
        setPadding(dp(horizontalDp), dp(verticalDp), dp(horizontalDp), dp(verticalDp))
        this.background = rounded(background, 16)
    }

    private fun wrap() = ViewGroup.LayoutParams.WRAP_CONTENT
    private fun match() = ViewGroup.LayoutParams.MATCH_PARENT

    private fun buildUi() {
        // Edge-to-edge: the preview is full-bleed and every control is padded by the system insets.
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

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
        stage = AspectFrameLayout(this).apply {
            addView(textureView, match(), match())
            addView(markView, match(), match())
        }

        timerText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.MONOSPACE
            text = "00:00"
        }
        val recDot = View(this).apply { background = rounded(RED, 6) }
        timerChip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(6), dp(14), dp(6))
            background = rounded(SCRIM, 16)
            addView(recDot, LinearLayout.LayoutParams(dp(10), dp(10)).apply { rightMargin = dp(8) })
            addView(timerText)
            visibility = View.GONE
        }
        statusText = chip(
            TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 14f
                gravity = Gravity.CENTER
                maxLines = 2
                text = IDLE_INSTRUCTION
            },
            SCRIM,
            horizontalDp = 16,
            verticalDp = 8,
        )
        warningText = chip(
            TextView(this).apply {
                text = "Sin referencia: el modelo quedará sin escala métrica."
                setTextColor(Color.BLACK)
                textSize = 13f
                visibility = View.GONE
            },
            Color.argb(235, 255, 193, 7),
        )
        hintText = chip(
            TextView(this).apply {
                setTextColor(Color.BLACK)
                textSize = 13f
                visibility = View.GONE
            },
            Color.argb(235, 255, 255, 255),
        )

        recordButton = circleAction(R.drawable.ic_video_record, "Grabar") { startRecording() }
        stopButton = circleAction(R.drawable.ic_video_stop, "Detener y guardar") { finishRecording(reachedTimeLimit = false) }
            .apply { visibility = View.GONE }
        referenceButton = railButton(R.drawable.ic_video_reference, "Marcar referencia") { beginReference() }
            .apply { visibility = View.GONE }
        nextRoomButton = railButton(R.drawable.ic_video_next_room, "Siguiente ambiente") { nextRoom() }
            .apply { visibility = View.GONE }
        val cancelButton = TextView(this).apply {
            text = "Cancelar"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            minHeight = dp(48)
            minWidth = dp(48)
            contentDescription = "Cancelar"
            setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_video_close, 0, 0, 0)
            compoundDrawablePadding = dp(4)
            compoundDrawableTintList = ColorStateList.valueOf(Color.WHITE)
            isClickable = true
            setOnClickListener { cancelCapture() }
        }
        controlsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(cancelButton, LinearLayout.LayoutParams(wrap(), wrap()))
            addView(View(this@VideoCaptureActivity), LinearLayout.LayoutParams(0, 0, 1f))
            addView(referenceButton, railItemParams())
            addView(nextRoomButton, railItemParams())
            addView(View(this@VideoCaptureActivity), LinearLayout.LayoutParams(0, 0, 1f))
            addView(recordButton, railItemParams())
            addView(stopButton, railItemParams())
        }
        // The rail runs to the window edge so its scrim also covers the navigation bar; its content is inset.
        rail = FrameLayout(this).apply {
            setBackgroundColor(RAIL_SCRIM)
            addView(controlsPanel, FrameLayout.LayoutParams(match(), match()))
        }
        referencePanel = buildReferencePanel().apply { setBackgroundColor(Color.argb(225, 0, 0, 0)) }.also { it.visibility = View.GONE }

        // Overlay for the chips and banners, kept inside the safe area plus a 16dp margin and clear of the rail.
        chipsLayer = FrameLayout(this).apply {
            addView(timerChip, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.START))
            addView(
                statusText,
                FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                    leftMargin = dp(112)
                    rightMargin = dp(8)
                },
            )
            val banners = LinearLayout(this@VideoCaptureActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(hintText, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(8) })
                addView(warningText, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(8) })
            }
            addView(banners, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.BOTTOM or Gravity.START))
        }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(stage, FrameLayout.LayoutParams(match(), match(), Gravity.CENTER))
            addView(chipsLayer, FrameLayout.LayoutParams(match(), match()))
            addView(rail, FrameLayout.LayoutParams(dp(RAIL_WIDTH_DP), match(), Gravity.END))
            addView(referencePanel, FrameLayout.LayoutParams(dp(REFERENCE_PANEL_WIDTH_DP), match(), Gravity.END))
        }
        root.setOnApplyWindowInsetsListener { _, insets ->
            applySafeInsets(insets)
            insets
        }
        setContentView(root)
        root.requestApplyInsets()
    }

    /** Pads the chipsLayer, the rail and the reference panel by the system bars and the display cutout. */
    private fun applySafeInsets(insets: WindowInsets) {
        val left: Int
        val top: Int
        val right: Int
        val bottom: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val safe = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            left = safe.left; top = safe.top; right = safe.right; bottom = safe.bottom
        } else {
            @Suppress("DEPRECATION")
            run {
                left = insets.systemWindowInsetLeft; top = insets.systemWindowInsetTop
                right = insets.systemWindowInsetRight; bottom = insets.systemWindowInsetBottom
            }
        }
        val margin = dp(MARGIN_DP)
        val railWidth = dp(RAIL_WIDTH_DP) + right
        rail.layoutParams = (rail.layoutParams as FrameLayout.LayoutParams).apply { width = railWidth }
        controlsPanel.setPadding(dp(8), top + margin, right + dp(8), bottom + margin)
        referencePanel.layoutParams = (referencePanel.layoutParams as FrameLayout.LayoutParams).apply {
            width = dp(REFERENCE_PANEL_WIDTH_DP) + right
        }
        referencePanel.setPadding(dp(12), top + dp(8), right + dp(12), bottom + dp(8))
        chipsLayer.setPadding(left + margin, top + margin, railWidth + margin, bottom + margin)
    }

    private fun railItemParams() = LinearLayout.LayoutParams(match(), wrap()).apply {
        topMargin = dp(6)
        bottomMargin = dp(6)
    }

    /** Large round action (record or stop) with its short label underneath. */
    private fun circleAction(icon: Int, label: String, onClick: () -> Unit): LinearLayout {
        val iconView = ImageView(this).apply {
            setImageResource(icon)
            scaleType = ImageView.ScaleType.CENTER
            background = rounded(RED, 32, Color.WHITE)
        }
        val text = TextView(this).apply {
            this.text = label
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            contentDescription = label
            isClickable = true
            addView(iconView, LinearLayout.LayoutParams(dp(64), dp(64)))
            addView(text, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(4) })
            setOnClickListener { onClick() }
        }
    }

    /** Secondary tonal action: icon over a short label, at least 48dp high. */
    private fun railButton(icon: Int, label: String, onClick: () -> Unit): LinearLayout {
        val iconView = ImageView(this).apply { setImageResource(icon) }
        val text = TextView(this).apply {
            this.text = label
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            maxLines = 2
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            minimumHeight = dp(60)
            setPadding(dp(4), dp(6), dp(4), dp(6))
            background = rounded(Color.argb(70, 255, 255, 255), 14)
            contentDescription = label
            isClickable = true
            addView(iconView, LinearLayout.LayoutParams(dp(24), dp(24)))
            addView(text, LinearLayout.LayoutParams(wrap(), wrap()))
            setOnClickListener { onClick() }
        }
    }

    private fun button(label: String, filled: Boolean = false, onClick: () -> Unit) = Button(this).apply {
        text = label
        minimumHeight = dp(48)
        isAllCaps = false
        setTextColor(Color.WHITE)
        background = rounded(if (filled) RED else Color.argb(70, 255, 255, 255), 14)
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
            setTextColor(Color.WHITE); textSize = 12f
            text = "Tocá los dos extremos del objeto sobre la imagen congelada. La grabación sigue."
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(hint)
            addView(presetSpinner)
            addView(lengthInput)
            addView(labelInput)
            addView(surfaceGroup)
            addView(button("Confirmar referencia", filled = true) { confirmReference() }, LinearLayout.LayoutParams(match(), wrap()).apply { topMargin = dp(2) })
            addView(button("Repetir puntos") { markView.clearPoints() }, LinearLayout.LayoutParams(match(), wrap()).apply { topMargin = dp(2) })
            addView(button("Seguir sin referencia") { endReference() }, LinearLayout.LayoutParams(match(), wrap()).apply { topMargin = dp(2) })
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

    /** Live hint (S8) over the preview; only while recording, hidden while the reference is marked. */
    private fun showGuidance(nowNs: Long) {
        val hint = if (phase == Phase.RECORDING) recorder?.guidance?.current(nowNs) else null
        hintText.text = hint?.message.orEmpty()
        hintText.visibility = if (hint == null) View.GONE else View.VISIBLE
    }

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
            timerChip.visibility = View.VISIBLE
            warningText.visibility = View.VISIBLE
            statusText.text = RECORDING_INSTRUCTION
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
        rail.visibility = View.GONE
        chipsLayer.visibility = View.GONE
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
        rail.visibility = View.VISIBLE
        chipsLayer.visibility = View.VISIBLE
    }

    // endregion

    // region finishing

    private fun finishRecording(reachedTimeLimit: Boolean) {
        if (phase != Phase.RECORDING && phase != Phase.MARKING) return
        phase = Phase.FINISHING
        main.removeCallbacks(tick)
        hintText.visibility = View.GONE
        statusText.text = "Guardando el recorrido…"
        rail.visibility = View.VISIBLE
        chipsLayer.visibility = View.VISIBLE
        referencePanel.visibility = View.GONE
        markView.visibility = View.GONE
        listOf(referenceButton, nextRoomButton, stopButton).forEach {
            it.isEnabled = false
            it.alpha = 0.4f
        }
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
        if (phase == Phase.RECORDING || phase == Phase.MARKING) {
            // An unrepeatable recording: never discard it on a single tap.
            if (cancelDialog?.isShowing == true) return
            cancelDialog = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setMessage("¿Descartar esta grabación?")
                .setPositiveButton("Descartar") { _, _ -> discardCapture() }
                .setNegativeButton("Seguir grabando", null)
                .show()
            return
        }
        discardCapture()
    }

    private fun discardCapture() {
        if (phase == Phase.FINISHING || phase == Phase.DONE) return
        main.removeCallbacks(tick)
        workDir.deleteRecursively()
        finishWithResult(VideoCaptureResult.cancelled())
    }

    private fun finishWithResult(result: Map<String, Any?>) {
        if (phase == Phase.DONE) return
        phase = Phase.DONE
        main.removeCallbacks(tick)
        cancelDialog?.dismiss()
        cancelDialog = null
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
        private const val MARGIN_DP = 16
        private const val RAIL_WIDTH_DP = 112
        private const val REFERENCE_PANEL_WIDTH_DP = 300
        private val RED = Color.rgb(229, 57, 53)
        private val SCRIM = Color.argb(150, 0, 0, 0)
        private val RAIL_SCRIM = Color.argb(170, 0, 0, 0)
        private const val IDLE_INSTRUCTION = "Encuadrá un objeto de medida conocida y tocá Grabar"
        private const val RECORDING_INSTRUCTION = "Grabando · marcá la referencia y recorré el inmueble"
    }
}

/**
 * Keeps its children at the 16:9 of the recorded frame so normalised taps map onto it, scaled to cover the
 * whole window (full-bleed): the part of the frame beyond the screen edges is cropped from view only, the
 * recorded video is unchanged.
 */
internal class AspectFrameLayout(context: android.content.Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec)
        val maxH = MeasureSpec.getSize(heightMeasureSpec)
        val widthLimited = maxW * VideoSpec.HEIGHT > maxH * VideoSpec.WIDTH
        val w = if (widthLimited) maxW else maxH * VideoSpec.WIDTH / VideoSpec.HEIGHT
        val h = if (widthLimited) maxW * VideoSpec.HEIGHT / VideoSpec.WIDTH else maxH
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
