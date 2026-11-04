package com.motortrack.motor_track.reader

import java.util.Calendar
import java.util.GregorianCalendar
import java.util.TimeZone
import java.util.regex.Pattern

/** One payment read from an M-Money SMS. */
data class ParsedPayment(
    val amount: Int,
    val name: String,
    val phone: String?,
    /** Payment time from the SMS text, or null if the template has no {datetime}. */
    val paidAtMillis: Long?,
    val txId: String,
)

/**
 * Applies the pattern the app compiled from the SMS template (SmsTemplate.regexSource
 * in Dart), so the background reader reads messages exactly like the setup screens.
 * [groups] names the field each capture group holds: amount, name, phone, datetime, txid.
 */
class ReaderParser(regex: String, private val groups: List<String>) {
    private val pattern: Pattern = Pattern.compile(regex, Pattern.CASE_INSENSITIVE or Pattern.DOTALL)

    fun parse(body: String): ParsedPayment? {
        val m = pattern.matcher(body)
        if (!m.find()) return null
        val values = HashMap<String, String>()
        for ((i, field) in groups.withIndex()) {
            values[field] = (m.group(i + 1) ?: return null).trim()
        }
        val amount = values["amount"]?.replace(",", "")?.toDoubleOrNull()?.toInt() ?: return null
        val name = values["name"]?.replace(Regex("\\s+"), " ") ?: return null
        val txId = values["txid"] ?: return null
        if (amount <= 0 || name.isEmpty() || txId.isEmpty()) return null
        return ParsedPayment(
            amount = amount,
            name = name,
            phone = values["phone"]?.replace(" ", ""),
            paidAtMillis = values["datetime"]?.let(::kigaliMillis),
            txId = txId,
        )
    }

    companion object {
        private val incoming = Regex("\\breceived\\b", RegexOption.IGNORE_CASE)
        private val dateTime = Regex("(\\d{4})-(\\d{2})-(\\d{2})\\s+(\\d{1,2}):(\\d{2})(?::(\\d{2}))?")

        /** Looks like money received, even if it doesn't fit the template. */
        fun looksLikeIncoming(body: String): Boolean = incoming.containsMatchIn(body)

        /** Same rule as the database: ignore case and repeated spaces. */
        fun normName(name: String): String = name.trim().replace(Regex("\\s+"), " ").uppercase()

        /** "2026-11-02 19:57:24" in Kigali (UTC+2, no daylight saving) to epoch millis. */
        fun kigaliMillis(text: String): Long? {
            val m = dateTime.find(text) ?: return null
            val g = m.groupValues
            val cal = GregorianCalendar(TimeZone.getTimeZone("GMT+02:00"))
            cal.clear()
            cal.set(g[1].toInt(), g[2].toInt() - 1, g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].ifEmpty { "0" }.toInt())
            cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }
    }
}
