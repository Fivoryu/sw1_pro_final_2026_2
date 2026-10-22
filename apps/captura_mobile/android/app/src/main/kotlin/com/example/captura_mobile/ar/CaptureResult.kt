package com.example.captura_mobile.ar

/** A floor point projected to world x/z (metres). */
data class Corner2(val x: Double, val z: Double) {
    fun toMap(): Map<String, Any?> = linkedMapOf("x" to x, "z" to z)
}

data class RoomHeight(val value: Double, val source: String) {
    fun toMap(): Map<String, Any?> = linkedMapOf("value" to value, "source" to source)

    companion object {
        const val SOURCE_CEILING_PLANE = "ceiling_plane"
        const val SOURCE_WALL_POINT = "wall_point"
    }
}

/** Occupancy footprint marked by two diagonal floor corners; no class or price is ever attached. */
data class CapturedBox(
    val corners: List<Corner2>,
    val height: Double?,
    val heightSource: String?,
    val confidence: Double?,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "corners" to corners.map { it.toMap() },
        "height" to height,
        "heightSource" to heightSource,
        "confidence" to confidence,
    )

    companion object {
        const val SOURCE_DEPTH = "depth"
    }
}

data class CaptureMetrics(
    val durationMs: Long,
    val trackingLossCount: Int,
    val depthSupported: Boolean,
    val cornerHitDistances: List<Double>,
    val floorY: Double,
    /** How the corners were obtained; omitted from the map when null. */
    val method: String? = null,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf<String, Any?>(
        "durationMs" to durationMs,
        "trackingLossCount" to trackingLossCount,
        "depthSupported" to depthSupported,
        "cornerHitDistances" to cornerHitDistances,
        "floorY" to floorY,
    ).also { map -> method?.let { map["method"] = it } }

    companion object {
        /** Corners intersected from two floor points per wall; hit distances are one per wall point. */
        const val METHOD_WALL_LINES = "wall_lines"

        /** Corners left to Dart: the result carries plane and trajectory observations instead. */
        const val METHOD_WALKTHROUGH = "walkthrough"
    }
}

/** Builds the `roomforge/ar_capture` `captureRoom` result maps (see odd/tasks/f07-spatial-capture.md). */
object CaptureResult {
    const val ERROR_CAMERA_PERMISSION_DENIED = "camera_permission_denied"
    const val ERROR_ARCORE_UNAVAILABLE = "arcore_unavailable"
    const val ERROR_ARCORE_INSTALL_DECLINED = "arcore_install_declined"
    const val ERROR_SESSION_FAILED = "session_failed"

    fun captured(
        corners: List<Corner2>,
        height: RoomHeight?,
        boxes: List<CapturedBox>,
        metrics: CaptureMetrics,
        /** Only in walkthrough mode; the key is omitted otherwise. */
        observations: WalkthroughObservations? = null,
        /** Only in walkthrough mode, when the package was built; the key is omitted otherwise. */
        capturePackage: CapturePackageResult? = null,
        /** Only in walkthrough mode, when the package could not be built: why, for the agent. */
        capturePackageError: String? = null,
    ): Map<String, Any?> = linkedMapOf<String, Any?>(
        "outcome" to "captured",
        "corners" to corners.map { it.toMap() },
        "height" to height?.toMap(),
        "boxes" to boxes.map { it.toMap() },
        "metrics" to metrics.toMap(),
    ).also { map ->
        observations?.let { map["observations"] = it.toMap() }
        capturePackage?.let { map["capturePackage"] = it.toMap() }
        capturePackageError?.let { map["capturePackageError"] = it }
    }

    fun cancelled(): Map<String, Any?> = linkedMapOf("outcome" to "cancelled")

    fun error(code: String, message: String): Map<String, Any?> =
        linkedMapOf("outcome" to "error", "code" to code, "message" to message)
}
