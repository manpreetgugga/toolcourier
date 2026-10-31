extends SceneTree
## Scripted check of every mechanism, each on its own small test level in
## dev/mechanisms/: a slider dragged into place, an elevator ridden up, a
## button calling an elevator down, a belt carrying the courier one way, a
## crank turning a bridge, and a gate opened by two buttons. Input goes
## through the real touch path. Prints PASS/FAIL per check, saves a
## screenshot per mechanism, and exits with status 1 on any failure. Needs a
## renderer.
##
##   godot --path . --resolution 405x720 -s res://tools/test_mechanisms.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)

var _viewport: SubViewport
var _level: Level
var _out_dir: String = "docs/screenshots"
var _failures: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_check_loader()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run()


func _check_loader() -> void:
	for name: String in ["slider", "elevator", "button", "conveyor", "rotator", "gate"]:
		var level: LevelData = LevelLoader.load_file("res://dev/mechanisms/%s.json" % name)
		_check(level.is_valid(), "the %s test level loads %s" % [name, level.errors])
	var broken: LevelData = LevelLoader.parse(JSON.stringify({
		"name": "Broken", "blocks": [[0, 0, 0, "stone"], [1, 0, 0, "stone"]],
		"mechanisms": [
			{"id": "b1", "type": "button", "pos": [0, 1, 0], "targets": ["nowhere"]},
			{"id": "s1", "type": "slider", "cells": [[1, 0, 0]], "axis": "x", "min": 0, "max": 2},
		],
		"start": [0, 1, 0], "exit": [0, 1, 0], "stars": [1, 2, 3],
	}))
	var report: String = "\n".join(broken.errors)
	_check(report.contains("no mechanism \"nowhere\""), "a button aimed at a missing mechanism is reported")
	_check(report.contains("overlaps a level block"), "a mechanism block inside a level block is reported")


func _run() -> void:
	await _slider()
	await _elevator()
	await _button()
	await _conveyor()
	await _rotator()
	await _gate()
	print("%d check(s) failed" % _failures if _failures > 0 else "All checks passed")
	quit(1 if _failures > 0 else 0)


func _slider() -> void:
	await _open("slider")
	# Drag the bar one cell along +z, into the gap.
	var from: Vector2 = _screen(Vector3(3.0, 1.0, 0.5))
	var to: Vector2 = _screen(Vector3(3.0, 1.0, 1.5))
	_touch(from, true)
	for i in range(1, 9):
		await _frames(1)
		_drag(from.lerp(to, i / 8.0))
	await _frames(1)
	_touch(to, false)
	await _settle()
	_check(_level.state.values["s1"] == 1 and _level.state.moves == 1, "dragging the slider one cell moves it there for one move")
	_capture("step6_slider.png")
	await _walk_to_exit(Vector3i(5, 0, 2))
	_check(_level.state.completed and _level.state.moves == 7, "the courier crosses the slider bridge to the exit in 7 moves (%d)" % _level.state.moves)


func _elevator() -> void:
	await _open("elevator")
	_tap_top(Vector3i(2, 0, 1))
	var shot: bool = false
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 6000:
		await process_frame
		if not shot and _level.is_busy() and _level.courier.global_position.y > 1.6:
			shot = true
			_capture("step6_elevator.png")
		if not _level.is_busy() and not _level.courier.is_moving() and _level.state.values["e1"] == 1:
			break
	await _settle()
	_check(_level.state.values["e1"] == 1 and _level.courier.cell == Vector3i(2, 3, 1),
		"stepping onto the elevator rides it up (courier at %s)" % [_level.courier.cell])
	_check(is_equal_approx(_level.courier.position.y, 3.0), "the courier stands on the raised platform")
	await _walk_to_exit(Vector3i(0, 2, 1))
	_check(_level.state.completed and _level.state.moves == 5, "then on to the exit in 5 moves (%d)" % _level.state.moves)


func _button() -> void:
	await _open("button")
	_check(_level.state.values["e1"] == 1 and not _level.pathfinder.is_walkable(Vector3i(2, 1, 1)),
		"the elevator starts out of reach at the top")
	_tap_top(Vector3i(5, 0, 2))
	await _settle()
	_check(_level.state.values["b1"] == 1 and _level.state.values["e1"] == 0, "stepping on the button brings the elevator down")
	_capture("step6_button.png")
	_tap_top(Vector3i(2, 0, 1))
	await _settle()
	await _walk_to_exit(Vector3i(0, 2, 1))
	_check(_level.state.completed and _level.state.moves == 9, "then up and on to the exit in 9 moves (%d)" % _level.state.moves)


func _conveyor() -> void:
	await _open("conveyor")
	_tap_top(Vector3i(6, 0, 0))
	var shot: bool = false
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 6000:
		await process_frame
		if not shot and _level.courier.global_position.x > 3.2:
			shot = true
			_capture("step6_conveyor.png")
		if _level.state.completed:
			break
	await _settle()
	_check(_level.state.completed and _level.state.moves == 4,
		"the belt carries the courier across; only the 4 walked cells count (%d)" % _level.state.moves)
	_check(_level.pathfinder.find_path(Vector3i(5, 1, 0), Vector3i(1, 1, 0)).is_empty(), "the belt only runs one way")


func _rotator() -> void:
	await _open("rotator")
	_check(_level.pathfinder.find_path(Vector3i(0, 1, 1), Vector3i(6, 1, 1)).is_empty(), "the bridge starts turned away")
	_tap_top(Vector3i(1, 1, 0), 0.6)
	await _settle()
	_check(_level.state.values["r1"] == 1 and _level.state.moves == 1, "tapping the crank turns the bridge a quarter, for one move")
	_capture("step6_rotator.png")
	await _walk_to_exit(Vector3i(6, 0, 1))
	_check(_level.state.completed and _level.state.moves == 7, "the courier crosses the turned bridge in 7 moves (%d)" % _level.state.moves)


func _gate() -> void:
	await _open("gate")
	_tap_top(Vector3i(1, 0, 0))
	await _settle()
	_check(_level.state.values["b1"] == 1 and _level.state.values["g1"] == 0, "one button alone leaves the gate shut")
	_tap_top(Vector3i(2, 0, 1))
	await _settle()
	_check(_level.state.values["b2"] == 1 and _level.state.values["g1"] == 1, "the second button opens it")
	_capture("step6_gate.png")
	await _walk_to_exit(Vector3i(6, 0, 1))
	_check(_level.state.completed and _level.state.moves == 7, "through the open gate to the exit in 7 moves (%d)" % _level.state.moves)


func _open(name: String) -> void:
	if _level:
		_level.queue_free()
		await _frames(2)
	_level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_level.level_path = "res://dev/mechanisms/%s.json" % name
	_viewport.add_child(_level)
	await _frames(8)


func _walk_to_exit(block: Vector3i) -> void:
	_tap_top(block)
	await _settle()
	await _wait(0.3)


## Waits until nothing moves: no animation, no walking.
func _settle() -> void:
	var still: int = 0
	var started: int = Time.get_ticks_msec()
	while still < 6 and Time.get_ticks_msec() - started < 8000:
		await process_frame
		still = still + 1 if not _level.is_busy() and not _level.courier.is_moving() else 0


func _tap_top(block: Vector3i, height: float = 1.0) -> void:
	var at: Vector2 = _screen(Vector3(block) + Vector3(0.5, height, 0.5))
	var hit: Dictionary = _level.pick(at)
	if hit.is_empty() or hit["cell"] != block:
		print("note: tap aimed at %s picks %s" % [block, hit])
	_touch(at, true)
	_touch(at, false)


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
