package com.voiceguard.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel

class PhoneStateReceiver : BroadcastReceiver() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        private const val CHANNEL_ID_CALL = "vaia_incoming_call"
        private const val NOTIF_ID_RINGING = 2001
        private const val NOTIF_ID_PROTECTION = 1001
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            TelephonyManager.ACTION_PHONE_STATE_CHANGED -> handlePhoneState(context, intent)
            Intent.ACTION_NEW_OUTGOING_CALL -> handleOutgoingCall(intent)
        }
    }

    private fun handlePhoneState(context: Context, intent: Intent) {
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val number = if (state == TelephonyManager.EXTRA_STATE_RINGING)
            intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
        else ""

        val eventState = when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> "ringing"
            TelephonyManager.EXTRA_STATE_OFFHOOK -> "offhook"
            TelephonyManager.EXTRA_STATE_IDLE    -> "idle"
            else -> return
        }

        // Flutter가 실행 중이면 즉시 EventChannel로 전달
        eventSink?.success(mapOf("state" to eventState, "number" to number))

        // 앱이 닫혀있을 때를 대비해 SharedPreferences에 상태 저장
        savePendingState(context, eventState, number)

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                // 앱 실행 (오버레이 권한 있으면 직접 실행, 없으면 알림으로 유도)
                launchApp(context)
                showIncomingCallNotification(context, number)

                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                if (!prefs.getBoolean("flutter.isProtectionOn", false)) {
                    showProtectionOffNotification(context)
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                dismissNotification(context, NOTIF_ID_RINGING)
                launchApp(context)
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                dismissNotification(context, NOTIF_ID_RINGING)
                clearPendingState(context)
            }
        }
    }

    private fun handleOutgoingCall(intent: Intent) {
        val number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER) ?: ""
        eventSink?.success(mapOf("state" to "outgoing", "number" to number))
    }

    // ── 앱 실행 ──────────────────────────────────────────────────────────────
    private fun launchApp(context: Context) {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP) }
            ?: return
        try { context.startActivity(launchIntent) } catch (_: Exception) { }
    }

    // ── 대기 상태 저장/삭제 ────────────────────────────────────────────────
    private fun savePendingState(context: Context, state: String, number: String) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.pendingCallState", state)
            .putString("flutter.pendingCallNumber", number)
            .apply()
    }

    private fun clearPendingState(context: Context) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .remove("flutter.pendingCallState")
            .remove("flutter.pendingCallNumber")
            .apply()
    }

    // ── 수신 전화 알림 (full-screen intent) ───────────────────────────────
    private fun showIncomingCallNotification(context: Context, number: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureCallChannel(manager)

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP) }

        val fullScreenPi = PendingIntent.getActivity(
            context, NOTIF_ID_RINGING, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val displayNumber = number.ifEmpty { "알 수 없는 번호" }
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_CALL)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("전화 수신 중 — Vaia 분석")
            .setContentText(displayNumber)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPi, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        manager.notify(NOTIF_ID_RINGING, notification)
    }

    private fun dismissNotification(context: Context, id: Int) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
    }

    private fun ensureCallChannel(manager: NotificationManager) {
        val channel = NotificationChannel(
            CHANNEL_ID_CALL, "Vaia 수신 전화", NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "전화 수신 시 보이스피싱 분석 알림" }
        manager.createNotificationChannel(channel)
    }

    // ── 보호 꺼짐 알림 ────────────────────────────────────────────────────
    private fun showProtectionOffNotification(context: Context) {
        val channelId = "vaia_protection"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(channelId, "Vaia 보호 알림", NotificationManager.IMPORTANCE_HIGH)
        )
        val openPi = PendingIntent.getActivity(
            context, 0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val msg = "현재 보호 상태가 꺼져 있어요! 앱에서 보호를 활성화하세요."
        manager.notify(
            NOTIF_ID_PROTECTION,
            NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("Vaia 보호 꺼짐")
                .setContentText(msg)
                .setStyle(NotificationCompat.BigTextStyle().bigText(msg))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(openPi)
                .build()
        )
    }
}
