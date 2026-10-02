package com.example.abooks_maker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ConversionForegroundService : Service() {
    companion object {
        const val ACTION_START = "com.example.abooks_maker.START"
        const val ACTION_UPDATE = "com.example.abooks_maker.UPDATE"
        const val ACTION_PAUSE = "com.example.abooks_maker.PAUSE"
        const val ACTION_RESUME = "com.example.abooks_maker.RESUME"
        const val ACTION_CANCEL = "com.example.abooks_maker.CANCEL"
        const val ACTION_STOP = "com.example.abooks_maker.STOP"
        const val COMMAND_KEY = "conversion.command"
        private const val CHANNEL_ID = "conversion_progress"
        private const val NOTIFICATION_ID = 1001
    }

    private var title = "有声书转换"
    private var progress = 0
    private var total = 0
    private var message = "正在准备"

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "转换进度",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { description = "有声书转换任务进度" }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                title = intent.getStringExtra("title") ?: title
                total = intent.getIntExtra("total", 0)
                progress = 0
                message = "正在准备"
                getPreferences().edit().remove(COMMAND_KEY).apply()
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_UPDATE -> {
                progress = intent?.getIntExtra("progress", progress) ?: progress
                total = intent?.getIntExtra("total", total) ?: total
                message = intent?.getStringExtra("message") ?: message
                updateNotification()
            }
            ACTION_PAUSE, ACTION_RESUME, ACTION_CANCEL -> {
                val command = when (intent.action) {
                    ACTION_PAUSE -> "pause"
                    ACTION_RESUME -> "resume"
                    else -> "cancel"
                }
                getPreferences().edit().putString(COMMAND_KEY, command).apply()
                updateNotification()
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun getPreferences() =
        getSharedPreferences("conversion_service", MODE_PRIVATE)

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val percent = if (total > 0) (progress * 100 / total).coerceIn(0, 100) else 0
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            1,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )
        val action = if (getPreferences().getString(COMMAND_KEY, null) == "pause") {
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_play,
                "继续",
                commandIntent(ACTION_RESUME)
            ).build()
        } else {
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_pause,
                "暂停",
                commandIntent(ACTION_PAUSE)
            ).build()
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("$message · $percent%")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, total == 0)
            .addAction(action)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "取消",
                    commandIntent(ACTION_CANCEL)
                ).build()
            )
            .build()
    }

    private fun commandIntent(action: String): PendingIntent = PendingIntent.getService(
        this,
        action.hashCode(),
        Intent(this, ConversionForegroundService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
    )

    private fun pendingIntentImmutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    override fun onBind(intent: Intent?): IBinder? = null
}
