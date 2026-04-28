package com.voiceguard.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val methodChannelName = "vaia/audio"
    private val eventChannelName = "vaia/phone_state"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSpeaker" -> {
                        AudioRouteHelper.enableSpeaker(this)
                        result.success(true)
                    }
                    "disableSpeaker" -> {
                        AudioRouteHelper.disableSpeaker(this)
                        result.success(true)
                    }
                    "checkPermissions" -> result.success(checkPermissions())
                    "openBatterySettings" -> {
                        openBatterySettings()
                        result.success(true)
                    }
                    "openOverlaySettings" -> {
                        openOverlaySettings()
                        result.success(true)
                    }
                    // Flutter가 준비되기 전에 수신된 전화 상태 복원
                    "getPendingCallState" -> {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        result.success(mapOf(
                            "state" to prefs.getString("flutter.pendingCallState", null),
                            "number" to (prefs.getString("flutter.pendingCallNumber", "") ?: ""),
                        ))
                    }
                    "clearPendingCallState" -> {
                        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                            .edit()
                            .remove("flutter.pendingCallState")
                            .remove("flutter.pendingCallNumber")
                            .apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    PhoneStateReceiver.eventSink = sink
                }
                override fun onCancel(args: Any?) {
                    PhoneStateReceiver.eventSink = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestRuntimePermissions()
        startCallMonitorService()
    }

    private fun requestRuntimePermissions() {
        val perms = mutableListOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.RECORD_AUDIO,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        ActivityCompat.requestPermissions(this, perms.toTypedArray(), 1001)
    }

    private fun startCallMonitorService() {
        startForegroundService(Intent(this, CallMonitorService::class.java))
    }

    private fun checkPermissions(): Map<String, Boolean> {
        val phone = checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val mic   = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val battery = (getSystemService(POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(packageName)
        val overlay = Settings.canDrawOverlays(this)
        return mapOf("phone" to phone, "microphone" to mic, "battery" to battery, "overlay" to overlay)
    }

    private fun openBatterySettings() {
        startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
        )
    }

    private fun openOverlaySettings() {
        startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
            }
        )
    }
}
