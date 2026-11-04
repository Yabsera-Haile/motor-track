package com.motortrack.motor_track.reader

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** An SMS waiting to be read and uploaded. */
data class QueuedSms(val address: String, val body: String, val dateMillis: Long)

/**
 * The Reader's settings and progress on this phone, shared by the app, the SMS
 * receiver and the background job. Written by the app through ReaderChannel.
 */
class ReaderStore(context: Context) {
    private val prefs = context.getSharedPreferences("motor_track_reader", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) = prefs.edit().putBoolean("enabled", v).apply()

    var url: String? by string("url")
    var publishableKey: String? by string("publishable_key")
    var readerKey: String? by string("reader_key")
    var sender: String? by string("sender")
    var regex: String? by string("regex")
    var lastError: String? by string("last_error")
    var lastResult: String? by string("last_result")

    var groups: List<String>
        get() = prefs.getString("groups", "")!!.split(',').filter { it.isNotEmpty() }
        set(v) = prefs.edit().putString("groups", v.joinToString(",")).apply()

    /** Normalized MoMo usernames of registered vehicles. Everything else is ignored. */
    var usernames: Set<String>
        get() = prefs.getString("usernames", "")!!.split('\n').filter { it.isNotEmpty() }.toSet()
        set(v) = prefs.edit().putString("usernames", v.joinToString("\n")).apply()

    /** Inbox messages newer than this have not been looked at yet. */
    var checkpointMillis: Long
        get() = prefs.getLong("checkpoint", 0L)
        set(v) = prefs.edit().putLong("checkpoint", v).apply()

    var lastRunMillis: Long
        get() = prefs.getLong("last_run", 0L)
        set(v) = prefs.edit().putLong("last_run", v).apply()

    /** M-Money messages that looked like money received but didn't fit the template. */
    var unreadable: Int
        get() = prefs.getInt("unreadable", 0)
        set(v) = prefs.edit().putInt("unreadable", v).apply()

    var uploadedTotal: Int
        get() = prefs.getInt("uploaded_total", 0)
        set(v) = prefs.edit().putInt("uploaded_total", v).apply()

    /** Recently handled messages (FT Id, or a body hash), so they are not sent twice. */
    var recent: List<String>
        get() = prefs.getString("recent", "")!!.split('\n').filter { it.isNotEmpty() }
        set(v) = prefs.edit().putString("recent", v.takeLast(500).joinToString("\n")).apply()

    @Synchronized
    fun queue(): List<QueuedSms> {
        val arr = JSONArray(prefs.getString("queue", "[]"))
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            QueuedSms(o.getString("address"), o.getString("body"), o.getLong("date"))
        }
    }

    @Synchronized
    fun setQueue(items: List<QueuedSms>) {
        val arr = JSONArray()
        for (s in items.takeLast(200)) {
            arr.put(JSONObject().put("address", s.address).put("body", s.body).put("date", s.dateMillis))
        }
        prefs.edit().putString("queue", arr.toString()).commit()
    }

    @Synchronized
    fun addToQueue(items: List<QueuedSms>) {
        val all = queue().toMutableList()
        for (s in items) if (all.none { it.body == s.body && it.address == s.address }) all.add(s)
        setQueue(all)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    private fun string(key: String) = object : kotlin.properties.ReadWriteProperty<Any?, String?> {
        override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): String? = prefs.getString(key, null)
        override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: String?) {
            prefs.edit().putString(key, value).apply()
        }
    }
}
