extends SceneTree
## Dev utility: loads a scene, lets it render for a number of frames, then
## saves the viewport to a PNG and quits. Needs a real renderer (not --headless).
##
## Usage (from the project root, under Xvfb on a server):
##   godot --path . --resolution 720x1280 -s res://tools/capture.gd -- \
##       --scene=res://dev/test_diorama.tscn --out=docs/screenshots/step1.png --frames=90

var _frames_left: int = 90
var _out_path: String = "capture.png"


func _initialize() -> void:
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_frames_left = maxi(arg.trim_prefix("--frames=").to_int(), 1)
	if not _out_path.is_absolute_path():
		_out_path = ProjectSettings.globalize_path("res://").path_join(_out_path)
	var err: Error = change_scene_to_file(scene_path)
	if err != OK:
		push_error("capture: cannot load %s (%s)" % [scene_path, error_string(err)])
		quit(1)


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var err: Error = image.save_png(_out_path)
	if err != OK:
		push_error("capture: cannot write %s (%s)" % [_out_path, error_string(err)])
	else:
		print("capture: saved ", _out_path, " ", image.get_size())
	quit(0 if err == OK else 1)
	return true
