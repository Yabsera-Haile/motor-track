package com.motortrack.motor_track.reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Wakes the Reader as soon as an SMS arrives. Messages from the chosen sender are
 * queued (multi-part SMS joined back together) and the background job runs.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val store = ReaderStore(context)
        val sender = store.sender
        if (!store.enabled || sender == null) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val items = parts
            .groupBy { it.originatingAddress ?: it.displayOriginatingAddress ?: "" }
            .filterKeys { it.equals(sender, ignoreCase = true) }
            .map { (address, pieces) ->
                QueuedSms(address, pieces.joinToString("") { it.messageBody ?: "" }, pieces.first().timestampMillis)
            }
        if (items.isEmpty()) return
        store.addToQueue(items)
        ReaderWorker.runNow(context)
    }
}
