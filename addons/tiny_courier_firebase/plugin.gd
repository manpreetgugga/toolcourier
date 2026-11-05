@tool
extends EditorPlugin
## Adds the statistics and crash reports to Android exports: the
## TinyCourierFirebase plugin (bin/tiny-courier-firebase.aar, built from
## android-firebase/ with the game's Firebase settings), and the Google
## Analytics for Firebase and Crashlytics libraries it needs, Crashlytics'
## native part included, for crashes in the engine itself. Android exports
## must use the Gradle build for any of this to be included.
##
## The .aar carries the game's Firebase settings, so it isn't checked in:
## build it (see the README, Statistics) before exporting, or the export
## stops with an error.

var _export: FirebaseExport


func _enter_tree() -> void:
	_export = FirebaseExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class FirebaseExport:
	extends EditorExportPlugin

	## Keep in step with android-firebase/build.gradle.
	const DEPENDENCIES: Array[String] = [
		"com.google.firebase:firebase-analytics:24.0.0",
		"com.google.firebase:firebase-crashlytics:21.0.1",
		"com.google.firebase:firebase-crashlytics-ndk:21.0.1",
	]
	const LIBRARY: String = "tiny_courier_firebase/bin/tiny-courier-firebase.aar"

	func _get_name() -> String:
		return "TinyCourierFirebase"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android"):
			return
		if not get_option("gradle_build/use_gradle_build"):
			push_error("Tiny Courier Firebase: turn on Gradle Build in the Android preset, or the export has no statistics or crash reports.")
		if not FileAccess.file_exists("res://addons/" + LIBRARY):
			push_error("Tiny Courier Firebase: no %s. Build it first: put google-services.json in android-firebase/, then run ./gradlew copyToAddon there." % LIBRARY)

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([LIBRARY])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(DEPENDENCIES)
