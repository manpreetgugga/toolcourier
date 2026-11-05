@file:Suppress("FunctionName")

package com.manpreetgugga.tinycourier.reminders

import android.content.pm.PackageManager
import android.os.Build
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

// The daily reminders as the Godot singleton TinyCourierReminders: the game
// (core/Reminders.gd) hands over what to say and when, and Reminders and
// ReminderReceiver show them, with the game closed too. This side also
// tells Reminders when the game comes and goes, and asks Android 13 and up
// for leave to notify. Method names are snake_case, as the game calls them.
class TinyCourierReminders(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "TinyCourierReminders"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        // (allowed): the answer to request_permission.
        SignalInfo(PERMISSION_RESULT, BOOL),
    )

    // Keeps the reminders (JSON, from core/Reminders.gd) and sets their
    // alarms, or clears them when the reminders are off.
    @UsedByGodot
    fun configure(json: String) {
        val host = activity ?: return
        Reminders.configure(host.applicationContext, json)
    }

    // Whether a reminder may show: notifications are allowed, and the
    // reminders' channel isn't turned off.
    @UsedByGodot
    fun can_notify(): Boolean {
        val host = activity ?: return false
        return Reminders.canNotify(host)
    }

    // Whether Android (13 and up) has yet to be asked for leave to notify.
    @UsedByGodot
    fun can_ask(): Boolean {
        val host = activity ?: return false
        return Build.VERSION.SDK_INT >= 33 && !Reminders.asked(host) &&
            host.checkSelfPermission(Reminders.PERMISSION) != PackageManager.PERMISSION_GRANTED
    }

    // Asks Android for leave to notify, then answers with permission_result.
    // Where Android won't ask (the player said no twice, or turned the
    // game's notifications off) and [openSettings] is true, the game's
    // notification settings open instead.
    @UsedByGodot
    fun request_permission(openSettings: Boolean) {
        val host = activity ?: return answer(false)
        host.runOnUiThread {
            val granted = Build.VERSION.SDK_INT < 33 ||
                host.checkSelfPermission(Reminders.PERMISSION) == PackageManager.PERMISSION_GRANTED
            when {
                Reminders.canNotify(host) -> answer(true)
                !granted && (!Reminders.asked(host) || host.shouldShowRequestPermissionRationale(Reminders.PERMISSION)) -> {
                    Reminders.markAsked(host)
                    host.requestPermissions(arrayOf(Reminders.PERMISSION), REQUEST_CODE)
                }
                openSettings -> {
                    Reminders.openSettings(host)
                    answer(false)
                }
                else -> answer(false)
            }
        }
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>?, grantResults: IntArray?) {
        if (requestCode != REQUEST_CODE) return
        val host = activity ?: return answer(false)
        val allowed = Reminders.canNotify(host)
        if (allowed) Reminders.armAll(host.applicationContext)
        answer(allowed)
    }

    override fun onMainResume() {
        val host = activity ?: return
        Reminders.opened(host.applicationContext)
        // Opened with a tap on a reminder: count it once.
        val intent = host.intent ?: return
        if (intent.hasExtra(Reminders.EXTRA_OPENED)) {
            Stats.log(host.applicationContext, Stats.OPENED, intent.getIntExtra(Reminders.EXTRA_OPENED, -1))
            intent.removeExtra(Reminders.EXTRA_OPENED)
        }
    }

    override fun onMainPause() {
        activity?.let { Reminders.closed(it.applicationContext) }
    }

    // Signals go out on Godot's render thread.
    private fun answer(allowed: Boolean) {
        runOnRenderThread { emitSignal(PERMISSION_RESULT, allowed) }
    }

    private companion object {
        const val PERMISSION_RESULT = "permission_result"
        const val REQUEST_CODE = 7402
        val BOOL: Class<*> = Boolean::class.javaObjectType
    }
}
