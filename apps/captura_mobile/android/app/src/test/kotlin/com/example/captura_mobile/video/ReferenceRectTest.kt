package com.example.captura_mobile.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ReferenceRectTest {
    private fun p(x: Double, y: Double) = ReferencePoint(x, y)

    // 0.30 x 0.2975 of a 16:9 frame is 384 x 214 px, an A4-like 1.79 ratio is not needed: orient only picks the longer pair.
    private val quad = listOf(p(0.30, 0.30), p(0.60, 0.30), p(0.60, 0.5975), p(0.30, 0.5975))

    @Test fun orientStartsOnTheLongSide() {
        val corners = ReferenceRect.orient(quad, 0.297, 0.210, 1280, 720)
        assertEquals(4, corners.size)
        assertEquals(quad[0], corners[0])
        assertEquals(quad[1], corners[1])
        assertEquals(quad[2], corners[2])
    }

    @Test fun orientRotatesWhenTheLongSideIsTheOtherPair() {
        // Same rectangle listed starting on the short side: 0->1 is short (vertical), 1->2 is long.
        val tall = listOf(p(0.60, 0.30), p(0.60, 0.5975), p(0.30, 0.5975), p(0.30, 0.30))
        val corners = ReferenceRect.orient(tall, 0.297, 0.210, 1280, 720)
        assertEquals(tall[1], corners[0])
        assertEquals(tall[2], corners[1])
        assertEquals(tall[3], corners[2])
        assertEquals(tall[0], corners[3])
    }

    @Test fun orientMeasuresSidesInFramePixelsNotNormalisedUnits() {
        // Normalised 0.20 x 0.30 is 256 x 216 px: the horizontal pair is the long one even though 0.30 > 0.20.
        val q = listOf(p(0.40, 0.10), p(0.60, 0.10), p(0.60, 0.40), p(0.40, 0.40))
        val corners = ReferenceRect.orient(q, 0.297, 0.210, 1280, 720)
        assertEquals(q[0], corners[0])
        assertEquals(q[1], corners[1])
    }

    @Test fun orientMeasuresSidesOnTheStoredFrameOfEachSize() {
        // Normalised 0.20 x 0.30: on a 16:9 frame it is 256 x 216 px (the horizontal pair is long), on a 4:3 frame
        // it is 288 x 324 px (the vertical pair is long). The same quad gets a different start corner.
        val q = listOf(p(0.40, 0.10), p(0.60, 0.10), p(0.60, 0.40), p(0.40, 0.40))
        val on169 = ReferenceRect.orient(q, 0.297, 0.210, 1280, 720)
        assertEquals(q[0], on169[0])
        val on43 = ReferenceRect.orient(q, 0.297, 0.210, 1440, 1080)
        assertEquals(q[1], on43[0])
        assertEquals(q[2], on43[1])
    }

    private fun build(source: ReferenceRectSource = ReferenceRectSource.AUTO): ReferenceMark {
        val corners = ReferenceRect.orient(quad, 0.297, 0.210, 1280, 720)
        val rect = ReferenceRect.create(0.297, 0.210, corners, source)
        return ReferenceMark.create(5L, corners[0], corners[1], 0.297, "Hoja A4", ReferenceSurface.WALL, rect)
    }

    @Suppress("UNCHECKED_CAST")
    @Test fun manifestCarriesRectWithEveryInvariant() {
        val map = build(ReferenceRectSource.ADJUSTED).toMap()
        val rect = map["rect"] as Map<String, Any?>
        assertEquals(0.297, rect["widthM"])
        assertEquals(0.210, rect["heightM"])
        assertEquals("adjusted", rect["source"])
        assertEquals(map["lengthM"], rect["widthM"])
        val corners = rect["corners"] as List<Map<String, Any?>>
        assertEquals(4, corners.size)
        assertEquals(map["p1"], corners[0])
        assertEquals(map["p2"], corners[1])
        assertTrue(corners.all { (it["x"] as Double) in 0.0..1.0 && (it["y"] as Double) in 0.0..1.0 })
        assertTrue((rect["widthM"] as Double) >= (rect["heightM"] as Double))
    }

    @Test fun sourceWireNamesFollowTheContract() {
        assertEquals(listOf("auto", "adjusted", "manual"), ReferenceRectSource.values().map { it.wireName })
    }

    @Test fun manualTwoPointReferenceHasNoRect() {
        val m = ReferenceMark.create(1L, p(0.1, 0.1), p(0.5, 0.5), 1.0, "x", ReferenceSurface.WALL)
        assertFalse(m.toMap().containsKey("rect"))
    }

    @Test fun rejectsHeightLongerThanWidth() {
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.2, 0.3, quad, ReferenceRectSource.AUTO) }
    }

    @Test fun rejectsNonPositiveOrNaNSides() {
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.3, 0.0, quad, ReferenceRectSource.AUTO) }
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(Double.NaN, 0.1, quad, ReferenceRectSource.AUTO) }
    }

    @Test fun rejectsWrongCornerCountOrOutOfRange() {
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.3, 0.2, quad.take(3), ReferenceRectSource.AUTO) }
        val off = quad.toMutableList().also { it[2] = p(1.2, 0.5) }
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.3, 0.2, off, ReferenceRectSource.AUTO) }
    }

    @Test fun rejectsABowTieOrDentedRing() {
        val bowTie = listOf(p(0.3, 0.3), p(0.6, 0.6), p(0.6, 0.3), p(0.3, 0.6))
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.3, 0.2, bowTie, ReferenceRectSource.AUTO) }
        val dent = listOf(p(0.3, 0.3), p(0.6, 0.3), p(0.45, 0.4), p(0.3, 0.6))
        assertThrows(IllegalArgumentException::class.java) { ReferenceRect.create(0.3, 0.2, dent, ReferenceRectSource.AUTO) }
    }

    @Test fun rejectsRectIncoherentWithMark() {
        val corners = ReferenceRect.orient(quad, 0.297, 0.210, 1280, 720)
        val rect = ReferenceRect.create(0.297, 0.210, corners, ReferenceRectSource.AUTO)
        // widthM != lengthM
        assertThrows(IllegalArgumentException::class.java) {
            ReferenceMark.create(5L, corners[0], corners[1], 0.30, "x", ReferenceSurface.WALL, rect)
        }
        // corners[0] != p1
        assertThrows(IllegalArgumentException::class.java) {
            ReferenceMark.create(5L, corners[1], corners[0], 0.297, "x", ReferenceSurface.WALL, rect)
        }
    }

    @Test fun presetsExposeBothSidesOnlyWhenKnown() {
        val a4 = ReferencePresets.ALL.first { it.label.contains("A4") }
        assertEquals(0.210, a4.otherSideM!!, 1e-9)
        val card = ReferencePresets.ALL.first { it.label.contains("Tarjeta") }
        assertEquals(0.05398, card.otherSideM!!, 1e-9)
        assertNull(ReferencePresets.ALL.first { it.label.contains("Puerta") }.otherSideM)
    }
}
