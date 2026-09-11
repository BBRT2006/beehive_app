package com.example.beehive_app

import android.content.Intent
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
            AlarmForegroundService.start(this, hiveName, hiveId)
        } catch (e: Exception) {
            Log.e("BeehiveFCM", "Could not start alarm foreground service", e)
        }
    }
}
