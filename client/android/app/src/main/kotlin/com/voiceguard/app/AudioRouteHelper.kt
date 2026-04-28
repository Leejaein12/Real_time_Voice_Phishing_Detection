package com.voiceguard.app

import android.content.Context
import android.media.AudioManager

object AudioRouteHelper {
    fun enableSpeaker(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isSpeakerphoneOn = true
    }

    fun disableSpeaker(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.isSpeakerphoneOn = false
        am.mode = AudioManager.MODE_NORMAL
    }
}
