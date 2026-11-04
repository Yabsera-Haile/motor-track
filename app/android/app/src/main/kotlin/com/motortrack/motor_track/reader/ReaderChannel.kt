package com.motortrack.motor_track.reader

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** What the app can ask the Android side to do: permissions and the Reader. */
class ReaderChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    /** Permission requests waiting for the user's answer, by request code. */
    private val pending = HashMap<Int, MethodChannel.Result>()
    private val store get() = ReaderStore(activity)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasSmsPermission" -> result.success(ReaderWorker.hasSmsPermission(activity))
                "requestSmsPermission" ->
                    if (ReaderWorker.hasSmsPermission(activity)) {
                        result.success(true)
                    } else {
                        ask(SMS_REQUEST, arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS), result)
                    }
                "hasNotificationPermission" -> result.success(notificationsAllowed())
                "requestNotificationPermission" ->
                    // Before Android 13 there is no prompt: notifications are on unless turned off in Settings.
                    if (notificationsAllowed() || Build.VERSION.SDK_INT < 33) {
                        result.success(notificationsAllowed())
                    } else {
                        ask(NOTIFY_REQUEST, arrayOf(Manifest.permission.POST_NOTIFICATIONS), result)
                    }
                "listSenders" -> result.success(listSenders())
                "messages" -> result.success(messages(call.argument<String>("sender")!!, call.argument<Int>("limit") ?: 50))
                "configure" -> {
                    val s = store
                    s.url = call.argument("url")
                    s.publishableKey = call.argument("publishableKey")
                    s.readerKey = call.argument("readerKey")
                    s.sender = call.argument("sender")
                    s.regex = call.argument("regex")
                    s.groups = call.argument<List<String>>("groups") ?: emptyList()
                    s.usernames = (call.argument<List<String>>("usernames") ?: emptyList()).map(ReaderParser::normName).toSet()
                    s.checkpointMillis = call.argument<Number>("checkpointMillis")?.toLong() ?: System.currentTimeMillis()
                    s.unreadable = 0
                    s.lastError = null
                    s.enabled = true
                    ReaderWorker.schedulePeriodic(activity)
                    ReaderWorker.runNow(activity)
                    result.success(true)
                }
                "updateUsernames" -> {
                    store.usernames = (call.argument<List<String>>("usernames") ?: emptyList()).map(ReaderParser::normName).toSet()
                    result.success(true)
                }
                "disable" -> {
                    ReaderWorker.cancel(activity)
                    store.clear()
                    result.success(true)
                }
                "runNow" -> {
                    if (store.enabled) ReaderWorker.runNow(activity)
                    result.success(store.enabled)
                }
                "status" -> {
                    val s = store
                    result.success(
                        mapOf(
                            "enabled" to s.enabled,
                            "sender" to s.sender,
                            "lastRunMillis" to s.lastRunMillis,
                            "lastResult" to s.lastResult,
                            "lastError" to s.lastError,
                            "unreadable" to s.unreadable,
                            "queued" to s.queue().size,
                            "uploadedTotal" to s.uploadedTotal,
                            "hasSmsPermission" to ReaderWorker.hasSmsPermission(activity),
                            "ignoringBatteryOptimizations" to ignoringBattery(),
                        ),
                    )
                }
                "isIgnoringBatteryOptimizations" -> result.success(ignoringBattery())
                "requestIgnoreBatteryOptimizations" -> {
                    if (!ignoringBattery()) {
                        activity.startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${activity.packageName}")),
                        )
                    }
                    result.success(true)
                }
                "openAppSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", "SMS permission is off", null)
        } catch (e: Exception) {
            result.error("reader", e.message, null)
        }
    }

    private fun ask(code: Int, permissions: Array<String>, result: MethodChannel.Result) {
        pending.remove(code)?.success(false)
        pending[code] = result
        ActivityCompat.requestPermissions(activity, permissions, code)
    }

    fun onPermissionResult(requestCode: Int): Boolean {
        val result = pending.remove(requestCode) ?: return false
        result.success(
            when (requestCode) {
                SMS_REQUEST -> ReaderWorker.hasSmsPermission(activity)
                else -> notificationsAllowed()
            },
        )
        return true
    }

    private fun notificationsAllowed(): Boolean = NotificationManagerCompat.from(activity).areNotificationsEnabled()

    private fun ignoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = activity.getSystemService(PowerManager::class.java)
        return pm.isIgnoringBatteryOptimizations(activity.packageName)
    }

    /** Senders in the inbox with how many messages each, busiest first. */
    private fun listSenders(): List<Map<String, Any?>> {
        data class Agg(var count: Int, val latestBody: String, val latestDate: Long)
        val byAddress = LinkedHashMap<String, Agg>()
        activity.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("address", "body", "date"),
            null,
            null,
            "date DESC",
        )?.use { c ->
            val a = c.getColumnIndexOrThrow("address")
            val b = c.getColumnIndexOrThrow("body")
            val d = c.getColumnIndexOrThrow("date")
            var seen = 0
            while (c.moveToNext() && seen < 3000) {
                seen++
                val address = c.getString(a) ?: continue
                val agg = byAddress[address]
                if (agg == null) byAddress[address] = Agg(1, c.getString(b) ?: "", c.getLong(d)) else agg.count++
            }
        }
        return byAddress.entries
            .sortedByDescending { it.value.count }
            .take(40)
            .map { mapOf("address" to it.key, "count" to it.value.count, "latestBody" to it.value.latestBody, "latestDate" to it.value.latestDate) }
    }

    /** Recent messages from one sender, newest first. */
    private fun messages(sender: String, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("address", "body", "date"),
            null,
            null,
            "date DESC",
        )?.use { c ->
            val a = c.getColumnIndexOrThrow("address")
            val b = c.getColumnIndexOrThrow("body")
            val d = c.getColumnIndexOrThrow("date")
            while (c.moveToNext() && out.size < limit) {
                if (c.getString(a)?.equals(sender, ignoreCase = true) == true) {
                    out.add(mapOf("body" to (c.getString(b) ?: ""), "date" to c.getLong(d)))
                }
            }
        }
        return out
    }

    companion object {
        const val NAME = "motor_track/reader"
        private const val SMS_REQUEST = 4711
        private const val NOTIFY_REQUEST = 4712
    }
}
