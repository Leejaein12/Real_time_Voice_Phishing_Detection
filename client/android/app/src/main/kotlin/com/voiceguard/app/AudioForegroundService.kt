package com.voiceguard.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

class AudioForegroundService : Service() {

    companion object {
        const val ACTION_START = "vaia.START_CAPTURE"
        const val ACTION_STOP = "vaia.STOP_CAPTURE"
        const val CHANNEL_ID = "vaia_audio_capture"
        const val NOTIF_ID = 2001

        var audioChunkCallback: ((ByteArray) -> Unit)? = null
    }

    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundNotification()
                startCapture()
            }
            ACTION_STOP -> {
                stopCapture()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun startForegroundNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, "Vaia 오디오 분석", NotificationManager.IMPORTANCE_LOW)
            .apply { description = "보이스피싱 실시간 탐지 중" }
        manager.createNotificationChannel(channel)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Vaia 보호 중")
            .setContentText("실시간 보이스피싱 탐지 활성화")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    private fun startCapture() {
        if (isRecording.get()) return

        val sampleRate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = minBuf * 4

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                stopSelf()
                return
            }

            audioRecord?.startRecording()
            isRecording.set(true)

            recordingThread = Thread {
                val buf = ByteArray(bufferSize)
                while (isRecording.get()) {
                    val read = audioRecord?.read(buf, 0, buf.size) ?: break
                    if (read > 0) {
                        audioChunkCallback?.invoke(buf.copyOf(read))
                    }
                }
            }.also { it.start() }

        } catch (e: Exception) {
            stopSelf()
        }
    }

    private fun stopCapture() {
        isRecording.set(false)
        recordingThread?.join(1000)
        recordingThread = null
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }
}
