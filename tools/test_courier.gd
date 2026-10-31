extends SceneTree
## Scripted check of pathfinding and tap-to-move on the sandbox level: which
## cells are walkable, climbing via stairs, unreachable taps, re-targeting
## mid-walk, and the courier's poses. Taps go through the real input path.
## Prints PASS/FAIL per check, saves screenshots (including close-up
## portraits of the courier), and exits with status 1 on any failure. Needs a
## renderer (not --headless).
##
##   godot --path . --resolution 405x720 -s res://tools/test_courier.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
## Open corner on the sand with nothing between it and a portrait camera.
const SAND_CORNER := Vector3i(0, 1, 0)

var _viewport: SubViewport
var _scene: Node3D
var _out_dir: String = "docs/screenshots"
var _failures: int = 0


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
	var paths: Pathfinder = _scene.pathfinder
	var courier: Courier = _scene.courier

	# The graph.
	_check(paths.is_walkable(Vector3i(1, 1, 2)), "the start cell on the grass is walkable")
	_check(paths.is_walkable(Vector3i(2, 1, 3)), "the stairs are walkable")
	_check(not paths.is_walkable(Vector3i(3, 1, 0)), "the top of water is not walkable")
	_check(not paths.is_walkable(Vector3i(0, 1, 3)), "a cell filled by a block is not walkable")
	var climb: Array[Vector3i] = paths.find_path(Vector3i(1, 1, 2), Vector3i(3, 2, 4))
	_check(climb.has(Vector3i(2, 1, 3)) and climb.size() == 5,
		"the way up to the walkway goes over the stairs: %s" % [climb])
	_check(paths.find_path(Vector3i(1, 1, 2), Vector3i(0, 5, 4)).is_empty(), "the tower top cannot be reached")
	_check(paths.find_path(Vector3i(2, 1, 2), Vector3i(2, 2, 3)).is_empty(), "nothing climbs a block without stairs")

	# Portrait in the open sand corner, front-right three-quarter view.
	courier.place(SAND_CORNER)
	await _wait(0.3)
	await _portrait("step4_courier.png", courier, _front_right(courier))
	courier.place(Vector3i(1, 1, 2))
	await _frames(2)

	# Tap the walkway top: the courier climbs the stairs to get there.
	_tap_top(Vector3i(3, 1, 4))
	var highest: float = 0.0
	var shot_on_stairs: bool = false
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 4000:
		await process_frame
		highest = maxf(highest, courier.position.y)
		if not shot_on_stairs and courier.position.y > 1.4:
			shot_on_stairs = true
			await _portrait("step4_climb.png", courier, _scene.camera.global_basis.z, 3.0)
		if not courier.is_moving():
			break
	_check(courier.cell == Vector3i(3, 2, 4), "tapping the walkway walks there (now at %s)" % [courier.cell])
	_check(is_equal_approx(courier.position.y, 2.0) and highest <= 2.001, "it stands on the walkway at height 2")

	# An unreachable tap: nothing moves, a red ripple and a puzzled tilt.
	_tap_top(Vector3i(0, 4, 4))
	await _wait(0.12)
	_check(not courier.is_moving() and courier.cell == Vector3i(3, 2, 4), "tapping the tower top does not move the courier")
	_check(courier._tilt > 0.1, "the courier tilts its head, puzzled")
	await _wait(0.8)

	# Re-targeting mid-walk: the second tap wins.
	_tap_top(Vector3i(1, 1, 4))
	await _wait(0.1)
	_tap_top(Vector3i(2, 1, 4))
	await _wait(1.5)
	_check(courier.cell == Vector3i(2, 2, 4), "a new tap mid-walk re-routes (now at %s)" % [courier.cell])

	# Back down the stairs and across to the sand corner.
	_tap_top(SAND_CORNER - Vector3i.UP)
	await _wait(3.0)
	_check(courier.cell == SAND_CORNER and is_equal_approx(courier.position.y, 1.0),
		"walking back down the stairs to the sand corner (now at %s)" % [courier.cell])

	courier.place(SAND_CORNER)
	courier.set_carried([&"red"])
	courier.celebrate()
	await _wait(0.62)
	await _portrait("step4_happy.png", courier, _front_right(courier))

	print("%d check(s) failed" % _failures if _failures > 0 else "All checks passed")
	quit(1 if _failures > 0 else 0)


## Taps the centre of the top face of [param block] through the camera.
func _tap_top(block: Vector3i) -> void:
	var camera: OrbitCamera = _scene.camera
	var at: Vector2 = camera.unproject_position(Vector3(block) + Vector3(0.5, 1.0, 0.5))
	var hit: Dictionary = _scene.pick(at)
	if hit.is_empty() or hit["cell"] != block:
		print("note: tap aimed at %s picks %s" % [block, hit])
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = at
		event.pressed = pressed
		_viewport.push_input(event, true)


## Direction from the courier towards a camera in front of it, to its right
## and above.
func _front_right(courier: Courier) -> Vector3:
	var forward: Vector3 = -courier.global_basis.z
	return (forward * 0.75 + courier.global_basis.x * 0.45 + Vector3.UP * 0.5).normalized()


## Close-up of the courier from [param direction] at [param distance] metres,
## taken with a temporary camera without depth of field.
func _portrait(file_name: String, courier: Courier, direction: Vector3, distance: float = 2.3) -> void:
	var orbit: OrbitCamera = _scene.camera
	var portrait := Camera3D.new()
	portrait.fov = 30.0
	portrait.attributes = CameraAttributesPractical.new()
	_scene.add_child(portrait)
	# Aim at the middle of the body, following it up when it hops.
	var target: Vector3 = courier.global_position + Vector3(0.0, 0.3 + courier._hop, 0.0)
	portrait.global_position = target + direction.normalized() * distance
	portrait.look_at(target)
	portrait.make_current()
	await _frames(3)
	var image: Image = _viewport.get_texture().get_image()
	image = image.get_region(Rect2i(0, (SIZE.y - SIZE.x) / 2, SIZE.x, SIZE.x))
	_save(image, file_name)
	orbit.make_current()
	portrait.queue_free()
	await _frames(1)


func _capture(file_name: String) -> void:
	_save(_viewport.get_texture().get_image(), file_name)


func _save(image: Image, file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var path: String = _out_dir.path_join(file_name)
	image.save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1
