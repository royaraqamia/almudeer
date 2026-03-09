package com.royaraqamia.almudeer

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        println("Almudeer: NotificationListener connected successfully")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Logging for verification
        // println("Almudeer: Notification received from ${sbn.packageName}")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Implement logic here if needed
    }
}

