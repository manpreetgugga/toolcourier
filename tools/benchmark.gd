extends SceneTree
## Measures what each graphics quality costs. Renders the main menu, the
## world select, the first level and the two heaviest (6-49 has the most
## draw calls of all the levels, 5-104 the most triangles) offscreen at a
## phone's size (1080 x 2400 by default) with each quality in turn, and
## prints for each: GPU time per frame, the whole frame time (vsync off),
## draw calls and triangles (all, and those for the shadow maps), the 3D
## render size, and memory. Also saves the first level at every quality side
## by side (step10_quality.png) to compare how each looks.
##
## Desktop GPUs are far faster than phones, so read the GPU times as ratios
## between qualities and scenes; draw calls, triangles, render sizes and
## memory carry over as they are. Needs a renderer (not --headless):
##
##   godot --path . -s res://tools/benchmark.gd -- [--size=1080x2400] [--out=docs/screenshots]

const SCENES: Array[Array] = [
	["menu", ""],
	["worlds", ""],
	["level 1-1", "res://levels/world_1/level_1.json"],
	["level 5-49", "res://levels/world_5/level_49.json"],
	["level 7-50", "res://levels/world_7/level_50.json"],
]
const WARM_UP: int = 90
const SAMPLES: int = 120

var _size := Vector2i(1080, 2400)
var _out_dir: String = ""
var _pictures: Array[Image] = []


func _initialize() -> void:
	Settings.use_file("user://test_settings.json")
	Progress.use_file("user://test_progress.json")
	Game.splash_done = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts: PackedStringArray = arg.trim_prefix("--size=").split("x")
			_size = Vector2i(parts[0].to_int(), parts[1].to_int())
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
			if not _out_dir.is_absolute_path():
				_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run()


func _run() -> void:
	print("%s at %dx%d on %s" % [Engine.get_version_info().string, _size.x, _size.y, RenderingServer.get_video_adapter_name()])
	print("quality | scene       |  GPU ms | frame ms | draws (shadow) | triangles (shadow) | 3D size   | static MB | video MB")
	for quality: int in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		Settings.set_value(&"quality", quality, false)
		for scene: Array in SCENES:
			await _measure(quality, scene[0], scene[1])
	if not _out_dir.is_empty() and _pictures.size() == 3:
		_save_comparison()
	quit()


func _measure(quality: int, label: String, level_path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = _size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	Settings.apply_quality(viewport)
	var scene: Node
	if level_path.is_empty():
		scene = (load(Game.MENU) as PackedScene).instantiate()
	else:
		var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
		level.level_path = level_path
		scene = level
	viewport.add_child(scene)
	if label == "worlds":
		(scene as Menu).show_screen(&"worlds", false)
	await _frames(WARM_UP)

	var viewports: Array[RID] = [viewport.get_viewport_rid()]
	for inner: Node in scene.find_children("*", "SubViewport", true, false):
		viewports.append((inner as SubViewport).get_viewport_rid())
	for rid: RID in viewports:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(2)
	var gpu: float = 0.0
	var draws: int = 0
	var shadow_draws: int = 0
	var triangles: int = 0
	var shadow_triangles: int = 0
	var started: int = Time.get_ticks_usec()
	for i in SAMPLES:
		await process_frame
		for rid: RID in viewports:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			draws += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			shadow_draws += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			triangles += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			shadow_triangles += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var frame_ms: float = (Time.get_ticks_usec() - started) / 1000.0 / SAMPLES
	var size_3d := Vector2i(Vector2(_size) * viewport.scaling_3d_scale)
	print("%-7s | %-11s | %7.2f | %8.2f | %5d (%5d) | %8d (%8d) | %4dx%-4d | %9.1f | %8.1f" % [
		Settings.QUALITY_NAMES[quality], label, gpu / SAMPLES, frame_ms,
		draws / SAMPLES, shadow_draws / SAMPLES, triangles / SAMPLES, shadow_triangles / SAMPLES,
		size_3d.x, size_3d.y,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if label == "level 1-1":
		_pictures.append(viewport.get_texture().get_image())
	viewport.queue_free()
	await _frames(4)


## The first level at Low, Medium and High, side by side at half size.
func _save_comparison() -> void:
	var half := Vector2i(_size.x / 2, _size.y / 2)
	var sheet := Image.create(half.x * 3, half.y, false, Image.FORMAT_RGBA8)
	for i in 3:
		var picture: Image = _pictures[i]
		picture.convert(Image.FORMAT_RGBA8)
		picture.resize(half.x, half.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(picture, Rect2i(Vector2i.ZERO, half), Vector2i(half.x * i, 0))
	var path: String = _out_dir.path_join("step10_quality.png")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	sheet.save_png(path)
	print("saved %s" % path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
