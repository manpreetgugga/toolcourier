extends SceneTree
## Scripted check of where and when ads may show (see Ads), with Ads.Preview
## answering at once in place of the Android plugin: the one switch turns
## everything off; world 1's first 20 levels never start the ads; from its
## level 21 on the first Hint in a level offers a video (Not now and back turn it down, a video
## closed early gives no hint, one watched to the end turns hints on for
## that level); a level break comes every 3 or 4 levels finished, only as
## the finish card is left by Next or back, never on Replay, after a
## restart, after a finish with no star or within 4 minutes of another ad
## or of the game opening, and the count survives a restart of the game (and a hint video watched
## first thing after one); an ad on screen doesn't
## pause the level; Settings offers the ad privacy options only when they
## are required. Levels are finished through their own completion event (the
## walking is checked elsewhere); buttons are pressed through the touch
## path. Prints PASS/FAIL per check, saves screenshots, and exits with
## status 1 on any failure. Needs a renderer.
##
##   godot --audio-driver Dummy --path . --resolution 405x720 -s res://tools/test_ads.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
const SAVE := "user://test_ads.json"
## World 1's first and last levels without ads, and its first with them.
const QUIET_FIRST := "res://levels/world_1/level_1.json"
const QUIET_LAST := "res://levels/world_1/level_20.json"
const WORLD_1_ADS := "res://levels/world_1/level_21.json"
const WORLD_2 := "res://levels/world_2/level_1.json"
const WORLD_2_NEXT := "res://levels/world_2/level_2.json"

var _viewport: SubViewport
var _preview: Ads.Preview
var _out_dir: String = "docs/screenshots"
var _failures: int = 0


func _initialize() -> void:
	# Default settings and an empty save, whatever the player has.
	Settings.use_file("user://test_settings.json")
	Progress.use_file("user://test_ads_progress.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_preview = Ads.Preview.new()
	_preview.auto = true
	Ads.use_provider(_preview)
	Ads.use_file(SAVE)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = root.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run()


func _run() -> void:
	await _frames(2)
	await _check_rules()
	await _check_hint_offer()
	await _check_breaks()
	await _check_quiet_places()
	await _check_settings()
	Ads.use_provider(null)
	if _failures == 0:
		print("all checks passed")
	else:
		print("%d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_rules() -> void:
	Ads.enabled = false
	Ads.start_for(WORLD_2)
	for i in 5:
		Ads.level_finished(WORLD_2, true)
	_check(not Ads.hint_needs_video(WORLD_2) and Ads.break_count().x == 0 and not Ads.break_due()
		and _preview.shown.is_empty(), "with the switch off nothing starts, hints are free and no finish counts")
	Ads.enabled = true

	for path: String in [QUIET_FIRST, QUIET_LAST]:
		Ads.start_for(path)
		for i in 5:
			Ads.level_finished(path, true)
	_check(not Ads.privacy_options_required() and not Ads.hint_needs_video(QUIET_FIRST)
		and not Ads.hint_needs_video(QUIET_LAST) and Ads.break_count().x == 0,
		"world 1's first 20 levels start no ads (no consent form either), their hints are free and their finishes never count")
	Ads.start_for(WORLD_1_ADS)
	await _frames(2)
	_check(Ads.hint_needs_video(WORLD_1_ADS) and Ads.hint_needs_video(WORLD_2) and Ads.privacy_options_required()
		and not Ads.hint_needs_video(QUIET_LAST), "world 1's level 21 starts them: a hint there, and in every later world, needs a video first")

	var gap: int = Ads.break_count().y
	_check(gap in Ads.BREAK_GAPS, "the next break waits for 3 or 4 levels (%d)" % gap)
	var early: bool = false
	for i in gap - 1:
		Ads.level_finished(WORLD_2, true)
		early = early or Ads.break_due()
	Ads.level_finished(WORLD_2, false)
	_check(not early and Ads.break_count().x == gap and not Ads.break_due(),
		"no break before then, nor after a finish that was restarted along the way or got no star (it still counts)")
	Ads.level_finished(WORLD_2, true)
	var held: bool = not Ads.break_due()
	Ads._opened -= Ads.QUIET_SECONDS
	_check(held and Ads.break_due(), "the next clean finish brings it, once the game has been open 4 minutes")
	Ads.enabled = false
	_check(not Ads.break_due(), "the switch holds a due break off")
	Ads.enabled = true
	Ads.use_file(SAVE, false)
	_check(Ads.break_count() == Vector2i(gap + 1, gap) and not Ads.break_due(),
		"the count survives a restart of the game (a break only ever follows a finish just made)")
	Ads.level_finished(WORLD_2, true)
	await Ads.play_break_if_due()
	var after: Vector2i = Ads.break_count()
	_check(_preview.shown == ["interstitial:level_complete"] and after.x == 0 and after.y in Ads.BREAK_GAPS
		and not Ads.break_due(), "a break is one full-screen ad at the level-complete placement, and the count starts again")
	for i in 4:
		Ads.level_finished(WORLD_2, true)
	_check(not Ads.break_due(), "within 4 minutes of an ad no break is due, however many levels are finished")
	Ads._last_ad -= Ads.QUIET_SECONDS
	_check(Ads.break_due(), "once the 4 minutes are up, it is")

	_preview.shown.clear()
	_preview.earn = false
	var result: Dictionary = await Ads.watch_hint_video(WORLD_2)
	_check(not result["earned"] and result["reason"] == "cancelled" and Ads.hint_needs_video(WORLD_2),
		"a hint video closed early turns no hints on")
	_preview.earn = true
	result = await Ads.watch_hint_video(WORLD_2)
	_check(result["earned"] and Ads.hints_unlocked(WORLD_2) and not Ads.hint_needs_video(WORLD_2)
		and Ads.hint_needs_video(WORLD_2_NEXT), "one watched to the end turns hints on for that level alone")
	_check(_preview.shown == ["rewarded:hint", "rewarded:hint"] and not Ads.break_due(),
		"hint videos are rewarded ads at the hint placement, and hold the next break off too")

	# A new launch, where a hint video comes before anything has read the count.
	var kept: Vector2i = Ads.break_count()
	Ads._loaded = false
	Ads._finished = 0
	Ads._gap = 0
	await Ads.watch_hint_video(WORLD_2_NEXT)
	_check(Ads.break_count() == kept, "a hint video first thing in a launch keeps the count towards the next break")


func _check_hint_offer() -> void:
	Ads.use_file(SAVE)
	_preview.shown.clear()
	var level: Level = await _open(WORLD_2)
	var hint: TouchButton = level.hud.get_node("Root/Safe/Buttons/Hint")
	var watch: TouchButton = level.hud.get_node("Root/Offer/Card/Watch video")
	await _wait(Hud.BADGE_CHECK + 0.1)
	_check(hint.badge == &"play", "in world 2 Hint wears a play mark while a hint needs a video")
	await _press(hint)
	await _wait(0.45)
	_check(level.hud.is_offer_showing() and paused and not level.has_hint() and _preview.shown.is_empty(),
		"the first Hint offers a video and pauses the game; nothing plays until the player chooses")
	_capture("ads_hint_offer.png")
	await _press(level.hud.get_node("Root/Offer/Card/Not now"))
	await _wait(0.3)
	_check(not level.hud.is_offer_showing() and not paused and not level.has_hint() and _preview.shown.is_empty(),
		"Not now closes it: no video, no hint")
	await _press(hint)
	await _wait(0.3)
	level.go_back()
	await _wait(0.3)
	_check(not level.hud.is_offer_showing() and not level.hud.is_paused() and not paused, "so does back")

	_preview.earn = false
	await _press(hint)
	await _wait(0.3)
	await _press(watch)
	await _wait(0.3)
	_check(_preview.shown == ["rewarded:hint"] and not level.has_hint()
		and level.hud.toast_text().begins_with("No hint this time"), "a video closed early gives no hint, and says so")
	_preview.earn = true
	await _press(hint)
	await _wait(0.3)
	await _press(watch)
	await _wait(0.3)
	_check(_preview.shown.size() == 2 and level.has_hint()
		and level.hud.toast_text().begins_with("Hints are on for this level.\n"),
		"one watched to the end shows the hint, saying hints are now on")
	_capture("ads_hint_on.png")
	await _wait(Hud.BADGE_CHECK + 0.1)
	await _press(hint)
	await _wait(0.2)
	_check(hint.badge == &"" and not level.hud.is_offer_showing() and level.has_hint() and _preview.shown.size() == 2,
		"then the play mark goes and Hint gives hints straight away")

	_preview.auto = false
	Ads.watch_hint_video(WORLD_2)
	await _frames(2)
	level.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _frames(3)
	_check(Ads.is_showing() and _preview.card != null and not level.hud.is_paused(),
		"the app pausing under an ad doesn't put the pause card up")
	(_preview.card.get_node("Close") as TouchButton).pressed.emit()
	await _frames(3)
	_preview.auto = true
	_check(not Ads.is_showing() and not paused, "closing the ad gives the game back")
	level.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _frames(3)
	_check(level.hud.is_paused(), "while the app pausing by itself still does")
	level.hud.resume()
	level.queue_free()
	await _frames(2)


func _check_breaks() -> void:
	Ads.use_file(SAVE)
	_preview.shown.clear()
	var gap: int = Ads.break_count().y
	for i in gap - 1:
		Ads.level_finished(WORLD_2, true)
	var level: Level = await _open(WORLD_2)
	await _finish(level, level.data.stars[0])
	_check(Ads.break_due(), "with %d levels finished a break is due as the finish card is left" % gap)
	_capture("ads_finish_card.png")
	await _press(level.hud.get_node("Root/Finish/Card/Replay"))
	await _wait(0.4)
	_check(_preview.shown.is_empty() and not level.state.completed, "Replay never plays one")
	await _finish(level, level.data.stars[0])
	_check(not Ads.break_due(), "nor does finishing it again after that restart")
	level = await _press_next(level)
	_check(_preview.shown.is_empty() and level.level_path == WORLD_2_NEXT, "Next then moves straight on")

	await _finish(level, level.data.stars[-1] + 4)
	_check(not Ads.break_due(), "a finish with no star brings no break")
	level = await _press_next(level)
	await _finish(level, level.data.stars[1])
	_check(Ads.break_due(), "the next finish with a star does")
	level = await _press_next(level)
	_check(_preview.shown == ["interstitial:level_complete"] and Ads.break_count().x == 0,
		"and Next plays it before moving on")

	for i in Ads.break_count().y - 1:
		Ads.level_finished(WORLD_2, true)
	Ads._last_ad -= Ads.QUIET_SECONDS
	await _finish(level, level.data.stars[0])
	level.go_back()
	await _until(func() -> bool: return current_scene is Menu and not Game.is_swapping(), 6.0)
	_check(_preview.shown.size() == 2 and current_scene is Menu, "back from the finish card plays a due break too, then leaves")
	current_scene.queue_free()
	current_scene = null
	if is_instance_valid(level):
		level.queue_free()
	await _frames(2)


func _check_quiet_places() -> void:
	Ads.use_file(SAVE)
	_preview.shown.clear()
	for i in 6:
		Ads.level_finished(WORLD_2, true)
	var level: Level = await _open(QUIET_LAST)
	var hint: TouchButton = level.hud.get_node("Root/Safe/Buttons/Hint")
	await _wait(Hud.BADGE_CHECK + 0.1)
	await _press(hint)
	await _wait(0.2)
	_check(hint.badge == &"" and not level.hud.is_offer_showing() and level.has_hint(),
		"in world 1's first 20 levels Hint gives hints straight away")
	await _finish(level, level.data.stars[0])
	level = await _press_next(level)
	_check(_preview.shown.is_empty(), "and no break plays there, however many levels came before")
	level.queue_free()
	await _frames(2)

	Ads.enabled = false
	level = await _open(WORLD_2_NEXT)
	hint = level.hud.get_node("Root/Safe/Buttons/Hint")
	await _wait(Hud.BADGE_CHECK + 0.1)
	await _press(hint)
	await _wait(0.2)
	var free_hint: bool = hint.badge == &"" and not level.hud.is_offer_showing() and level.has_hint()
	await _finish(level, level.data.stars[0])
	level = await _press_next(level)
	_check(free_hint and _preview.shown.is_empty(), "with the switch off, world 2 plays no ads either")
	Ads.enabled = true
	level.queue_free()
	await _frames(2)


func _check_settings() -> void:
	var level: Level = await _open(WORLD_2)
	var settings: SettingsCard = level.hud.get_node("Root/Settings")
	var card: Control = settings.get_node("Card")
	var options: TouchButton = card.get_node("AdPrivacy")
	_preview.privacy_required = true
	settings.open()
	await _wait(0.45)
	_check(options.visible and is_equal_approx(card.size.y, SettingsCard.SIZE.y + SettingsCard.ROW_HEIGHT),
		"where the law asks for it, Settings has an Ad privacy row")
	_capture("ads_settings.png")
	_preview.shown.clear()
	await _press(options)
	await _frames(3)
	_check(_preview.shown == ["privacy_options"], "which opens Google's privacy options")
	_preview.privacy_required = false
	Ads.events.changed.emit()
	await _frames(2)
	_check(not options.visible and is_equal_approx(card.size.y, SettingsCard.SIZE.y), "elsewhere the row isn't there")
	settings.close()
	level.queue_free()
	await _frames(2)


func _open(path: String) -> Level:
	var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
	level.level_path = path
	_viewport.add_child(level)
	await _frames(3)
	return level


## Finishes [param level] in [param moves] moves through its own completion
## event, and waits for the finish card.
func _finish(level: Level, moves: int) -> void:
	level.state.moves = moves
	level.state.completed = true
	level._play([{"event": LevelState.Event.COMPLETED}])
	await _until(func() -> bool: return level.hud.is_finish_showing(), 3.0)
	await _wait(0.6)


## Presses Next on [param level]'s finish card and returns the level that
## replaces it.
func _press_next(level: Level) -> Level:
	var old: WeakRef = weakref(level)
	await _press(level.hud.get_node("Root/Finish/Card/Next"))
	await _until(func() -> bool: return old.get_ref() == null, 3.0)
	await _frames(3)
	return _viewport.get_child(_viewport.get_child_count() - 1) as Level


## Presses [param control] through the touch path, in its middle.
func _press(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		_viewport.push_input(event, true)
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
