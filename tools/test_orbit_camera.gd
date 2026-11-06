extends SceneTree
## Scripted check of the orbit camera and tap handling on the sandbox level:
## tap vs drag, inertia, pitch clamp, pinch and wheel zoom, double-tap reset,
## grid picking and the auto-fit. Feeds synthetic touch events into a 720x1280
## offscreen viewport, prints PASS/FAIL per check, saves screenshots, and exits
## with status 1 on any failure. Needs a renderer (not --headless).
##
##   godot --path . --resolution 405x720 -s res://tools/test_orbit_camera.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
## Tolerance for smoothed values that approach their target exponentially.
const SETTLED: float = 0.05

var _viewport: SubViewport
var _scene: Node3D
var _camera: OrbitCamera
var _out_dir: String = "docs/screenshots"
var _failures: int = 0
var _taps: int = 0
var _double_taps: int = 0


func _initialize() -> void:
	# Default settings, whatever the player has chosen.
	Settings.use_file("user://test_settings.json")
	# Keep the player's own save out of it.
	Progress.use_file("user://test_progress.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_scene = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_scene.level_path = "res://dev/sandbox_level.json"
	_viewport.add_child(_scene)
	_run()


func _run() -> void:
	await _frames(10)
	_camera = _scene.camera
	_camera.tapped.connect(func(_at: Vector2) -> void: _taps += 1)
	_camera.double_tapped.connect(func(_at: Vector2) -> void: _double_taps += 1)

	await _check_fit()
	await _check_taps()
	await _check_orbit()
	await _check_zoom()
	await _check_reset()

	print("%d check(s) failed" % _failures if _failures > 0 else "All checks passed")
	quit(1 if _failures > 0 else 0)


func _check_fit() -> void:
	var default_fill: float = _fill()
	_check(default_fill > 0.6 and default_fill <= 0.76, "default view fills %.0f%% of the frame" % (default_fill * 100.0))
	var worst: float = 0.0
	for step in 72:
		_set_view(step * 5.0, _camera.default_pitch, 1.0)
		worst = maxf(worst, _fill())
	_check(worst > 0.72 and worst < 0.78, "fill peaks at %.0f%% over a full orbit (target 75%%)" % (worst * 100.0))
	_set_view(_camera.default_yaw, _camera.default_pitch, 1.0)
	await _frames(2)


func _check_taps() -> void:
	# Open top of the front grass block.
	var top: Vector2 = _camera.unproject_position(Vector3(4.5, 1.0, 4.5))
	var hit: Dictionary = _scene.pick(top)
	_check(not hit.is_empty() and hit["cell"] == Vector3i(4, 0, 4) and hit["normal"] == Vector3i.UP,
		"picking the grass top returns cell (4,0,4), face up: %s" % [hit])
	var side: Vector2 = _camera.unproject_position(Vector3(5.0, 1.5, 2.5))
	hit = _scene.pick(side)
	_check(not hit.is_empty() and hit["cell"] == Vector3i(4, 1, 2) and hit["normal"] == Vector3i(1, 0, 0),
		"picking the house wall returns cell (4,1,2), face +x: %s" % [hit])
	_check(_scene.pick(Vector2(40, 60)).is_empty(), "picking the sky returns nothing")

	var taps_before: int = _taps
	_tap(top)
	await _frames(1)
	_check(_taps == taps_before + 1, "a still press is a tap")
	_check(_count_ripples() == 1, "a tap spawns a ripple")
	await _wait(0.15)
	_capture("step3_tap.png")

	taps_before = _taps
	_touch(0, top, true)
	_drag(0, top + Vector2(10, 0))
	_touch(0, top + Vector2(10, 0), false)
	_check(_taps == taps_before + 1, "moving 10 px is still a tap")

	var yaw_before: float = _camera._target_yaw
	taps_before = _taps
	_touch(0, top, true)
	_drag(0, top + Vector2(14, 0))
	_touch(0, top + Vector2(14, 0), false)
	_check(_taps == taps_before, "moving 14 px is a drag, not a tap")
	_check(not is_equal_approx(_camera._target_yaw, yaw_before), "the 14 px drag turned the view")
	await _wait(0.8)


func _check_orbit() -> void:
	# A quick flick: release right after the last move.
	var start := Vector2(200, 900)
	var yaw_before: float = _camera._target_yaw
	_touch(0, start, true)
	for i in range(1, 11):
		await _frames(1)
		_drag(0, start + Vector2(30 * i, 0))
	_touch(0, start + Vector2(300, 0), false)
	var yaw_at_release: float = _camera._target_yaw
	var expected: float = -300.0 / SIZE.x * OrbitCamera.YAW_PER_SCREEN
	_check(is_equal_approx(yaw_at_release - yaw_before, expected),
		"dragging right 300 px turns the yaw by %.1f° (expected %.1f°)" % [yaw_at_release - yaw_before, expected])
	await _wait(1.5)
	var coast: float = _camera._target_yaw - yaw_at_release
	_check(coast < -10.0 and coast > -150.0, "the flick keeps turning after release (%.1f° of inertia)" % coast)
	var settled: float = _camera._target_yaw
	await _wait(0.3)
	_check(absf(_camera._target_yaw - settled) < 1.0, "inertia settles")

	# A drag that rests before lifting does not fling.
	_touch(0, start, true)
	for i in range(1, 6):
		await _frames(1)
		_drag(0, start + Vector2(30 * i, 0))
	await _wait(0.2)
	_touch(0, start + Vector2(150, 0), false)
	var rested: float = _camera._target_yaw
	await _wait(0.4)
	_check(is_equal_approx(_camera._target_yaw, rested), "resting before lifting cancels the fling")

	# Pitch stays within its limits.
	_touch(0, start, true)
	for i in range(1, 6):
		_drag(0, start + Vector2(0, 600 * i))
	_touch(0, start + Vector2(0, 3000), false)
	await _wait(1.0)
	_check(absf(_camera.pitch - OrbitCamera.PITCH_MAX) < SETTLED, "pitch clamps at %.1f° (max 70°)" % _camera.pitch)
	_touch(0, start, true)
	for i in range(1, 6):
		_drag(0, start - Vector2(0, 600 * i))
	_touch(0, start - Vector2(0, 3000), false)
	await _wait(1.0)
	_check(absf(_camera.pitch - OrbitCamera.PITCH_MIN) < SETTLED, "pitch clamps at %.1f° (min 15°)" % _camera.pitch)


func _check_zoom() -> void:
	var taps_before: int = _taps
	_touch(0, Vector2(300, 640), true)
	_touch(1, Vector2(420, 640), true)
	_drag(0, Vector2(10, 640))
	_drag(1, Vector2(710, 640))
	_touch(0, Vector2(10, 640), false)
	_touch(1, Vector2(710, 640), false)
	await _wait(1.0)
	_check(absf(_camera.zoom - OrbitCamera.ZOOM_MAX) < SETTLED * 0.1, "pinching out zooms to %.2f (max 2.5)" % _camera.zoom)
	_check(_taps == taps_before, "a pinch is never a tap")

	_touch(0, Vector2(10, 640), true)
	_touch(1, Vector2(710, 640), true)
	_drag(0, Vector2(350, 640))
	_drag(1, Vector2(370, 640))
	_touch(0, Vector2(350, 640), false)
	_touch(1, Vector2(370, 640), false)
	await _wait(1.0)
	_check(absf(_camera.zoom - OrbitCamera.ZOOM_MIN) < SETTLED * 0.1, "pinching in zooms to %.2f (min 0.5)" % _camera.zoom)

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_viewport.push_input(wheel, true)
	_check(is_equal_approx(_camera._target_zoom, OrbitCamera.ZOOM_MIN * OrbitCamera.WHEEL_ZOOM_STEP), "the mouse wheel zooms in")
	await _wait(0.8)

	# Two fingers moving together pan the view, but never off the diorama.
	var yaw_before: float = _camera.yaw
	_touch(0, Vector2(300, 640), true)
	_touch(1, Vector2(420, 640), true)
	_drag(0, Vector2(300, 520))
	_drag(1, Vector2(420, 520))
	await _wait(0.6)
	var panned: Vector3 = _camera.pan
	for i in 6:
		_drag(0, Vector2(300 + 400 * (i % 2), 520 - 300 * i))
		_drag(1, Vector2(420 + 400 * (i % 2), 520 - 300 * i))
	_touch(0, Vector2(300, -1000), false)
	_touch(1, Vector2(420, -1000), false)
	await _wait(1.0)
	var half: Vector3 = _camera._bounds.size * 0.5
	_check(panned.length() > 0.2 and absf(wrapf(_camera.yaw - yaw_before, -180.0, 180.0)) < 0.5,
		"two fingers moving together pan the view (%.2f m) without turning it" % panned.length())
	_check(absf(_camera.pan.x) <= half.x + 0.01 and _camera.pan.y == 0.0 and absf(_camera.pan.z) <= half.z + 0.01,
		"the pan slides over the ground and stops at the diorama's edge (%s)" % [_camera.pan])


func _check_reset() -> void:
	# Show off a different angle with a red ripple on a wall first.
	_set_view(150.0, 50.0, 1.2)
	await _frames(2)
	var wall: Vector2 = _camera.unproject_position(Vector3(3.5, 1.5, 2.0))
	var hit: Dictionary = _scene.pick(wall)
	_check(not hit.is_empty() and hit["cell"] == Vector3i(3, 1, 2) and hit["normal"] == Vector3i(0, 0, -1),
		"picking from behind returns cell (3,1,2), face -z: %s" % [hit])
	_tap(wall)
	await _wait(0.15)
	_capture("step3_orbit.png")
	await _wait(0.8)

	var doubles_before: int = _double_taps
	var block: Vector2 = _camera.unproject_position(Vector3(2.5, 1.0, 2.5))
	_tap(block)
	_tap(block)
	await _wait(1.0)
	_check(_double_taps == doubles_before + 1, "two quick taps make a double tap")
	_check(absf(wrapf(_camera.yaw - 150.0, -180.0, 180.0)) < 0.5, "a double tap on a block keeps the view")

	_tap(Vector2(40, 420))
	_tap(Vector2(40, 420))
	await _wait(1.5)
	_check(absf(wrapf(_camera.yaw - _camera.default_yaw, -180.0, 180.0)) < SETTLED
			and absf(_camera.pitch - _camera.default_pitch) < SETTLED
			and absf(_camera.zoom - 1.0) < SETTLED * 0.1 and _camera.pan.length() < 0.05,
		"a double tap on empty space resets the view (yaw %.1f, pitch %.1f, zoom %.2f, pan %.2f m)" % [_camera.yaw, _camera.pitch, _camera.zoom, _camera.pan.length()])


## Largest distance of a bounds corner from the screen centre, as a fraction
## of the half width/height.
func _fill() -> float:
	var half := Vector2(SIZE) * 0.5
	var bounds: AABB = _scene.grid.bounds
	var worst: float = 0.0
	for i in 8:
		var at: Vector2 = _camera.unproject_position(bounds.get_endpoint(i))
		worst = maxf(worst, maxf(absf(at.x - half.x) / half.x, absf(at.y - half.y) / half.y))
	return worst


func _set_view(yaw: float, pitch: float, zoom: float) -> void:
	_camera._velocity = Vector2.ZERO
	_camera.yaw = yaw
	_camera._target_yaw = yaw
	_camera.pitch = pitch
	_camera._target_pitch = pitch
	_camera.zoom = zoom
	_camera._target_zoom = zoom
	_camera.pan = Vector3.ZERO
	_camera._target_pan = Vector3.ZERO
	_camera._update_transform()


func _count_ripples() -> int:
	var count: int = 0
	for child in _scene.get_children():
		if child is TapRipple:
			count += 1
	return count


func _tap(at: Vector2) -> void:
	_touch(0, at, true)
	_touch(0, at, false)


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_viewport.push_input(event, true)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	_viewport.push_input(event, true)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _capture(file_name: String) -> void:
	var path: String = _out_dir.path_join(file_name)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_viewport.get_texture().get_image().save_png(path)
	print("saved ", path)
