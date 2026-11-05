@file:Suppress("FunctionName")

package com.manpreetgugga.tinycourier.firebase

import android.content.Context
import android.os.Bundle
import android.telephony.TelephonyManager
import android.util.Log
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.Locale
import java.util.TimeZone

// Statistics and crash reports as the Godot singleton TinyCourierFirebase:
// Google Analytics for Firebase and Crashlytics, for core/Analytics.gd,
// which decides what is collected and when. Until the game calls configure,
// nothing is (see the manifest). Method names are snake_case, as the game
// calls them.
class TinyCourierFirebase(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "TinyCourierFirebase"

    private val appContext: Context? get() = activity?.applicationContext

    // Starts or stops collecting, and keeps the answer for the next start.
    // [adIds] lets Analytics use the advertising ID as well, where no
    // consent is needed; Analytics data is never used to personalize ads.
    // Stopping also drops any crash report not sent yet.
    @UsedByGodot
    fun configure(collect: Boolean, adIds: Boolean) {
        val context = appContext ?: return
        val granted = FirebaseAnalytics.ConsentStatus.GRANTED
        val denied = FirebaseAnalytics.ConsentStatus.DENIED
        val analytics = FirebaseAnalytics.getInstance(context)
        analytics.setConsent(
            mapOf(
                FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE to if (collect) granted else denied,
                FirebaseAnalytics.ConsentType.AD_STORAGE to if (collect && adIds) granted else denied,
                FirebaseAnalytics.ConsentType.AD_USER_DATA to if (collect && adIds) granted else denied,
                FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to denied,
            ),
        )
        analytics.setAnalyticsCollectionEnabled(collect)
        val crashlytics = FirebaseCrashlytics.getInstance()
        crashlytics.setCrashlyticsCollectionEnabled(collect)
        if (!collect) crashlytics.deleteUnsentReports()
    }

    // Logs an Analytics event. [params] is a JSON object of numbers (and
    // true or false, sent as 1 or 0) and strings.
    @UsedByGodot
    fun log_event(name: String, params: String) {
        val context = appContext ?: return
        FirebaseAnalytics.getInstance(context).logEvent(name, bundleOf(params))
    }

    @UsedByGodot
    fun set_user_property(name: String, value: String) {
        val context = appContext ?: return
        FirebaseAnalytics.getInstance(context).setUserProperty(name, value)
    }

    // A value shown with any crash report from now on.
    @UsedByGodot
    fun set_crash_key(key: String, value: String) {
        FirebaseCrashlytics.getInstance().setCustomKey(key, value)
    }

    // A line in the log sent with the next crash report.
    @UsedByGodot
    fun crash_log(message: String) {
        FirebaseCrashlytics.getInstance().log(message)
    }

    // Reports an error the game survived (a script error, say) as a
    // non-fatal crash report. [frames] is a JSON array of {"function",
    // "file", "line"}, innermost first: where it happened, which is how
    // Crashlytics tells one error from another.
    @UsedByGodot
    fun record_error(message: String, frames: String) {
        val error = GodotError(message)
        error.stackTrace = stackOf(frames)
        FirebaseCrashlytics.getInstance().recordException(error)
    }

    // What the phone says about where it is, for the game to tell whether
    // the player must be asked first (see Analytics.gd): the SIM's and the
    // mobile network's countries (lower case; empty without them), the
    // language's country and the time zone. Read on the phone; nothing is
    // looked up.
    @UsedByGodot
    fun region_signals(): String {
        val json = JSONObject()
        try {
            val phone = appContext?.getSystemService(TelephonyManager::class.java)
            json.put("sim", phone?.simCountryIso.orEmpty())
            json.put("network", phone?.networkCountryIso.orEmpty())
        } catch (e: RuntimeException) {
            Log.w(TAG, "No SIM or network country: ${e.message}")
        }
        json.put("locale", Locale.getDefault().country)
        json.put("zone", TimeZone.getDefault().id)
        return json.toString()
    }

    // An error the game reported (see record_error).
    class GodotError(message: String) : RuntimeException(message)

    private companion object {
        const val TAG = "TinyCourierFirebase"

        fun bundleOf(json: String): Bundle {
            val bundle = Bundle()
            val values = try {
                JSONObject(json)
            } catch (e: JSONException) {
                Log.w(TAG, "Event parameters unreadable: ${e.message}")
                return bundle
            }
            for (key in values.keys()) {
                when (val value = values.get(key)) {
                    is Boolean -> bundle.putLong(key, if (value) 1L else 0L)
                    is Int -> bundle.putLong(key, value.toLong())
                    is Long -> bundle.putLong(key, value)
                    is Number -> bundle.putDouble(key, value.toDouble())
                    else -> bundle.putString(key, value.toString())
                }
            }
            return bundle
        }

        // res://game/Level.gd, line 12, in show_hint reads as
        // game.Level.show_hint(Level.gd:12).
        fun stackOf(json: String): Array<StackTraceElement> {
            val frames = try {
                JSONArray(json)
            } catch (e: JSONException) {
                JSONArray()
            }
            val stack = List(frames.length()) { index ->
                val frame = frames.optJSONObject(index) ?: JSONObject()
                val file = frame.optString("file").ifEmpty { "unknown" }
                val owner = file.removePrefix("res://").substringBeforeLast('.').replace('/', '.').ifEmpty { "godot" }
                StackTraceElement(owner, frame.optString("function").ifEmpty { "?" }, file.substringAfterLast('/'), frame.optInt("line", -1))
            }
            return if (stack.isEmpty()) arrayOf(StackTraceElement("godot", "?", "unknown", -1)) else stack.toTypedArray()
        }
    }
}
