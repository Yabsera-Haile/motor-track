package com.motortrack.motor_track.reader

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * One Reader pass: heartbeat, pull new M-Money SMS from the inbox, read them and
 * upload the ones from registered drivers. Runs when an SMS arrives, every 15
 * minutes, and when the app opens. Messages from anyone else never leave the phone.
 */
class ReaderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = lock.withLock {
        withContext(Dispatchers.IO) { runOnce(applicationContext) }
    }

    private fun runOnce(context: Context): Result {
        val store = ReaderStore(context)
        if (!store.enabled) return Result.success()
        val url = store.url
        val key = store.publishableKey
        val readerKey = store.readerKey
        val regex = store.regex
        val sender = store.sender
        if (url == null || key == null || readerKey == null || regex == null || sender == null) return Result.success()

        val api = ReaderApi(url, key)
        val parser = ReaderParser(regex, store.groups)

        // 1. Heartbeat, and the latest usernames to look for.
        try {
            val sync = api.sync(readerKey, store.unreadable)
            if (!sync.ok) {
                if (sync.error == "bad_key") turnOff(context, store, "This phone's Reader was turned off. Set it up again in Settings.")
                return Result.success()
            }
            store.usernames = sync.usernames.map(ReaderParser::normName).toSet()
        } catch (e: IOException) {
            store.lastError = "Couldn't reach the server. Will try again."
            return Result.retry()
        }

        // 2. Pull new messages from the sender into the queue.
        var unreadable = store.unreadable
        if (hasSmsPermission(context)) {
            val (fresh, newest) = readInbox(context, sender, store.checkpointMillis)
            val readable = fresh.filter {
                val ok = parser.parse(it.body) != null
                if (!ok && ReaderParser.looksLikeIncoming(it.body)) unreadable++
                ok
            }
            store.addToQueue(readable)
            if (newest > store.checkpointMillis) store.checkpointMillis = newest
            store.unreadable = unreadable
        } else {
            store.lastError = "SMS permission is off. Turn it on in Settings."
        }

        // 3. Upload the queue, oldest first. Stop on a network problem and retry later.
        val queue = store.queue().sortedBy { it.dateMillis }
        val recent = store.recent.toMutableList()
        var uploaded = 0
        var handled = 0
        for ((i, sms) in queue.withIndex()) {
            val p = parser.parse(sms.body)
            val id = p?.txId ?: "h:${sms.body.hashCode()}"
            if (p == null || id in recent || ReaderParser.normName(p.name) !in store.usernames) {
                handled++
                if (id !in recent) recent.add(id)
                continue
            }
            try {
                when (api.ingest(readerKey, p, p.paidAtMillis ?: sms.dateMillis)) {
                    "inserted" -> uploaded++
                    "bad_key" -> {
                        turnOff(context, store, "This phone's Reader was turned off. Set it up again in Settings.")
                        return Result.success()
                    }
                }
                recent.add(id)
                handled++
            } catch (e: IOException) {
                store.setQueue(queue.drop(i))
                store.recent = recent
                store.lastError = "Couldn't reach the server. ${queue.size - i} payment(s) waiting."
                return Result.retry()
            }
        }
        store.setQueue(emptyList())
        store.recent = recent
        store.uploadedTotal = store.uploadedTotal + uploaded
        store.lastRunMillis = System.currentTimeMillis()
        store.lastError = null
        store.lastResult = when {
            uploaded > 0 -> "Sent $uploaded new payment${if (uploaded == 1) "" else "s"}"
            handled > 0 -> "Checked $handled message${if (handled == 1) "" else "s"}, no new payments"
            else -> "No new messages"
        }
        return Result.success()
    }

    private fun turnOff(context: Context, store: ReaderStore, why: String) {
        store.enabled = false
        store.readerKey = null
        store.lastError = why
        cancel(context)
    }

    companion object {
        private val lock = Mutex()
        private const val NOW = "motor-track-reader-now"
        private const val PERIODIC = "motor-track-reader-periodic"

        private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        fun runNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<ReaderWorker>()
                .setConstraints(online)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }

        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<ReaderWorker>(15, TimeUnit.MINUTES).setConstraints(online).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(NOW)
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC)
        }

        fun hasSmsPermission(context: Context): Boolean =
            listOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS).all {
                ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
            }

        /** Messages from [sender] received after [since], oldest first, and the newest date seen. */
        fun readInbox(context: Context, sender: String, since: Long): Pair<List<QueuedSms>, Long> {
            val out = ArrayList<QueuedSms>()
            var newest = since
            context.contentResolver.query(
                Uri.parse("content://sms/inbox"),
                arrayOf("address", "body", "date"),
                "date > ?",
                arrayOf(since.toString()),
                "date ASC",
            )?.use { c ->
                val a = c.getColumnIndexOrThrow("address")
                val b = c.getColumnIndexOrThrow("body")
                val d = c.getColumnIndexOrThrow("date")
                while (c.moveToNext()) {
                    val date = c.getLong(d)
                    if (date > newest) newest = date
                    val address = c.getString(a) ?: continue
                    if (address.equals(sender, ignoreCase = true)) out.add(QueuedSms(address, c.getString(b) ?: "", date))
                }
            }
            return out to newest
        }
    }
}
