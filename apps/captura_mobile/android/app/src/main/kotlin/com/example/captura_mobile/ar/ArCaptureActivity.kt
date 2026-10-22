package com.example.captura_mobile.ar

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Build
import android.os.Bundle
import android.media.Image
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.window.OnBackInvokedDispatcher
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.DepthPoint
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.LightEstimate
import com.google.ar.core.Plane
import com.google.ar.core.Point
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.SessionPausedException
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.concurrent.thread
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2

/**
 * Native ARCore capture of one room: wall lines on the floor (corners are derived by intersecting
 * consecutive walls, see [WallLines]), room height and furniture footprints.
 *
 * In [CaptureMode.WALKTHROUGH] nothing is marked: while the agent walks along the walls the tracked
 * floor and wall planes and the camera path are recorded, and «Terminar recorrido» returns them as
 * `observations` (see [WalkthroughGeometry]); the Dart domain proposes the corners.
 *
 * Threading: ARCore state (session frames, anchors, marks) is only touched on the GL thread.
 * Buttons enqueue actions that run right after the next `session.update()`; UI changes are posted
 * back to the main thread. The camera is a live preview only: nothing is recorded or saved.
 */
class ArCaptureActivity : Activity(), GLSurfaceView.Renderer {

    companion object {
        const val EXTRA_ROOM_NAME = "roomName"
        const val EXTRA_RESULT_JSON = "resultJson"
        const val EXTRA_MODE = "mode"

        /** Optional; written to the capture package manifest when the channel passes it. */
        const val EXTRA_LISTING_ID = "listingId"
        private const val TAG = "ArCaptureActivity"
        private const val CAMERA_PERMISSION_REQUEST = 4107
        private const val STATUS_INTERVAL_MS = 150L

        /** Plane and trajectory sampling period in walkthrough mode (10 Hz). */
        private const val WALKTHROUGH_SAMPLE_INTERVAL_MS = 100L

        /** How long finishing waits for queued keyframes to be written. */
        private const val KEYFRAME_FLUSH_TIMEOUT_MS = 30_000L

        private const val WALKTHROUGH_GUIDANCE =
            "Caminá despacio por el borde del ambiente apuntando a la unión entre piso y pared. " +
                "Recorré todas las paredes."
    }

    /** A floor point at the base of a wall; every two consecutive points form one wall line. */
    private class WallPoint(val anchor: Anchor, val hitDistance: Double)

    private class BoxMark(val first: Anchor, val second: Anchor) {
        var height: Double? = null
        var confidence: Double? = null
    }

    /** Undo history, newest last. */
    private sealed class Mark {
        object WallPointMarked : Mark()
        object BoxFirstCorner : Mark()
        object BoxCompleted : Mark()
        class RoomHeightMeasured(val previous: RoomHeight?) : Mark()
        class BoxHeightMeasured(val box: BoxMark, val previousHeight: Double?, val previousConfidence: Double?) : Mark()
    }

    private lateinit var surfaceView: GLSurfaceView
    private lateinit var overlay: CaptureOverlayView
    private lateinit var statusText: TextView
    private lateinit var messageText: TextView
    private lateinit var wallButton: Button
    private lateinit var undoButton: Button
    private lateinit var heightButton: Button
    private lateinit var boxButton: Button
    private lateinit var boxHeightButton: Button
    private lateinit var finishButton: Button
    private lateinit var cancelButton: Button
    private lateinit var recordButton: Button
    private lateinit var nextRoomButton: Button

    private val backgroundRenderer = BackgroundRenderer()

    @Volatile
    private var session: Session? = null
    private var sessionTextureBound: Session? = null
    private var installRequested = false
    private var permissionRequested = false
    private var finished = false
    private var startedAtMs = 0L
    private var roomName = ""
    private var mode = CaptureMode.WALLS

    @Volatile
    private var depthSupported = false

    /** The session's configuration, kept to switch depth on when the walkthrough starts recording. */
    private var sessionConfig: Config? = null

    @Volatile
    private var viewportWidth = 0

    @Volatile
    private var viewportHeight = 0

    @Volatile
    private var displayGeometryChanged = true

    private val pendingActions = ConcurrentLinkedQueue<(Frame, Camera) -> Unit>()

    // GL-thread state.
    private val wallPoints = mutableListOf<WallPoint>()
    private var roomHeight: RoomHeight? = null
    private var pendingBoxCorner: Anchor? = null
    private val boxes = mutableListOf<BoxMark>()
    private val history = ArrayDeque<Mark>()
    private val lossCounter = TrackingLossCounter()
    private var lastStatusAtMs = 0L
    private var lastTracking: Boolean? = null
    private val trackingDebouncer = TrackingDebouncer()

    // GL-thread state, walkthrough mode.
    private var recording = false
    private var walkFloorY: Double? = null
    private var trajectory = TrajectorySampler()
    private var liveWalls: List<WallSegment> = emptyList()
    private var liveFloorArea = 0.0
    private var lastWalkSampleAtMs = 0L

    // GL-thread state, capture package (S13): keyframes, rooms and trajectory with room ids.
    private var recorder: KeyframeRecorder? = null
    private var keyframeSelector = KeyframeSelector()
    private var rooms = RoomSequence("")
    private var captureId = ""
    private var listingId: String? = null
    private var recordStartedAtMs = 0L
    private val trajectoryLog = mutableListOf<TrajectorySample>()
    private var imageIntrinsics: Intrinsics? = null
    private var depthIntrinsics: Intrinsics? = null

    @Volatile
    private var packagingStarted = false

    // GL-thread state, walkthrough guidance (S12).
    private val motionMeter = MotionMeter()
    private var lastMotion: MotionSample? = null
    private var lightIntensity: Double? = null
    private var headingRad = 0.0
    private var coverage = Coverage.EMPTY
    private val announcer = GuidanceAnnouncer()
    private var maxWallCount = 0

    /** Voice and vibration; walkthrough mode only. */
    private var feedback: GuidanceFeedback? = null

    /** Main-thread mirror of [recording] for the button state. */
    private var recordingShown = false

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) {
            displayGeometryChanged = true
        }
    }

    // region Lifecycle

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        roomName = intent.getStringExtra(EXTRA_ROOM_NAME).orEmpty()
        mode = CaptureMode.fromArgument(intent.getStringExtra(EXTRA_MODE))
        listingId = intent.getStringExtra(EXTRA_LISTING_ID)
        startedAtMs = SystemClock.elapsedRealtime()
        if (mode == CaptureMode.WALKTHROUGH) feedback = GuidanceFeedback(this)
        setContentView(buildLayout())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) {
                cancelCapture()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (finished) return
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            if (!permissionRequested) {
                permissionRequested = true
                requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
            }
            return
        }
        if (session == null && !createSession()) return
        val current = session ?: return
        try {
            current.resume()
        } catch (e: CameraNotAvailableException) {
            finishWithError(CaptureResult.ERROR_SESSION_FAILED, "La cámara no está disponible. Cerrá otras apps que la usen.")
            return
        } catch (e: Exception) {
            Log.e(TAG, "Session resume failed", e)
            finishWithError(CaptureResult.ERROR_SESSION_FAILED, "No se pudo iniciar la sesión de realidad aumentada.")
            return
        }
        getSystemService(DisplayManager::class.java)?.registerDisplayListener(displayListener, null)
        displayGeometryChanged = true
        surfaceView.onResume()
    }

    override fun onPause() {
        super.onPause()
        getSystemService(DisplayManager::class.java)?.unregisterDisplayListener(displayListener)
        if (::surfaceView.isInitialized) surfaceView.onPause()
        session?.pause()
    }

    override fun onDestroy() {
        if (!packagingStarted) recorder?.abort()
        recorder = null
        feedback?.shutdown()
        feedback = null
        session?.close()
        session = null
        super.onDestroy()
    }

    @Deprecated("Used below API 33 and when predictive back is not enabled.")
    override fun onBackPressed() {
        cancelCapture()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            finishWithError(
                CaptureResult.ERROR_CAMERA_PERMISSION_DENIED,
                "Sin permiso de cámara no se puede medir la habitación.",
            )
        }
        // When granted, onResume runs again and creates the session.
    }

    /** Returns true when a session exists or was created; false when waiting for install or finishing. */
    private fun createSession(): Boolean {
        try {
            when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    installRequested = true
                    return false
                }
                ArCoreApk.InstallStatus.INSTALLED -> Unit
            }
            val created = Session(this)
            depthSupported = created.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            val config = Config(created).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                // Fixed focus is ARCore's default and keeps the image stable for motion tracking.
                focusMode = Config.FocusMode.FIXED
                lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                // Depth from motion is CPU-heavy: in walkthrough mode it starts with the recording, so
                // tracking and plane finding get the CPU while the agent looks for the floor.
                depthMode = if (depthSupported && mode != CaptureMode.WALKTHROUGH) {
                    Config.DepthMode.AUTOMATIC
                } else {
                    Config.DepthMode.DISABLED
                }
            }
            created.configure(config)
            sessionConfig = config
            session = created
            runOnUiThread { refreshButtons(tracking = false) }
            return true
        } catch (e: UnavailableUserDeclinedInstallationException) {
            finishWithError(
                CaptureResult.ERROR_ARCORE_INSTALL_DECLINED,
                "Se canceló la instalación de Servicios de Google Play para RA.",
            )
        } catch (e: UnavailableDeviceNotCompatibleException) {
            finishWithError(CaptureResult.ERROR_ARCORE_UNAVAILABLE, "Este teléfono no es compatible con ARCore.")
        } catch (e: UnavailableArcoreNotInstalledException) {
            finishWithError(CaptureResult.ERROR_ARCORE_UNAVAILABLE, "Servicios de Google Play para RA no está instalado.")
        } catch (e: UnavailableApkTooOldException) {
            finishWithError(CaptureResult.ERROR_ARCORE_UNAVAILABLE, "Actualizá Servicios de Google Play para RA.")
        } catch (e: UnavailableSdkTooOldException) {
            finishWithError(CaptureResult.ERROR_ARCORE_UNAVAILABLE, "Esta versión de la app no es compatible con ARCore.")
        } catch (e: Exception) {
            Log.e(TAG, "Session creation failed", e)
            finishWithError(CaptureResult.ERROR_SESSION_FAILED, "No se pudo crear la sesión de realidad aumentada.")
        }
        return false
    }

    // endregion

    // region GLSurfaceView.Renderer

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        backgroundRenderer.createOnGlThread()
        sessionTextureBound = null
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewportWidth = width
        viewportHeight = height
        displayGeometryChanged = true
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val current = session ?: return
        if (sessionTextureBound !== current) {
            current.setCameraTextureName(backgroundRenderer.textureId)
            sessionTextureBound = current
        }
        if (displayGeometryChanged && viewportWidth > 0) {
            current.setDisplayGeometry(displayRotation(), viewportWidth, viewportHeight)
            displayGeometryChanged = false
        }
        val frame = try {
            current.update()
        } catch (e: SessionPausedException) {
            return
        } catch (e: CameraNotAvailableException) {
            postMessage("La cámara no está disponible. Cerrá otras apps que la usen.")
            return
        } catch (e: Exception) {
            Log.e(TAG, "Frame update failed", e)
            return
        }
        val camera = frame.camera
        backgroundRenderer.draw(frame)

        val tracking = camera.trackingState == TrackingState.TRACKING
        lossCounter.update(tracking)
        val shownTracking = trackingDebouncer.update(tracking, SystemClock.elapsedRealtime())
        if (lastTracking != shownTracking) {
            lastTracking = shownTracking
            runOnUiThread { refreshButtons(shownTracking) }
        }

        while (true) {
            val action = pendingActions.poll() ?: break
            try {
                action(frame, camera)
            } catch (e: Exception) {
                Log.e(TAG, "Capture action failed", e)
                postMessage("No se pudo completar la acción. Probá de nuevo.")
            }
        }
        if (finished) return

        val centreHits = if (tracking) centreHitTest(frame) else emptyList()
        if (mode == CaptureMode.WALKTHROUGH) {
            // Tracking loss pauses the walkthrough: nothing is sampled until tracking returns.
            updateGuidanceSignals(frame, camera, tracking)
            if (tracking) sampleWalkthrough(current, camera)
            if (recording && tracking) recordKeyframe(frame, camera)
            publishWalkthroughOverlay(camera, tracking, centreHits)
            publishWalkthroughStatus(camera)
            return
        }
        publishOverlay(camera, tracking, centreHits)
        publishStatus(current, camera, centreHits)
    }

    // endregion

    // region Actions (GL thread)

    private fun markWallPoint(frame: Frame, camera: Camera) {
        if (!requireTracking(camera)) return
        val hit = floorHit(frame) ?: run {
            postMessage("Apuntá el centro al piso, junto al pie de la pared, para marcar el punto.")
            return
        }
        val hitY = hit.hitPose.ty().toDouble()
        val check = CaptureRules.checkFloorPoint(currentFloorY(), hitY)
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        val wallNumber = wallPoints.size / 2 + 1
        val secondPoint = wallPoints.size % 2 == 1
        var spacing = 0.0
        if (secondPoint) {
            val pose = hit.hitPose
            spacing = CaptureGeometry.horizontalDistance(
                toVec3(wallPoints.last().anchor),
                Vec3(pose.tx().toDouble(), pose.ty().toDouble(), pose.tz().toDouble()),
            )
            val spacingCheck = CaptureRules.checkWallPointSpacing(spacing)
            if (spacingCheck is RuleCheck.Rejected) {
                postMessage(spacingCheck.message)
                return
            }
        }
        wallPoints.add(WallPoint(hit.createAnchor(), hit.distance.toDouble()))
        history.addLast(Mark.WallPointMarked)
        if (!secondPoint) {
            postMessage("Punto 1 de la pared $wallNumber marcado. Marcá el segundo punto de esta pared.")
        } else {
            val advice = if (spacing < CaptureRules.RECOMMENDED_WALL_POINT_SPACING_M) {
                " Conviene separar los puntos 50 cm o más."
            } else {
                ""
            }
            postMessage(
                "Pared $wallNumber marcada (${CaptureGeometry.formatMeters(spacing)} entre puntos).$advice " +
                    "Seguí con la pared siguiente, en orden alrededor de la habitación.",
            )
        }
    }

    private fun markBoxCorner(frame: Frame, camera: Camera) {
        if (!requireTracking(camera)) return
        val floorY = currentFloorY() ?: run {
            postMessage("Marcá primero un punto de pared para fijar el piso.")
            return
        }
        val hit = floorHit(frame) ?: run {
            postMessage("Apuntá al piso junto al mueble.")
            return
        }
        val check = CaptureRules.checkFloorPoint(floorY, hit.hitPose.ty().toDouble())
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        val first = pendingBoxCorner
        if (first == null) {
            pendingBoxCorner = hit.createAnchor()
            history.addLast(Mark.BoxFirstCorner)
            postMessage("Primera esquina del mueble marcada. Marcá la esquina opuesta en diagonal.")
        } else {
            boxes.add(BoxMark(first, hit.createAnchor()))
            pendingBoxCorner = null
            history.addLast(Mark.BoxCompleted)
            val next = if (depthSupported) {
                "Apuntá a la parte superior y tocá «Medir alto del mueble», o seguí sin medir."
            } else {
                "Profundidad no disponible: el alto del mueble se carga a mano después."
            }
            postMessage("Mueble ${boxes.size} marcado. $next")
        }
    }

    private fun measureRoomHeight(frame: Frame, camera: Camera) {
        if (!requireTracking(camera)) return
        val floorY = currentFloorY() ?: run {
            postMessage(
                if (mode == CaptureMode.WALKTHROUGH) {
                    "Todavía no se detectó el piso. Apuntá al piso unos segundos."
                } else {
                    "Marcá primero un punto de pared en el piso."
                },
            )
            return
        }
        val hits = centreHitTest(frame)
        val ceiling = hits.firstOrNull { isTrackedPlaneHit(it, Plane.Type.HORIZONTAL_DOWNWARD_FACING) }
        val wall = if (ceiling == null) hits.firstOrNull { isTrackedPlaneHit(it, Plane.Type.VERTICAL) } else null
        val hit = ceiling ?: wall ?: run {
            postMessage("No se detecta techo ni pared en el centro. Apuntá a la unión entre pared y techo.")
            return
        }
        val value = hit.hitPose.ty().toDouble() - floorY
        val check = CaptureRules.checkRoomHeight(value)
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        val source = if (ceiling != null) RoomHeight.SOURCE_CEILING_PLANE else RoomHeight.SOURCE_WALL_POINT
        history.addLast(Mark.RoomHeightMeasured(roomHeight))
        roomHeight = RoomHeight(value, source)
        val origin = if (ceiling != null) "plano del techo" else "punto de pared"
        postMessage("Altura: ${CaptureGeometry.formatMeters(value)} ($origin).")
    }

    private fun measureBoxHeight(frame: Frame, camera: Camera) {
        if (!requireTracking(camera)) return
        if (!depthSupported) {
            postMessage("Profundidad no disponible: el alto del mueble se carga a mano después.")
            return
        }
        val box = boxes.lastOrNull() ?: run {
            postMessage("Marcá primero un mueble.")
            return
        }
        val floorY = currentFloorY() ?: return
        val hits = centreHitTest(frame)
        val hit = hits.firstOrNull { it.trackable is DepthPoint && isMeasurableHit(it) }
            ?: hits.firstOrNull { isMeasurableHit(it) }
            ?: run {
                postMessage("Sin datos de profundidad en el centro. Acercate un poco al mueble.")
                return
            }
        val value = hit.hitPose.ty().toDouble() - floorY
        val check = CaptureRules.checkBoxHeight(value)
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        history.addLast(Mark.BoxHeightMeasured(box, box.height, box.confidence))
        box.height = value
        box.confidence = centreDepthConfidence(frame)
        val confidenceText = box.confidence?.let { " · confianza ${(it * 100).toInt()} %" } ?: ""
        postMessage("Alto del mueble ${boxes.size}: ${CaptureGeometry.formatMeters(value)}$confidenceText.")
    }

    private fun undo() {
        when (val mark = history.removeLastOrNull()) {
            null -> postMessage("No hay marcas para deshacer.")
            Mark.WallPointMarked -> {
                wallPoints.removeAt(wallPoints.lastIndex).anchor.detach()
                postMessage("Se quitó el último punto de pared.")
            }
            Mark.BoxFirstCorner -> {
                pendingBoxCorner?.detach()
                pendingBoxCorner = null
                postMessage("Se quitó la esquina del mueble.")
            }
            Mark.BoxCompleted -> {
                val box = boxes.removeAt(boxes.lastIndex)
                box.second.detach()
                pendingBoxCorner = box.first
                postMessage("Se quitó la segunda esquina del mueble.")
            }
            is Mark.RoomHeightMeasured -> {
                roomHeight = mark.previous
                postMessage("Se quitó la medida de altura.")
            }
            is Mark.BoxHeightMeasured -> {
                mark.box.height = mark.previousHeight
                mark.box.confidence = mark.previousConfidence
                postMessage("Se quitó el alto del mueble.")
            }
        }
    }

    private fun finishCapture() {
        val anchors = wallPoints.map { it.anchor } + boxes.flatMap { listOf(it.first, it.second) }
        val allTracking = anchors.all { it.trackingState == TrackingState.TRACKING }
        val check = CaptureRules.checkWallFinish(
            completeWalls = wallPoints.size / 2,
            pendingPoint = wallPoints.size % 2 == 1,
            allAnchorsTracking = allTracking,
        )
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        // Corners from the current (drift-corrected) anchor poses.
        val derived = when (val computed = WallLines.cornersFromWallLines(currentWallLines())) {
            is WallCornersResult.Corners -> computed.corners
            is WallCornersResult.Failure -> {
                postMessage(computed.message)
                return
            }
        }
        val result = CaptureResult.captured(
            corners = derived.map { Corner2(it.x, it.z) },
            height = roomHeight,
            boxes = boxes.map { box ->
                CapturedBox(
                    corners = listOf(toCorner(box.first), toCorner(box.second)),
                    height = box.height,
                    heightSource = if (box.height != null) CapturedBox.SOURCE_DEPTH else null,
                    confidence = if (box.height != null) box.confidence else null,
                )
            },
            metrics = CaptureMetrics(
                durationMs = SystemClock.elapsedRealtime() - startedAtMs,
                trackingLossCount = lossCounter.count,
                depthSupported = depthSupported,
                cornerHitDistances = wallPoints.map { it.hitDistance },
                floorY = wallPoints.first().anchor.pose.ty().toDouble(),
                method = CaptureMetrics.METHOD_WALL_LINES,
            ),
        )
        finished = true
        runOnUiThread { deliver(result) }
    }

    private fun toggleRecording(camera: Camera) {
        if (recording) {
            finishWalkthrough()
            return
        }
        if (camera.trackingState != TrackingState.TRACKING) {
            postMessage("Sin seguimiento no se puede iniciar el recorrido. Mové el teléfono despacio apuntando al piso.")
            return
        }
        recording = true
        enableDepthForRecording()
        startPackage()
        trajectory = TrajectorySampler()
        maxWallCount = liveWalls.size
        motionMeter.reset()
        val pose = camera.pose
        if (trajectory.offer(pose.tx().toDouble(), pose.tz().toDouble())) logTrajectory(pose.tx().toDouble(), pose.tz().toDouble())
        runOnUiThread {
            recordingShown = true
            recordButton.text = "Terminar recorrido"
            recordButton.isEnabled = true
            nextRoomButton.isEnabled = true
        }
        postMessage(WALKTHROUGH_GUIDANCE)
        feedback?.speak(WALKTHROUGH_GUIDANCE)
    }

    /**
     * Uses the planes tracked right now (ARCore refines them over time); planes that were seen but are
     * now paused or stopped are left out. Rejected finishes keep recording.
     */
    /** Turns depth on when the walkthrough starts recording; keyframes need it, the floor search does not. */
    private fun enableDepthForRecording() {
        val current = session ?: return
        val config = sessionConfig ?: return
        if (!depthSupported || config.depthMode == Config.DepthMode.AUTOMATIC) return
        try {
            config.depthMode = Config.DepthMode.AUTOMATIC
            current.configure(config)
        } catch (e: Exception) {
            Log.w(TAG, "Could not enable depth for the recording; keyframes go without depth", e)
            config.depthMode = Config.DepthMode.DISABLED
        }
    }

    private fun finishWalkthrough() {
        val current = session ?: return
        val planes = trackedPlanes(current)
        walkFloorY = WalkthroughGeometry.refineFloorY(walkFloorY, upwardPlaneYs(planes))
        val floorY = walkFloorY
        val walls = wallSegments(planes)
        val check = CaptureRules.checkWalkthroughFinish(floorFound = floorY != null, wallCount = walls.size)
        if (check is RuleCheck.Rejected) {
            postMessage(check.message)
            return
        }
        if (floorY == null) return
        val metrics = CaptureMetrics(
            durationMs = SystemClock.elapsedRealtime() - startedAtMs,
            trackingLossCount = lossCounter.count,
            depthSupported = depthSupported,
            cornerHitDistances = emptyList(),
            floorY = floorY,
            method = CaptureMetrics.METHOD_WALKTHROUGH,
        )
        val observations = WalkthroughObservations(
            floorY = floorY,
            walls = walls,
            floors = floorPolygons(planes, floorY),
            trajectory = trajectory.points,
        )
        val height = roomHeight
        // Everything the packager needs is snapshotted here, on the GL thread, before it stops.
        val snapshot = PackageSnapshot(
            recorder = recorder,
            captureId = captureId,
            listingId = listingId,
            floorY = floorY,
            planes = packagePlanes(planes, floorY),
            rooms = rooms.rooms,
            trajectory = trajectoryLog.toList(),
            image = imageIntrinsics,
            depth = depthIntrinsics,
        )
        finished = true
        packagingStarted = true
        postMessage("Armando el paquete de captura. Esperá un momento…")
        thread(name = "capture-packager") {
            val (capturePackage, packageError) = buildPackage(snapshot)
            val result = CaptureResult.captured(
                corners = emptyList(),
                height = height,
                boxes = emptyList(),
                metrics = metrics,
                observations = observations,
                capturePackage = capturePackage,
                capturePackageError = packageError,
            )
            runOnUiThread { deliver(result) }
        }
    }

    // endregion

    // region Walkthrough helpers (GL thread)

    private fun sampleWalkthrough(session: Session, camera: Camera) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastWalkSampleAtMs < WALKTHROUGH_SAMPLE_INTERVAL_MS) return
        lastWalkSampleAtMs = now
        val planes = trackedPlanes(session)
        walkFloorY = WalkthroughGeometry.refineFloorY(walkFloorY, upwardPlaneYs(planes))
        liveWalls = wallSegments(planes)
        liveFloorArea = walkFloorY?.let { floorY ->
            floorPolygons(planes, floorY).sumOf { WalkthroughGeometry.polygonArea(it) }
        } ?: 0.0
        if (recording) {
            val pose = camera.pose
            if (trajectory.offer(pose.tx().toDouble(), pose.tz().toDouble())) logTrajectory(pose.tx().toDouble(), pose.tz().toDouble())
        }
        coverage = WalkthroughCoverage.compute(liveWalls, coverageCentre(camera))
    }

    // region Capture package (S13)

    /** What the packager thread needs; built on the GL thread. */
    private class PackageSnapshot(
        val recorder: KeyframeRecorder?,
        val captureId: String,
        val listingId: String?,
        val floorY: Double,
        val planes: List<PackagePlane>,
        val rooms: List<PackageRoom>,
        val trajectory: List<TrajectorySample>,
        val image: Intrinsics?,
        val depth: Intrinsics?,
    )

    private fun startPackage() {
        captureId = UUID.randomUUID().toString()
        recordStartedAtMs = SystemClock.elapsedRealtime()
        keyframeSelector = KeyframeSelector()
        rooms = RoomSequence(roomName)
        trajectoryLog.clear()
        imageIntrinsics = null
        depthIntrinsics = null
        // Only one capture runs at a time, so anything left in the work folder is from a dead run.
        File(cacheDir, "capture_work").deleteRecursively()
        recorder = KeyframeRecorder(File(cacheDir, "capture_work/$captureId"), AndroidKeyframeEncoder())
    }

    private fun logTrajectory(x: Double, z: Double) {
        trajectoryLog.add(TrajectorySample(SystemClock.elapsedRealtime() - recordStartedAtMs, x, z, rooms.currentId))
    }

    /** «Siguiente ambiente»: later trajectory samples and keyframes carry the new room id. */
    private fun nextRoom() {
        if (!recording) return
        val room = rooms.next()
        postMessage("Empezaste «${room.name}». Pasá al nuevo ambiente y recorré sus paredes.")
    }

    private fun recordKeyframe(frame: Frame, camera: Camera) {
        val target = recorder ?: return
        val pose = toCameraPose(camera.pose)
        val timestampNs = frame.timestamp
        if (!keyframeSelector.offer(timestampNs / 1_000_000L, tracking = true, pose = pose)) return
        target.submit(timestampNs, rooms.currentId, pose) { copyKeyframe(frame, camera) }
    }

    /**
     * Copies the CPU camera image (and the raw depth with its confidence when supported) out of the
     * ARCore images, which are closed right away. Encoding and writing happen on the writer thread.
     * Depth is the raw 16-bit depth because only it has a matching confidence image.
     */
    private fun copyKeyframe(frame: Frame, camera: Camera): KeyframePayload? {
        val yuv = try {
            val image = frame.acquireCameraImage()
            try {
                val planes = image.planes
                RawYuv(
                    width = image.width,
                    height = image.height,
                    y = bytesOf(planes[0].buffer),
                    yRowStride = planes[0].rowStride,
                    u = bytesOf(planes[1].buffer),
                    v = bytesOf(planes[2].buffer),
                    uvRowStride = planes[1].rowStride,
                    uvPixelStride = planes[1].pixelStride,
                )
            } finally {
                image.close()
            }
        } catch (e: NotYetAvailableException) {
            return null
        }
        if (imageIntrinsics == null) {
            val intrinsics = camera.imageIntrinsics
            val focal = intrinsics.focalLength
            val principal = intrinsics.principalPoint
            val size = intrinsics.imageDimensions
            imageIntrinsics = Intrinsics(size[0], size[1], focal[0].toDouble(), focal[1].toDouble(), principal[0].toDouble(), principal[1].toDouble())
                .scaledTo(yuv.width, yuv.height)
        }
        val depth = if (depthSupported) {
            acquireGray { frame.acquireRawDepthImage16Bits() }?.let {
                DepthDecoder.millimetres(it.bytes, it.width, it.height, it.rowStride)
            }
        } else {
            null
        }
        val confidence = if (depth != null) {
            acquireGray { frame.acquireRawDepthConfidenceImage() }
                ?.takeIf { it.width == depth.width && it.height == depth.height }
                ?.let { DepthDecoder.gray8(it.bytes, it.width, it.height, it.rowStride) }
        } else {
            null
        }
        if (depth != null && depthIntrinsics == null) {
            depthIntrinsics = imageIntrinsics?.scaledTo(depth.width, depth.height)
        }
        return KeyframePayload(yuv, depth, confidence)
    }

    private class GrayCopy(val bytes: ByteArray, val width: Int, val height: Int, val rowStride: Int)

    /** Copies plane 0 of a single-plane ARCore image and closes it; null while not yet available. */
    private fun acquireGray(acquire: () -> Image): GrayCopy? {
        val image = try {
            acquire()
        } catch (e: NotYetAvailableException) {
            return null
        }
        return try {
            val plane = image.planes[0]
            GrayCopy(bytesOf(plane.buffer), image.width, image.height, plane.rowStride)
        } finally {
            image.close()
        }
    }

    private fun bytesOf(buffer: java.nio.ByteBuffer): ByteArray {
        val copy = buffer.duplicate()
        copy.rewind()
        return ByteArray(copy.remaining()).also { copy.get(it) }
    }

    private fun toCameraPose(pose: com.google.ar.core.Pose) = CameraPose(
        pose.tx().toDouble(), pose.ty().toDouble(), pose.tz().toDouble(),
        pose.qx().toDouble(), pose.qy().toDouble(), pose.qz().toDouble(), pose.qw().toDouble(),
    )

    /**
     * Floor (upward plane at the floor level), ceiling (downward plane) and wall (vertical) planes
     * tracked at the end of the session. Other upward planes (tables, beds) have no contract type
     * and are left out.
     */
    private fun packagePlanes(planes: List<Plane>, floorY: Double): List<PackagePlane> {
        val result = mutableListOf<PackagePlane>()
        for (plane in planes) {
            val kind = when (plane.type) {
                Plane.Type.HORIZONTAL_UPWARD_FACING ->
                    if (WalkthroughGeometry.isAtFloorHeight(plane.centerPose.ty().toDouble(), floorY)) PlaneKind.FLOOR else null
                Plane.Type.HORIZONTAL_DOWNWARD_FACING -> PlaneKind.CEILING
                Plane.Type.VERTICAL -> PlaneKind.WALL
                else -> null
            } ?: continue
            val buffer = plane.polygon.duplicate()
            buffer.rewind()
            val polygon = ArrayList<Pair<Double, Double>>(buffer.remaining() / 2)
            while (buffer.remaining() >= 2) polygon.add(buffer.get().toDouble() to buffer.get().toDouble())
            result.add(PackagePlane("p${result.size + 1}", kind, toCameraPose(plane.centerPose), polygon))
        }
        return result
    }

    /** Runs on the packager thread: waits for the writer, writes the manifest and zips the package. */
    private fun buildPackage(snapshot: PackageSnapshot): Pair<CapturePackageResult?, String?> {
        val target = snapshot.recorder ?: return null to "No se registraron cuadros del recorrido."
        return try {
            val recording = target.finish(KEYFRAME_FLUSH_TIMEOUT_MS)
            val image = snapshot.image
            if (recording.keyframes.isEmpty() || image == null) {
                target.abort()
                return null to "No se guardaron cuadros del recorrido. Caminá más despacio y con más luz."
            }
            val workDir = File(cacheDir, "capture_work/${snapshot.captureId}")
            val manifest = ManifestBuilder.build(
                ManifestInput(
                    captureId = snapshot.captureId,
                    listingId = snapshot.listingId,
                    capturedAt = utcNow(),
                    deviceModel = Build.MODEL,
                    arcoreVersion = arcoreVersion(),
                    depthSupported = depthSupported,
                    image = image,
                    depth = snapshot.depth,
                    floorY = snapshot.floorY,
                    rooms = snapshot.rooms,
                    planes = snapshot.planes,
                    trajectory = snapshot.trajectory,
                    keyframes = recording.keyframes.map {
                        PackageKeyframe(
                            it.index, it.timestampNs, it.roomId, it.pose,
                            it.files.image, it.files.depth, it.files.confidence,
                        )
                    },
                ),
            )
            File(workDir, "manifest.json").writeText(JsonWriter.write(manifest))
            val zip = File(filesDir, "capture_packages/${snapshot.captureId}.zip").also { it.parentFile?.mkdirs() }
            PackageZip.zipDirectory(workDir, zip)
            workDir.deleteRecursively()
            CapturePackageResult(
                zipPath = zip.absolutePath,
                captureId = snapshot.captureId,
                sizeBytes = zip.length(),
                keyframeCount = recording.keyframes.size,
                droppedKeyframes = recording.dropped,
                failedKeyframes = recording.failed,
                rooms = snapshot.rooms,
            ) to null
        } catch (e: Exception) {
            Log.e(TAG, "Capture package failed", e)
            target.abort()
            null to "No pudimos armar el paquete de captura (¿poco espacio en el teléfono?)."
        }
    }

    private fun utcNow(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())

    private fun arcoreVersion(): String = try {
        packageManager.getPackageInfo("com.google.ar.core", 0).versionName ?: "unknown"
    } catch (e: Exception) {
        "unknown"
    }

    // endregion

    /** Centre of the walked path, which approximates the room centre when walking along the walls. */
    private fun coverageCentre(camera: Camera): Corner2 {
        val points = trajectory.points
        if (points.isEmpty()) return Corner2(camera.pose.tx().toDouble(), camera.pose.tz().toDouble())
        return Corner2(points.sumOf { it.x } / points.size, points.sumOf { it.z } / points.size)
    }

    /** Heading, speed and light for the live guidance; motion restarts after every tracking loss. */
    private fun updateGuidanceSignals(frame: Frame, camera: Camera, tracking: Boolean) {
        if (!tracking) {
            motionMeter.reset()
            lastMotion = null
            return
        }
        val pose = camera.pose
        // The camera looks down its local -z axis.
        val zAxis = pose.zAxis
        headingRad = atan2(-zAxis[2].toDouble(), -zAxis[0].toDouble())
        motionMeter.offer(SystemClock.elapsedRealtime(), pose.tx().toDouble(), pose.tz().toDouble(), headingRad)
            ?.let { lastMotion = it }
        val estimate = frame.lightEstimate
        lightIntensity = if (estimate.state == LightEstimate.State.VALID) estimate.pixelIntensity.toDouble() else null
    }

    /** Speaks a stable cue, warns with vibration when too fast and ticks when a new wall is registered. */
    private fun announce(guidance: Guidance, nowMs: Long) {
        val target = feedback ?: return
        if (recording && liveWalls.size > maxWallCount) {
            maxWallCount = liveWalls.size
            target.tick()
        }
        val cue = announcer.offer(guidance.cue, nowMs) ?: return
        if (cue == GuidanceCue.TOO_FAST) target.warn()
        target.speak(guidance.message)
    }

    private fun trackedPlanes(session: Session): List<Plane> =
        session.getAllTrackables(Plane::class.java).filter {
            it.trackingState == TrackingState.TRACKING && it.subsumedBy == null
        }

    private fun upwardPlaneYs(planes: List<Plane>): List<Double> =
        planes.filter { it.type == Plane.Type.HORIZONTAL_UPWARD_FACING }.map { it.centerPose.ty().toDouble() }

    private fun wallSegments(planes: List<Plane>): List<WallSegment> =
        planes.filter { it.type == Plane.Type.VERTICAL }.mapNotNull { plane ->
            WalkthroughGeometry.fitWallSegment(worldPolygon(plane), (plane.extentX * plane.extentZ).toDouble())
        }

    private fun floorPolygons(planes: List<Plane>, floorY: Double): List<List<Corner2>> =
        planes.filter {
            it.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                WalkthroughGeometry.isAtFloorHeight(it.centerPose.ty().toDouble(), floorY)
        }.map { plane -> worldPolygon(plane).map { Corner2(it.x, it.z) } }

    /** The plane boundary (local x/z pairs around its centre pose) in world coordinates. */
    private fun worldPolygon(plane: Plane): List<Vec3> {
        val buffer = plane.polygon.duplicate()
        buffer.rewind()
        val pose = plane.centerPose
        val points = ArrayList<Vec3>(buffer.remaining() / 2)
        val local = FloatArray(3)
        while (buffer.remaining() >= 2) {
            local[0] = buffer.get()
            local[1] = 0f
            local[2] = buffer.get()
            val world = pose.transformPoint(local)
            points.add(Vec3(world[0].toDouble(), world[1].toDouble(), world[2].toDouble()))
        }
        return points
    }

    private fun publishWalkthroughOverlay(camera: Camera, tracking: Boolean, centreHits: List<HitResult>) {
        val width = viewportWidth
        val height = viewportHeight
        if (width == 0 || height == 0) return
        val view = FloatArray(16)
        val projection = FloatArray(16)
        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(projection, 0, 0.05f, 100f)
        fun project(x: Double, y: Double, z: Double) =
            CaptureGeometry.projectToScreen(Vec3(x, y, z), view, projection, width, height)

        val segments = mutableListOf<OverlaySegment>()
        val floorY = walkFloorY
        val walls = liveWalls
        if (floorY != null) {
            for (wall in walls) {
                val start = project(wall.start.x, floorY, wall.start.z)
                val end = project(wall.end.x, floorY, wall.end.z)
                if (start != null && end != null) {
                    segments.add(OverlaySegment(start, end, CaptureGeometry.formatMeters(wall.length), dashed = false))
                }
            }
        }
        val notice = if (walls.size < CaptureRules.MIN_CORNERS) {
            "Paredes detectadas: ${walls.size}. Apuntá a la base de cada pared mientras caminás."
        } else {
            null
        }
        val onFloor = tracking && centreHits.any { isTrackedPlaneHit(it, Plane.Type.HORIZONTAL_UPWARD_FACING) }
        val minimap = if (recording || walls.isNotEmpty()) {
            val pose = camera.pose
            MinimapModel(walls, trajectory.points, Corner2(pose.tx().toDouble(), pose.tz().toDouble()), headingRad, coverage)
        } else {
            null
        }
        val model = OverlayModel(emptyList(), segments, emptyList(), emptyList(), onFloor, notice, minimap)
        overlay.post { overlay.update(model) }
    }

    private fun publishWalkthroughStatus(camera: Camera) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastStatusAtMs < STATUS_INTERVAL_MS) return
        lastStatusAtMs = now
        val guidance = WalkthroughGuidance.evaluate(
            GuidanceInput(
                trackingStateName = camera.trackingState.name,
                failureReasonName = camera.trackingFailureReason.name,
                recording = recording,
                floorFound = walkFloorY != null,
                speed = lastMotion?.speed,
                yawRateDeg = lastMotion?.yawRateDeg,
                lightIntensity = lightIntensity,
                coverage = coverage,
                headingRad = headingRad,
            ),
        )
        announce(guidance, now)
        val depthText = if (depthSupported) "profundidad disponible" else "sin profundidad"
        val stateText = if (recording) "recorrido en curso" else "recorrido sin iniciar"
        val heightText = roomHeight?.let { " · altura ${CaptureGeometry.formatMeters(it.value)}" } ?: ""
        val text = "${guidance.message}\nParedes detectadas: ${liveWalls.size} · " +
            "piso: ${WalkthroughGeometry.formatSquareMeters(liveFloorArea)} · " +
            "trayectoria: ${WalkthroughGeometry.formatTrajectory(trajectory.length())} · " +
            "cobertura ${(coverage.fraction * 100).toInt()} %\n" +
            "$depthText · $stateText$heightText"
        runOnUiThread { statusText.text = text }
    }

    // endregion

    // region Helpers (GL thread)

    private fun requireTracking(camera: Camera): Boolean {
        if (camera.trackingState == TrackingState.TRACKING) return true
        postMessage("Sin seguimiento no se marcan puntos. Mové el teléfono despacio hasta recuperarlo.")
        return false
    }

    private fun centreHitTest(frame: Frame): List<HitResult> {
        if (viewportWidth == 0 || viewportHeight == 0) return emptyList()
        return frame.hitTest(viewportWidth / 2f, viewportHeight / 2f)
    }

    private fun isTrackedPlaneHit(hit: HitResult, type: Plane.Type): Boolean {
        val plane = hit.trackable as? Plane ?: return false
        return plane.trackingState == TrackingState.TRACKING &&
            plane.type == type &&
            plane.isPoseInPolygon(hit.hitPose)
    }

    /** Hits the camera observed; excludes plane extensions outside their detected polygon. */
    private fun isMeasurableHit(hit: HitResult): Boolean {
        val trackable = hit.trackable
        val kind = when (trackable) {
            is Plane -> HitKind.PLANE
            is DepthPoint -> HitKind.DEPTH_POINT
            is Point -> HitKind.FEATURE_POINT
            else -> HitKind.OTHER
        }
        return CaptureRules.isMeasurableHit(
            kind,
            tracking = trackable.trackingState == TrackingState.TRACKING,
            insidePolygon = (trackable as? Plane)?.isPoseInPolygon(hit.hitPose) ?: false,
        )
    }

    private fun floorHit(frame: Frame): HitResult? =
        centreHitTest(frame).firstOrNull { isTrackedPlaneHit(it, Plane.Type.HORIZONTAL_UPWARD_FACING) }

    private fun currentFloorY(): Double? = if (mode == CaptureMode.WALKTHROUGH) {
        walkFloorY
    } else {
        wallPoints.firstOrNull()?.anchor?.pose?.ty()?.toDouble()
    }

    /** Complete walls (pairs of consecutive points) at current anchor poses; a pending half-wall is left out. */
    private fun currentWallLines(): List<Pair<Vec3, Vec3>> =
        wallPoints.chunked(2).filter { it.size == 2 }.map { (a, b) -> toVec3(a.anchor) to toVec3(b.anchor) }

    private fun toCorner(anchor: Anchor): Corner2 = Corner2(anchor.pose.tx().toDouble(), anchor.pose.tz().toDouble())

    private fun toVec3(anchor: Anchor): Vec3 =
        anchor.pose.let { Vec3(it.tx().toDouble(), it.ty().toDouble(), it.tz().toDouble()) }

    /** Raw depth confidence (0..1) at the screen centre, or null when unavailable. */
    private fun centreDepthConfidence(frame: Frame): Double? {
        if (!depthSupported) return null
        return try {
            val image = frame.acquireRawDepthConfidenceImage()
            try {
                val view = floatArrayOf(viewportWidth / 2f, viewportHeight / 2f)
                val normalized = FloatArray(2)
                frame.transformCoordinates2d(Coordinates2d.VIEW, view, Coordinates2d.IMAGE_NORMALIZED, normalized)
                val x = (normalized[0] * image.width).toInt().coerceIn(0, image.width - 1)
                val y = (normalized[1] * image.height).toInt().coerceIn(0, image.height - 1)
                val plane = image.planes[0]
                val raw = plane.buffer.get(y * plane.rowStride + x * plane.pixelStride).toInt() and 0xFF
                raw / 255.0
            } finally {
                image.close()
            }
        } catch (e: NotYetAvailableException) {
            null
        } catch (e: Exception) {
            Log.w(TAG, "Raw depth confidence unavailable", e)
            null
        }
    }

    private fun publishOverlay(camera: Camera, tracking: Boolean, centreHits: List<HitResult>) {
        val width = viewportWidth
        val height = viewportHeight
        if (width == 0 || height == 0) return
        val view = FloatArray(16)
        val projection = FloatArray(16)
        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(projection, 0, 0.05f, 100f)
        fun project(anchor: Anchor) = CaptureGeometry.projectToScreen(toVec3(anchor), view, projection, width, height)

        fun projectPoint(point: Vec3) = CaptureGeometry.projectToScreen(point, view, projection, width, height)

        val screenPoints = wallPoints.map { project(it.anchor) }
        val segments = mutableListOf<OverlaySegment>()
        // Each marked wall: its two points and the solid segment between them.
        screenPoints.chunked(2).filter { it.size == 2 }.forEach { (a, b) ->
            if (a != null && b != null) segments.add(OverlaySegment(a, b, label = null, dashed = false))
        }
        // Derived room polygon (dashed, with edge lengths), or why it cannot be computed.
        var notice: String? = null
        val walls = currentWallLines()
        if (walls.size >= CaptureRules.MIN_CORNERS) {
            when (val computed = WallLines.cornersFromWallLines(walls)) {
                is WallCornersResult.Corners -> {
                    val derived = computed.corners
                    val screenCorners = derived.map { projectPoint(it) }
                    CaptureGeometry.edgeLengths(derived, closed = true).forEachIndexed { index, length ->
                        val start = screenCorners[index]
                        val end = screenCorners[(index + 1) % screenCorners.size]
                        if (start != null && end != null) {
                            segments.add(OverlaySegment(start, end, CaptureGeometry.formatMeters(length), dashed = true))
                        }
                    }
                }
                is WallCornersResult.Failure -> notice = computed.message
            }
        }
        val boxPoints = mutableListOf<ScreenPoint>()
        val boxSegments = mutableListOf<OverlaySegment>()
        pendingBoxCorner?.let { project(it) }?.let { boxPoints.add(it) }
        boxes.forEachIndexed { index, box ->
            val a = project(box.first)
            val b = project(box.second)
            a?.let { boxPoints.add(it) }
            b?.let { boxPoints.add(it) }
            if (a != null && b != null) {
                val label = box.height?.let { "Mueble ${index + 1} · ${CaptureGeometry.formatMeters(it)}" }
                    ?: "Mueble ${index + 1}"
                boxSegments.add(OverlaySegment(a, b, label, dashed = false))
            }
        }
        val onFloor = tracking && centreHits.any { isTrackedPlaneHit(it, Plane.Type.HORIZONTAL_UPWARD_FACING) }
        val model = OverlayModel(screenPoints.filterNotNull(), segments, boxPoints, boxSegments, onFloor, notice)
        overlay.post { overlay.update(model) }
    }

    private fun publishStatus(session: Session, camera: Camera, centreHits: List<HitResult>) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastStatusAtMs < STATUS_INTERVAL_MS) return
        lastStatusAtMs = now
        val guidance = CaptureRules.trackingGuidance(camera.trackingState.name, camera.trackingFailureReason.name)
        val floorPlanes = session.getAllTrackables(Plane::class.java).count {
            it.trackingState == TrackingState.TRACKING &&
                it.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                it.subsumedBy == null
        }
        val distance = centreHits.firstOrNull { isMeasurableHit(it) }?.distance?.toDouble()
        val distanceText = distance?.let { CaptureGeometry.formatMeters(it) } ?: "sin superficie observada"
        val depthText = if (depthSupported) "profundidad disponible" else "sin profundidad"
        val pendingText = if (wallPoints.size % 2 == 1) " · Marcá el segundo punto de esta pared" else ""
        val heightText = roomHeight?.let { " · altura ${CaptureGeometry.formatMeters(it.value)}" } ?: ""
        val text = "$guidance\nPisos detectados: $floorPlanes · $depthText · distancia al centro: $distanceText\n" +
            "Paredes: ${wallPoints.size / 2}$pendingText · muebles: ${boxes.size}$heightText"
        runOnUiThread { statusText.text = text }
    }

    private fun displayRotation(): Int {
        @Suppress("DEPRECATION")
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        return display?.rotation ?: Surface.ROTATION_0
    }

    // endregion

    // region UI (main thread)

    private fun enqueue(action: (Frame, Camera) -> Unit) {
        if (!finished) pendingActions.add(action)
    }

    private fun postMessage(message: String) {
        runOnUiThread { messageText.text = message }
    }

    private fun refreshButtons(tracking: Boolean) {
        if (mode == CaptureMode.WALKTHROUGH) {
            if (!::recordButton.isInitialized) return
            // «Terminar recorrido» stays available; the finish rule decides with what is tracked then.
            recordButton.isEnabled = tracking || recordingShown
            heightButton.isEnabled = tracking
            nextRoomButton.isEnabled = recordingShown
            if (!tracking) {
                messageText.text = "Sin seguimiento el recorrido queda en pausa y no se registra nada. " +
                    "Mové el teléfono despacio apuntando al piso."
            }
            return
        }
        if (!::wallButton.isInitialized) return
        wallButton.isEnabled = tracking
        heightButton.isEnabled = tracking
        boxButton.isEnabled = tracking
        boxHeightButton.isEnabled = tracking && depthSupported
        if (!tracking) {
            messageText.text = "Sin seguimiento no se marcan puntos. Mové el teléfono despacio apuntando al piso."
        }
    }

    private fun cancelCapture() {
        if (finished) return
        finished = true
        if (!packagingStarted) recorder?.abort()
        deliver(CaptureResult.cancelled())
    }

    private fun finishWithError(code: String, message: String) {
        runOnUiThread {
            if (!isFinishing) {
                finished = true
                deliver(CaptureResult.error(code, message))
            }
        }
    }

    private fun deliver(result: Map<String, Any?>) {
        if (isFinishing) return
        setResult(RESULT_OK, Intent().putExtra(EXTRA_RESULT_JSON, JsonWriter.write(result)))
        finish()
    }

    private fun buildLayout(): View {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = GLSurfaceView(this).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(this@ArCaptureActivity)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
            setWillNotDraw(false)
        }
        overlay = CaptureOverlayView(this)
        root.addView(surfaceView, FrameLayout.LayoutParams(MATCH, MATCH))
        root.addView(overlay, FrameLayout.LayoutParams(MATCH, MATCH))

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.argb(160, 0, 0, 0))
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            text = if (roomName.isBlank()) "Captura del ambiente" else "Captura: $roomName"
        }
        statusText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            text = "Iniciando la cámara… Mové el teléfono despacio apuntando al piso."
        }
        top.addView(title)
        top.addView(statusText)
        root.addView(top, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))

        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.argb(160, 0, 0, 0))
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        messageText = TextView(this).apply {
            setTextColor(Color.rgb(255, 224, 130))
            textSize = 14f
            text = if (mode == CaptureMode.WALKTHROUGH) {
                "Tocá «Iniciar recorrido». $WALKTHROUGH_GUIDANCE"
            } else {
                "Apuntá el centro al piso, al pie de una pared, y tocá «Marcar punto de pared». " +
                    "Marcá dos puntos por pared, recorriendo las paredes en orden alrededor de la habitación."
            }
            setPadding(dp(4), 0, dp(4), dp(6))
        }
        bottom.addView(messageText)
        if (mode == CaptureMode.WALKTHROUGH) {
            recordButton = button("Iniciar recorrido") { enqueue { _, camera -> toggleRecording(camera) } }
            nextRoomButton = button("Siguiente ambiente") { enqueue { _, _ -> nextRoom() } }
            heightButton = button("Medir altura") { enqueue(::measureRoomHeight) }
            cancelButton = button("Cancelar") { cancelCapture() }
            bottom.addView(row(recordButton, nextRoomButton))
            bottom.addView(row(heightButton, cancelButton))
        } else {
            addWallControls(bottom)
        }
        root.addView(bottom, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        applyInsets(root, top, bottom)
        refreshButtons(tracking = false)
        return root
    }

    /** Walls mode controls, unchanged from before the walkthrough mode. */
    private fun addWallControls(bottom: LinearLayout) {
        wallButton = button("Marcar punto de pared") { enqueue(::markWallPoint) }
        undoButton = button("Deshacer") { enqueue { _, _ -> undo() } }
        heightButton = button("Medir altura") { enqueue(::measureRoomHeight) }
        boxButton = button("Marcar mueble") { enqueue(::markBoxCorner) }
        boxHeightButton = button("Medir alto del mueble") { enqueue(::measureBoxHeight) }
        finishButton = button("Terminar") { enqueue { _, _ -> finishCapture() } }
        cancelButton = button("Cancelar") { cancelCapture() }
        bottom.addView(row(wallButton, undoButton, heightButton))
        bottom.addView(row(boxButton, boxHeightButton))
        bottom.addView(row(cancelButton, finishButton))
    }

    private fun applyInsets(root: View, top: View, bottom: View) {
        // Edge-to-edge (enforced on Android 15+): keep controls clear of the system bars.
        root.setOnApplyWindowInsetsListener { _, insets ->
            val (topInset, bottomInset) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                bars.top to bars.bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop to insets.systemWindowInsetBottom
            }
            top.setPadding(dp(12), dp(8) + topInset, dp(12), dp(8))
            bottom.setPadding(dp(8), dp(8), dp(8), dp(8) + bottomInset)
            insets
        }
    }

    private fun button(label: String, onClick: () -> Unit): Button = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 13f
        setOnClickListener { onClick() }
    }

    private fun row(vararg buttons: Button): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        for (button in buttons) {
            addView(button, LinearLayout.LayoutParams(0, WRAP, 1f).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) })
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
    private val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT

    // endregion
}
