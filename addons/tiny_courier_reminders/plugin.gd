@tool
extends EditorPlugin
## Adds the daily reminders to Android exports: the TinyCourierReminders
## plugin (bin/tiny-courier-reminders.aar, built from android-reminders/).
## Its manifest brings the rest: the receiver that shows each reminder, and
## the permissions to post notifications and to set the alarms again after a
## restart. Android exports must use the Gradle build for it to be included.

var _export: RemindersExport


func _enter_tree() -> void:
	_export = RemindersExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class RemindersExport:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "TinyCourierReminders"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if features.has("android") and not get_option("gradle_build/use_gradle_build"):
			push_error("Tiny Courier Reminders: turn on Gradle Build in the Android preset, or the export has no reminders.")

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["tiny_courier_reminders/bin/tiny-courier-reminders.aar"])
