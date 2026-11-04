package com.motortrack.motor_track.reader

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SyncResult(val ok: Boolean, val error: String?, val usernames: List<String>)

/**
 * The two database functions a Reader phone calls in the background. Uses only
 * the publishable key plus this phone's Reader key, never the app's login.
 * Network problems throw IOException so the job can retry later.
 */
class ReaderApi(private val baseUrl: String, private val publishableKey: String) {

    fun sync(readerKey: String, unreadable: Int): SyncResult {
        val json = JSONObject(rpc("reader_sync", JSONObject().put("p_key", readerKey).put("p_unreadable", unreadable)))
        val names = json.optJSONArray("usernames")
        return SyncResult(
            ok = json.optBoolean("ok", false),
            error = json.optString("error").ifEmpty { null },
            usernames = if (names == null) emptyList() else (0 until names.length()).map { names.getString(it) },
        )
    }

    /** Returns inserted, duplicate, unmatched, ambiguous, before_start, invalid or bad_key. */
    fun ingest(readerKey: String, p: ParsedPayment, paidAtMillis: Long): String {
        val body = JSONObject()
            .put("p_key", readerKey)
            .put("p_amount", p.amount)
            .put("p_paid_at", iso(paidAtMillis))
            .put("p_sender_name", p.name)
            .put("p_sender_phone", p.phone ?: JSONObject.NULL)
            .put("p_tx_id", p.txId)
        return JSONObject(rpc("reader_ingest", body)).optString("status", "unknown")
    }

    private fun rpc(name: String, body: JSONObject): String {
        val conn = URL("${baseUrl.trimEnd('/')}/rest/v1/rpc/$name").openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = 20_000
            conn.doOutput = true
            conn.setRequestProperty("apikey", publishableKey)
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() } ?: ""
            if (code !in 200..299) throw IOException("HTTP $code from $name: ${text.take(200)}")
            return text
        } finally {
            conn.disconnect()
        }
    }

    private fun iso(millis: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.format(Date(millis))
    }
}
