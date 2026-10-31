extends SceneTree
## Plays every level in the catalog the way a player would: checks that the
## solver's fewest moves is the level's three-star limit and that its plan
## finishes the level by the rules, then follows the hints alone through the
## touch path (taps, slider drags, crank taps) until the level is finished
## with three stars, turning the camera a quarter when something hides the
## next tap. Saves a contact sheet of every level as it starts. Prints
## PASS/FAIL per check and exits with status 1 on any failure. Needs a
## renderer.
##
##   godot --path . --resolution 405x720 -s res://tools/test_levels.gd -- --out=docs/screenshots
##   godot --path . --resolution 405x720 -s res://tools/test_levels.gd -- res://levels/world_2/level_3.json
##
## With level paths it plays only those and saves no contact sheet.

const SIZE := Vector2i(720, 1280)
const SAVE := "user://test_progress.json"
const CheckLevels := preload("res://tools/check_levels.gd")
## Game speed while playing, so the whole catalog takes minutes, not ten.
const SPEED: float = 3.0
## The part of a frame a contact sheet thumbnail shows (the HUD is hidden),
## and the thumbnail size.
const CROP := Rect2i(0, 190, 720, 900)
const THUMB := Vector2i(256, 320)
const COLUMNS: int = 5
const SHEET := "step8_levels.png"

var _viewport: SubViewport
var _level: Level
var _out_dir: String = "docs/screenshots"
var _failures: int = 0
## [path, thumbnail Image] in play order.
var _thumbs: Array[Array] = []


func _initialize() -> void:
	# Default settings, whatever the player has chosen.
	Settings.use_file("user://test_settings.json")
	var paths: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		else:
			paths.append(arg if arg.begins_with("res://") else "res://" + arg.trim_prefix("./"))
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	var sheet: bool = paths.is_empty()
	if sheet:
		paths = LevelCatalog.all()
	# Keep the player's own save out of it.
	Progress.use_file(SAVE)
	_check(not sheet or paths.size() == 50, "the catalog has 50 levels (%d)" % paths.size())
	for path: String in paths:
		_check_solution(path)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run(paths, sheet)


func _run(paths: Array[String], sheet: bool) -> void:
	await _frames(2)
	Engine.time_scale = SPEED
	for path: String in paths:
		await _play(path)
	Engine.time_scale = 1.0
	if _level:
		_level.queue_free()
	if sheet:
		await _contact_sheet()
	print("%d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_solution(path: String) -> void:
	var label: String = Progress.level_id(path)
	var data: LevelData = LevelLoader.load_file(path)
	if not _check(data.is_valid(), "%s loads %s" % [label, data.errors]):
		return
	_check(path.get_base_dir().get_file() == "world_%d" % data.world, "%s: \"world\" matches its folder" % label)
	var solver := Solver.new(data)
	var plan: Array[Dictionary] = solver.solve(LevelState.new(data).snapshot())
	var moves: int = plan[-1]["moves"] if not plan.is_empty() else -1
	_check(moves == data.stars[0], "%s: the fewest moves (%d) is the 3-star limit %d" % [label, moves, data.stars[0]])
	_check(solver.explored <= CheckLevels.STATE_BUDGET, "%s: a hint from the start looks at %d states (budget %d)"
		% [label, solver.explored, CheckLevels.STATE_BUDGET])
	var replay := LevelState.new(data)
	for action: Dictionary in plan:
		Solver.apply_to(replay, action)
	_check(replay.completed and replay.moves == moves, "%s: playing the plan by the rules finishes it" % label)


## Opens [param path], keeps a thumbnail of how it starts, and follows the
## hints to the end.
func _play(path: String) -> void:
	var label: String = Progress.level_id(path)
	await _open(path)
	_level.hud.visible = false
	await _wait(0.4 * SPEED)
	_thumbs.append([path, _viewport.get_texture().get_image().get_region(CROP)])
	_level.hud.visible = true

	var hint: TouchButton = _level.hud.get_node("Root/Safe/Buttons/Hint")
	var hints: int = 0
	var turns: int = 0
	var stuck: String = ""
	while not _level.state.completed and hints < 80 and stuck.is_empty():
		await _settle()
		await _press(hint)
		var asked: Dictionary = _level.hinted()
		if asked.is_empty():
			stuck = "no hint (%s)" % _level.hud.toast_text()
			break
		hints += 1
		# Turn the camera until the hinted spot can be reached by a tap.
		var done: bool = false
		for quarter in 4:
			done = await _follow(asked)
			if done:
				break
			turns += 1
			_level.camera.default_yaw += 90.0
			_level.camera.frame_bounds(_level._view_bounds())
			await _frames(3)
		if not done:
			stuck = "cannot reach the hint %s from any side" % [asked]
		await _settle()
	var moves: int = _level.state.moves
	_check(_level.state.completed and _level.data.stars_for(moves) == 3,
		"%s: %d hints alone finish it with 3 stars in %d moves%s%s" % [label, hints, moves,
			" (%d camera turn(s))" % turns if turns > 0 else "", "; " + stuck if not stuck.is_empty() else ""])


## Does what a hint asks through the touch path. False if what it needs to
## touch is hidden from this side.
func _follow(asked: Dictionary) -> bool:
	match asked["action"]:
		Solver.Action.STEP:
			return _tap_cell(asked["cell"])
		Solver.Action.SLIDE:
			return await _drag_slider(asked["id"], asked["to"])
		Solver.Action.TURN:
			var mechanism: Mechanism = _level.state.mechanisms[asked["id"]]
			var at: Vector2 = _screen(Vector3(mechanism.handle) + Vector3(0.5, 0.6, 0.5))
			var hit: Dictionary = _level.pick(at)
			if hit.is_empty() or hit["cell"] != mechanism.handle:
				return false
			var value: int = _level.state.values[asked["id"]]
			_touch(at, true)
			_touch(at, false)
			await _frames(2)
			return _level.state.values[asked["id"]] != value
	return false


func _open(path: String) -> void:
	if _level:
		_level.queue_free()
		await _frames(2)
	Progress.drop_in_progress(Progress.level_id(path))
	_level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_level.level_path = path
	_viewport.add_child(_level)
	await _frames(8)


## Taps the block whose top (or stairs) leads to [param cell], trying a few
## spots on it in case another block hides the middle.
func _tap_cell(cell: Vector3i) -> bool:
	var stairs: bool = _level.grid.is_stairs_at(cell)
	var block: Vector3i = cell if stairs else cell - Vector3i.UP
	var height: float = 0.5 if stairs else 1.0
	for spot: Vector2 in [Vector2(0.5, 0.5), Vector2(0.3, 0.3), Vector2(0.7, 0.7), Vector2(0.3, 0.7), Vector2(0.7, 0.3)]:
		var at: Vector2 = _screen(Vector3(block) + Vector3(spot.x, height, spot.y))
		var hit: Dictionary = _level.pick(at)
		if not hit.is_empty() and _level.pathfinder.target_for_block(hit["cell"]) == cell:
			_touch(at, true)
			_touch(at, false)
			return true
	return false


## Drags slider [param id] by its top to offset [param to].
func _drag_slider(id: String, to: int) -> bool:
	var mechanism: Mechanism = _level.state.mechanisms[id]
	var value: int = _level.state.values[id]
	var top: Vector3 = Level._centre(mechanism.cells_at(value)) + Vector3(0.0, 0.5, 0.0)
	var from: Vector2 = _screen(top)
	var hit: Dictionary = _level.pick(from)
	if hit.is_empty() or not mechanism.cells_at(value).has(hit["cell"]):
		return false
	var target: Vector2 = _screen(top + Vector3(mechanism.axis * (to - value)))
	_touch(from, true)
	for i in range(1, 11):
		await _frames(1)
		_drag(from.lerp(target, i / 10.0))
	await _frames(1)
	_touch(target, false)
	await _settle()
	return _level.state.values[id] == to


## Lays the thumbnails out by world, five to a row, each with its name.
func _contact_sheet() -> void:
	var sheet := SubViewport.new()
	sheet.transparent_bg = false
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", Ui.card(Ui.CREAM, 0))
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	page.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	margin.add_child(rows)
	var grid: GridContainer
	var world: int = 0
	for entry: Array in _thumbs:
		var path: String = entry[0]
		var data: LevelData = LevelLoader.load_file(path)
		if data.world != world:
			world = data.world
			var heading := Label.new()
			heading.text = "World %d · %s" % [world, LevelCatalog.world_name(world)]
			heading.label_settings = Ui.label_settings(30, Ui.INK)
			rows.add_child(heading)
			grid = GridContainer.new()
			grid.columns = COLUMNS
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			rows.add_child(grid)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var picture := TextureRect.new()
		var image: Image = entry[1]
		image.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		picture.texture = ImageTexture.create_from_image(image)
		cell.add_child(picture)
		var caption := Label.new()
		caption.text = "%d-%s  %s · %d" % [world, path.get_file().get_basename().trim_prefix("level_"), data.name, data.stars[0]]
		caption.label_settings = Ui.label_settings(17, Ui.INK)
		caption.custom_minimum_size.x = THUMB.x
		caption.clip_text = true
		cell.add_child(caption)
		grid.add_child(cell)
	sheet.add_child(page)
	root.add_child(sheet)
	await _frames(2)
	sheet.size = Vector2i(page.get_combined_minimum_size())
	page.size = sheet.size
	await _frames(3)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var file: String = _out_dir.path_join(SHEET)
	sheet.get_texture().get_image().save_png(file)
	print("saved ", file)
	sheet.queue_free()


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
	while still < 4 and Time.get_ticks_msec() - started < 8000:
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


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(ok: bool, what: String) -> bool:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1
	return ok
