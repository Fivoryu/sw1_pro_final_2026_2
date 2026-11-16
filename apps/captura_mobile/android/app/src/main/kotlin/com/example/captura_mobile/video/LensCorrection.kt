package com.example.captura_mobile.video

/** What the device lists as available for lens distortion correction (plain data, no Android types). */
data class LensCorrectionSupport(
    val sdkInt: Int,
    /** `DISTORTION_CORRECTION_AVAILABLE_MODES` (API 28+), null when absent. */
    val standardModes: List<Int>?,
    /** Samsung vendor request key is present among the available request keys. */
    val vendorKeyPresent: Boolean,
    /** Vendor characteristics modes (0 off, 1 on), null when absent. */
    val vendorModes: List<Int>?,
)

sealed class LensCorrectionChoice {
    data class Standard(val mode: Int) : LensCorrectionChoice()
    data class Vendor(val mode: Int) : LensCorrectionChoice()
}

object LensCorrection {
    const val VENDOR_REQUEST_KEY = "samsung.android.control.lensDistortionCorrectionMode"
    const val VENDOR_MODES_KEY = "samsung.android.control.lensDistortionCorrectionAvailableModes"

    // Values of CaptureRequest.DISTORTION_CORRECTION_MODE_* (kept literal so the function stays JVM-pure).
    const val STANDARD_FAST = 1
    const val STANDARD_HIGH_QUALITY = 2
    const val VENDOR_ON = 1
    private const val MIN_SDK_STANDARD = 28

    /** Picks the best correction the device explicitly lists, or null to keep the previous behaviour. */
    fun choose(support: LensCorrectionSupport): LensCorrectionChoice? {
        if (support.sdkInt >= MIN_SDK_STANDARD) {
            val modes = support.standardModes.orEmpty()
            if (STANDARD_HIGH_QUALITY in modes) return LensCorrectionChoice.Standard(STANDARD_HIGH_QUALITY)
            if (STANDARD_FAST in modes) return LensCorrectionChoice.Standard(STANDARD_FAST)
        }
        if (support.vendorKeyPresent && VENDOR_ON in support.vendorModes.orEmpty()) {
            return LensCorrectionChoice.Vendor(VENDOR_ON)
        }
        return null
    }
}
