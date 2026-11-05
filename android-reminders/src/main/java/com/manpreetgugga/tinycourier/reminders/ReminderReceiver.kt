package com.manpreetgugga.tinycourier.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Shows a reminder when its alarm goes off (see Reminders), and sets the
// alarms again when Android has cleared or moved them: after a restart, an
// update of the game, or a change of clock or time zone.
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Reminders.ACTION_REMIND -> Reminders.remind(
                context,
                intent.getIntExtra(Reminders.EXTRA_SLOT, -1),
                intent.getLongExtra(Reminders.EXTRA_AT, 0L),
            )
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> Reminders.armAll(context)
        }
    }
}
