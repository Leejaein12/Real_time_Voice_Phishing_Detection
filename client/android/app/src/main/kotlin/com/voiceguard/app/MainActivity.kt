package com.voiceguard.app

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannel = "vaia/audio"
    private val eventChannelName = "vaia/audioStream"

    private var audioEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "enableSpeaker" -> {
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        audioManager.isSpeakerphoneOn = true
                        result.success(true)
                    }
                    "disableSpeaker" -> {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.mode = AudioManager.MODE_NORMAL
                        result.success(true)
                    }
                    "startCapture" -> result.success(startAudioCapture())
                    "stopCapture" -> {
                        stopAudioCapture()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    audioEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                }
            })
    }

    private fun startAudioCapture(): Boolean {
        AudioForegroundService.audioChunkCallback = { chunk ->
            runOnUiThread { audioEventSink?.success(chunk) }
        }
        val intent = Intent(this, AudioForegroundService::class.java)
            .setAction(AudioForegroundService.ACTION_START)
        startForegroundService(intent)
        return true
    }

    private fun stopAudioCapture() {
        AudioForegroundService.audioChunkCallback = null
        val intent = Intent(this, AudioForegroundService::class.java)
            .setAction(AudioForegroundService.ACTION_STOP)
        startService(intent)
    }
}
