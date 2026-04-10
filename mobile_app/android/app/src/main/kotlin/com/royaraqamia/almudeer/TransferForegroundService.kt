package com.royaraqamia.almudeer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service for handling file transfers in the background.
 * 
 * Features:
 * - Persistent notification showing transfer progress
 * - Continues operation when app is backgrounded
 * - Handles app kills gracefully
 * - Communicates with Flutter via MethodChannel
 */
class TransferForegroundService : Service() {
    
    companion object {
        const val CHANNEL_ID = "transfer_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "STOP_TRANSFER_SERVICE"
        
        // Notification actions
        const val ACTION_CANCEL_TRANSFER = "CANCEL_TRANSFER"
        const val ACTION_OPEN_APP = "OPEN_APP"
    }
    
    private val binder = LocalBinder()
    private var notificationManager: NotificationManager? = null
    private var currentProgress = 0
    private var isTransferring = false
    
    inner class LocalBinder : Binder() {
        fun getService(): TransferForegroundService = this@TransferForegroundService
    }
    
    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }
    
    override fun onBind(intent: Intent?): IBinder {
        return binder
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CANCEL_TRANSFER -> {
                // Notify Flutter about cancel request
                sendBroadcast(Intent("com.almudeer.TRANSFER_CANCEL"))
                return START_STICKY
            }
            else -> {
                // Start foreground service with initial notification
                val title = intent?.getStringExtra("title") ?: "Transferring files"
                val body = intent?.getStringExtra("body") ?: "File transfer in progress"
                
                startForeground(NOTIFICATION_ID, createNotification(title, body, 0))
                isTransferring = true
            }
        }
        
        return START_STICKY
    }
    
    /**
     * Create notification channel for Android O and above
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress of file transfers"
                setSound(null, null)
                enableVibration(false)
            }
            
            notificationManager?.createNotificationChannel(channel)
        }
    }
    
    /**
     * Create the foreground notification
     */
    private fun createNotification(title: String, body: String, progress: Int): Notification {
        // Intent to open app when notification is clicked
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_APP
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Cancel action
        val cancelIntent = Intent(this, TransferForegroundService::class.java).apply {
            action = ACTION_CANCEL_TRANSFER
        }
        
        val cancelPendingIntent = PendingIntent.getService(
            this,
            1,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(openAppPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, progress == 0)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
            .build()
    }
    
    /**
     * Update notification progress
     */
    fun updateProgress(progress: Int, title: String? = null, body: String? = null) {
        currentProgress = progress
        
        val notificationTitle = title ?: "Transferring files"
        val notificationBody = body ?: if (progress < 100) {
            "Transfer in progress: $progress%"
        } else {
            "Transfer complete"
        }
        
        val notification = createNotification(notificationTitle, notificationBody, progress)
        notificationManager?.notify(NOTIFICATION_ID, notification)
    }
    
    /**
     * Update to completion notification
     */
    fun showCompletionNotification(success: Boolean, fileName: String) {
        isTransferring = false
        
        val title = if (success) "Transfer Complete" else "Transfer Failed"
        val body = if (success) {
            "Successfully transferred $fileName"
        } else {
            "Failed to transfer $fileName"
        }
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_notification)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        
        notificationManager?.notify(NOTIFICATION_ID + 1, notification)
        
        // Stop foreground service after a delay
        stopForeground(false)
        stopSelf()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        isTransferring = false
    }
}
