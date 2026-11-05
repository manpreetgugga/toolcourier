extends SceneTree
## Scripted check of the daily reminders (see Reminders), with a stand-in
## answering for the Android plugin: the 200 messages (all different, short,
## plain ASCII, and right at any time of day); the three times and their
## titles; no reminders and no Settings row away from Android; what the
## plugin is handed when the reminders start and after each change of the
## setting; Android asked for leave to notify a moment after a level is
## finished (the first time only, never over an ad) and when the player
## turns the reminders on while Android doesn't allow them; the setting kept
## in the settings file; and the Settings card's Reminders row, tapped
## through the touch path, with the ad privacy row under it. Prints
## PASS/FAIL per check, saves screenshots, and exits with status 1 on any
## failure. Needs a renderer.
##
##   godot --audio-driver Dummy --path . --resolution 405x720 -s res://tools/test_reminders.gd -- --out=docs/screenshots

const SIZE := Vector2i(720, 1280)
const SETTINGS := "user://test_reminders_settings.json"
const ADS_SAVE := "user://test_reminders_ads.json"
## The first level with ads (and so the ad privacy row, where the law asks
## for it).
const WORLD_1_ADS := "res://levels/world_1/level_21.json"
const LONGEST: int = 90
## Words that would be wrong at some time of day, under some title.
const TIME_WORDS := "(?i)\\b(morning|afternoon|evening|tonight|night|noon|midday|breakfast|lunch|dinner|supper|sunrise|sunset|dawn|dusk|bedtime|yesterday)\\b"

var _viewport: SubViewport
var _stand_in: StandIn
var _out_dir: String = "docs/screenshots"
var _failures: int = 0
## How many times Reminders.events.changed has fired.
var _changes: int = 0


## Answers for the TinyCourierReminders plugin and keeps what it was asked.
class StandIn:
	extends RefCounted

	signal permission_result(allowed: bool)

	## can_notify(): Android allows notifications.
	var allowed: bool = true
	## can_ask(): Android has yet to be asked.
	var askable: bool = false
	## The JSON of every configure(), in order.
	var configured: Array = []
	## The open_settings of every request_permission(), in order.
	var requests: Array = []

	func configure(json: String) -> void:
		configured.append(json)

	func can_notify() -> bool:
		return allowed

	func can_ask() -> bool:
		return askable

	func request_permission(open_settings: bool) -> void:
		requests.append(open_settings)

	## The player answers Android's question.
	func answer(yes: bool) -> void:
		askable = false
		allowed = yes
		permission_result.emit(yes)

	## What the last configure() said, parsed.
	func last() -> Dictionary:
		return JSON.parse_string(configured.back()) if not configured.is_empty() else {}


func _initialize() -> void:
	Settings.use_file(SETTINGS)
	Progress.use_file("user://test_reminders_progress.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if not _out_dir.is_absolute_path():
		_out_dir = ProjectSettings.globalize_path("res://").path_join(_out_dir)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_run()


func _run() -> void:
	await _frames(2)
	_check_messages()
	var settings := SettingsCard.new()
	_viewport.add_child(settings)
	await _frames(2)
	await _check_without_plugin(settings)
	_check_handover()
	await _check_asking()
	_check_settings_file()
	await _check_settings_card(settings)
	Reminders.use_provider(null)
	Ads.use_provider(null)
	if _failures == 0:
		print("all checks passed")
	else:
		print("%d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_messages() -> void:
	var messages: Array[String] = ReminderMessages.ALL
	var time_words := RegEx.create_from_string(TIME_WORDS)
	var seen: Dictionary = {}
	var longest: String = ""
	var bad: Array[String] = []
	for message: String in messages:
		seen[message] = true
		if message.length() > longest.length():
			longest = message
		var plain: bool = true
		for i in message.length():
			plain = plain and message.unicode_at(i) >= 32 and message.unicode_at(i) < 127
		var tidy: bool = message == message.strip_edges() and not message.contains("  ") \
			and message.left(1) == message.left(1).to_upper() and message.right(1) in [".", "!", "?"]
		if not plain or not tidy or time_words.search(message) != null:
			bad.append(message)
	_check(messages.size() == 200 and seen.size() == 200, "there are 200 messages, all different (%d, %d)"
		% [messages.size(), seen.size()])
	_check(longest.length() <= LONGEST, "the longest is %d characters (at most %d): %s" % [longest.length(), LONGEST, longest])
	_check(bad.is_empty(), "each is plain ASCII, starts with a capital, ends a sentence and suits any time of day %s"
		% ("" if bad.is_empty() else str(bad)))
	_check(Reminders.TIMES == [540, 840, 1170] and Reminders.TITLES == ["Good morning", "Good afternoon", "Good evening"],
		"the reminders come at 9:00, 14:00 and 19:30, titled for the time of day")


func _check_without_plugin(settings: SettingsCard) -> void:
	var card: Control = settings.get_node("Card")
	var toggle: Control = card.get_node("Reminders")
	Reminders.start()
	Reminders.level_finished()
	settings.open()
	await _wait(0.45)
	_check(not Reminders.is_supported() and not Reminders.is_on() and not toggle.visible
		and is_equal_approx(card.size.y, SettingsCard.SIZE.y), "away from Android there are no reminders and no Settings row")
	settings.close()
	await _wait(0.3)


func _check_handover() -> void:
	Reminders.events.changed.connect(func() -> void: _changes += 1)
	_stand_in = StandIn.new()
	Reminders.use_provider(_stand_in)
	var config: Dictionary = _stand_in.last()
	_check(_stand_in.configured.size() == 1 and _stand_in.configured[0] == JSON.stringify(Reminders.config(true)),
		"once started, the reminders are handed over as soon as the plugin is there")
	var times: Array = config.get("times", []).map(func(minutes: Variant) -> int: return int(minutes))
	_check(config.get("enabled") == true and times == [540, 840, 1170] and config.get("titles") == Reminders.TITLES
		and config.get("messages") == ReminderMessages.ALL and int(config.get("quiet_minutes", 0)) == 120
		and int(config.get("late_minutes", 0)) == 120 and int(config.get("idle_days", 0)) == 7,
		"with the times, titles, all 200 messages, two quiet hours after play, two hours' grace and a week's idling")
	Reminders.start()
	_check(_stand_in.configured.size() == 1, "and only once a launch")

	Settings.set_value(&"reminders", false)
	_check(_stand_in.configured.size() == 2 and _stand_in.last().get("enabled") == false and _stand_in.requests.is_empty()
		and _changes == 1 and not Reminders.is_on(), "turning them off in Settings clears them")
	Settings.set_value(&"reminders", true)
	_check(_stand_in.configured.size() == 3 and _stand_in.last().get("enabled") == true and _stand_in.requests.is_empty()
		and _changes == 2 and Reminders.is_on(), "turning them on sets them again, with no question while Android allows them")
	Settings.set_value(&"music", 0.5)
	_check(_stand_in.configured.size() == 3 and _changes == 2, "other settings leave them be")

	Settings.set_value(&"reminders", false)
	_stand_in.allowed = false
	_changes = 0
	Settings.set_value(&"reminders", true)
	_check(_stand_in.last().get("enabled") == true and _stand_in.requests == [true] and _changes == 0 and not Reminders.is_on(),
		"turned on while Android doesn't allow them, Android asks the player (or its settings open)")
	_stand_in.answer(true)
	_check(_changes == 1 and Reminders.is_on(), "and a yes turns them on")
	Settings.set_value(&"reminders", false)
	_stand_in.allowed = false
	Settings.set_value(&"reminders", true)
	_stand_in.answer(false)
	_check(_changes == 3 and not Reminders.is_on() and Settings.reminders,
		"a no leaves them off, with the setting kept for when Android allows them")
	_stand_in.allowed = true
	_stand_in.requests.clear()


func _check_asking() -> void:
	_stand_in.allowed = false
	_stand_in.askable = true
	Reminders.level_finished()
	await _wait(Reminders.ASK_DELAY * 0.5)
	_check(_stand_in.requests.is_empty(), "a finished level doesn't ask at once (the finish card comes first)")
	await _wait(Reminders.ASK_DELAY * 0.5 + 0.3)
	_check(_stand_in.requests == [false], "a moment later Android asks the player, the first time")
	_stand_in.answer(true)
	_stand_in.requests.clear()
	Reminders.level_finished()
	await _wait(Reminders.ASK_DELAY + 0.3)
	_check(_stand_in.requests.is_empty(), "and not again once asked")

	_stand_in.askable = true
	Ads._showing = true
	Reminders.level_finished()
	await _wait(Reminders.ASK_DELAY + 0.3)
	Ads._showing = false
	_check(_stand_in.requests.is_empty(), "never over an ad (the next finish asks)")
	Settings.set_value(&"reminders", false)
	Reminders.level_finished()
	await _wait(Reminders.ASK_DELAY + 0.3)
	_check(_stand_in.requests.is_empty(), "nor with the reminders turned off")
	Settings.set_value(&"reminders", true)
	_stand_in.askable = false
	_stand_in.requests.clear()


func _check_settings_file() -> void:
	Settings.set_value(&"reminders", false)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	Settings.use_file(SETTINGS, false)
	_check(saved is Dictionary and saved.get("reminders") == false and not Settings.reminders,
		"the setting is saved and comes back from the file")
	# A file saved by 1.0.0, before there were reminders.
	var file := FileAccess.open(SETTINGS, FileAccess.WRITE)
	file.store_string(JSON.stringify({"music": 0.4}))
	file.close()
	Settings.use_file(SETTINGS, false)
	_check(Settings.reminders and is_equal_approx(Settings.music, 0.4),
		"a settings file from before there were reminders turns them on")
	Settings.set_value(&"reminders", false, false)
	Settings.use_file(SETTINGS)
	_check(Settings.reminders, "and so does a fresh one")
	Settings.set_value(&"reminders", true)


func _check_settings_card(settings: SettingsCard) -> void:
	var card: Control = settings.get_node("Card")
	var toggle: Control = card.get_node("Reminders")
	var options: Control = card.get_node("AdPrivacy")
	settings.open()
	await _wait(0.45)
	_check(toggle.visible and toggle.get("on") and not options.visible
		and is_equal_approx(card.size.y, SettingsCard.SIZE.y + SettingsCard.ROW_HEIGHT),
		"on Android, Settings has a Reminders row, switched on")
	_capture("reminders_settings.png")
	var handed: int = _stand_in.configured.size()
	await _press(toggle)
	await _frames(2)
	_check(not Settings.reminders and not toggle.get("on") and _stand_in.configured.size() == handed + 1
		and _stand_in.last().get("enabled") == false, "tapping the switch turns the reminders off")
	_stand_in.allowed = false
	await _press(toggle)
	await _frames(2)
	_check(Settings.reminders and _stand_in.requests == [true], "tapping it on while Android doesn't allow them asks Android")
	_stand_in.answer(false)
	await _wait(0.3)
	_check(not toggle.get("on"), "and the switch goes back off after a no")
	_stand_in.allowed = true
	settings.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _wait(0.3)
	_check(toggle.get("on"), "back from Android's settings with notifications allowed, it shows on")

	var preview := Ads.Preview.new()
	preview.auto = true
	preview.privacy_required = true
	Ads.use_provider(preview)
	Ads.use_file(ADS_SAVE)
	Ads.start_for(WORLD_1_ADS)
	await _frames(3)
	var rect := Rect2(card.position, card.size)
	_check(toggle.visible and options.visible and options.position.y > toggle.position.y + SettingsCard.ROW_HEIGHT * 0.5
		and is_equal_approx(card.size.y, SettingsCard.SIZE.y + SettingsCard.ROW_HEIGHT * 2.0)
		and Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(rect),
		"with the ad privacy row under it, the card still fits the screen (%s)" % rect)
	_capture("reminders_settings_ads.png")
	settings.close()
	await _wait(0.3)


func _press(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		_viewport.push_input(event, true)
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
