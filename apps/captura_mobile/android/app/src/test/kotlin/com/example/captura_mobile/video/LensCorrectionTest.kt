package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LensCorrectionTest {
    private fun support(
        sdk: Int = 34,
        standard: List<Int>? = null,
        key: Boolean = false,
        vendor: List<Int>? = null,
    ) = LensCorrectionSupport(sdk, standard, key, vendor)

    @Test
    fun highQualityBeatsFast() {
        assertEquals(LensCorrectionChoice.Standard(2), LensCorrection.choose(support(standard = listOf(0, 1, 2))))
    }

    @Test
    fun fastWhenHighQualityMissing() {
        assertEquals(LensCorrectionChoice.Standard(1), LensCorrection.choose(support(standard = listOf(0, 1))))
    }

    @Test
    fun standardBeatsVendor() {
        val s = support(standard = listOf(2), key = true, vendor = listOf(0, 1))
        assertEquals(LensCorrectionChoice.Standard(2), LensCorrection.choose(s))
    }

    @Test
    fun vendorOnWhenListed() {
        assertEquals(LensCorrectionChoice.Vendor(1), LensCorrection.choose(support(key = true, vendor = listOf(0, 1))))
    }

    @Test
    fun vendorNeedsTheRequestKey() {
        assertNull(LensCorrection.choose(support(key = false, vendor = listOf(0, 1))))
    }

    @Test
    fun vendorNeedsModeOneListed() {
        assertNull(LensCorrection.choose(support(key = true, vendor = listOf(0))))
    }

    @Test
    fun nothingListedMeansNothing() {
        assertNull(LensCorrection.choose(support()))
        assertNull(LensCorrection.choose(support(standard = emptyList(), vendor = emptyList())))
        assertNull(LensCorrection.choose(support(standard = listOf(0))))
    }

    @Test
    fun offOnlyIsNeverChosen() {
        assertNull(LensCorrection.choose(support(standard = listOf(0), key = true, vendor = listOf(0))))
    }

    @Test
    fun standardIgnoredBelowApi28ButVendorStillWorks() {
        assertNull(LensCorrection.choose(support(sdk = 27, standard = listOf(2))))
        assertEquals(
            LensCorrectionChoice.Vendor(1),
            LensCorrection.choose(support(sdk = 27, standard = listOf(2), key = true, vendor = listOf(1))),
        )
    }
}
