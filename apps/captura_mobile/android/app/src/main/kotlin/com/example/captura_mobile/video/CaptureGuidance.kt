package com.example.captura_mobile.video

import kotlin.math.abs
import kotlin.math.sqrt

/** One live hint shown over the preview while recording (S8). Live only: never stored in the package. */
enum class GuidanceHint(val message: String) {
    ABRUPT_MOVEMENT("Movimiento brusco: mové el teléfono más suave."),
    LOW_LIGHT("Poca luz: encendé más luces o abrí las cortinas."),
    SLOW_DOWN("Giro rápido: girá más despacio."),
    CLOSE_LOOP("Volviste cerca del inicio: podés cerrar el recorrido."),
}

/**
 * ASSUMPTIONS, not measured: every value below was chosen without a device test (S8 and S9 of
 * odd/tasks/f07-video-capture-reconstruction.md). The first real recording (T1) may reopen them.
 */
object GuidanceThresholds {
    /** Smoothed gyro magnitude (rad/s) above which turning is «fast». */
    const val FAST_TURN_RAD_S = 0.8f

    /** Smoothed gyro magnitude (rad/s) above which the movement is «abrupt». */
    const val ABRUPT_RAD_S = 2.0f

    /** Time constant (s) of the gyro low-pass filter. */
    const val GYRO_SMOOTHING_TAU_S = 0.3f

    /** Camera2 SENSOR_SENSITIVITY (ISO) at or above which a capture counts as dark. */
    const val LOW_LIGHT_ISO = 1600

    /** Consecutive dark captures (about 0.5 s at 30 fps) before the low light hint appears. */
    const val LOW_LIGHT_CAPTURES = 15

    /** How long a hint stays after its condition ends, to avoid flicker. */
    const val HOLD_NS = 2_000_000_000L

    /** No close-loop suggestion before this much recording time (60 s). */
    const val CLOSE_LOOP_MIN_NS = 60_000_000_000L

    /** Accumulated absolute heading change (degrees) needed before a loop can be suggested. */
    const val CLOSE_LOOP_MIN_TURNED_DEG = 300.0

    /** Net heading must be within this many degrees of a whole turn from the start heading. */
    const val CLOSE_LOOP_TOLERANCE_DEG = 30.0

    /** Gaps between gyro samples above this (s) are not integrated. */
    const val MAX_GYRO_GAP_S = 0.5
}

/**
 * Pure decision logic for the live guidance, free of Android types so it runs on the JVM. Inputs
 * are the same sensor and Camera2 data the recorder already has; timestamps use the
 * `elapsedRealtimeNanos` clock. Thread-safe: sensors and the camera feed it from their threads, the
 * UI reads it from the main thread.
 *
 * Speed is derived from the gyro only (turning rate); the accelerometer is not integrated into a
 * walking speed because that drifts. «Near the start» is a heading proxy: the gyro rotation about
 * gravity is integrated and the loop is suggested once, when the net heading returns to the start
 * after enough turning. It is not a position, so it can fire without the agent being at the start.
 * «Pared faltante» has no sensor basis in the contract and is intentionally not implemented.
 */
class CaptureGuidance {
    private var gravity: FloatArray? = null
    private var lastGyroNs = 0L
    private var smoothedRadS = 0f
    private var abruptUntilNs = Long.MIN_VALUE
    private var fastUntilNs = Long.MIN_VALUE
    private var lowLightUntilNs = Long.MIN_VALUE
    private var loopUntilNs = Long.MIN_VALUE
    private var loopShown = false
    private var darkCaptures = 0
    private var yawRad = 0.0
    private var turnedRad = 0.0

    @Synchronized
    fun onGravity(x: Float, y: Float, z: Float) {
        gravity = floatArrayOf(x, y, z)
    }

    /** Gyro sample in rad/s on the raw device axes. Ignored until a gravity sample exists. */
    @Synchronized
    fun onGyro(tNs: Long, x: Float, y: Float, z: Float) {
        val g = gravity ?: return
        val dt = if (lastGyroNs == 0L) 0.0 else (tNs - lastGyroNs) / 1e9
        lastGyroNs = tNs
        if (dt <= 0.0 || dt > GuidanceThresholds.MAX_GYRO_GAP_S) return
        val magnitude = sqrt(x * x + y * y + z * z)
        val alpha = (dt / (GuidanceThresholds.GYRO_SMOOTHING_TAU_S + dt)).toFloat()
        smoothedRadS += alpha * (magnitude - smoothedRadS)
        if (smoothedRadS >= GuidanceThresholds.ABRUPT_RAD_S) abruptUntilNs = tNs + GuidanceThresholds.HOLD_NS
        if (smoothedRadS >= GuidanceThresholds.FAST_TURN_RAD_S) fastUntilNs = tNs + GuidanceThresholds.HOLD_NS

        val gNorm = sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])
        if (gNorm < 1e-3f) return
        val yawRate = (x * g[0] + y * g[1] + z * g[2]) / gNorm
        yawRad += yawRate * dt
        turnedRad += abs(yawRate) * dt
        val netDeg = Math.toDegrees(yawRad)
        val offFromWholeTurn = abs(netDeg - 360.0 * Math.round(netDeg / 360.0))
        val minNetDeg = GuidanceThresholds.CLOSE_LOOP_MIN_TURNED_DEG - GuidanceThresholds.CLOSE_LOOP_TOLERANCE_DEG
        if (!loopShown &&
            tNs >= GuidanceThresholds.CLOSE_LOOP_MIN_NS &&
            Math.toDegrees(turnedRad) >= GuidanceThresholds.CLOSE_LOOP_MIN_TURNED_DEG &&
            abs(netDeg) >= minNetDeg &&
            offFromWholeTurn <= GuidanceThresholds.CLOSE_LOOP_TOLERANCE_DEG
        ) {
            loopShown = true
            loopUntilNs = tNs + GuidanceThresholds.HOLD_NS
        }
    }

    /** Feeds one finished capture: its timestamp and Camera2 SENSOR_SENSITIVITY (ISO). */
    @Synchronized
    fun onExposure(tNs: Long, iso: Int) {
        darkCaptures = if (iso >= GuidanceThresholds.LOW_LIGHT_ISO) darkCaptures + 1 else 0
        if (darkCaptures >= GuidanceThresholds.LOW_LIGHT_CAPTURES) lowLightUntilNs = tNs + GuidanceThresholds.HOLD_NS
    }

    /** The hint to show at [nowNs], or null. Priority: abrupt, low light, fast turn, close loop. */
    @Synchronized
    fun current(nowNs: Long): GuidanceHint? = when {
        nowNs <= abruptUntilNs -> GuidanceHint.ABRUPT_MOVEMENT
        nowNs <= lowLightUntilNs -> GuidanceHint.LOW_LIGHT
        nowNs <= fastUntilNs -> GuidanceHint.SLOW_DOWN
        nowNs <= loopUntilNs -> GuidanceHint.CLOSE_LOOP
        else -> null
    }
}
