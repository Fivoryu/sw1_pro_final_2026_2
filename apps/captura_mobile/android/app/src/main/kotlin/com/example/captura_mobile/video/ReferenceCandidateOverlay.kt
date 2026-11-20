package com.example.captura_mobile.video

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/** Non-interactive candidate outline. Actual adjustment/confirmation uses the encoded MP4 frame. */
internal class ReferenceCandidateOverlay(context: Context) : View(context) {
    var corners: List<ReferencePoint>? = null
        set(value) { field = value; invalidate() }
    var rotationDegrees = 0
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.YELLOW; strokeWidth = 3 * resources.displayMetrics.density; style = Paint.Style.STROKE
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val points = corners ?: return
        val path = Path()
        for ((i, point) in points.withIndex()) {
            val (x, y) = PreviewGeometry.storedToDisplay(rotationDegrees, point.x, point.y)
            if (i == 0) path.moveTo(x.toFloat() * width, y.toFloat() * height)
            else path.lineTo(x.toFloat() * width, y.toFloat() * height)
            canvas.drawCircle(x.toFloat() * width, y.toFloat() * height, 5 * resources.displayMetrics.density, paint)
        }
        path.close(); canvas.drawPath(path, paint)
    }
}
