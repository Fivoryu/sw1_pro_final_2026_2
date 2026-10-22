package com.example.captura_mobile.ar

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/**
 * Speaks and vibrates walkthrough guidance so the agent does not have to read the screen. Uses the offline
 * system text-to-speech engine; when no Spanish voice is available it stays silent and the on-screen text
 * remains the source of guidance.
 */
class GuidanceFeedback(context: Context) {

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Vibrator::class.java)
    }

    @Volatile
    private var speechReady = false

    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        if (status != TextToSpeech.SUCCESS) return@TextToSpeech
        val result = engine().setLanguage(Locale.forLanguageTag("es"))
        speechReady = result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
        if (!speechReady) Log.w(TAG, "No Spanish text-to-speech voice; guidance stays on screen only")
    }

    private fun engine(): TextToSpeech = tts

    fun speak(message: String) {
        if (!speechReady) return
        tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID)
    }

    /** Short tick, for example when a new wall is registered. */
    fun tick() = vibrate(TICK_MS)

    /** Longer pulse for warnings such as moving too fast. */
    fun warn() = vibrate(WARN_MS)

    fun shutdown() {
        tts.stop()
        tts.shutdown()
    }

    private fun vibrate(durationMs: Long) {
        val target = vibrator ?: return
        if (!target.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            target.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            target.vibrate(durationMs)
        }
    }

    private companion object {
        const val TAG = "GuidanceFeedback"
        const val UTTERANCE_ID = "walkthrough-guidance"
        const val TICK_MS = 30L
        const val WARN_MS = 120L
    }
}
