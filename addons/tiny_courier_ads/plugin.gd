@tool
extends EditorPlugin
## Adds the ads to Android exports: the TinyCourierAds plugin
## (bin/tiny-courier-ads.aar, built from android-plugin/), the Google Mobile
## Ads and consent (UMP) libraries it needs, and the AdMob ids, which go into
## the manifest for the plugin to read. Android exports must use the Gradle
## build for any of this to be included.
##
## Debug exports always get Google's test ids. Release exports get them too,
## until the game is live on Google Play: then export with
## TINY_COURIER_LIVE_ADS=1 in the environment for the game's own ids. Your own
## phones must get test ads even then (tapping your own ads breaks AdMob's
## rules): put their hashed ids, from logcat, in ADMOB_TEST_DEVICE_IDS,
## comma-separated.

var _export: AdsExport


func _enter_tree() -> void:
	_export = AdsExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AdsExport:
	extends EditorExportPlugin

	## Keep in step with android-plugin/build.gradle.
	const DEPENDENCIES: Array[String] = [
		"com.google.android.gms:play-services-ads:25.5.0",
		"com.google.android.ump:user-messaging-platform:4.0.0",
	]
	## Google's sample ids, which always serve test ads.
	const TEST_IDS: Dictionary = {
		"app": "ca-app-pub-3940256099942544~3347511713",
		"rewarded": "ca-app-pub-3940256099942544/5224354917",
		"interstitial": "ca-app-pub-3940256099942544/1033173712",
	}
	## The game's own ids: the app Tiny Courier in AdMob, its rewarded unit
	## "Hint video" and its interstitial unit "Level break".
	const LIVE_IDS: Dictionary = {
		"app": "ca-app-pub-6111568882988372~2256360108",
		"rewarded": "ca-app-pub-6111568882988372/4370940449",
		"interstitial": "ca-app-pub-6111568882988372/5812461734",
	}
	const META: String = "com.manpreetgugga.tinycourier.ads"

	## The ids an export gets (see the plugin's description).
	static func ids_for(debug: bool) -> Dictionary:
		return LIVE_IDS if not debug and OS.get_environment("TINY_COURIER_LIVE_ADS") == "1" else TEST_IDS

	func _get_name() -> String:
		return "TinyCourierAds"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android"):
			return
		if not get_option("gradle_build/use_gradle_build"):
			push_error("Tiny Courier Ads: turn on Gradle Build in the Android preset, or the export has no ads.")
		var live: bool = ids_for(is_debug) == LIVE_IDS
		print("Tiny Courier Ads: %s ids" % ("the game's own" if live else "Google's test"))

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["tiny_courier_ads/bin/tiny-courier-ads.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(DEPENDENCIES)

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, debug: bool) -> String:
		var ids: Dictionary = ids_for(debug)
		var devices: String = OS.get_environment("ADMOB_TEST_DEVICE_IDS").strip_edges()
		return "\n".join([
			_meta("com.google.android.gms.ads.APPLICATION_ID", ids["app"]),
			_meta(META + ".REWARDED_ID", ids["rewarded"]),
			_meta(META + ".INTERSTITIAL_ID", ids["interstitial"]),
			_meta(META + ".TEST_DEVICES", devices.xml_escape(true)),
		])

	static func _meta(name: String, value: String) -> String:
		return '<meta-data android:name="%s" android:value="%s" />' % [name, value]
