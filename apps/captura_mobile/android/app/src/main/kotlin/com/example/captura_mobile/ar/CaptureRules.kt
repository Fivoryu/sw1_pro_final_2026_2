package com.example.captura_mobile.ar

import kotlin.math.abs

/** Outcome of a capture rule: accepted, or rejected with a Spanish message for the agent. */
sealed class RuleCheck {
    object Ok : RuleCheck() {
        override fun toString(): String = "Ok"
    }

    data class Rejected(val message: String) : RuleCheck()
}

/** What an ARCore hit landed on, mapped from its trackable so the rule stays JVM-testable. */
enum class HitKind { PLANE, DEPTH_POINT, FEATURE_POINT, OTHER }

/** Pure acceptance rules for the AR capture. ARCore enums are passed by name to stay JVM-testable. */
object CaptureRules {
    const val FLOOR_TOLERANCE_M = 0.10
    const val MIN_ROOM_HEIGHT_M = 1.8
    const val MAX_ROOM_HEIGHT_M = 4.5
    const val MIN_BOX_HEIGHT_M = 0.05
    const val MAX_BOX_HEIGHT_M = 3.0
    const val MIN_CORNERS = 3
    const val MIN_WALL_POINT_SPACING_M = 0.30
    const val RECOMMENDED_WALL_POINT_SPACING_M = 0.50

    private const val EPSILON = 1e-9

    /**
     * Whether a hit is something the camera actually observed. ARCore also returns hits on
     * the infinite extension of a detected plane; those are not measurements (a textureless
     * wall 1 m away can "hit" the extended floor 10 m behind it).
     */
    fun isMeasurableHit(kind: HitKind, tracking: Boolean, insidePolygon: Boolean): Boolean =
        tracking && when (kind) {
            HitKind.PLANE -> insidePolygon
            HitKind.DEPTH_POINT, HitKind.FEATURE_POINT -> true
            HitKind.OTHER -> false
        }

    /** The first floor point fixes the floor; later ones must stay within [FLOOR_TOLERANCE_M] of it. */
    fun checkFloorPoint(floorY: Double?, hitY: Double): RuleCheck {
        if (floorY == null) return RuleCheck.Ok
        return if (abs(hitY - floorY) <= FLOOR_TOLERANCE_M + EPSILON) {
            RuleCheck.Ok
        } else {
            RuleCheck.Rejected(
                "Ese punto está a más de 10 cm de la altura del primer punto del piso. " +
                    "Apuntá al mismo piso.",
            )
        }
    }

    fun checkRoomHeight(height: Double): RuleCheck {
        if (height.isNaN() || height < MIN_ROOM_HEIGHT_M - EPSILON || height > MAX_ROOM_HEIGHT_M + EPSILON) {
            return RuleCheck.Rejected(
                "La altura medida no está entre 1,80 m y 4,50 m. " +
                    "Apuntá al techo o a la unión entre pared y techo.",
            )
        }
        return RuleCheck.Ok
    }

    fun checkBoxHeight(height: Double): RuleCheck {
        if (height.isNaN() || height < MIN_BOX_HEIGHT_M || height > MAX_BOX_HEIGHT_M) {
            return RuleCheck.Rejected(
                "La altura del mueble no es válida. Apuntá a la parte superior del mueble.",
            )
        }
        return RuleCheck.Ok
    }

    fun checkFinish(cornerCount: Int, allAnchorsTracking: Boolean): RuleCheck {
        if (cornerCount < MIN_CORNERS) {
            return RuleCheck.Rejected("Marcá al menos 3 esquinas antes de terminar.")
        }
        if (!allAnchorsTracking) {
            return RuleCheck.Rejected(
                "Algunos puntos marcados perdieron el seguimiento. " +
                    "Mové el teléfono despacio sobre la habitación hasta recuperarlos.",
            )
        }
        return RuleCheck.Ok
    }

    /** The second point of a wall must be at least [MIN_WALL_POINT_SPACING_M] from the first (on x/z). */
    fun checkWallPointSpacing(distance: Double): RuleCheck {
        if (distance.isNaN() || distance < MIN_WALL_POINT_SPACING_M - EPSILON) {
            return RuleCheck.Rejected(
                "Ese punto está a menos de 30 cm del primero. " +
                    "Marcá el segundo punto más lejos sobre la misma pared (mejor a 50 cm o más).",
            )
        }
        return RuleCheck.Ok
    }

    fun checkWallFinish(completeWalls: Int, pendingPoint: Boolean, allAnchorsTracking: Boolean): RuleCheck {
        if (pendingPoint) {
            return RuleCheck.Rejected("Falta el segundo punto de la última pared: marcalo o tocá «Deshacer».")
        }
        if (completeWalls < MIN_CORNERS) {
            return RuleCheck.Rejected("Marcá al menos 3 paredes antes de terminar.")
        }
        if (!allAnchorsTracking) {
            return RuleCheck.Rejected(
                "Algunos puntos marcados perdieron el seguimiento. " +
                    "Mové el teléfono despacio sobre la habitación hasta recuperarlos.",
            )
        }
        return RuleCheck.Ok
    }

    /** A walkthrough needs a detected floor and at least three wall segments. */
    fun checkWalkthroughFinish(floorFound: Boolean, wallCount: Int): RuleCheck {
        if (!floorFound) {
            return RuleCheck.Rejected(
                "Todavía no detectamos el piso. Apuntá al piso unos segundos mientras caminás.",
            )
        }
        if (wallCount < MIN_CORNERS) {
            return RuleCheck.Rejected(
                "Detectamos $wallCount paredes; recorré las que faltan apuntando a su base, " +
                    "o usá el modo Marcar paredes.",
            )
        }
        return RuleCheck.Ok
    }

    /** Maps `ArCoreApk.Availability` names to the channel contract statuses. */
    fun availabilityStatus(availabilityName: String): String = when (availabilityName) {
        "SUPPORTED_INSTALLED" -> "supported"
        "SUPPORTED_NOT_INSTALLED", "SUPPORTED_APK_TOO_OLD" -> "supported_not_installed"
        "UNSUPPORTED_DEVICE_NOT_CAPABLE" -> "unsupported"
        else -> "unknown"
    }

    /** Maps `TrackingState` and `TrackingFailureReason` names to Spanish guidance. */
    fun trackingGuidance(trackingStateName: String, failureReasonName: String): String {
        if (trackingStateName == "TRACKING") return "Seguimiento activo."
        if (trackingStateName == "STOPPED") return "Seguimiento detenido. Cerrá y volvé a abrir la captura."
        return when (failureReasonName) {
            "INSUFFICIENT_LIGHT" -> "Falta luz. Encendé las luces o abrí las cortinas."
            "EXCESSIVE_MOTION" -> "Te estás moviendo muy rápido. Mové el teléfono más despacio."
            "INSUFFICIENT_FEATURES" -> "No hay suficiente textura. Apuntá a zonas con objetos o bordes visibles."
            "CAMERA_UNAVAILABLE" -> "La cámara no está disponible. Cerrá otras apps que la usen."
            "BAD_STATE" -> "La sesión quedó en mal estado. Cerrá la captura y reiniciá."
            else -> "Buscando superficies. Mové el teléfono despacio apuntando al piso."
        }
    }
}

/** Counts transitions from TRACKING to any non-tracking state. */
class TrackingLossCounter {
    var count: Int = 0
        private set

    private var wasTracking = false

    fun update(isTracking: Boolean) {
        if (wasTracking && !isTracking) count++
        wasTracking = isTracking
    }
}
