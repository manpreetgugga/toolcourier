@file:Suppress("FunctionName")

package com.manpreetgugga.tinycourier.ads

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentInformation.PrivacyOptionsRequirementStatus
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

// Google AdMob as the Godot singleton TinyCourierAds: a rewarded video (for
// hints) and an interstitial (the break on the level-complete card). When
// they may play is decided in core/Ads.gd; this only loads, shows and
// reports. Nothing loads until Google's consent form (UMP) has had its say.
//
// Godot calls in on its render thread; the ads run on the UI thread, and
// each result goes back as a signal. Every show_* call gets exactly one
// reply. Method names are snake_case so the game calls this just as it
// calls its desktop stand-in (Ads.Preview in core/Ads.gd).
class TinyCourierAds(godot: Godot) : GodotPlugin(godot) {
    private val main = Handler(Looper.getMainLooper())
    private var ids: Ids? = null
    private var consent: ConsentInformation? = null
    private var asked = false
    private var started = false
    private var destroyed = false
    private var showing: Showing? = null

    @Volatile
    private var privacyRequired = false

    private val rewarded = Slot<RewardedAd>("rewarded") { host, ids, loaded, failed ->
        RewardedAd.load(
            host,
            ids.rewarded,
            AdRequest.Builder().build(),
            object : RewardedAdLoadCallback() {
                override fun onAdLoaded(ad: RewardedAd) = loaded(ad)
                override fun onAdFailedToLoad(error: LoadAdError) = failed(error)
            },
        )
    }

    private val interstitial = Slot<InterstitialAd>("interstitial") { host, ids, loaded, failed ->
        InterstitialAd.load(
            host,
            ids.interstitial,
            AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) = loaded(ad)
                override fun onAdFailedToLoad(error: LoadAdError) = failed(error)
            },
        )
    }

    override fun getPluginName() = "TinyCourierAds"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        // The consent answer, or whether Settings must offer the privacy options, may have changed.
        SignalInfo("consent_changed"),
        // (earned, reason): earned only if the video was watched to the end.
        SignalInfo("rewarded_finished", BOOL, STRING),
        // (shown, reason): shown once the ad has closed.
        SignalInfo("interstitial_finished", BOOL, STRING),
        // (error): empty once Google's privacy options form has closed.
        SignalInfo("privacy_options_closed", STRING),
    )

    // Asks for consent where the law needs it, then starts the ads SDK. Once
    // a launch: later calls do nothing.
    @UsedByGodot
    fun start() {
        main.post { startNow() }
    }

    @UsedByGodot
    fun is_rewarded_ready(): Boolean = rewarded.ready

    @UsedByGodot
    fun is_interstitial_ready(): Boolean = interstitial.ready

    // UMP says the player must be able to reopen the consent form (Settings → Ad privacy).
    @UsedByGodot
    fun is_privacy_options_required(): Boolean = privacyRequired

    @UsedByGodot
    fun show_rewarded(placement: String) {
        main.post { showRewarded(placement) }
    }

    @UsedByGodot
    fun show_interstitial(placement: String) {
        main.post { showInterstitial(placement) }
    }

    @UsedByGodot
    fun show_privacy_options() {
        main.post { showPrivacy() }
    }

    // Forgets the consent answer, so the next launch asks again (for testing the form).
    @UsedByGodot
    fun reset_consent() {
        main.post { consent?.reset() }
    }

    // The ad covers the game, then it's back.
    override fun onMainPause() {
        showing?.let { it.away = true }
    }

    override fun onMainResume() {
        val shown = showing ?: return
        // Back in front with no word from the SDK (say the launcher brought
        // the game back and the ad was cleared): call the ad closed.
        if (shown.away) main.postDelayed({ closed(shown) }, LOST_AD_MS)
    }

    override fun onMainDestroy() {
        destroyed = true
        main.removeCallbacksAndMessages(null)
    }

    private fun startNow() {
        if (asked || destroyed) return
        val host = activity ?: return
        val found = Ids.read(host)
        if (found == null) {
            Log.w(TAG, "No ad unit ids in the manifest; the ads stay off")
            return
        }
        asked = true
        ids = found
        val info = UserMessagingPlatform.getConsentInformation(host)
        consent = info
        val params = ConsentRequestParameters.Builder()
        if (found.testDevices.isNotEmpty() || found.debug) {
            val debug = ConsentDebugSettings.Builder(host)
            found.testDevices.forEach { debug.addTestDeviceHashedId(it) }
            // Debug builds on a test device (an emulator is one) see the form as if in the EEA.
            if (found.debug) debug.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA)
            params.setConsentDebugSettings(debug.build())
        }
        info.requestConsentInfoUpdate(
            host,
            params.build(),
            {
                if (!destroyed) {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(host) { error ->
                        if (error != null) Log.w(TAG, "Consent form: ${error.message}")
                        consentChanged()
                    }
                }
            },
            { error ->
                Log.w(TAG, "Consent info: ${error.message}")
                consentChanged()
            },
        )
        // Consent given on an earlier run lets the ads start while that check runs.
        consentChanged()
    }

    private fun consentChanged() {
        val info = consent ?: return
        if (destroyed) return
        privacyRequired = info.privacyOptionsRequirementStatus == PrivacyOptionsRequirementStatus.REQUIRED
        emit("consent_changed")
        if (started || !info.canRequestAds()) return
        val host = activity ?: return
        val found = ids ?: return
        started = true
        MobileAds.setRequestConfiguration(
            RequestConfiguration.Builder()
                .setTestDeviceIds(found.testDevices)
                // A calm puzzle game: nothing rated above PG.
                .setMaxAdContentRating(RequestConfiguration.MAX_AD_CONTENT_RATING_PG)
                .build(),
        )
        // Google asks for initialize() off the main thread.
        Thread {
            MobileAds.initialize(host) {
                main.post {
                    rewarded.fill()
                    interstitial.fill()
                }
            }
        }.start()
    }

    private fun showRewarded(placement: String) {
        if (showing != null) return emit(REWARDED, false, "busy")
        val host = activity ?: return emit(REWARDED, false, "unavailable")
        val ad = rewarded.take() ?: return emit(REWARDED, false, "unavailable")
        Log.i(TAG, "Rewarded video for $placement")
        val shown = Showing(rewarded = true)
        showing = shown
        ad.fullScreenContentCallback = callbacks(shown, rewarded)
        ad.show(host) {
            shown.earned = true
            if (shown.closed) settle(shown, true)
        }
    }

    private fun showInterstitial(placement: String) {
        if (showing != null) return emit(INTERSTITIAL, false, "busy")
        val host = activity ?: return emit(INTERSTITIAL, false, "unavailable")
        val ad = interstitial.take() ?: return emit(INTERSTITIAL, false, "unavailable")
        Log.i(TAG, "Interstitial for $placement")
        val shown = Showing(rewarded = false)
        showing = shown
        ad.fullScreenContentCallback = callbacks(shown, interstitial)
        ad.show(host)
    }

    private fun showPrivacy() {
        val host = activity ?: return emit("privacy_options_closed", "unavailable")
        UserMessagingPlatform.showPrivacyOptionsForm(host) { error ->
            emit("privacy_options_closed", error?.message ?: "")
            consentChanged()
        }
    }

    private fun callbacks(shown: Showing, slot: Slot<*>) = object : FullScreenContentCallback() {
        override fun onAdShowedFullScreenContent() = slot.fill()

        override fun onAdDismissedFullScreenContent() = closed(shown)

        override fun onAdFailedToShowFullScreenContent(error: AdError) {
            Log.w(TAG, "Couldn't show the ad (${error.code}: ${error.message})")
            settle(shown, false, "show-failed-${error.code}")
            slot.fill()
        }
    }

    // A video pays only once the SDK says the reward was earned. That can
    // come just after the video closes, so a closed unpaid video waits a moment.
    private fun closed(shown: Showing) {
        if (shown.closed) return
        shown.closed = true
        when {
            !shown.rewarded -> settle(shown, true)
            shown.earned -> settle(shown, true)
            else -> main.postDelayed({ settle(shown, shown.earned, "cancelled") }, LATE_REWARD_MS)
        }
    }

    private fun settle(shown: Showing, ok: Boolean, reason: String = "") {
        if (shown.replied) return
        shown.replied = true
        if (showing === shown) showing = null
        emit(if (shown.rewarded) REWARDED else INTERSTITIAL, ok, if (ok) "" else reason)
    }

    // Signals go out on Godot's render thread (which waits while an ad covers the game).
    private fun emit(signal: String, vararg args: Any) {
        if (!destroyed) runOnRenderThread { emitSignal(signal, *args) }
    }

    private class Showing(val rewarded: Boolean) {
        var earned = false
        var closed = false
        var replied = false
        var away = false
    }

    // The ad unit ids and test devices, which the export plugin
    // (addons/tiny_courier_ads/plugin.gd) writes into the manifest.
    private class Ids(
        val rewarded: String,
        val interstitial: String,
        val testDevices: List<String>,
        val debug: Boolean,
    ) {
        companion object {
            @Suppress("DEPRECATION")
            fun read(host: Activity): Ids? {
                val info = host.packageManager.getApplicationInfo(host.packageName, PackageManager.GET_META_DATA)
                val meta = info.metaData ?: return null
                val rewarded = meta.getString("$META.REWARDED_ID").orEmpty()
                val interstitial = meta.getString("$META.INTERSTITIAL_ID").orEmpty()
                if (rewarded.isBlank() || interstitial.isBlank()) return null
                val devices = meta.getString("$META.TEST_DEVICES").orEmpty()
                    .split(",").map { it.trim() }.filter { it.isNotEmpty() }
                return Ids(rewarded, interstitial, devices, (info.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0)
            }
        }
    }

    // One preloaded ad of a kind. A failed load tries again later and later;
    // an ad left unshown for nearly an hour is swapped for a fresh one.
    private inner class Slot<T : Any>(
        private val kind: String,
        private val load: (host: Activity, ids: Ids, loaded: (T) -> Unit, failed: (LoadAdError) -> Unit) -> Unit,
    ) {
        @Volatile
        private var ad: T? = null
        private var loading = false
        private var failures = 0
        private val retry = Runnable { fill() }
        private val expire = Runnable {
            ad = null
            fill()
        }

        val ready: Boolean get() = ad != null

        fun fill() {
            if (!started || destroyed || loading || ad != null) return
            val host = activity ?: return
            val found = ids ?: return
            main.removeCallbacks(retry)
            loading = true
            load(
                host,
                found,
                { loaded ->
                    loading = false
                    failures = 0
                    if (!destroyed) {
                        ad = loaded
                        main.postDelayed(expire, AD_LIFETIME_MS)
                    }
                },
                { error ->
                    loading = false
                    failures += 1
                    val wait = minOf(RETRY_MS shl minOf(failures - 1, 6), MAX_RETRY_MS)
                    Log.w(TAG, "No $kind ad (${error.code}: ${error.message}); trying again in ${wait / 1000}s")
                    if (!destroyed) main.postDelayed(retry, wait)
                },
            )
        }

        fun take(): T? {
            val taken = ad ?: return null
            ad = null
            main.removeCallbacks(expire)
            return taken
        }
    }

    private companion object {
        const val TAG = "TinyCourierAds"
        const val META = "com.manpreetgugga.tinycourier.ads"
        const val REWARDED = "rewarded_finished"
        const val INTERSTITIAL = "interstitial_finished"
        const val RETRY_MS = 15_000L
        const val MAX_RETRY_MS = 10 * 60_000L
        const val AD_LIFETIME_MS = 55 * 60_000L
        const val LATE_REWARD_MS = 1_000L
        const val LOST_AD_MS = 1_500L
        val BOOL: Class<*> = Boolean::class.javaObjectType
        val STRING: Class<*> = String::class.java
    }
}
