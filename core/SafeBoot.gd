extends Node
## Safe mode for phones whose Vulkan driver dies under the game (Crashlytics:
## a SIGTRAP in the engine at start-up on Samsung phones with an Adreno 618,
## the same crash Boomlets had; the engine cannot survive it).
##
## Two guards, both in the Android activity (GodotApp.java, patched in by
## tools/prepare_android_build.ps1 before each export):
##  1. Qualcomm phones with a Vulkan driver older than 1.3 start on OpenGL
##     from the very first launch.
##  2. Every other phone: while the game is on screen on Vulkan, a marker file
##     sits in user://. Going to the background takes it away. If the game
##     dies while on screen the marker is left behind, the next start finds
##     it, and that start and every later one use OpenGL.
## The game already runs on OpenGL (the Compatibility renderer) on phones
## without Vulkan, so nothing else changes.

## Left behind by a run that died on screen. Read by GodotApp.java: keep the
## two names the same there.
const PENDING: String = "user://boot_pending"
## Once this exists the game always starts on OpenGL. Written by GodotApp.java.
const USE_GL: String = "user://use_gl"

var _watching: bool = false


## True when this run is on OpenGL on Android: safe mode, or a phone without
## Vulkan.
static func is_safe_mode() -> bool:
	return OS.get_name() == "Android" and RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_name() != "Android":
		return
	if is_safe_mode():
		_clear()
		return
	_watching = true
	_arm()


func _notification(what: int) -> void:
	if not _watching:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_clear()
		NOTIFICATION_APPLICATION_RESUMED:
			_arm()


func _arm() -> void:
	var f := FileAccess.open(PENDING, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()


func _clear() -> void:
	if FileAccess.file_exists(PENDING):
		DirAccess.remove_absolute(PENDING)
