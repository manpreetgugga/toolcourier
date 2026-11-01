extends SceneTree
## Scripted check of levels: LevelLoader error reporting, the delivery rules
## in LevelState, and a full play-through of world 1 level 1 by tapping
## (pickup, delivery, exit, stars). Prints PASS/FAIL per check, saves
## screenshots, and exits with status 1 on any failure. Needs a renderer.
##
##   godot --path . --resolution 405x720 -s res://tools/test_level.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
const LEVEL := "res://levels/world_1/level_1.json"
## Shortest route through level 1: to the parcel, up the stairs to the pad,
## then to the exit.
const ROUTE: Array[Vector3i] = [
	Vector3i(1, 1, 3), Vector3i(2, 1, 3), Vector3i(1, 1, 3), Vector3i(1, 1, 2), Vector3i(1, 1, 1),
	Vector3i(2, 1, 1), Vector3i(3, 2, 1), Vector3i(4, 2, 1), Vector3i(5, 2, 1), Vector3i(4, 2, 1),
	Vector3i(4, 2, 0),
]

var _viewport: SubViewport
var _scene: Level
var _out_dir: String = "docs/screenshots"
var _failures: int = 0
var _completed: Array = []


func _initialize() -> void:
	# Default settings, whatever the player has chosen.
	Settings.use_file("user://test_settings.json")
	# Keep the player's own save out of it.
	Progress.use_file("user://test_progress.json")
	# No ads: Hint gives hints straight away, and no level break plays.
	Ads.enabled = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_check_loader()
	_check_rules()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_scene = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_scene.level_path = LEVEL
	_scene.level_completed.connect(func(moves: int, stars: int) -> void: _completed = [moves, stars])
	_viewport.add_child(_scene)
	_play()


func _check_loader() -> void:
	var level: LevelData = LevelLoader.load_file(LEVEL)
	_check(level.is_valid(), "level 1 loads without problems %s" % [level.errors])
	_check(level.name == "First Delivery" and level.carry_limit == 1 and level.stars == [11, 14, 18],
		"level 1 has its name, carry limit and star limits")
	_check(not LevelLoader.parse("{ \"name\": ").is_valid(), "broken JSON is reported")
	var broken: LevelData = LevelLoader.parse(JSON.stringify({
		"name": "Broken", "blocks": [[0, 0, 0, "stone"], [1, 0, 0, "lava"]],
		"packages": [{"pos": [0, 0, 0], "color": "red"}], "pads": [],
		"start": [0, 1, 0], "exit": [0, 1, 0], "stars": [3, 2, 1],
	}))
	var report: String = "\n".join(broken.errors)
	_check(report.contains("blocks[1]") and report.contains("lava"), "an unknown block type is named with its index")
	_check(report.contains("stars"), "decreasing star limits are reported")
	var misplaced: LevelData = LevelLoader.parse(JSON.stringify({
		"name": "Misplaced", "blocks": [[0, 0, 0, "stone"], [1, 0, 0, "stone"]],
		"packages": [{"pos": [0, 0, 0], "color": "red"}], "pads": [{"pos": [1, 1, 0], "color": "blue"}],
		"start": [0, 1, 0], "exit": [1, 1, 0], "stars": [3, 4, 5],
	}))
	report = "\n".join(misplaced.errors)
	_check(report.contains("packages[0]") and report.contains("not a cell the courier can stand in"),
		"a parcel inside a block is reported")
	_check(report.contains("red: 1 parcel(s) but 0 pad(s)") and report.contains("blue: 0 parcel(s) but 1 pad(s)"),
		"unmatched parcel and pad colours are reported")
	_check(report.contains("pads[0]") and report.contains("already used by exit"), "two things in one cell are reported")


func _check_rules() -> void:
	var level: LevelData = LevelLoader.load_file(LEVEL)
	var rules := LevelState.new(level)
	_check(rules.enter(level.exit).is_empty() and not rules.completed, "the exit does nothing before the pad is filled")
	rules = LevelState.new(level)
	var log: Array[String] = []
	var saved: Dictionary
	for cell: Vector3i in ROUTE:
		for event: Dictionary in rules.enter(cell):
			log.append("%s@%s" % [LevelState.Event.keys()[event["event"]], event["cell"]])
		if cell == Vector3i(2, 1, 3):
			saved = rules.snapshot()
	_check(log == ["PICKUP@(2, 1, 3)", "DROP@(5, 2, 1)", "EXIT_OPENED@(4, 2, 0)", "COMPLETED@(4, 2, 0)"],
		"the shortest route picks up, delivers, opens the exit and completes: %s" % [log])
	_check(rules.moves == 11 and level.stars_for(rules.moves) == 3, "it takes 11 moves, worth three stars")
	_check(level.stars_for(14) == 2 and level.stars_for(18) == 1 and level.stars_for(19) == 0, "star limits 11 / 14 / 18")
	rules.restore(saved)
	_check(rules.moves == 2 and rules.carried == [&"red"] and rules.filled.is_empty() and not rules.completed,
		"a snapshot restores moves, load and pads")


func _play() -> void:
	await _frames(10)
	_capture("step5_level.png")
	var courier: Courier = _scene.courier

	await _tap_and_walk(Vector3i(2, 0, 3))
	_check(courier.cell == Vector3i(2, 1, 3) and _scene.state.carried == [&"red"], "tapping the parcel picks it up")
	await _wait(0.5)
	_check(_scene._carried.size() == 1 and not _scene._carried[0].visible, "the parcel disappears into the mailbox")

	_tap(Vector3i(5, 1, 1))
	var pad: Pad = _scene._pads[Vector3i(5, 2, 1)]
	var started: int = Time.get_ticks_msec()
	while not pad.filled and Time.get_ticks_msec() - started < 6000:
		await process_frame
	await _wait(0.12)
	await _portrait("step5_delivery.png", pad.global_position + Vector3(0.0, 0.25, 0.0), 3.2)
	await _until_still(courier)
	_check(pad.filled and _scene.state.all_delivered() and _scene.state.carried.is_empty(), "walking onto the pad delivers the parcel")
	_check(_scene._exit.open, "the exit opens once every pad is filled")

	await _tap_and_walk(Vector3i(4, 1, 0))
	await _wait(0.4)
	_check(_completed == [11, 3], "reaching the exit completes the level in 11 moves for 3 stars (got %s)" % [_completed])
	await _wait(0.9)
	_capture("step5_complete.png")

	print("%d check(s) failed" % _failures if _failures > 0 else "All checks passed")
	quit(1 if _failures > 0 else 0)


## Taps the top of [param block] and waits until the courier stops.
func _tap_and_walk(block: Vector3i) -> void:
	_tap(block)
	await _until_still(_scene.courier)


func _tap(block: Vector3i) -> void:
	var at: Vector2 = _scene.camera.unproject_position(Vector3(block) + Vector3(0.5, 1.0, 0.5))
	var hit: Dictionary = _scene.pick(at)
	if hit.is_empty() or hit["cell"] != block:
		print("note: tap aimed at %s picks %s" % [block, hit])
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = at
		event.pressed = pressed
		_viewport.push_input(event, true)


func _until_still(courier: Courier) -> void:
	await _frames(2)
	var started: int = Time.get_ticks_msec()
	while courier.is_moving() and Time.get_ticks_msec() - started < 8000:
		await process_frame


## Close-up looking at [param target] from the orbit camera's side.
func _portrait(file_name: String, target: Vector3, distance: float) -> void:
	var orbit: OrbitCamera = _scene.camera
	var portrait := Camera3D.new()
	portrait.fov = 30.0
	portrait.attributes = CameraAttributesPractical.new()
	_scene.add_child(portrait)
	portrait.global_position = target + orbit.global_basis.z * distance
	portrait.look_at(target)
	portrait.make_current()
	await _frames(2)
	var image: Image = _viewport.get_texture().get_image()
	_save(image.get_region(Rect2i(0, (SIZE.y - SIZE.x) / 2, SIZE.x, SIZE.x)), file_name)
	orbit.make_current()
	portrait.queue_free()


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
