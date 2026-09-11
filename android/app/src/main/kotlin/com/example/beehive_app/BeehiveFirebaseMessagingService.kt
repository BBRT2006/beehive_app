package com.example.beehive_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Native FCM receiver. Data-only, high-priority theft messages arrive here even
 * when the Flutter UI/process is not running. It immediately starts the native
 * foreground alarm service.
 */
class BeehiveFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val data = remoteMessage.data
        val title = data["title"] ?: remoteMessage.notification?.title.orEmpty()
        val type = data["type"].orEmpty()

        val isTheft =
            type.equals("theft", ignoreCase = true) ||
                title.contains("ΚΛΟΠΗ", ignoreCase = true) ||
                title.contains("THEFT", ignoreCase = true) ||
                title.contains("ΣΥΝΑΓΕΡΜΟΣ", ignoreCase = true)

        if (!isTheft) return

        val hiveName = data["hive_name"] ?: "Κυψέλη"
        val hiveId = data["hive_id"] ?: ""

        Log.i(
            "BeehiveFCM",
            "Theft FCM received. messageId=${remoteMessage.messageId}, " +
                "priority=${remoteMessage.priority}, hive=$hiveName"
        )

        try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.stop_alarm", false)
                .apply()
            showTheftNotification(remoteMessage, hiveName)
            AlarmForegroundService.start(this, hiveName, hiveId)
        } catch (e: Exception) {
            Log.e("BeehiveFCM", "Could not start alarm foreground service", e)
        }
    }

    private fun showTheftNotification(remoteMessage: RemoteMessage, hiveName: String) {
        val channelId = "theft_alerts"
        val manager = getSystemService(NotificationManager::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Ειδοποιήσεις κλοπής",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Συναγερμοί κλοπής κυψελών"
                    enableVibration(true)
                }
            )
        }

        val title = remoteMessage.data["title"]
            ?: remoteMessage.notification?.title
            ?: "Συναγερμός κλοπής"
        val body = remoteMessage.data["body"]
            ?: remoteMessage.notification?.body
            ?: "Ελέγξτε την κυψέλη $hiveName"
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        contentIntent?.let { builder.setContentIntent(it) }
        manager.notify(remoteMessage.messageId?.hashCode() ?: System.currentTimeMillis().toInt(), builder.build())
    }
}
