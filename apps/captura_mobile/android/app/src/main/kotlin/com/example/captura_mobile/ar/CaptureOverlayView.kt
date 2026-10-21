package com.example.captura_mobile.ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.view.View

/** A labelled segment in view pixels. */
data class OverlaySegment(
    val start: ScreenPoint,
    val end: ScreenPoint,
    val label: String?,
    val dashed: Boolean,
)

/** Immutable snapshot of what the overlay draws; produced on the GL thread, drawn on the UI thread. */
data class OverlayModel(
    val corners: List<ScreenPoint>,
    val segments: List<OverlaySegment>,
    val boxPoints: List<ScreenPoint>,
    val boxSegments: List<OverlaySegment>,
    val reticleOnFloor: Boolean,
    /** Shown instead of the room polygon when it cannot be computed (Spanish). */
    val notice: String? = null,
) {
    companion object {
        val EMPTY = OverlayModel(emptyList(), emptyList(), emptyList(), emptyList(), false)
    }
}

/** Draws the reticle, marked wall points and lines, the derived polygon with lengths and furniture footprints. */
class CaptureOverlayView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density

    private val reticlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.5f * density
    }
    private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(255, 193, 7) }
    private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(255, 193, 7)
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
    }
    private val dashedEdgePaint = Paint(edgePaint).apply {
        pathEffect = DashPathEffect(floatArrayOf(12f * density, 8f * density), 0f)
    }
    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(3, 169, 244)
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
    }
    private val boxPointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(3, 169, 244) }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 14f * density
        textAlign = Paint.Align.CENTER
    }
    private val labelBackground = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(170, 0, 0, 0) }

    private var model: OverlayModel = OverlayModel.EMPTY

    fun update(next: OverlayModel) {
        model = next
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val current = model
        for (segment in current.segments) drawSegment(canvas, segment, if (segment.dashed) dashedEdgePaint else edgePaint)
        for (segment in current.boxSegments) drawSegment(canvas, segment, boxPaint)
        for (corner in current.corners) canvas.drawCircle(corner.x, corner.y, 7f * density, cornerPaint)
        for (point in current.boxPoints) canvas.drawCircle(point.x, point.y, 6f * density, boxPointPaint)
        drawReticle(canvas, current.reticleOnFloor)
        current.notice?.let { drawNotice(canvas, it) }
    }

    /** Wraps the notice above the reticle on a dark background. */
    private fun drawNotice(canvas: Canvas, notice: String) {
        val maxWidth = width - 48f * density
        val lines = mutableListOf<String>()
        var line = ""
        for (word in notice.split(' ')) {
            val candidate = if (line.isEmpty()) word else "$line $word"
            if (line.isNotEmpty() && labelPaint.measureText(candidate) > maxWidth) {
                lines.add(line)
                line = word
            } else {
                line = candidate
            }
        }
        if (line.isNotEmpty()) lines.add(line)
        val lineHeight = labelPaint.descent() - labelPaint.ascent()
        val cx = width / 2f
        val bottom = height / 2f - 48f * density
        val top = bottom - lines.size * lineHeight - 12f * density
        val halfWidth = (lines.maxOf { labelPaint.measureText(it) } / 2f) + 10f * density
        canvas.drawRoundRect(cx - halfWidth, top, cx + halfWidth, bottom, 8f * density, 8f * density, labelBackground)
        lines.forEachIndexed { index, text ->
            canvas.drawText(text, cx, top + 6f * density - labelPaint.ascent() + index * lineHeight, labelPaint)
        }
    }

    private fun drawSegment(canvas: Canvas, segment: OverlaySegment, paint: Paint) {
        canvas.drawLine(segment.start.x, segment.start.y, segment.end.x, segment.end.y, paint)
        val label = segment.label ?: return
        val midX = (segment.start.x + segment.end.x) / 2f
        val midY = (segment.start.y + segment.end.y) / 2f
        val halfWidth = labelPaint.measureText(label) / 2f + 6f * density
        val ascent = labelPaint.ascent()
        val descent = labelPaint.descent()
        canvas.drawRoundRect(
            midX - halfWidth,
            midY + ascent - 4f * density,
            midX + halfWidth,
            midY + descent + 4f * density,
            6f * density,
            6f * density,
            labelBackground,
        )
        canvas.drawText(label, midX, midY, labelPaint)
    }

    private fun drawReticle(canvas: Canvas, onFloor: Boolean) {
        val cx = width / 2f
        val cy = height / 2f
        val radius = 16f * density
        reticlePaint.color = if (onFloor) Color.rgb(76, 175, 80) else Color.WHITE
        canvas.drawCircle(cx, cy, radius, reticlePaint)
        canvas.drawLine(cx - radius * 1.6f, cy, cx - radius * 0.5f, cy, reticlePaint)
        canvas.drawLine(cx + radius * 0.5f, cy, cx + radius * 1.6f, cy, reticlePaint)
        canvas.drawLine(cx, cy - radius * 1.6f, cx, cy - radius * 0.5f, reticlePaint)
        canvas.drawLine(cx, cy + radius * 0.5f, cx, cy + radius * 1.6f, reticlePaint)
    }
}
