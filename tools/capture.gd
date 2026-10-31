extends SceneTree
## Dev utility: loads a scene, lets it render for a number of frames, then
## saves the viewport to a PNG and quits. Needs a real renderer (not --headless).
##
## Usage (from the project root, under Xvfb on a server):
##   godot --path . --resolution 720x1280 -s res://tools/capture.gd -- \
##       --scene=res://game/Level.tscn --out=docs/screenshots/level.png --frames=90
##
## --size=WxH renders into an offscreen viewport of exactly that size, for
## captures larger than the desktop allows. --crop=X,Y,W,H saves only that
## region, for close-up inspection.

var _frames_left: int = 90
var _out_path: String = "capture.png"
var _crop := Rect2i()
var _viewport: Viewport


func _initialize() -> void:
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var size := Vector2i.ZERO
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_frames_left = maxi(arg.trim_prefix("--frames=").to_int(), 1)
		elif arg.begins_with("--size="):
			var parts: PackedStringArray = arg.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				size = Vector2i(parts[0].to_int(), parts[1].to_int())
		elif arg.begins_with("--crop="):
			var parts: PackedStringArray = arg.trim_prefix("--crop=").split(",")
			if parts.size() == 4:
				_crop = Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int())
	if not _out_path.is_absolute_path():
		_out_path = ProjectSettings.globalize_path("res://").path_join(_out_path)

	if size == Vector2i.ZERO:
		_viewport = root
		var err: Error = change_scene_to_file(scene_path)
		if err != OK:
			push_error("capture: cannot load %s (%s)" % [scene_path, error_string(err)])
			quit(1)
		return

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("capture: cannot load %s" % scene_path)
		quit(1)
		return
	var sub := SubViewport.new()
	sub.size = size
	sub.msaa_3d = root.msaa_3d
	sub.use_debanding = root.use_debanding
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	sub.add_child(packed.instantiate())
	_viewport = sub


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	var image: Image = _viewport.get_texture().get_image()
	if _crop.has_area():
		image = image.get_region(_crop.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var err: Error = image.save_png(_out_path)
	if err != OK:
		push_error("capture: cannot write %s (%s)" % [_out_path, error_string(err)])
	else:
		var visible := Viewport.RENDER_INFO_TYPE_VISIBLE
		var draws: int = _viewport.get_render_info(visible, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var shadow_draws: int = _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var triangles: int = _viewport.get_render_info(visible, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		print("capture: saved %s %s, %d draw calls (+%d shadow), %d triangles" % [_out_path, image.get_size(), draws, shadow_draws, triangles])
	quit(0 if err == OK else 1)
	return true
