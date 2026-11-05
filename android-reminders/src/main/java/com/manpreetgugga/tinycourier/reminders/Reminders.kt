package com.manpreetgugga.tinycourier.reminders

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.util.Calendar

// What the reminders do, for the plugin (with the game open) and for
// ReminderReceiver (often with it closed). What to say and when comes from
// the game (core/Reminders.gd) as JSON and is kept in shared preferences,
// with when the game was last open and the shuffled order of the messages
// still to come.
//
// Each reminder time has an alarm of its own, set for its next turn. When
// it goes off it sets the next day's, then shows a reminder unless the game
// is open or was in the last quiet_minutes, the alarm is more than
// late_minutes late (the phone slept through it), or notifications aren't
// allowed. Once the game hasn't been open for idle_days the alarms stop,
// until it is opened again. A new reminder takes the place of one still
// showing, and opening the game clears it.
internal object Reminders {
    const val ACTION_REMIND = "com.manpreetgugga.tinycourier.reminders.REMIND"
    const val EXTRA_SLOT = "slot"
    const val EXTRA_AT = "at"

    // On the game's launch intent from a reminder: which one (its slot).
    const val EXTRA_OPENED = "com.manpreetgugga.tinycourier.reminders.OPENED"
    const val PERMISSION = "android.permission.POST_NOTIFICATIONS"

    private const val TAG = "TinyCourierReminders"
    private const val PREFS = "tiny_courier_reminders"
    private const val KEY_CONFIG = "config"
    private const val KEY_LAST_OPEN = "last_open"
    private const val KEY_DECK = "deck"
    private const val KEY_LAST_MESSAGE = "last_message"
    private const val KEY_ASKED = "asked"
    private const val CHANNEL = "reminders"
    private const val NOTIFICATION_ID = 1

    // Alarms cleared by armAll; the game uses three.
    private const val SLOTS = 8

    // How long after its time Android may run an alarm, to save battery.
    private const val WINDOW_MS = 20 * 60_000L
    private const val MINUTE_MS = 60_000L
    private const val DAY_MS = 24 * 60 * MINUTE_MS

    // The game's accent orange, for the icon.
    private const val COLOR = 0xFFF2A541.toInt()

    // Whether the game is in front. Kept in memory only, so a process that
    // ends can't leave it stuck on.
    @Volatile
    var open = false

    fun configure(context: Context, json: String) {
        if (Config.parse(json) == null) {
            Log.w(TAG, "Reminders unchanged: the game sent nothing usable")
            return
        }
        prefs(context).edit().putString(KEY_CONFIG, json).apply()
        createChannel(context)
        armAll(context)
    }

    // The game came to the front: note the time, clear a reminder still
    // showing and set the alarms afresh (a force stop clears them).
    fun opened(context: Context) {
        open = true
        prefs(context).edit().putLong(KEY_LAST_OPEN, System.currentTimeMillis()).apply()
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        armAll(context)
    }

    fun closed(context: Context) {
        open = false
        prefs(context).edit().putLong(KEY_LAST_OPEN, System.currentTimeMillis()).apply()
    }

    // Clears every reminder alarm, then sets one for each time if the
    // reminders are on, allowed, and the game has been open lately.
    fun armAll(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        for (slot in 0 until SLOTS) alarms.cancel(alarm(context, slot, 0L))
        val config = load(context) ?: return
        if (!config.enabled || idle(context, config) || !canNotify(context)) return
        config.times.forEachIndexed { slot, minutes -> arm(context, alarms, slot, minutes) }
    }

    // The alarm for [slot] went off; [at] is when it was due.
    fun remind(context: Context, slot: Int, at: Long) {
        val config = load(context) ?: return
        if (!config.enabled || slot !in config.times.indices) return
        if (idle(context, config)) {
            Log.i(TAG, "The game hasn't been open for ${config.idleDays} days: no more reminders until it is")
            return
        }
        context.getSystemService(AlarmManager::class.java)?.let { arm(context, it, slot, config.times[slot]) }
        val now = System.currentTimeMillis()
        val sinceOpen = now - prefs(context).getLong(KEY_LAST_OPEN, 0L)
        when {
            open -> Log.i(TAG, "No reminder: the game is open")
            sinceOpen in 0 until config.quietMinutes * MINUTE_MS -> Log.i(TAG, "No reminder: the game was open lately")
            at > 0L && now - at > config.lateMinutes * MINUTE_MS -> Log.i(TAG, "No reminder: ${(now - at) / MINUTE_MS} minutes late")
            !canNotify(context) -> Log.i(TAG, "No reminder: notifications are off")
            else -> show(context, slot, config.titles[slot], nextMessage(context, config.messages))
        }
    }

    // Notifications are allowed, and the reminders' channel isn't turned off.
    fun canNotify(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = manager.getNotificationChannel(CHANNEL)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    // Whether the game has asked Android's question before.
    fun asked(context: Context): Boolean = prefs(context).getBoolean(KEY_ASKED, false)

    fun markAsked(context: Context) {
        prefs(context).edit().putBoolean(KEY_ASKED, true).apply()
    }

    // Android's notification settings for the game.
    fun openSettings(host: Activity) {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, host.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", host.packageName, null))
        }
        try {
            host.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "No notification settings to open: ${e.message}")
        }
    }

    private fun arm(context: Context, alarms: AlarmManager, slot: Int, minutes: Int) {
        val at = nextTime(System.currentTimeMillis(), minutes)
        alarms.setWindow(AlarmManager.RTC_WAKEUP, at, WINDOW_MS, alarm(context, slot, at))
    }

    // The next time [minutes] after midnight, local time, at least a minute
    // after [now].
    private fun nextTime(now: Long, minutes: Int): Long {
        val next = Calendar.getInstance()
        next.timeInMillis = now
        next.set(Calendar.HOUR_OF_DAY, minutes / 60)
        next.set(Calendar.MINUTE, minutes % 60)
        next.set(Calendar.SECOND, 0)
        next.set(Calendar.MILLISECOND, 0)
        while (next.timeInMillis < now + MINUTE_MS) next.add(Calendar.DAY_OF_YEAR, 1)
        return next.timeInMillis
    }

    private fun alarm(context: Context, slot: Int, at: Long): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ACTION_REMIND)
            .putExtra(EXTRA_SLOT, slot)
            .putExtra(EXTRA_AT, at)
        return PendingIntent.getBroadcast(context, slot, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun idle(context: Context, config: Config): Boolean {
        val lastOpen = prefs(context).getLong(KEY_LAST_OPEN, 0L)
        return lastOpen > 0L && System.currentTimeMillis() - lastOpen > config.idleDays * DAY_MS
    }

    // The next message from a shuffled deck of them all, so every one shows
    // before any shows again.
    private fun nextMessage(context: Context, messages: List<String>): String {
        val prefs = prefs(context)
        val deck = prefs.getString(KEY_DECK, "").orEmpty().split(',')
            .mapNotNull { it.toIntOrNull() }.filter { it in messages.indices }.toMutableList()
        if (deck.isEmpty()) {
            deck.addAll(messages.indices.shuffled())
            // A new deck doesn't start with the message just shown.
            if (deck.size > 1 && deck[0] == prefs.getInt(KEY_LAST_MESSAGE, -1)) deck.add(deck.removeAt(0))
        }
        val index = deck.removeAt(0)
        prefs.edit().putString(KEY_DECK, deck.joinToString(",")).putInt(KEY_LAST_MESSAGE, index).apply()
        return messages[index]
    }

    private fun show(context: Context, slot: Int, title: String, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        createChannel(context)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder.setSmallIcon(R.drawable.tiny_courier_reminder)
            .setColor(COLOR)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
        // A tap opens the game, as its launcher icon would, saying which
        // reminder it came from (for the statistics, see Stats).
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            launch.putExtra(EXTRA_OPENED, slot)
            builder.setContentIntent(
                PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
        }
        try {
            manager.notify(NOTIFICATION_ID, builder.build())
            Stats.log(context, Stats.SHOWN, slot)
        } catch (e: SecurityException) {
            Log.w(TAG, "Couldn't show a reminder: ${e.message}")
        }
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Daily reminders", NotificationManager.IMPORTANCE_DEFAULT)
        channel.description = "A short note in the morning, afternoon and evening when parcels are waiting"
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    private fun load(context: Context): Config? = Config.parse(prefs(context).getString(KEY_CONFIG, null))

    private fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // The game's reminders: whether they're on, their times (minutes after
    // midnight, local time) with a title each, the messages to pick from,
    // and the rules above.
    private class Config(
        val enabled: Boolean,
        val times: List<Int>,
        val titles: List<String>,
        val messages: List<String>,
        val quietMinutes: Int,
        val lateMinutes: Int,
        val idleDays: Int,
    ) {
        companion object {
            fun parse(text: String?): Config? {
                if (text.isNullOrEmpty()) return null
                return try {
                    val json = JSONObject(text)
                    val times = json.getJSONArray("times").let { list -> List(list.length()) { list.getInt(it) } }
                    val titles = json.getJSONArray("titles").let { list -> List(list.length()) { list.getString(it) } }
                    val messages = json.getJSONArray("messages").let { list -> List(list.length()) { list.getString(it) } }
                    val usable = times.size in 1..SLOTS && titles.size == times.size && messages.isNotEmpty() &&
                        times.all { it in 0 until 24 * 60 }
                    if (!usable) {
                        null
                    } else {
                        Config(
                            json.optBoolean("enabled", true),
                            times,
                            titles,
                            messages,
                            json.optInt("quiet_minutes", 120),
                            json.optInt("late_minutes", 120),
                            json.optInt("idle_days", 7),
                        )
                    }
                } catch (e: JSONException) {
                    null
                }
            }
        }
    }
}
