package com.jmreader.jm_reader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 下载前台服务：仅用于把进程提升为前台，避免后台下载时被系统冻结/回收。
 * 真正的下载逻辑仍在 Flutter 侧执行。
 */
class DownloadForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "jm_download_fg"
        private const val CHANNEL_NAME = "后台下载"
        private const val NOTIFICATION_ID = 2001
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "EAX管理器"
        val text = intent?.getStringExtra("text") ?: "正在下载"

        createChannel()

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_jm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "下载期间保持后台运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
