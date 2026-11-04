package com.motortrack.motor_track.push

import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The push side of the app: this phone's Firebase token, and taps on notifications. */
class PushChannel : MethodChannel.MethodCallHandler {
    var channel: MethodChannel? = null

    /** What a tapped notification asked to open, until the app takes it. */
    private var pending: Map<String, String?>? = null

    fun handleIntent(context: Context, intent: Intent?) {
        val what = intent?.getStringExtra(Notifications.EXTRA_OPEN) ?: return
        // Reopened from Recents: the old intent comes back. Don't act on it twice.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val alertId = intent.getStringExtra(Notifications.EXTRA_ALERT_ID)
        pending = mapOf(
            "open" to what,
            "alertId" to alertId,
            "vehicleId" to intent.getStringExtra(Notifications.EXTRA_VEHICLE_ID),
        )
        // A button tap doesn't dismiss the notification by itself.
        if (alertId != null) NotificationManagerCompat.from(context).cancel(Notifications.idFor(alertId))
        intent.removeExtra(Notifications.EXTRA_OPEN)
        channel?.invokeMethod("opened", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "token" ->
                try {
                    FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                        result.success(if (task.isSuccessful) task.result else null)
                    }
                } catch (e: Exception) {
                    // No Google Play services, or Firebase isn't set up.
                    result.success(null)
                }
            "takeOpenAction" -> {
                result.success(pending)
                pending = null
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val NAME = "motor_track/push"
    }
}
