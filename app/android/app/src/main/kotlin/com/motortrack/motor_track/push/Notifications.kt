package com.motortrack.motor_track.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.motortrack.motor_track.MainActivity
import com.motortrack.motor_track.R

/** Draws payment alerts sent by the database (through the `push` Edge Function). */
object Notifications {
    const val CHANNEL = "alerts"
    const val EXTRA_OPEN = "motor_track.open"
    const val EXTRA_ALERT_ID = "motor_track.alert_id"
    const val EXTRA_VEHICLE_ID = "motor_track.vehicle_id"

    /** Alert types about one driver, where "Message driver" makes sense. */
    private val DRIVER_TYPES = setOf("unpaid_deadline", "short_deadline", "missed_day", "overpayment")

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Payment alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Late, short and missed payments, overpayments and Reader problems"
            },
        )
    }

    fun show(context: Context, data: Map<String, String>) {
        val title = data["title"] ?: return
        val body = data["body"].orEmpty()
        val type = data["type"].orEmpty()
        val alertId = data["alert_id"]
        val vehicleId = data["vehicle_id"]
        // One notification per alert or payment: the same one pushed twice replaces itself.
        val key = alertId ?: data["payment_id"] ?: "$type:$title"
        ensureChannel(context)

        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alert)
            .setColor(0xFF111418.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(
                when (type) {
                    "test" -> open(context, "home", key)
                    "payment" -> open(context, "vehicle", key, vehicleId = vehicleId)
                    else -> open(context, "alerts", key, alertId = alertId)
                },
            )

        if (alertId != null && type in DRIVER_TYPES && vehicleId != null) {
            builder.addAction(0, "Message driver", open(context, "message", key, alertId = alertId))
        }

        try {
            NotificationManagerCompat.from(context).notify(idFor(key), builder.build())
        } catch (e: SecurityException) {
            // Notifications are turned off for the app. The alert is still in the in-app list.
            Log.w("MotorTrackPush", "Notification not allowed", e)
        }
    }

    fun idFor(key: String) = key.hashCode()

    private fun open(
        context: Context,
        what: String,
        key: String,
        alertId: String? = null,
        vehicleId: String? = null,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            // A distinct URI per notification and button, so Android keeps each PendingIntent apart.
            data = Uri.parse("motortrack://open/${Uri.encode(key)}/$what")
            putExtra(EXTRA_OPEN, what)
            putExtra(EXTRA_ALERT_ID, alertId)
            putExtra(EXTRA_VEHICLE_ID, vehicleId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
