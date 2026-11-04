package com.motortrack.motor_track.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives alerts from Firebase, even when the app is closed. The messages are
 * data only, so this draws every notification itself (see [Notifications]).
 */
class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        Notifications.show(this, message.data)
    }

    override fun onNewToken(token: String) {
        // Nothing to do here: the app sends its current token to the database
        // every time it opens (lib/push/push_service.dart).
    }
}
