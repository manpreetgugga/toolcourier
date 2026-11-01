extends SceneTree
## Scripted check of the menus and the polish around play: which levels and
## worlds are open, the settings file and what follows a change (volumes,
## quality, tilt-shift, haptics), the splash, main menu, world select, level
## grid and settings card driven through the touch path, the back button,
## a level's build-up, safe area, sounds, haptic ticks, pause card, confetti
## and take-down, and moving between the menu and a level. Prints PASS/FAIL
## per check, saves screenshots, and exits with status 1 on any failure.
## Needs a renderer.
##
##   godot --path . --resolution 405x720 -s res://tools/test_ui.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
const LEVEL_1 := "res://levels/world_1/level_1.json"
const LEVEL_2 := "res://levels/world_1/level_2.json"
const SETTINGS := "user://test_ui_settings.json"
## Level 1: the parcel's block, the pad's and the exit's.
const PARCEL := Vector3i(2, 0, 3)
const PAD := Vector3i(5, 1, 1)
const EXIT := Vector3i(4, 1, 0)

var _viewport: SubViewport
var _out_dir: String = "docs/screenshots"
var _failures: int = 0


func _initialize() -> void:
	Progress.use_file("user://test_ui_progress.json")
	Settings.use_file(SETTINGS)
	# No ads: Hint gives hints straight away, and no level break plays.
	Ads.enabled = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_check_unlocking()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run()


func _run() -> void:
	await _frames(2)
	await _check_settings()
	await _check_menu()
	await _check_level()
	await _check_flow()
	if _failures == 0:
		print("all checks passed")
	else:
		print("%d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_unlocking() -> void:
	_check(LevelCatalog.next_to_play() == LEVEL_1 and LevelCatalog.is_unlocked(LEVEL_1)
		and not LevelCatalog.is_unlocked(LEVEL_2), "on a fresh save only the first level is open, and it is next")
	Progress.record(Progress.level_id(LEVEL_1), 11, 3)
	_check(LevelCatalog.is_unlocked(LEVEL_2) and LevelCatalog.next_to_play() == LEVEL_2,
		"finishing a level opens the one after it, which is next")
	var world_2: String = LevelCatalog.levels(2)[0]
	_check(not LevelCatalog.is_unlocked(world_2), "the next world stays shut until the level before it is finished")
	_check(LevelCatalog.world_stars(1) == Vector2i(3, 30) and LevelCatalog.world_finished(1) == 1,
		"a world counts its stars (%s) and finished levels" % LevelCatalog.world_stars(1))
	_check(LevelCatalog.world_of(world_2) == 2 and LevelCatalog.world_name(5) == "Frost Peaks",
		"levels know their world, and worlds their names")


func _check_settings() -> void:
	_check(is_equal_approx(Settings.music, 0.7) and is_equal_approx(Settings.sfx, 0.9) and Settings.tilt_shift
		and Settings.haptics and Settings.quality == Settings.Quality.HIGH, "fresh settings start from the defaults")
	Settings.set_value(&"music", 0.3)
	Settings.set_value(&"sfx", 0.0)
	var music: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	var sfx: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))
	_check(is_equal_approx(music, Settings.volume_db(0.3)) and sfx <= -79.0,
		"the Music and SFX buses follow the volumes at once (%.1f dB, %.1f dB)" % [music, sfx])
	Settings.set_value(&"quality", Settings.Quality.LOW)
	_check(root.msaa_3d == Viewport.MSAA_DISABLED, "low quality turns multisampling off")
	Settings.set_value(&"quality", Settings.Quality.HIGH)
	_check(root.msaa_3d == Viewport.MSAA_4X, "high quality turns it back up")
	var phone := SubViewport.new()
	phone.size = Vector2i(1080, 2400)
	var scales: Array[float] = []
	for quality: int in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		Settings.set_value(&"quality", quality, false)
		scales.append(Settings.render_scale(phone))
	phone.size = Vector2i(720, 1280)
	scales.append(Settings.render_scale(phone))
	phone.free()
	_check(absf(scales[0] - 0.56) < 0.01 and absf(scales[1] - 0.71) < 0.01 and scales[2] == 1.0 and scales[3] == 1.0,
		"on a 1080 x 2400 phone the 3D view is drawn at %.2f, %.2f and %.2f of full size, and a smaller screen in full"
		% [scales[0], scales[1], scales[2]])
	Settings.set_value(&"quality", Settings.Quality.HIGH)

	Settings.set_value(&"haptics", false)
	Haptics.tap()
	_check(not Haptics.history[-1]["on"], "with haptics off a tap does not vibrate")
	Settings.set_value(&"haptics", true)
	await create_timer(0.06).timeout
	Haptics.snap()
	Haptics.tap()
	_check(Haptics.history[-2]["on"] and Haptics.history[-2]["kind"] == &"snap" and not Haptics.history[-1]["on"],
		"with haptics on a snap ticks, and a tick right after it merges into it")

	Settings.use_file(SETTINGS, false)
	_check(is_equal_approx(Settings.music, 0.3) and Settings.sfx == 0.0 and Settings.haptics
		and Settings.quality == Settings.Quality.HIGH, "settings come back from the file")
	_check(FileAccess.get_file_as_string(SETTINGS).contains("\"quality\": \"high\""), "quality is saved by name")
	var file := FileAccess.open(SETTINGS, FileAccess.WRITE)
	file.store_string("{ oops")
	file.close()
	print("(a warning about unreadable settings is expected next)")
	Settings.use_file(SETTINGS, false)
	_check(is_equal_approx(Settings.music, 0.7) and Settings.tilt_shift, "unreadable settings fall back to the defaults")
	Settings.use_file(SETTINGS)
	Settings.set_value(&"music", 0.7)
	Settings.set_value(&"sfx", 0.9)


func _check_menu() -> void:
	Game.splash_done = false
	var menu: Menu = (load(Game.MENU) as PackedScene).instantiate()
	_viewport.add_child(menu)
	await _wait(0.5)
	_capture("step9_splash.png")
	_check(menu.get_node_or_null("Ui/Splash") != null, "the menu opens with the splash")
	_check(menu.screen() == &"main" and menu.backdrop.level_path == LEVEL_2,
		"behind it the main menu shows the next level to play")
	await _until(func() -> bool: return menu.backdrop.is_assembling(), 3.0)
	_check(menu.backdrop.is_assembling(), "the diorama builds itself up as the splash fades")
	await _wait(0.35)
	_capture("step9_menu_build.png")
	await _until(func() -> bool: return not menu.backdrop.is_assembling(), 5.0)
	await _wait(0.4)
	_check(Game.splash_done and menu.get_node_or_null("Ui/Splash") == null, "then the splash is gone")
	_check(AudioManager.current_music() == 1, "the main menu plays the next level's world music")
	_capture("step9_menu.png")

	await _press(menu.get_node("Ui/Root/Safe/Main/Bottom/Levels"))
	await _wait(0.8)
	var world_1: TouchButton = menu.get_node("Ui/Root/Safe/Worlds/Cards/World_1")
	var world_2: TouchButton = menu.get_node("Ui/Root/Safe/Worlds/Cards/World_2")
	_check(menu.screen() == &"worlds" and not world_1.disabled and world_2.disabled,
		"Levels opens the world select: world 1 open, world 2 locked")
	_check((world_1.get_node("Preview") as TextureRect).texture is ViewportTexture,
		"each world card shows a turning diorama")
	_capture("step9_worlds.png")
	await _press(world_2)
	await _wait(0.2)
	_check(menu.screen() == &"worlds", "a locked world does not open")
	await _press(world_1)
	await _wait(0.5)
	var grid: Node = menu.get_node("Ui/Root/Safe/Levels/Grid")
	var first: TouchButton = grid.get_node("Level_1")
	var second: TouchButton = grid.get_node("Level_2")
	var third: TouchButton = grid.get_node("Level_3")
	_check(menu.screen() == &"levels" and menu.world() == 1 and grid.get_child_count() == 10,
		"a world opens its grid of ten levels")
	_check(not first.disabled and not second.disabled and third.disabled and second.outline == Ui.ACCENT,
		"finished and next levels are open, the next one ringed; the rest are locked")
	_capture("step9_levels.png")
	menu.go_back()
	await _wait(0.4)
	_check(menu.screen() == &"worlds", "back goes from the grid to the worlds")
	menu.go_back()
	await _wait(0.4)
	_check(menu.screen() == &"main" and menu.backdrop.visible, "and from the worlds to the main menu and its diorama")

	await _press(menu.get_node("Ui/Root/Safe/Main/Bottom/Settings"))
	await _wait(0.5)
	var card: SettingsCard = menu.get_node("Ui/Root/Settings")
	_check(card.visible, "Settings opens the settings card")
	_capture("step9_settings.png")
	await _press(card.get_node("Card/Tilt-shift"))
	await _frames(2)
	_check(not Settings.tilt_shift and not menu.backdrop._stage.tilt_shift_enabled,
		"turning tilt-shift off takes the blur off the diorama at once")
	await _press(card.get_node("Card/Tilt-shift"))
	var quality: Control = card.get_node("Card/Quality")
	await _press(quality, Vector2(quality.size.x * 0.1, quality.size.y * 0.5))
	_check(Settings.quality == Settings.Quality.LOW, "the quality picker sets low quality")
	await _press(quality, Vector2(quality.size.x * 0.9, quality.size.y * 0.5))
	for i in 5:
		await _press(card.get_node("Card/Version"))
	_check(PerfOverlay.is_shown(), "five taps on the version number bring up the performance readout")
	for i in 5:
		await _press(card.get_node("Card/Version"))
	_check(not PerfOverlay.is_shown(), "and five more take it away")
	var slider: Control = card.get_node("Card/Music")
	await _drag(slider, Vector2(slider.size.x * 0.8, 30.0), Vector2(slider.size.x * 0.3, 30.0))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	_check(Settings.music < 0.35 and Settings.tilt_shift and Settings.quality == Settings.Quality.HIGH
		and is_equal_approx(saved["music"], Settings.music), "dragging the music slider sets and saves the volume (%.2f)"
		% Settings.music)
	Settings.set_value(&"music", 0.7)
	menu.go_back()
	await _wait(0.3)
	_check(not card.visible and menu.screen() == &"main", "back closes the settings card first")
	menu.queue_free()
	await _frames(2)


func _check_level() -> void:
	Ui.simulated_insets = Vector4(0.0, 90.0, 0.0, 60.0)
	var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
	level.level_path = LEVEL_1
	level.intro = true
	var assembled: Array[bool] = [false]
	level.assembled.connect(func() -> void: assembled[0] = true)
	_viewport.add_child(level)
	Ui.simulated_insets = Vector4.ZERO
	await _frames(3)
	var blocks: MeshInstance3D = level.get_node("Blocks")
	_check(level.is_assembling() and level.is_busy() and float(blocks.get_instance_shader_parameter(&"build_time")) < 1.0,
		"a level opened from the menu builds itself up, and input waits")
	await _wait(0.55)
	_capture("step9_buildup.png")
	await _until(func() -> bool: return assembled[0], 5.0)
	_check(assembled[0] and not level.is_busy()
		and float(blocks.get_instance_shader_parameter(&"build_time")) == Assembly.AT_REST,
		"then it stands at rest and play starts")
	var safe: Control = level.hud.get_node("Root/Safe")
	_check(is_equal_approx(safe.offset_top, 90.0) and is_equal_approx(safe.offset_bottom, -60.0),
		"the HUD keeps clear of a notch and the gesture bar")

	var ticks: int = Haptics.history.size()
	_tap(level, PARCEL)
	await _until_still(level.courier)
	_check(AudioManager.played(&"tap") and AudioManager.played(&"step") and AudioManager.played(&"pickup"),
		"a walk taps, steps and picks the parcel up with sounds")
	_check(Haptics.history.size() > ticks and Haptics.history[-1]["kind"] == &"tap", "a tap on the diorama ticks")

	level.hud.pause()
	await _wait(0.45)
	_check(paused and level.hud.is_paused(), "the pause button stops the game under the pause card")
	_capture("step9_pause.png")
	level.go_back()
	await _wait(0.3)
	_check(not paused and not level.hud.is_paused(), "back resumes it")

	_tap(level, PAD)
	await _until_still(level.courier)
	_tap(level, EXIT)
	await _until_still(level.courier)
	await _wait(0.25)
	_check(level.state.completed and level.find_child("Confetti", false, false) != null
		and AudioManager.played(&"pad_complete") and AudioManager.played(&"level_complete"),
		"a full pad chimes, and finishing plays the jingle and throws confetti")
	_capture("step9_confetti.png")
	await _wait(1.6)

	var left: Array[bool] = [false]
	level.leave(func() -> void: left[0] = true)
	await _frames(3)
	_check(level.is_assembling() and not left[0], "leaving takes the diorama down first")
	await _wait(0.3)
	_capture("step9_takedown.png")
	await _until(func() -> bool: return left[0], 4.0)
	_check(left[0], "and moves on once it is down")
	level.queue_free()
	await _frames(2)


func _check_flow() -> void:
	Game.open_level(LEVEL_1)
	await _until(func() -> bool: return current_scene is Level and not Game.is_swapping(), 5.0)
	var level := current_scene as Level
	_check(level != null and level.level_path == LEVEL_1 and level.intro and level.get_parent() == root,
		"opening a level fades it in as the scene, building itself up")
	await _until(func() -> bool: return not level.is_assembling(), 5.0)
	level.go_home(&"levels")
	await _until(func() -> bool: return current_scene is Menu and not Game.is_swapping(), 6.0)
	var menu := current_scene as Menu
	_check(menu != null and menu.screen() == &"levels" and menu.world() == 1 and not is_instance_valid(level),
		"Levels takes the level down and opens its world's grid")
	menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.3)
	_check(menu.screen() == &"worlds", "the back button goes up a screen")
	menu.queue_free()
	current_scene = null
	await _frames(2)


## Presses [param control] through the touch path, at [param at] inside it
## (its middle by default).
func _press(control: Control, at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	var point: Vector2 = control.get_global_rect().get_center() if at.x < 0.0 else control.get_global_transform() * at
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		_viewport.push_input(event, true)
		await process_frame


func _drag(control: Control, from: Vector2, to: Vector2) -> void:
	var transform: Transform2D = control.get_global_transform()
	var touch := InputEventScreenTouch.new()
	touch.position = transform * from
	touch.pressed = true
	_viewport.push_input(touch, true)
	await process_frame
	for step in 6:
		var drag := InputEventScreenDrag.new()
		drag.position = transform * from.lerp(to, (step + 1) / 6.0)
		_viewport.push_input(drag, true)
		await process_frame
	touch = InputEventScreenTouch.new()
	touch.position = transform * to
	touch.pressed = false
	_viewport.push_input(touch, true)
	await process_frame


func _tap(level: Level, block: Vector3i) -> void:
	var at: Vector2 = level.camera.unproject_position(Vector3(block) + Vector3(0.5, 1.0, 0.5))
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


func _until(condition: Callable, seconds: float) -> void:
	var started: int = Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - started < seconds * 1000.0:
		await process_frame


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
