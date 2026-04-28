package com.voiceguard.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                // CE storage available; check user preference
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (prefs.getBoolean("flutter.isProtectionOn", false)) {
                    startMonitorService(context)
                }
            }
            "android.intent.action.LOCKED_BOOT_COMPLETED" -> {
                // Direct boot: CE storage not yet available; start unconditionally
                startMonitorService(context)
            }
        }
    }

    private fun startMonitorService(context: Context) {
        val intent = Intent(context, CallMonitorService::class.java)
        context.startForegroundService(intent)
    }
}
