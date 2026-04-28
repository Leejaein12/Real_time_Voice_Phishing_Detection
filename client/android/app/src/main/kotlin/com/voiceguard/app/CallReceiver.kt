package com.voiceguard.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat

class CallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return

        // Flutter SharedPreferences 키: "flutter.isProtectionOn"
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isProtectionOn = prefs.getBoolean("flutter.isProtectionOn", false)

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (!isProtectionOn) {
                    showNotification(
                        context,
                        title = "Vaia 보호 꺼짐",
                        message = "현재 보호 상태가 켜지지 않았어요! 앱에서 보호를 활성화하세요.",
                        notifId = 1001,
                    )
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                if (isProtectionOn) {
                    // 통화 연결 시 앱 실행 (포그라운드로 올려서 오버레이 시작)
                    val launchIntent = context.packageManager
                        .getLaunchIntentForPackage(context.packageName)
                        ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    if (launchIntent != null) context.startActivity(launchIntent)
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                // 통화 종료 — 별도 처리 없음 (오버레이는 앱에서 관리)
            }
        }
    }

    private fun showNotification(context: Context, title: String, message: String, notifId: Int) {
        val channelId = "vaia_protection"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channel = NotificationChannel(
            channelId, "Vaia 보호 알림", NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "보이스피싱 보호 상태 알림" }
        manager.createNotificationChannel(channel)

        val openAppIntent = PendingIntent.getActivity(
            context, 0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent)
            .build()

        manager.notify(notifId, notification)
    }
}
