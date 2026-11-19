package com.example.captura_mobile.video

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.media.MediaMetadataRetriever
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.Surface
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
 * in [VideoRecorder] and the package logic in VideoPackage.kt. Works in the four orientations (T17): the
 * recorded frame stays the raw sensor image in the negotiated size (4:3 preferred), the preview is rotated upright for display only
 * ([PreviewGeometry]), and the reference points and corners are mapped back to the stored frame before they
 * reach the package. The orientation is locked while a recording is in progress.
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
    private var previewReady = false
    private var referenceRequested = false
    private var pendingPackage: (() -> Unit)? = null
    private var reviewDialog: AlertDialog? = null
    private val foreground = VideoCaptureForeground()
    private var finalizedRooms: List<VideoRoom>? = null
    private val startTimeout = Runnable {
        if (phase == Phase.PREVIEW) onFailure("La camara no respondio. Cerra y reintenta la captura.")
    }

    private var startedAtNs = 0L
    private var reference: ReferenceMark? = null
    private var visualSampler: PreviewGuidanceSampler? = null
    private var visualEnabled = true
    private var visualStep = 0
    private val guidedProgress = GuidedCaptureProgress()
    private var preparationChosen = false
    private var wantsReference = true
    private val guidanceRoomNotes = mutableListOf<String>()
    private var visualRoomName = "Ambiente 1"
    private lateinit var visualStepText: TextView
    private lateinit var guidanceConfirm: TextView
    private lateinit var guidanceHidden: TextView
    private lateinit var visualOverlay: ReferenceCandidateOverlay
    private lateinit var captureSummaryText: TextView


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
    private lateinit var referencePanel: LinearLayout
    private lateinit var root: FrameLayout
    private lateinit var cancelButton: TextView
    private lateinit var banners: LinearLayout
    private var sensorOrientation = 90

    /** Size of the stored frame; the preferred one until the recorder negotiates it with the camera. */
    private var videoSize = VideoSpec.PREFERRED_SIZES.first()

    /** Size of the preview buffer; the stage takes its aspect (same as the video's when the camera offers such a size). */
    private var previewSize = videoSize

    /** Rotation the platform already applies to the TextureView content, read from the SurfaceTexture matrix. */
    private var measuredHint = 0
    private val surfaceMatrix = FloatArray(16)
    private var lastLoggedState = ""
    private var portrait = false
    private var controlsBuilt = false

    /** Clockwise rotation of the frozen frame that was shown for marking; converts taps to the stored frame. */
    private var markRotation = 0
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) {
            main.post { updateOrientation() }
        }
    }
    private lateinit var presetSpinner: Spinner
    private lateinit var lengthInput: EditText
    private lateinit var labelInput: EditText
    private lateinit var shortSideInput: EditText
    private lateinit var referenceHint: TextView
    private lateinit var detectStatus: TextView
    private lateinit var modeButton: Button
    private lateinit var repeatPointsButton: Button
    private var detectToken = 0
    private lateinit var surfaceGroup: RadioGroup

    private val tick = object : Runnable {
        override fun run() {
            if (phase != Phase.RECORDING && phase != Phase.MARKING) return
            val now = SystemClock.elapsedRealtimeNanos()
            val elapsedS = ((now - startedAtNs) / 1_000_000_000L).coerceAtLeast(0)
            timerText.text = String.format(Locale.ROOT, "%02d:%02d", elapsedS / 60, elapsedS % 60)
            showGuidance()
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
        visualRoomName = intent.getStringExtra(EXTRA_FIRST_ROOM_NAME)?.trim()?.takeIf { it.isNotEmpty() } ?: "Ambiente 1"
        workDir = File(filesDir, "video_work/$captureId").also { it.mkdirs() }
        checkpointRecovery("preview")
        sensorOrientation = VideoRecorder.backCameraSensorOrientation(applicationContext)
        buildUi()
        getSystemService(DisplayManager::class.java).registerDisplayListener(displayListener, main)
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

                override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = applyTextureTransform()
                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
                    // The hint can appear only after the first frame: re-apply the transform whenever it changes.
                    try {
                        surface.getTransformMatrix(surfaceMatrix)
                    } catch (e: Exception) {
                        return
                    }
                    val hint = PreviewGeometry.hintRotationDegrees(surfaceMatrix)
                    if (hint != measuredHint || lastLoggedState.isEmpty()) {
                        measuredHint = hint
                        applyTextureTransform()
                    }
                }
            }
        }
        textureView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) applyTextureTransform()
        }
        markView = ReferenceMarkView(this).apply { visibility = View.GONE }
        visualOverlay = ReferenceCandidateOverlay(this)
        stage = AspectFrameLayout(this).apply {
            addView(textureView, match(), match())
            addView(visualOverlay, match(), match())
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
        recordButton.isEnabled = false
        stopButton = circleAction(R.drawable.ic_video_stop, "Detener y guardar") { finishRecording(reachedTimeLimit = false) }
            .apply { visibility = View.GONE }
        referenceButton = railButton(R.drawable.ic_video_reference, "Referencia inicial") { beginReference() }
            .apply { visibility = View.GONE }
        nextRoomButton = railButton(R.drawable.ic_video_next_room, "Siguiente ambiente") { nextRoom() }
            .apply { visibility = View.GONE }
        cancelButton = TextView(this).apply {
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
        // The children of the rail and of the chips layer are placed by buildControls() for the current orientation.
        controlsPanel = LinearLayout(this)
        // The rail runs to the window edge so its scrim also covers the navigation bar; its content is inset.
        rail = FrameLayout(this).apply {
            setBackgroundColor(RAIL_SCRIM)
            addView(controlsPanel, FrameLayout.LayoutParams(match(), match()))
        }
        referencePanel = buildReferencePanel().apply { setBackgroundColor(Color.argb(225, 0, 0, 0)) }.also { it.visibility = View.GONE }

        // Overlay for the chips and banners, kept inside the safe area plus a 16dp margin and clear of the rail.
        chipsLayer = FrameLayout(this)
        visualStepText = chip(TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 16f; maxLines = 3
            text = "Encuadrá el objeto completo y detalles del piso o pared; medí sus lados reales en cm."
            setOnClickListener {
                if (phase != Phase.PREVIEW && phase != Phase.RECORDING) return@setOnClickListener
                if (!visualEnabled) { visualEnabled = true; visualSampler?.start() }
                renderGuidance()
            }
            setOnLongClickListener {
                if (phase != Phase.PREVIEW && phase != Phase.RECORDING) return@setOnLongClickListener true
                AlertDialog.Builder(this@VideoCaptureActivity)
                    .setTitle("Guía visual · detalles")
                    .setMessage(visualSampler?.summary().orEmpty() + "\n\n" + guidedProgress.summary())
                    .setPositiveButton("Cerrar", null)
                    .setNegativeButton(if (visualEnabled) "Desactivar guía" else "Activar guía") { _, _ ->
                        if (!this@VideoCaptureActivity.foreground.resumed ||
                            (phase != Phase.PREVIEW && phase != Phase.RECORDING)) return@setNegativeButton
                        visualEnabled = !visualEnabled
                        if (visualEnabled) visualSampler?.start() else visualSampler?.pause()
                        visualOverlay.corners = null
                        guidedProgress.invalidateObservation()
                        renderGuidance()
                    }.show()
                true
            }
        }, SCRIM)
        guidanceConfirm = chip(TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 13f; maxLines = 2
            minHeight = dp(48)
            visibility = View.GONE
        }, SCRIM)
        guidanceHidden = chip(TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 13f; minHeight = dp(48)
            text = "Zona tapada"
            visibility = View.GONE
        }, SCRIM)
        banners = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(visualStepText, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(8) })
            addView(LinearLayout(this@VideoCaptureActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(guidanceConfirm, LinearLayout.LayoutParams(0, wrap(), 1f))
                addView(guidanceHidden, LinearLayout.LayoutParams(wrap(), wrap()).apply { leftMargin = dp(4) })
            }, LinearLayout.LayoutParams(match(), wrap()).apply { topMargin = dp(4) })
            addView(hintText, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(8) })
            addView(warningText, LinearLayout.LayoutParams(wrap(), wrap()).apply { topMargin = dp(8) })
        }

        root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(stage, FrameLayout.LayoutParams(match(), match(), Gravity.CENTER))
            addView(chipsLayer, FrameLayout.LayoutParams(match(), match()))
            addView(rail, FrameLayout.LayoutParams(dp(RAIL_WIDTH_DP), match(), Gravity.END))
            addView(referencePanel, FrameLayout.LayoutParams(dp(REFERENCE_PANEL_WIDTH_DP), match(), Gravity.END))
        }
        root.setOnApplyWindowInsetsListener { _, windowInsets ->
            readInsets(windowInsets)
            updateOrientation()
            windowInsets
        }
        root.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) updateOrientation()
        }
        setContentView(root)
        root.requestApplyInsets()
    }

    private class SafeInsets(val left: Int, val top: Int, val right: Int, val bottom: Int)

    private var insets = SafeInsets(0, 0, 0, 0)

    /** Reads the system bars and the display cutout; the layout is padded by them in [applyLayout]. */
    private fun readInsets(windowInsets: WindowInsets) {
        insets = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val safe = windowInsets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            SafeInsets(safe.left, safe.top, safe.right, safe.bottom)
        } else {
            @Suppress("DEPRECATION")
            SafeInsets(
                windowInsets.systemWindowInsetLeft, windowInsets.systemWindowInsetTop,
                windowInsets.systemWindowInsetRight, windowInsets.systemWindowInsetBottom,
            )
        }
    }

    private fun displayRotationDegrees(): Int {
        @Suppress("DEPRECATION")
        return when (windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    /** Clockwise rotation that makes the raw sensor frame upright for the way the phone is held now. */
    private fun imageRotation(): Int = PreviewGeometry.imageRotation(sensorOrientation, displayRotationDegrees())

    /**
     * Re-lays the screen for how the phone is held: portrait or landscape controls, the preview stage in the upright
     * aspect and the texture matrix. Called when the window size, the insets or the display rotation change (a turn
     * between the two portraits or the two landscapes keeps the window size, so the display listener calls it too).
     */
    private fun updateOrientation() {
        if (!::root.isInitialized || root.width <= 0 || root.height <= 0) return
        val nowPortrait = root.height > root.width
        if (!controlsBuilt || nowPortrait != portrait) {
            portrait = nowPortrait
            controlsBuilt = true
            buildControls()
        }
        applyLayout()
        applyTextureTransform()
    }

    /** Rotates the raw sensor buffer upright inside the stage (the stage already has the upright aspect). */
    private fun applyTextureTransform() {
        val w = textureView.width
        val h = textureView.height
        if (w <= 0 || h <= 0) return
        val plan = PreviewGeometry.plan(sensorOrientation, displayRotationDegrees(), measuredHint)
        val matrix = Matrix()
        matrix.setValues(PreviewGeometry.bufferToView(plan.remainder, w.toFloat(), h.toFloat()))
        textureView.setTransform(matrix)
        logOrientation(plan, w, h)
    }

    /** One line per change, to verify on a device: `adb logcat -s VideoPreview`. */
    private fun logOrientation(plan: PreviewGeometry.Plan, textureWidth: Int, textureHeight: Int) {
        val state = "display=${displayRotationDegrees()} sensor=$sensorOrientation hint=${plan.hint} (measured $measuredHint) " +
            "remainder=${plan.remainder} texture=${textureWidth}x$textureHeight stage=${stage.width}x${stage.height} " +
            "matrix2x2=[${surfaceMatrix[0]}, ${surfaceMatrix[4]}; ${surfaceMatrix[1]}, ${surfaceMatrix[5]}]"
        if (state == lastLoggedState) return
        lastLoggedState = state
        Log.i(PREVIEW_TAG, state)
    }

    /**
     * Places the rail, the chips, the reference panel and the stage by the safe insets for the current orientation.
     * The whole recorded frame is always visible (letterbox, never cropped): the controls use the space it leaves.
     * Landscape: the image sits at the left and the rail takes the rest of the width. Portrait: the image sits just
     * above the bottom rail and the top bar (Cancelar, timer, instruction) uses the space above it.
     */
    private fun applyLayout() {
        val margin = dp(MARGIN_DP)
        val marking = phase == Phase.MARKING
        val panelHeight = (root.height * PORTRAIT_PANEL_FRACTION).toInt()
        val rotation = imageRotation()
        val stageParams: FrameLayout.LayoutParams
        if (portrait) {
            val railHeight = dp(PORTRAIT_RAIL_DP) + insets.bottom
            rail.layoutParams = FrameLayout.LayoutParams(match(), railHeight, Gravity.BOTTOM)
            controlsPanel.setPadding(insets.left + dp(8), dp(8), insets.right + dp(8), insets.bottom + dp(8))
            referencePanel.layoutParams = FrameLayout.LayoutParams(match(), panelHeight, Gravity.BOTTOM)
            referencePanel.setPadding(insets.left + dp(12), dp(8), insets.right + dp(12), insets.bottom + dp(8))
            chipsLayer.setPadding(insets.left + margin, insets.top + margin, insets.right + margin, railHeight + margin)
            statusText.maxWidth = Int.MAX_VALUE
            // While marking, the image stays on top above the bottom panel; otherwise it sits on the rail.
            stageParams = if (marking) {
                FrameLayout.LayoutParams(match(), match(), Gravity.TOP or Gravity.CENTER_HORIZONTAL)
                    .apply { topMargin = insets.top; bottomMargin = panelHeight }
            } else {
                FrameLayout.LayoutParams(match(), match(), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
                    .apply { topMargin = insets.top + dp(TOP_BAR_DP); bottomMargin = railHeight }
            }
        } else {
            val minRail = dp(RAIL_WIDTH_DP) + insets.right
            val (stageWidth, _) = PreviewGeometry.stageSize(
                rotation, previewSize.width, previewSize.height, (root.width - insets.left - minRail).coerceAtLeast(1), root.height,
            )
            val railWidth = maxOf(minRail, root.width - insets.left - stageWidth)
            rail.layoutParams = FrameLayout.LayoutParams(railWidth, match(), Gravity.END)
            controlsPanel.setPadding(dp(8), insets.top + margin, insets.right + dp(8), insets.bottom + margin)
            referencePanel.layoutParams = FrameLayout.LayoutParams(dp(REFERENCE_PANEL_WIDTH_DP) + insets.right, match(), Gravity.END)
            referencePanel.setPadding(dp(12), insets.top + dp(8), insets.right + dp(12), insets.bottom + dp(8))
            chipsLayer.setPadding(insets.left + margin, insets.top + margin, railWidth + margin, insets.bottom + margin)
            // The instruction chip clears the timer chip on its left and never grows past the image.
            statusText.maxWidth = (stageWidth - 2 * margin - dp(112) - dp(8)).coerceAtLeast(dp(160))
            stageParams = FrameLayout.LayoutParams(match(), match(), Gravity.START or Gravity.CENTER_VERTICAL)
                .apply { leftMargin = insets.left; rightMargin = railWidth }
        }
        stage.layoutParams = stageParams
        stage.configure(rotation, previewSize.width, previewSize.height)
        markView.centeredDefault = portrait
    }

    private fun detach(view: View) {
        (view.parent as? ViewGroup)?.removeView(view)
    }

    /** Builds the control rail and the chips for the current orientation (the same views, placed differently). */
    private fun buildControls() {
        listOf(cancelButton, referenceButton, nextRoomButton, recordButton, stopButton, timerChip, statusText, banners).forEach(::detach)
        controlsPanel.removeAllViews()
        chipsLayer.removeAllViews()
        if (portrait) {
            // Bottom rail: the record or stop button is centred and primary; the secondary actions sit beside it.
            controlsPanel.orientation = LinearLayout.HORIZONTAL
            controlsPanel.gravity = Gravity.CENTER_VERTICAL
            fun slot(vararg views: View, width: Int = wrap()) = FrameLayout(this).apply {
                views.forEach { addView(it, FrameLayout.LayoutParams(width, wrap(), Gravity.CENTER)) }
            }
            controlsPanel.addView(slot(referenceButton, width = dp(SECONDARY_WIDTH_DP)), LinearLayout.LayoutParams(0, wrap(), 1f))
            controlsPanel.addView(slot(recordButton, stopButton), LinearLayout.LayoutParams(0, wrap(), 1f))
            controlsPanel.addView(slot(nextRoomButton, width = dp(SECONDARY_WIDTH_DP)), LinearLayout.LayoutParams(0, wrap(), 1f))
            cancelButton.background = rounded(SCRIM, 16)
            cancelButton.setPadding(dp(10), 0, dp(14), 0)
            chipsLayer.addView(cancelButton, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.START))
            chipsLayer.addView(timerChip, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.END).apply { topMargin = dp(6) })
            chipsLayer.addView(
                statusText,
                FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(56) },
            )
        } else {
            controlsPanel.orientation = LinearLayout.VERTICAL
            controlsPanel.gravity = Gravity.CENTER_HORIZONTAL
            cancelButton.background = null
            cancelButton.setPadding(0, 0, 0, 0)
            controlsPanel.addView(cancelButton, LinearLayout.LayoutParams(wrap(), wrap()))
            controlsPanel.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))
            controlsPanel.addView(referenceButton, railItemParams())
            controlsPanel.addView(nextRoomButton, railItemParams())
            controlsPanel.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))
            controlsPanel.addView(recordButton, railItemParams())
            controlsPanel.addView(stopButton, railItemParams())
            chipsLayer.addView(timerChip, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.START))
            chipsLayer.addView(
                statusText,
                FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                    leftMargin = dp(112)
                    rightMargin = dp(8)
                },
            )
        }
        chipsLayer.addView(banners, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.BOTTOM or Gravity.START))
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

    private fun buildReferencePanel(): LinearLayout {
        val presets = ReferencePresets.ALL
        presetSpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@VideoCaptureActivity,
                android.R.layout.simple_spinner_dropdown_item,
                presets.map { it.label } + "Otro (valor libre)",
            )
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    // A preset only fills the fields; the agent can edit the sizes and label afterwards.
                    presets.getOrNull(position)?.let { applyPreset(it) }
                }

                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            }
        }
        lengthInput = EditText(this).apply {
            hint = "Lado largo real (cm)"
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
        }
        shortSideInput = EditText(this).apply {
            hint = "Lado corto real (cm)"
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
        referenceHint = TextView(this).apply { setTextColor(Color.WHITE); textSize = 12f }
        detectStatus = TextView(this).apply { setTextColor(Color.rgb(255, 213, 79)); textSize = 12f }
        captureSummaryText = TextView(this).apply { setTextColor(Color.WHITE); textSize = 12f }
        modeButton = button("Marcar a mano") { toggleReferenceMode() }
        repeatPointsButton = button("Repetir puntos") { markView.clearPoints() }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(captureSummaryText)
            addView(referenceHint)
            addView(detectStatus)
            addView(presetSpinner)
            addView(TextView(this@VideoCaptureActivity).apply { text = "Lado largo o distancia real (cm)"; setTextColor(Color.WHITE) })
            addView(lengthInput)
            addView(TextView(this@VideoCaptureActivity).apply { text = "Lado corto real, para rectángulos (cm)"; setTextColor(Color.WHITE) })
            addView(shortSideInput)
            addView(labelInput)
            addView(surfaceGroup)
        }
        // The buttons stay fixed under the scrolling fields so Confirmar and Marcar a mano are always reachable.
        fun cell() = LinearLayout.LayoutParams(0, wrap(), 1f).apply { marginEnd = dp(4); marginStart = dp(4); topMargin = dp(2) }
        val footer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(
                LinearLayout(this@VideoCaptureActivity).apply {
                    addView(button("Confirmar", filled = true) { confirmReference() }, cell())
                    addView(modeButton, cell())
                },
                LinearLayout.LayoutParams(match(), wrap()),
            )
            addView(
                LinearLayout(this@VideoCaptureActivity).apply {
                    addView(repeatPointsButton, cell())
                    addView(button("Guardar sin referencia") { endReference() }, cell())
                },
                LinearLayout.LayoutParams(match(), wrap()),
            )
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(ScrollView(this@VideoCaptureActivity).apply { addView(panel) }, LinearLayout.LayoutParams(match(), 0, 1f))
            addView(footer, LinearLayout.LayoutParams(match(), wrap()))
        }
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
        previewReady = false
        recordButton.isEnabled = false
        visualStepText.text = if (wantsReference) "Primer cuadro: objeto completo y apoyo con textura."
            else "Sin referencia · preparando la imagen estable."
        main.postDelayed(startTimeout, 15_000)
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

    override fun onVideoSize(size: VideoSize) {
        main.post {
            videoSize = size
            previewSize = size
            updateOrientation()
        }
    }

    override fun onPreviewSize(size: VideoSize) {
        main.post {
            previewSize = size
            updateOrientation()
        }
    }

    override fun onPreviewReady() {
        main.post {
            if (isFinishing || isDestroyed || phase == Phase.DONE) return@post
            // Readiness can arrive while paused; retain it for onResume instead of losing it.
            main.removeCallbacks(startTimeout); previewReady = true
            resumePreviewGuidance()
        }
    }

    private fun resumePreviewGuidance() {
        if (isFinishing || isDestroyed || !foreground.canGuide(
                previewReady, phase == Phase.PREVIEW || phase == Phase.RECORDING)) return
        recordButton.isEnabled = phase == Phase.PREVIEW
        if (visualSampler == null) visualSampler = PreviewGuidanceSampler(textureView, main) { feedback, quad ->
            if (!foreground.resumed || (phase != Phase.PREVIEW && phase != Phase.RECORDING)) return@PreviewGuidanceSampler
            if (phase == Phase.RECORDING && visualEnabled) {
                visualStep = guidedProgress.observe(feedback, referenceCandidate = quad != null)
                visualSampler?.step = visualStep
                renderGuidance()
            } else {
                hintText.maxLines = 2
                hintText.text = feedback.message
                hintText.visibility = if (visualEnabled && feedback.issue != VisualIssue.NONE) View.VISIBLE else View.GONE
            }
            visualOverlay.rotationDegrees = PreviewGeometry.imageRotation(sensorOrientation, displayRotationDegrees())
            visualOverlay.corners = if (visualEnabled && wantsReference) quad else null
        }
        visualSampler?.bufferSize = previewSize
        if (visualEnabled) visualSampler?.start()
        renderGuidance()
    }

    override fun onFailure(message: String) {
        main.post {
            if (phase == Phase.DONE) return@post
            finishWithResult(VideoCaptureResult.error(VideoCaptureResult.ERROR_RECORDING_FAILED, message))
        }
    }

    // endregion

    // region recording

    private fun renderGuidance() {
        val active = visualEnabled && foreground.resumed && phase == Phase.RECORDING
        guidanceConfirm.visibility = View.GONE
        guidanceHidden.visibility = View.GONE
        if (!visualEnabled) {
            visualStepText.text = "Guía desactivada; podés grabar y guardar."
            hintText.visibility = View.GONE
            return
        }
        if (!active) return
        val roomRevision = guidedProgress.revision
        guidanceHidden.visibility = View.VISIBLE
        guidanceHidden.setOnClickListener {
            if (foreground.resumed && phase == Phase.RECORDING && visualEnabled) {
                guidedProgress.markHidden(roomRevision)
                renderGuidance()
            }
        }
        visualStepText.text = "${guidedProgress.state.label} · ${guidedProgress.instruction()}"
        val confirmation = guidedProgress.confirmation()
        if (confirmation != null) {
            val revision = guidedProgress.revision
            guidanceConfirm.text = confirmation
            guidanceConfirm.visibility = View.VISIBLE
            guidanceConfirm.setOnClickListener {
                if (foreground.resumed && phase == Phase.RECORDING && visualEnabled) {
                    visualStep = guidedProgress.confirm(revision)
                    visualSampler?.step = visualStep
                    renderGuidance()
                }
            }
        }
        val warning = guidedProgress.qualityWarning()
        hintText.maxLines = 2
        hintText.text = warning.orEmpty()
        hintText.visibility = if (warning == null) View.GONE else View.VISIBLE
    }

    /** Live hint (S8) over the preview; only while recording, hidden while the reference is marked. */
    private fun showGuidance() {
        // Image guidance works without a physical gyro; sensor heading never proves coverage.
        if (!visualEnabled) hintText.visibility = View.GONE
    }

    private fun startRecording() {
        val active = recorder ?: run {
            toast("La cámara todavía no está lista.")
            return
        }
        if (!previewReady) { toast("Espera a que la camara este lista."); return }
        if (!preparationChosen) {
            AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Prepará el recorrido")
                .setMessage("Con referencia: medí los lados reales en cm y dejá margen alrededor del objeto. " +
                    "Debe verse completo en el PRIMER fotograma, con detalles del piso o pared alrededor. " +
                    "Después alejate despacio manteniendo esos detalles en vistas superpuestas. " +
                    "Al guardar confirmarás sus esquinas y medidas. " +
                    "No asumimos tamaño A4. Sin referencia no habrá metros certificados. " +
                    "Si hay muebles, buscá bases y esquinas visibles desde otra posición.")
                .setPositiveButton("Con objeto medido") { _, _ ->
                    preparationChosen = true; wantsReference = true; startRecording()
                }
                .setNegativeButton("Sin referencia") { _, _ ->
                    preparationChosen = true; wantsReference = false; startRecording()
                }
                .setNeutralButton("Volver", null).show()
            return
        }
        recordButton.isEnabled = false
        statusText.text = if (wantsReference)
            "Iniciando: objeto medido completo y apoyo con textura hasta empezar la grabación."
        else "Iniciando: mantené la cámara estable."
        main.postDelayed(startTimeout, 15_000)
        lockOrientation()
        active.startRecording()
    }

    override fun onRecordingStarted(startedAtNs: Long) {
        main.post {
            if (phase != Phase.PREVIEW) return@post
            main.removeCallbacks(startTimeout)
            // This clock drives only the UI timer. Room boundaries must use
            // Camera2 timestamps, whose epoch may differ on UNKNOWN devices.
            this.startedAtNs = startedAtNs
            checkpointRecovery("recording")
            phase = Phase.RECORDING
            foreground.recordingStarted()
            referenceRequested = wantsReference
            // A delayed Camera2 start after onStop must finalize, never restart UI in background.
            if (!foreground.resumed) { finishRecording(false); return@post }
            visualStep = 0
            guidedProgress.reset(wantsReference = wantsReference)
            visualStep = guidedProgress.step
            visualSampler?.resetRecording(visualRoomName)
            visualSampler?.step = visualStep
            renderGuidance()
            recordButton.visibility = View.GONE
            referenceButton.visibility = if (wantsReference) View.VISIBLE else View.GONE
            nextRoomButton.visibility = View.VISIBLE
            stopButton.visibility = View.VISIBLE
            timerChip.visibility = View.VISIBLE
            warningText.visibility = View.GONE
            statusText.text = "Grabando · $visualRoomName"
            main.post(tick)
        }
    }

    private fun nextRoom() {
        if (phase != Phase.RECORDING) return
        val captured = recorder?.frames?.timestamps().orEmpty()
        val first = captured.firstOrNull() ?: run {
            toast("Esperá al primer cuadro de la grabación para cambiar de ambiente.")
            return
        }
        if (timeline.currentId == null) timeline.start(first)
        val room = timeline.nextRoom(captured.last())
        if (room != null) {
            guidanceRoomNotes.add("$visualRoomName: ${guidedProgress.summary()}")
            visualRoomName = room.name
            guidedProgress.reset(firstRoom = false, wantsReference = wantsReference)
            visualStep = 1 // Only the first frame of the whole video is the scale reference.
            visualSampler?.beginRoom(room.id, room.name)
            visualOverlay.corners = null
            renderGuidance()
            statusText.text = "Grabando · $visualRoomName"
            hintText.visibility = View.GONE
            toast("${room.name} iniciado")
        }
    }

    // endregion

    // region reference (S5)

    private fun beginReference() {
        if (phase != Phase.RECORDING || !wantsReference) return
        referenceRequested = true
        toast("Se usa solo el primer fotograma del video. Mostrar el objeto ahora no lo agrega a ese cuadro. Si no estaba al inicio, guardá sin referencia.")
    }

    private fun showEncodedReference(frame: Bitmap, frameNs: Long) {
        phase = Phase.MARKING
        captureSummaryText.text = "Primer fotograma real del MP4: ajustá las esquinas del objeto completo y confirmá sus medidas reales. " +
            "El piso o pared alrededor debe aportar detalles compartidos con las siguientes vistas; detectar el objeto no verifica pose ni escala. " +
            "Si no se ve completo, guardá sin referencia. Confirmar objeto y dimensiones no significa " +
            "que la escala esté aplicada: Worker3D debe ubicar la referencia en la geometría reconstruida.\n\n" +
            (guidanceRoomNotes + "$visualRoomName: ${guidedProgress.summary()}").joinToString("\n")
        captureSummaryText.setOnClickListener {
            if (foreground.resumed) AlertDialog.Builder(this).setTitle("Diagnóstico visual")
                .setMessage(visualSampler?.summary().orEmpty()).setPositiveButton("Cerrar", null).show()
        }
        // The frame is the view-oriented bitmap (upright); remember how it relates to the stored frame.
        markRotation = 0 // MediaMetadataRetriever returns the stored, unrotated frame.
        markView.show(frame, frameNs)
        markView.visibility = View.VISIBLE
        rail.visibility = View.GONE
        chipsLayer.visibility = View.GONE
        referencePanel.visibility = View.VISIBLE
        updateOrientation()
        presetSpinner.setSelection(0)
        // The first preset (A4) has both sides: start in rectangle mode and detect.
        markView.mode = ReferenceMarkView.Mode.POINTS
        applyPreset(ReferencePresets.ALL[0])
    }

    /** Presets select the kind, never assert the real dimensions of an object. */
    private fun applyPreset(preset: ReferencePreset) {
        // A visual rectangle/preset cannot identify the physical size of the user's sheet.
        lengthInput.setText("")
        shortSideInput.setText("")
        lengthInput.hint = "Ingresá tu medida real en cm"
        labelInput.setText(if (preset.otherSideM != null) "Rectángulo medido" else preset.label.substringBefore(" ("))
        surfaceGroup.check(if (preset.surface == ReferenceSurface.FLOOR) SURFACE_FLOOR_ID else SURFACE_WALL_ID)
        if (phase != Phase.MARKING) return
        if (preset.otherSideM != null) {
            if (markView.mode != ReferenceMarkView.Mode.RECT) setReferenceMode(ReferenceMarkView.Mode.RECT)
            else if (!markView.moved) runDetection()
        } else {
            setReferenceMode(ReferenceMarkView.Mode.POINTS)
        }
    }

    private fun toggleReferenceMode() {
        setReferenceMode(if (markView.mode == ReferenceMarkView.Mode.RECT) ReferenceMarkView.Mode.POINTS else ReferenceMarkView.Mode.RECT)
    }

    private fun setReferenceMode(mode: ReferenceMarkView.Mode) {
        markView.mode = mode
        val rect = mode == ReferenceMarkView.Mode.RECT
        shortSideInput.visibility = if (rect) View.VISIBLE else View.GONE
        repeatPointsButton.visibility = if (rect) View.GONE else View.VISIBLE
        modeButton.text = if (rect) "Marcar a mano" else "Detectar el objeto"
        lengthInput.hint = if (rect) "Lado largo real (cm)" else "Largo real entre los dos puntos (cm)"
        if (rect) {
            referenceHint.text = "Arrastrá las esquinas hasta que coincidan con el objeto y tocá Confirmar. El video ya está finalizado."
            markView.clearPoints()
            runDetection()
        } else {
            detectToken++
            detectStatus.text = ""
            referenceHint.text = "Tocá los dos extremos del objeto sobre la imagen del video finalizado."
        }
    }

    /** Looks for the rectangle off the UI thread; a newer call or leaving the screen discards a late result. */
    private fun runDetection() {
        val frame = markView.frameBitmap ?: return
        val ratio = parseMeters(lengthInput)?.let { long -> parseMeters(shortSideInput)?.let { short -> maxOf(long, short) / minOf(long, short) } }
        val token = ++detectToken
        detectStatus.text = "Buscando el objeto…"
        thread(name = "rect-detect") {
            val quad = try {
                detectRectangle(frame, ratio)
            } catch (e: Exception) {
                Log.w(TAG, "Rectangle detection failed", e)
                null
            }
            main.post {
                if (token != detectToken || phase != Phase.MARKING || markView.mode != ReferenceMarkView.Mode.RECT) return@post
                markView.setQuad(quad)
                detectStatus.text = if (quad != null) "Rectángulo candidato en el primer fotograma. Revisá que sea tu objeto y ajustá las esquinas." else RECT_NOT_FOUND
            }
        }
    }

    private fun detectRectangle(frame: Bitmap, ratio: Double?): List<ReferencePoint>? {
        // Read the pixels without recycling the frame: the view still draws it.
        val scaled = if (frame.width > DETECTION_MAX_WIDTH) {
            Bitmap.createScaledBitmap(frame, DETECTION_MAX_WIDTH, maxOf(1, frame.height * DETECTION_MAX_WIDTH / frame.width), true)
        } else frame
        val pixels = IntArray(scaled.width * scaled.height)
        scaled.getPixels(pixels, 0, scaled.width, 0, 0, scaled.width, scaled.height)
        val quad = RectDetector.detect(pixels, scaled.width, scaled.height, ratio)
        if (scaled !== frame) scaled.recycle()
        return quad
    }

    private fun parseMeters(field: EditText): Double? =
        field.text.toString().replace(',', '.').toDoubleOrNull()?.div(100.0)?.takeIf { it.isFinite() && it > 0.0 }

    /** Maps a point on the upright marking view to the stored (unrotated) frame, which is what the package holds. */
    private fun toStored(point: ReferencePoint): ReferencePoint =
        PreviewGeometry.displayToStored(markRotation, point.x, point.y).let { (x, y) -> ReferencePoint(x, y) }

    private fun confirmReference() {
        if (parseMeters(lengthInput) == null ||
            (markView.mode == ReferenceMarkView.Mode.RECT && parseMeters(shortSideInput) == null)) {
            toast("Ingresá las dimensiones reales medidas en centímetros.")
            return
        }
        val dimensions = if (markView.mode == ReferenceMarkView.Mode.RECT)
            "Lado largo: ${lengthInput.text} cm; lado corto: ${shortSideInput.text} cm."
        else "Distancia entre puntos: ${lengthInput.text} cm."
        AlertDialog.Builder(this)
            .setMessage("Confirmá que el objeto medido aparece completo en ESTE primer fotograma y que ajustaste sus puntos o esquinas. ¿Mediste estos valores reales? $dimensions Una hoja de 27 cm no es de 29,7 cm por elegir A4. Estas son dimensiones aportadas por vos; la escala del modelo sigue pendiente de Worker3D y puede no aplicarse si no se reconstruye el apoyo del objeto.")
            .setPositiveButton("Confirmo objeto y medidas reales") { _, _ ->
                if (markView.mode == ReferenceMarkView.Mode.RECT) confirmRectangle() else confirmPoints()
            }.setNegativeButton("Revisar", null).show()
    }

    private fun confirmRectangle() {
        val quad = markView.quad()?.map(::toStored)
        if (quad == null) {
            toast("Esperá a que termine la búsqueda o marcá el objeto a mano.")
            return
        }
        val first = parseMeters(lengthInput)
        val second = parseMeters(shortSideInput)
        if (first == null || second == null) {
            toast("Ingresá el lado largo y el lado corto reales del objeto en centímetros.")
            return
        }
        val width = maxOf(first, second)
        val height = minOf(first, second)
        val surface = if (surfaceGroup.checkedRadioButtonId == SURFACE_FLOOR_ID) ReferenceSurface.FLOOR else ReferenceSurface.WALL
        val source = when {
            !markView.detected -> ReferenceRectSource.MANUAL
            markView.moved -> ReferenceRectSource.ADJUSTED
            else -> ReferenceRectSource.AUTO
        }
        try {
            val corners = ReferenceRect.orient(quad, width, height, videoSize.width, videoSize.height)
            val rect = ReferenceRect.create(width, height, corners, source)
            reference = ReferenceMark.create(markView.frameNs, corners[0], corners[1], width, labelInput.text.toString(), surface, rect)
        } catch (e: IllegalArgumentException) {
            toast("Las cuatro esquinas no forman un rectángulo. Ajustalas o marcá a mano.")
            return
        }
        warningText.visibility = View.GONE
        referenceButton.visibility = View.GONE
        endReference()
    }

    private fun confirmPoints() {
        val points = markView.points()
        if (points == null) {
            toast("Tocá los dos extremos del objeto sobre la imagen.")
            return
        }
        val length = parseMeters(lengthInput)
        if (length == null || length <= 0.0) {
            toast("Ingresá el largo real del objeto en centímetros.")
            return
        }
        val surface = if (surfaceGroup.checkedRadioButtonId == SURFACE_FLOOR_ID) ReferenceSurface.FLOOR else ReferenceSurface.WALL
        try {
            reference = ReferenceMark.create(
                markView.frameNs, toStored(points.first), toStored(points.second), length, labelInput.text.toString(), surface,
            )
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
        val packageNow = pendingPackage
        if (packageNow != null) {
            pendingPackage = null
            phase = Phase.FINISHING
            packageNow()
            return
        }
        phase = Phase.RECORDING
        detectToken++
        markView.visibility = View.GONE
        markView.clear()
        referencePanel.visibility = View.GONE
        rail.visibility = View.VISIBLE
        chipsLayer.visibility = View.VISIBLE
        updateOrientation()
    }

    // endregion

    // region finishing

    private fun finishRecording(reachedTimeLimit: Boolean) {
        if (phase != Phase.RECORDING && phase != Phase.MARKING) return
        visualSampler?.pause()
        visualOverlay.corners = null
        pendingPackage?.let { packageNow ->
            pendingPackage = null
            phase = Phase.FINISHING
            packageNow()
            return
        }
        phase = Phase.FINISHING
        guidanceConfirm.visibility = View.GONE
        guidanceHidden.visibility = View.GONE
        main.removeCallbacks(tick)
        hintText.visibility = View.GONE
        statusText.text = "Guardando el recorrido…"
        rail.visibility = View.VISIBLE
        chipsLayer.visibility = View.VISIBLE
        referencePanel.visibility = View.GONE
        markView.visibility = View.GONE
        updateOrientation()
        listOf(referenceButton, nextRoomButton, stopButton).forEach {
            it.isEnabled = false
            it.alpha = 0.4f
        }
        val active = recorder ?: return
        // Capture the intent on the main thread. A background-triggered stop stays interrupted
        // even if the user returns before encoder finalization completes.
        val requestReference = referenceRequested && foreground.canConfirmReference
        active.stopRecording { videoOk ->
            if (videoOk && active.frames.count > 0) {
                try {
                    val captured = active.frames.timestamps()
                    val first = captured.first()
                    val end = captured.last() + 1
                    if (timeline.currentId == null) timeline.start(first)
                    val rooms = timeline.finish(end).also { finalizedRooms = it }
                    val manifest = VideoManifestBuilder.build(VideoManifestInput(
                        captureId = captureId, listingId = checkNotNull(listingId), deviceModel = Build.MODEL,
                        osVersion = Build.VERSION.RELEASE, startedAtNs = first, timestampSource = active.timestampSource,
                        sensorOrientation = active.sensorOrientation, rooms = rooms, reference = reference,
                        videoSize = active.videoSize,
                    ))
                    CaptureRecovery.checkpoint(File(workDir, VideoSpec.MANIFEST_FILE), JsonWriter.write(manifest))
                    val prototype = VideoCaptureResult.captured(File(filesDir, "capture_packages/$captureId.zip").absolutePath,
                        captureId, 0, active.frames.count, rooms, reference != null, (end - first) / 1_000_000L,
                        reachedTimeLimit, active.timestampSource)
                    CaptureRecovery.checkpoint(File(filesDir, "video_recovery/$captureId.finalized.json"),
                        JsonWriter.write(mapOf("captureId" to captureId, "ownerId" to intent.getStringExtra("ownerId"),
                            "listingId" to listingId, "timelineValidated" to true, "result" to prototype)))
                } catch (e: Exception) { Log.e(TAG, "Finalized recovery checkpoint failed; raw files preserved", e) }
            }
            val packageNow = {
                thread(name = "video-package") {
                    val result = buildPackage(active, videoOk, reachedTimeLimit)
                    val owner = intent.getStringExtra("ownerId")
                    if (result["outcome"] == "captured" && owner != null) {
                        try {
                            val journal = File(filesDir, "capture_packages/$captureId.json")
                            CaptureRecovery.checkpoint(journal, JsonWriter.write(mapOf("ownerId" to owner,
                                "listingId" to listingId, "result" to result)))
                            workDir.deleteRecursively() // ZIP and durable recovery record now exist.
                            File(filesDir, "video_recovery/$captureId.finalized.json").delete()
                            File(filesDir, "video_recovery/$captureId.json").delete()
                        } catch (e: Exception) { Log.e(TAG, "Recovery journal failed; ZIP preserved", e) }
                    }
                    main.post { finishWithResult(result) }
                }
                Unit
            }
            val reviewOrPackage = {
                main.post {
                    if (!foreground.canConfirmReference || isFinishing || isDestroyed || phase != Phase.FINISHING) {
                        packageNow()
                    } else {
                        pendingPackage = packageNow
                        reviewDialog = AlertDialog.Builder(this)
                            .setTitle("Recorrido finalizado")
                            .setMessage((guidanceRoomNotes + "$visualRoomName: ${guidedProgress.summary()}").joinToString("\n") +
                                "\n\nSin referencia confirmada: no habrá metros certificados. El servidor aún debe validar la geometría.")
                            .setPositiveButton("Guardar recorrido") { _, _ -> saveFinalReview() }
                            .setOnCancelListener { saveFinalReview() }.show()
                    }
                }
                Unit
            }
            if (videoOk && requestReference) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(File(workDir, VideoSpec.VIDEO_FILE).absolutePath)
                    val bitmap = if (Build.VERSION.SDK_INT >= 28) retriever.getFrameAtIndex(0) else null
                    if (bitmap == null) { reviewOrPackage() }
                    else main.post {
                        if (!foreground.canConfirmReference || isFinishing || isDestroyed || phase != Phase.FINISHING) {
                            bitmap.recycle()
                            packageNow()
                        } else {
                            pendingPackage = packageNow
                            showEncodedReference(bitmap, active.frames.firstTimestampNs ?: startedAtNs)
                        }
                    }
                } catch (e: Exception) { reviewOrPackage() }
                finally { retriever.release() }
            } else if (videoOk) reviewOrPackage() else packageNow()
        }
    }

    private fun saveFinalReview() {
        if (phase != Phase.FINISHING) return
        val packageNow = pendingPackage ?: return
        pendingPackage = null
        reviewDialog?.dismiss(); reviewDialog = null
        packageNow()
    }

    private fun buildPackage(active: VideoRecorder, videoOk: Boolean, reachedTimeLimit: Boolean): Map<String, Any?> {
        if (!videoOk || active.frames.count == 0) {
            return VideoCaptureResult.error(
                VideoCaptureResult.ERROR_RECORDING_FAILED,
                "No se pudo finalizar o validar la sincronización del video. Los archivos disponibles se conservaron para recuperación.",
            )
        }
        return try {
            val captured = active.frames.timestamps()
            val firstFrameNs = captured.first()
            // Rooms are [from, to): +1 keeps the last frame inside the last room.
            val endNs = captured.last() + 1
            val rooms = finalizedRooms ?: run {
                if (timeline.currentId == null) timeline.start(firstFrameNs)
                timeline.finish(endNs)
            }
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
                    videoSize = active.videoSize,
                ),
            )
            val zip = File(filesDir, "capture_packages/$captureId.zip")
            val outcome = VideoPackageBuilder.build(workDir, zip, manifest, active.frames, active.sensors)
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
                    sha256 = CaptureRecovery.sha256(zip),
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Video package failed; original preserved", e)
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
        File(filesDir, "video_recovery/$captureId.json").delete()
        File(filesDir, "video_recovery/$captureId.finalized.json").delete()
        finishWithResult(VideoCaptureResult.cancelled())
    }

    private fun finishWithResult(result: Map<String, Any?>) {
        if (phase == Phase.DONE) return
        phase = Phase.DONE
        main.removeCallbacks(tick)
        unlockOrientation()
        cancelDialog?.dismiss()
        cancelDialog = null
        reviewDialog?.dismiss(); reviewDialog = null
        recorder?.release()
        recorder = null
        main.removeCallbacks(startTimeout) // Failed raw recordings remain private for recovery.
        setResult(RESULT_OK, Intent().putExtra(EXTRA_RESULT_JSON, JsonWriter.write(result)))
        finish()
    }

    @Deprecated("Used below API 33 and when predictive back is not enabled.")
    override fun onBackPressed() {
        if (phase == Phase.MARKING) endReference() else cancelCapture()
    }

    override fun onResume() {
        super.onResume()
        foreground.resume()
        resumePreviewGuidance()
    }

    override fun onPause() {
        foreground.pause()
        guidedProgress.invalidateObservation()
        if (::guidanceConfirm.isInitialized) guidanceConfirm.visibility = View.GONE
        if (::guidanceHidden.isInitialized) guidanceHidden.visibility = View.GONE
        if (::hintText.isInitialized) hintText.visibility = View.GONE
        visualSampler?.pause()
        if (::visualOverlay.isInitialized) visualOverlay.corners = null
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        visualSampler?.pause()
        if (::visualOverlay.isInitialized) visualOverlay.corners = null
        foreground.stop(phase == Phase.RECORDING || (phase == Phase.MARKING && pendingPackage == null))
        if (::workDir.isInitialized && phase != Phase.DONE) checkpointRecovery("interrupted")
        // A stopped encoder awaiting only the optional summary can be saved in background.
        // Consume the closure once; dismissing its old dialog later cannot package twice.
        if (phase == Phase.FINISHING && pendingPackage != null) { saveFinalReview(); return }
        when (CaptureRecovery.onBackground(phase == Phase.RECORDING, phase == Phase.MARKING, pendingPackage != null)) {
            CaptureRecovery.StopAction.FINALIZE, CaptureRecovery.StopAction.PACKAGE_FINALIZED -> finishRecording(false)
            CaptureRecovery.StopAction.PRESERVE -> Unit
        }
    }

    private fun checkpointRecovery(state: String) {
        try {
            if (phase == Phase.MARKING) {
                // Keep unfinished input with the recording, never as a confirmed
                // scale reference. Packaging/restart recovery preserves this file.
                val points = markView.points()
                CaptureRecovery.checkpoint(File(workDir, "reference-draft.json"), JsonWriter.write(mapOf(
                    "confirmed" to false, "frameNs" to markView.frameNs,
                    "corners" to markView.quad()?.map { it.toMap() },
                    "points" to points?.let { listOf(it.first.toMap(), it.second.toMap()) },
                    "lengthInput" to lengthInput.text.toString(), "shortSideInput" to shortSideInput.text.toString(),
                    "lengthUnit" to "cm",
                )))
            }
            CaptureRecovery.checkpoint(File(filesDir, "video_recovery/$captureId.json"), JsonWriter.write(mapOf(
                "captureId" to captureId, "listingId" to listingId,
                "ownerId" to intent.getStringExtra("ownerId"), "state" to state,
                "referenceConfirmed" to (reference != null),
                "reference" to reference?.toMap(),
                "pendingCorners" to (if (::markView.isInitialized) markView.quad()?.map { it.toMap() } else null),
            )))
        } catch (e: Exception) { Log.e(TAG, "Recovery checkpoint failed; original preserved", e) }
    }

    override fun onDestroy() {
        reviewDialog?.dismiss(); reviewDialog = null
        visualSampler?.close()
        getSystemService(DisplayManager::class.java).unregisterDisplayListener(displayListener)
        if (phase != Phase.DONE && phase != Phase.FINISHING) {
            unlockOrientation()
            main.removeCallbacks(tick)
            recorder?.release()
            recorder = null
            // A process/lifecycle interruption must not erase the only raw recording.
        }
        main.removeCallbacks(startTimeout)
        super.onDestroy()
    }

    // endregion

    /** Keeps the layout from reflowing mid-recording: pins the orientation the phone is held in right now. */
    private fun lockOrientation() {
        requestedOrientation = when (displayRotationDegrees()) {
            90 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
            270 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    /** Back to the manifest behaviour: follow the sensor in all four orientations unless the user locked rotation. */
    private fun unlockOrientation() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_USER
    }

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
        private const val PREVIEW_TAG = "VideoPreview"
        private const val DETECTION_MAX_WIDTH = 1280
        private const val RECT_NOT_FOUND = "No encontré el objeto; ajustá las esquinas o marcalo a mano"
        private const val MARGIN_DP = 16
        private const val RAIL_WIDTH_DP = 112
        private const val REFERENCE_PANEL_WIDTH_DP = 300
        private const val PORTRAIT_RAIL_DP = 124
        private const val TOP_BAR_DP = 128
        private const val SECONDARY_WIDTH_DP = 96
        private const val PORTRAIT_PANEL_FRACTION = 0.46f
        private val RED = Color.rgb(229, 57, 53)
        private val SCRIM = Color.argb(150, 0, 0, 0)
        private val RAIL_SCRIM = Color.argb(170, 0, 0, 0)
        private const val IDLE_INSTRUCTION = "Preparación · guía visual opcional"
        private const val RECORDING_INSTRUCTION = "Grabando · mantené el objeto al inicio; después recorré el ambiente"
    }
}

/** Main-thread lifecycle state: current visibility is separate from an interrupted recording. */
internal class VideoCaptureForeground {
    var resumed = false
        private set
    private var recordingInterrupted = false

    val canConfirmReference: Boolean get() = resumed && !recordingInterrupted
    fun canGuide(previewReady: Boolean, previewOrRecording: Boolean): Boolean =
        resumed && previewReady && previewOrRecording

    fun resume() { resumed = true }
    fun pause() { resumed = false }
    fun stop(recording: Boolean) {
        pause()
        if (recording) recordingInterrupted = true
    }
    fun recordingStarted() { recordingInterrupted = !resumed }
}

/**
 * Keeps its children at the aspect of the UPRIGHT preview image (4:3 or 3:4 for the preferred size) so normalised
 * taps map onto it and the picture is never stretched. The whole image always fits inside the space the parent
 * gives it (letterbox): nothing is cropped from view, and the recorded video is unchanged.
 */
internal class AspectFrameLayout(context: android.content.Context) : FrameLayout(context) {
    private var rotation = 0
    private var bufferWidth = VideoSpec.PREFERRED_SIZES.first().width
    private var bufferHeight = VideoSpec.PREFERRED_SIZES.first().height

    fun configure(rotation: Int, bufferWidth: Int, bufferHeight: Int) {
        if (rotation == this.rotation && bufferWidth == this.bufferWidth && bufferHeight == this.bufferHeight) return
        this.rotation = rotation
        this.bufferWidth = bufferWidth
        this.bufferHeight = bufferHeight
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec)
        val maxH = MeasureSpec.getSize(heightMeasureSpec).coerceAtLeast(1)
        val (w, h) = PreviewGeometry.stageSize(rotation, bufferWidth, bufferHeight, maxW, maxH)
        super.onMeasure(
            MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY),
        )
    }
}

/**
 * A frozen frame for the scale reference. In [Mode.RECT] it shows a quadrilateral (detected or default) with four
 * draggable corner handles; in [Mode.POINTS], the manual fallback, the agent taps the two ends of the object.
 * Coordinates are kept normalised to 0..1 on the frame as displayed (upright); the activity maps them to the stored frame.
 */
internal class ReferenceMarkView(context: android.content.Context) : View(context) {
    enum class Mode { RECT, POINTS }

    private val density = resources.displayMetrics.density
    private var frame: Bitmap? = null
    var frameNs: Long = 0L
        private set
    val frameBitmap: Bitmap? get() = frame
    var mode: Mode = Mode.RECT
        set(value) {
            field = value
            invalidate()
        }

    /** True when the current quad came from the detector (even if the agent moved it afterwards). */
    var detected = false
        private set

    /** With a bottom panel (portrait) the whole frame is visible, so the fallback quad sits in its middle. */
    var centeredDefault = false

    /** True once the agent dragged a corner. */
    var moved = false
        private set

    private var quadPoints: List<ReferencePoint>? = null
    private var dragging = -1
    private val taps = ArrayList<Pair<Float, Float>>(2)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 4f; color = Color.YELLOW }
    private val quadStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 3f * density; color = Color.rgb(0, 229, 255) }
    private val quadFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = Color.argb(45, 0, 229, 255) }
    private val handleFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = Color.WHITE }
    private val handleRing = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 3f * density; color = Color.rgb(0, 229, 255) }

    fun show(bitmap: Bitmap, frameNs: Long) {
        frame = bitmap
        this.frameNs = frameNs
        taps.clear()
        quadPoints = null
        detected = false
        moved = false
        dragging = -1
        invalidate()
    }

    fun clear() {
        frame = null
        taps.clear()
        quadPoints = null
        detected = false
        moved = false
        dragging = -1
    }

    fun clearPoints() {
        taps.clear()
        invalidate()
    }

    /** Puts the detector's [detectedQuad], or a centred default the agent can drag when nothing was found. */
    fun setQuad(detectedQuad: List<ReferencePoint>?) {
        detected = detectedQuad != null
        moved = false
        quadPoints = detectedQuad ?: if (centeredDefault) CENTERED_QUAD else DEFAULT_QUAD
        invalidate()
    }

    /** The four corners, normalised, or null before the detection ended. */
    fun quad(): List<ReferencePoint>? = quadPoints

    /** The two ends normalised to 0..1 on the frame, or null until both were tapped. */
    fun points(): Pair<ReferencePoint, ReferencePoint>? {
        if (taps.size < 2 || width <= 0 || height <= 0) return null
        val (a, b) = taps
        return ReferencePoint.fromPixels(a.first, a.second, width.toFloat(), height.toFloat()) to
            ReferencePoint.fromPixels(b.first, b.second, width.toFloat(), height.toFloat())
    }

    override fun onDraw(canvas: Canvas) {
        frame?.let { canvas.drawBitmap(it, null, android.graphics.Rect(0, 0, width, height), null) }
        if (mode == Mode.POINTS) {
            taps.forEach { canvas.drawCircle(it.first, it.second, 14f, paint) }
            if (taps.size == 2) canvas.drawLine(taps[0].first, taps[0].second, taps[1].first, taps[1].second, paint)
            return
        }
        val q = quadPoints ?: return
        val path = Path()
        q.forEachIndexed { i, p ->
            val x = (p.x * width).toFloat()
            val y = (p.y * height).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        canvas.drawPath(path, quadFill)
        canvas.drawPath(path, quadStroke)
        q.forEach {
            canvas.drawCircle((it.x * width).toFloat(), (it.y * height).toFloat(), 11f * density, handleFill)
            canvas.drawCircle((it.x * width).toFloat(), (it.y * height).toFloat(), 11f * density, handleRing)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (mode == Mode.RECT) return onRectTouch(event)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            if (taps.size == 2) taps.clear()
            taps.add(event.x to event.y)
            invalidate()
        }
        return true
    }

    private fun onRectTouch(event: MotionEvent): Boolean {
        val q = quadPoints ?: return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // 30dp radius: a 60dp target, above the 48dp minimum; the closest handle wins.
                val reach = HANDLE_TOUCH_RADIUS_DP * density
                fun distance(i: Int) = Math.hypot(q[i].x * width - event.x.toDouble(), q[i].y * height - event.y.toDouble())
                dragging = q.indices.minByOrNull { distance(it) }?.takeIf { distance(it) <= reach } ?: -1
            }
            MotionEvent.ACTION_MOVE -> if (dragging >= 0 && width > 0 && height > 0) {
                val target = ReferencePoint.fromPixels(event.x, event.y, width.toFloat(), height.toFloat())
                quadPoints = q.mapIndexed { i, p -> if (i == dragging) target else p }
                moved = true
                invalidate()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = -1
        }
        return true
    }

    private companion object {
        const val HANDLE_TOUCH_RADIUS_DP = 30f
        val CENTERED_QUAD = listOf(
            ReferencePoint(0.15, 0.36), ReferencePoint(0.85, 0.36),
            ReferencePoint(0.85, 0.56), ReferencePoint(0.15, 0.56),
        )
        val DEFAULT_QUAD = listOf(
            // Left of the 300dp reference panel, which may cover the right of the frame on a narrow screen.
            ReferencePoint(0.10, 0.30), ReferencePoint(0.45, 0.30),
            ReferencePoint(0.45, 0.70), ReferencePoint(0.10, 0.70),
        )
    }
}
