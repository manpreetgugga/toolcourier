package com.manpreetgugga.tinycourier.reminders

import android.content.Context
import android.os.Bundle
import com.google.firebase.analytics.FirebaseAnalytics

// Counts the reminders shown and opened in the game's statistics: the
// Analytics events reminder_shown and reminder_open, with the slot (0 for
// the morning's, 1 the afternoon's, 2 the evening's). Analytics drops them
// unless the player's statistics are on (see core/Analytics.gd), and a
// build without the Firebase plugin simply has none.
internal object Stats {
    const val SHOWN = "reminder_shown"
    const val OPENED = "reminder_open"

    fun log(context: Context, event: String, slot: Int) {
        try {
            FirebaseAnalytics.getInstance(context).logEvent(event, Bundle().apply { putLong("slot", slot.toLong()) })
        } catch (e: Throwable) {
            // No Firebase in this build.
        }
    }
}
