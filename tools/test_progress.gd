extends SceneTree
## Scripted check of undo, restart, hints, stars and saving: the Solver finds
## each level's 3-star route, Progress keeps bests and survives a corrupt
## file, a game in progress comes back after closing, undo and restart
## rebuild the diorama, the HUD buttons work through the touch path, and
## following the hints alone finishes every level with 3 stars. Prints
## PASS/FAIL per check, saves screenshots, and exits with status 1 on any
## failure. Needs a renderer.
##
##   godot --path . --resolution 405x720 -s res://tools/test_progress.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
const SAVE := "user://test_progress.json"
const LEVEL_1 := "res://levels/world_1/level_1.json"
## Every finishable level (the sandbox is only for walking about).
const LEVELS: Array[String] = [
	"res://dev/mechanisms/slider.json", "res://dev/mechanisms/elevator.json", "res://dev/mechanisms/button.json",
	"res://dev/mechanisms/conveyor.json", "res://dev/mechanisms/rotator.json", "res://dev/mechanisms/gate.json",
	LEVEL_1,
]
## Level 1: the parcel, and the pad up the stairs.
const PARCEL := Vector3i(2, 1, 3)
const PAD := Vector3i(5, 2, 1)

var _viewport: SubViewport
var _level: Level
var _out_dir: String = "docs/screenshots"
var _failures: int = 0


func _initialize() -> void:
	# Default settings, whatever the player has chosen.
	Settings.use_file("user://test_settings.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_check_solver()
	_check_save_file()
	_check_saved_game()
	Progress.use_file(SAVE)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run()


func _check_solver() -> void:
	for path: String in LEVELS:
		var data: LevelData = LevelLoader.load_file(path)
		var solver := Solver.new(data)
		var plan: Array[Dictionary] = solver.solve(LevelState.new(data).snapshot())
		var moves: int = plan[-1]["moves"] if not plan.is_empty() else -1
		_check(moves == data.stars[0], "%s: the shortest finish (%d moves, %d states) is the 3-star limit %d"
			% [path.get_file(), moves, solver.explored, data.stars[0]])
		var replay := LevelState.new(data)
		for action: Dictionary in plan:
			Solver.apply_to(replay, action)
		_check(replay.completed and replay.moves == moves, "%s: playing the plan by the rules finishes it" % path.get_file())
	var stuck: LevelData = LevelLoader.parse(JSON.stringify({
		"name": "Stuck", "blocks": [[0, 0, 0, "grass"], [1, 0, 0, "grass"], [2, 0, 0, "grass"], [4, 0, 0, "grass"]],
		"packages": [{"pos": [4, 1, 0], "color": "red"}], "pads": [{"pos": [1, 1, 0], "color": "red"}],
		"start": [0, 1, 0], "exit": [2, 1, 0], "stars": [3, 4, 5],
	}))
	var solver := Solver.new(stuck)
	_check(stuck.is_valid() and solver.solve(LevelState.new(stuck).snapshot()).is_empty() and not solver.gave_up,
		"a level that cannot be finished has no plan %s" % [stuck.errors])


func _check_save_file() -> void:
	var id: String = "world_1/level_1"
	Progress.use_file(SAVE)
	_check(Progress.best(id).is_empty() and Progress.total_stars() == 0, "a fresh save has nothing finished")
	_check(Progress.record(id, 14, 2), "a first finish is a new best")
	_check(not Progress.record(id, 16, 2), "a slower finish with as many stars is not")
	_check(Progress.record(id, 13, 2), "fewer moves for as many stars is")
	_check(Progress.record(id, 11, 3) and not Progress.record(id, 12, 2), "more stars is; fewer stars never is")
	Progress.record("world_1/level_2", 9, 2)
	_check(Progress.total_stars() == 5, "stars add up over levels (%d)" % Progress.total_stars())
	Progress.use_file(SAVE, false)
	_check(Progress.best(id) == {"stars": 3, "moves": 11} and Progress.total_stars() == 5,
		"bests come back from the file, which each save replaced (%s)" % [Progress.best(id)])
	_check(not FileAccess.file_exists(SAVE + ".tmp"), "no temporary file is left behind")

	if FileAccess.file_exists(SAVE + ".bad"):
		DirAccess.remove_absolute(SAVE + ".bad")
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string("{\"levels\": [1, 2")
	file.close()
	print("(a warning about an unreadable save is expected next)")
	Progress.use_file(SAVE, false)
	_check(Progress.total_stars() == 0 and FileAccess.file_exists(SAVE + ".bad") and not FileAccess.file_exists(SAVE),
		"a corrupt save is set aside as .bad and play starts afresh")
	Progress.record(id, 15, 1)
	_check(FileAccess.file_exists(SAVE), "the next finish writes a new save")
	DirAccess.remove_absolute(SAVE + ".bad")


func _check_saved_game() -> void:
	var id: String = "world_1/level_1"
	Progress.use_file(SAVE)
	var data: LevelData = LevelLoader.load_file(LEVEL_1)
	var play := LevelState.new(data)
	var history: Array[Dictionary] = []
	for cell: Vector3i in [Vector3i(1, 1, 3), PARCEL]:
		history.append(play.snapshot())
		play.enter(cell)
	Progress.keep_in_progress(id, data.fingerprint, history, play.snapshot())
	Progress.use_file(SAVE, false)
	var saved: Dictionary = Progress.in_progress(id, data.fingerprint, LevelState.new(data))
	_check(not saved.is_empty() and var_to_str(saved["state"]) == var_to_str(play.snapshot())
		and var_to_str(saved["history"]) == var_to_str(history), "a game in progress comes back from the file exactly")
	_check(Progress.in_progress(id, "an older version", LevelState.new(data)).is_empty(),
		"a game saved on an older version of the level is not resumed")
	var broken: Dictionary = play.snapshot()
	broken["carried"] = []
	Progress.keep_in_progress(id, data.fingerprint, history, broken)
	_check(Progress.in_progress(id, data.fingerprint, LevelState.new(data)).is_empty(),
		"a saved game that does not fit the level (a parcel missing) is not resumed")


func _run() -> void:
	await _undo_and_restart()
	await _hud_buttons()
	await _resume()
	for path: String in LEVELS:
		await _follow_hints(path)
	await _finish_card()
	print("%d check(s) failed" % _failures if _failures > 0 else "All checks passed")
	quit(1 if _failures > 0 else 0)


func _undo_and_restart() -> void:
	await _open(LEVEL_1)
	var start: Vector3i = _level.state.courier
	await _walk_to(PARCEL)
	_check(_level.state.carried.size() == 1 and _level.state.moves == 2, "walking onto the parcel picks it up in 2 moves")
	_check(_level.undo(), "undo is allowed")
	await _frames(2)
	_check(_level.state.moves == 0 and _level.courier.cell == start
		and _level.courier.position.is_equal_approx(_level.pathfinder.floor_position(start)),
		"undo takes the whole walk back, courier and all")
	_check(_level._packages.has(PARCEL) and (_level._packages[PARCEL] as Package).visible and _level._carried.is_empty(),
		"and puts the parcel back on the floor")

	await _walk_to(PARCEL)
	_tap_cell(PAD)
	var started: int = Time.get_ticks_msec()
	while not _level.state.filled.has(PAD) and Time.get_ticks_msec() - started < 8000:
		await process_frame
	_check(_level.undo(), "undo works the moment the parcel is dropped")
	await _wait(Package.DROP_TIME + 0.3)
	var pad: Pad = _level._pads[PAD]
	_check(not pad.filled and _level._delivered.is_empty() and _level._carried.size() == 1
		and not _level._carried[0].visible and _level.courier.cell == PARCEL,
		"the parcel goes back in the mailbox and the pad stays unlit")

	_check(_level.restart(), "restart is allowed")
	await _frames(2)
	_check(_level.state.moves == 0 and _level.courier.cell == start and _level._packages.has(PARCEL), "restart goes back to the start")
	_check(_level.undo() and _level.state.moves == 2 and _level.courier.cell == PARCEL, "and can itself be undone")


func _hud_buttons() -> void:
	await _open(LEVEL_1)
	var hud: Hud = _level.hud
	var undo: TouchButton = hud.get_node("Root/Safe/Buttons/Undo")
	var restart: TouchButton = hud.get_node("Root/Safe/Buttons/Restart")
	var hint: TouchButton = hud.get_node("Root/Safe/Buttons/Hint")
	await _frames(2)
	_check(undo.disabled and restart.disabled and not hint.disabled, "at the start only Hint can be used")
	await _walk_to(PARCEL)
	await _frames(2)
	_check(not undo.disabled and not restart.disabled and hud._moves.text == "2", "after a walk Undo and Restart light up and the HUD counts 2")
	_capture("step7_hud.png")
	await _press(undo)
	_check(_level.state.moves == 0 and hud._moves.text == "0", "tapping Undo takes the walk back")
	await _press(hint)
	_check(_level.has_hint() and _level.hinted()["cell"] == PARCEL and hud.toast_text() == "Walk to the arrow.",
		"tapping Hint points at the parcel and says what to do (%s)" % [_level.hinted()])
	await _wait(0.5)
	_capture("step7_hint.png")
	_tap_cell(Vector3i(1, 1, 1))
	await _settle()
	await _frames(2)
	_check(not _level.has_hint() and hud.toast_text().is_empty(), "walking elsewhere clears the hint and its toast")


func _resume() -> void:
	await _open(LEVEL_1)
	await _walk_to(PARCEL)
	await _walk_to(Vector3i(1, 1, 1))
	var moves: int = _level.state.moves
	var undos: int = _level.undo_count()
	# Closing saves the game; reloading the file stands in for a fresh app start.
	await _open(LEVEL_1, false)
	_check(_level.state.moves == moves and _level.courier.cell == Vector3i(1, 1, 1) and _level.undo_count() == undos
		and _level._carried.size() == 1 and _level.hud._moves.text == str(moves),
		"closing and reopening the level picks up where it was, undo history and all (%d moves)" % _level.state.moves)
	_check(_level.undo() and _level.courier.cell == PARCEL and _level.state.moves == 2, "and undo still works after resuming")


func _follow_hints(path: String) -> void:
	await _open(path)
	var data: LevelData = _level.data
	var hint: TouchButton = _level.hud.get_node("Root/Safe/Buttons/Hint")
	var hints: int = 0
	while not _level.state.completed and hints < 60:
		await _settle()
		await _press(hint)
		var asked: Dictionary = _level.hinted()
		if asked.is_empty():
			print("note: no hint on %s (%s)" % [path.get_file(), _level.hud.toast_text()])
			break
		hints += 1
		if asked["action"] == Solver.Action.SLIDE:
			await _wait(0.5)
			_capture("step7_hint_slider.png")
		match asked["action"]:
			Solver.Action.STEP:
				_tap_cell(asked["cell"])
			Solver.Action.SLIDE:
				await _drag_slider(asked["id"], asked["to"])
			Solver.Action.TURN:
				var handle: Vector3i = (_level.state.mechanisms[asked["id"]] as Mechanism).handle
				var at: Vector2 = _screen(Vector3(handle) + Vector3(0.5, 0.6, 0.5))
				_touch(at, true)
				_touch(at, false)
		await _settle()
	var moves: int = _level.state.moves
	_check(_level.state.completed and moves == data.stars[0] and data.stars_for(moves) == 3,
		"%s: following %d hints alone finishes with 3 stars (%d moves)" % [path.get_file(), hints, moves])


## Level 1 was just finished by following hints.
func _finish_card() -> void:
	var hud: Hud = _level.hud
	var id: String = Progress.level_id(LEVEL_1)
	_check(_level.finished_best and Progress.best(id) == {"stars": 3, "moves": _level.data.stars[0]},
		"the finish is saved as level 1's best (%s)" % [Progress.best(id)])
	Progress.use_file(SAVE, false)
	_check(Progress.in_progress(id, _level.data.fingerprint, LevelState.new(_level.data)).is_empty(),
		"a finished level is not kept as a game in progress")
	await _wait(Hud.FINISH_DELAY + 1.2)
	_check(hud.is_finish_showing() and hud._finish_stars.lit == 3 and hud._finish_best.text == "New best!",
		"the finish card shows 3 stars and a new best")
	_capture("step7_complete.png")
	await _press(hud.get_node("Root/Finish/Card/Replay"))
	await _wait(0.5)
	_check(_level.state.moves == 0 and not _level.state.completed and not hud.is_finish_showing() and not _level.can_undo(),
		"Replay starts afresh (a finished game is not brought back by undo)")
	_check(Progress.best(id)["moves"] == _level.data.stars[0], "and the best is kept")


## Opens [param path]; [param fresh] forgets a saved game of it first,
## otherwise the save file is reread as if the app had restarted.
func _open(path: String, fresh: bool = true) -> void:
	if _level:
		_level.queue_free()
		await _frames(2)
	if fresh:
		Progress.drop_in_progress(Progress.level_id(path))
	else:
		Progress.use_file(SAVE, false)
	_level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_level.level_path = path
	_viewport.add_child(_level)
	await _frames(8)


func _walk_to(cell: Vector3i) -> void:
	_tap_cell(cell)
	await _settle()


## Taps the block whose top (or stairs) leads to [param cell], trying a few
## spots on it in case another block hides the middle.
func _tap_cell(cell: Vector3i) -> void:
	var stairs: bool = _level.grid.is_stairs_at(cell)
	var block: Vector3i = cell if stairs else cell - Vector3i.UP
	var height: float = 0.5 if stairs else 1.0
	for spot: Vector2 in [Vector2(0.5, 0.5), Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.3, 0.7), Vector2(0.7, 0.3)]:
		var at: Vector2 = _screen(Vector3(block) + Vector3(spot.x, height, spot.y))
		var hit: Dictionary = _level.pick(at)
		if not hit.is_empty() and _level.pathfinder.target_for_block(hit["cell"]) == cell:
			_touch(at, true)
			_touch(at, false)
			return
	print("note: nothing on screen taps %s" % [cell])


func _drag_slider(id: String, to: int) -> void:
	var mechanism: Mechanism = _level.state.mechanisms[id]
	var value: int = _level.state.values[id]
	var top: Vector3 = Level._centre(mechanism.cells_at(value)) + Vector3(0.0, 0.5, 0.0)
	var from: Vector2 = _screen(top)
	var target: Vector2 = _screen(top + Vector3(mechanism.axis * (to - value)))
	_touch(from, true)
	for i in range(1, 11):
		await _frames(1)
		_drag(from.lerp(target, i / 10.0))
	await _frames(1)
	_touch(target, false)


## Taps a HUD button through the touch path.
func _press(button: TouchButton) -> void:
	var at: Vector2 = button.get_global_rect().get_center()
	_touch(at, true)
	await _frames(1)
	_touch(at, false)
	await _frames(2)


## Waits until nothing moves: no animation, no walking.
func _settle() -> void:
	var still: int = 0
	var started: int = Time.get_ticks_msec()
	while still < 6 and Time.get_ticks_msec() - started < 8000:
		await process_frame
		still = still + 1 if not _level.is_busy() and not _level.courier.is_moving() else 0


func _screen(point: Vector3) -> Vector2:
	return _level.camera.unproject_position(point)


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	_viewport.push_input(event, true)


func _drag(at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = at
	_viewport.push_input(event, true)


func _capture(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var path: String = _out_dir.path_join(file_name)
	_viewport.get_texture().get_image().save_png(path)
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
