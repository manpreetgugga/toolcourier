class_name Ads
extends RefCounted
## Google AdMob, kept calm. World 1's first 20 levels (its first five
## chapters) have no ads at all (they don't even start there), there are no
## banners, and from its level 21 on only two kinds play:
##
## - **Hint video** (rewarded), only when the player asks for one: the first
##   Hint in a level offers a short video that turns hints on for the rest of
##   that level. When no video is ready (offline, nothing to show, no consent)
##   the hint is simply free.
## - **Level break** (interstitial), only on the level-complete card, as the
##   player moves on from it (Next, Levels or back), and at most once every 3
##   or 4 levels finished. Never on Replay, never after a level that was
##   restarted along the way or finished without a star, never within 4
##   minutes of another ad or of the game opening, and never mid-puzzle.
##
## [member enabled] is the one switch for every ad: off, Google's consent
## form never shows, the ads SDK never starts, hints are free and no break
## plays. The tests turn it off, as does --no-ads on the command line, and so
## would a "remove ads" purchase.
##
## On Android the ads come from the TinyCourierAds plugin (android-plugin/,
## added to exports by addons/tiny_courier_ads). Elsewhere there are none,
## unless --ads-preview puts [Ads.Preview] in its place, which shows a plain
## card for each ad so the placements can be tried on the desktop. The count
## towards the next break is kept in user://ads.json. Everything is static.

## Shown in Settings, and given to Play Console.
const PRIVACY_URL: String = "https://github.com/manpreetgugga/toolcourier/blob/main/PRIVACY.md"
const DEFAULT_PATH: String = "user://ads.json"
## The first level with ads: world 1's level 21, where the sliding bridges
## come in.
const FIRST_WORLD: int = 1
const FIRST_LEVEL: int = 21
## Levels finished between breaks: one of these, picked afresh after each break.
const BREAK_GAPS: Array[int] = [3, 4]
## Seconds after any ad, or after the game opens, before a break may play
## (so coming back to the game never starts with one).
const QUIET_SECONDS: int = 240

## The one switch (see the class description).
static var enabled: bool = not (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has("--no-ads")
static var path: String = DEFAULT_PATH
## Emits changed() when the consent answer, or whether Settings must offer
## the ad privacy options, may have changed.
static var events := Events.new()

## The plugin's singleton, a Preview, or null (no ads).
static var _provider: Object
static var _provider_found: bool = false
static var _started: bool = false
## An ad is on screen (or about to be).
static var _showing: bool = false
## Levels whose hints a video has turned on, this launch.
static var _hint_levels: Dictionary = {}
## Levels finished (with ads) since the last break, and how many the next
## break waits for.
static var _finished: int = 0
static var _gap: int = 0
## Unix time of the last ad of any kind.
static var _last_ad: int = 0
## Unix time the game opened (as this script loaded).
static var _opened: int = int(Time.get_unix_time_from_system())
## Whether the latest finish may be followed by a break.
static var _break_allowed: bool = false
static var _loaded: bool = false


class Events:
	extends RefCounted
	signal changed


## Switches to another file (tests use their own); with [param fresh] it
## starts from nothing and deletes what was there.
static func use_file(file_path: String, fresh: bool = true) -> void:
	path = file_path
	_hint_levels.clear()
	_break_allowed = false
	if fresh:
		_reset()
		_loaded = true
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		load_file()


## Puts [param provider] behind the ads (a Preview in the tests; null for
## none). It is started at once if the ads already were.
static func use_provider(provider: Object) -> void:
	_provider_found = true
	if _provider and _provider.is_connected(&"consent_changed", _on_consent_changed):
		_provider.disconnect(&"consent_changed", _on_consent_changed)
	_provider = provider
	_showing = false
	if _provider:
		_provider.connect(&"consent_changed", _on_consent_changed)
		if _started:
			_provider.call(&"start")


## Starts the ads for a player who has reached [param level_path], from
## world 1's level 21 on: Google's consent form where the law needs it, then
## the ads SDK, which loads one ad of each kind. Once a launch.
static func start_for(level_path: String) -> void:
	if _started or not _active_in(level_path):
		return
	_started = true
	_provider.call(&"start")


## Whether an ad covers the game (the level doesn't pause itself for one).
static func is_showing() -> bool:
	return _showing


## Whether a hint in [param level_path] needs a video first (see the class
## description).
static func hint_needs_video(level_path: String) -> bool:
	return _active_in(level_path) and not _hint_levels.has(level_path) and _can_show(&"rewarded")


## Whether a video has turned hints on for [param level_path].
static func hints_unlocked(level_path: String) -> bool:
	return _hint_levels.has(level_path)


## Plays the hint video for [param level_path]. Returns {"earned": true} once
## it was watched to the end, which turns hints on for the level; otherwise
## {"earned": false, "reason": ...}, the reason "cancelled" when the player
## closed it early.
static func watch_hint_video(level_path: String) -> Dictionary:
	var result: Dictionary = await _show(&"rewarded", "hint")
	if result["ok"]:
		_hint_levels[level_path] = true
	return {"earned": result["ok"], "reason": result["reason"]}


## Counts a finish of [param level_path] towards the next break (in levels
## with ads). Only a [param clean] finish (with a star, and no restart along
## the way) may be followed by one.
static func level_finished(level_path: String, clean: bool) -> void:
	_break_allowed = false
	if not _active_in(level_path):
		return
	_load_once()
	_finished += 1
	_break_allowed = clean
	save()


## Whether moving on from the level-complete card would play a break.
static func break_due() -> bool:
	_load_once()
	return enabled and _break_allowed and _finished >= _gap and _quiet() and _can_show(&"interstitial")


## Plays a break if one is due, as the player moves on from the
## level-complete card, and returns once it is over (at once if none is).
static func play_break_if_due() -> void:
	if not break_due():
		return
	_break_allowed = false
	var result: Dictionary = await _show(&"interstitial", "level_complete")
	if result["ok"]:
		_finished = 0
		_gap = BREAK_GAPS.pick_random()
		save()


## Levels finished since the last break, and how many the next one waits for.
static func break_count() -> Vector2i:
	_load_once()
	return Vector2i(_finished, _gap)


## Whether Settings must offer Google's ad privacy options (where the law
## gives the player the right to change their consent).
static func privacy_options_required() -> bool:
	return enabled and _started and _provider != null and bool(_provider.call(&"is_privacy_options_required"))


## Opens Google's ad privacy options and returns once they close.
static func show_privacy_options() -> void:
	if _provider == null:
		return
	_provider.call(&"show_privacy_options")
	await Signal(_provider, &"privacy_options_closed")
	events.changed.emit()


static func save() -> void:
	var text: String = JSON.stringify({"finished": _finished, "gap": _gap, "last_ad": _last_ad}, "\t")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Ads: cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	file.close()
	var error: Error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		push_warning("Ads: cannot replace %s (%s)" % [path, error_string(error)])


## Reads the file; anything missing or unreadable starts afresh.
static func load_file() -> void:
	_loaded = true
	_reset()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ads: %s is unreadable; starting afresh" % path)
		return
	if typeof(parsed.get("finished")) in [TYPE_INT, TYPE_FLOAT]:
		_finished = maxi(int(parsed["finished"]), 0)
	if typeof(parsed.get("gap")) in [TYPE_INT, TYPE_FLOAT] and int(parsed["gap"]) in BREAK_GAPS:
		_gap = int(parsed["gap"])
	if typeof(parsed.get("last_ad")) in [TYPE_INT, TYPE_FLOAT]:
		_last_ad = int(parsed["last_ad"])


## Ads can play in [param level_path]: the switch is on, there is something
## to show them, and the level is world 1's level 21 or a later one.
static func _active_in(level_path: String) -> bool:
	_find_provider_once()
	if not enabled or _provider == null:
		return false
	var world: int = LevelCatalog.world_of(level_path)
	return world > FIRST_WORLD or (world == FIRST_WORLD and LevelCatalog.number_of(level_path) >= FIRST_LEVEL)


static func _can_show(kind: StringName) -> bool:
	return _started and not _showing and bool(_provider.call(StringName("is_%s_ready" % kind)))


static func _quiet() -> bool:
	var now: int = int(Time.get_unix_time_from_system())
	# A clock put back counts as quiet rather than holding the breaks off.
	return (now - _last_ad >= QUIET_SECONDS or now < _last_ad) and (now - _opened >= QUIET_SECONDS or now < _opened)


## Shows an ad of [param kind] ("rewarded" or "interstitial") and waits for
## it to close: {"ok": bool, "reason": String}.
static func _show(kind: StringName, placement: String) -> Dictionary:
	# Read the count first, or saving the ad's time would write over it.
	_load_once()
	_showing = true
	_provider.call(StringName("show_%s" % kind), placement)
	var reply: Array = await Signal(_provider, StringName("%s_finished" % kind))
	_showing = false
	var ok: bool = reply[0]
	var reason: String = reply[1]
	if ok or reason == "cancelled":
		_last_ad = int(Time.get_unix_time_from_system())
		save()
	return {"ok": ok, "reason": reason}


static func _find_provider_once() -> void:
	if _provider_found:
		return
	_provider_found = true
	if Engine.has_singleton("TinyCourierAds"):
		use_provider(Engine.get_singleton("TinyCourierAds"))
	elif (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has("--ads-preview"):
		use_provider(Preview.new())


static func _on_consent_changed() -> void:
	events.changed.emit()


static func _load_once() -> void:
	if not _loaded:
		load_file()


static func _reset() -> void:
	_finished = 0
	_gap = BREAK_GAPS.pick_random()
	_last_ad = 0


## A stand-in for the Android plugin away from phones (--ads-preview, and
## the tests): it always has an ad ready and shows a plain card where the ad
## would be, with a close button (a video pays only once its countdown has
## run out), so the placements can be tried and screenshotted on the
## desktop. With [member auto] it answers at once instead, paying a video
## when [member earn] is true.
class Preview:
	extends RefCounted

	signal consent_changed
	signal rewarded_finished(earned: bool, reason: String)
	signal interstitial_finished(shown: bool, reason: String)
	signal privacy_options_closed(error: String)

	const VIDEO_SECONDS: int = 5

	var auto: bool = false
	var earn: bool = true
	var privacy_required: bool = true
	## Everything asked for, in order: "rewarded:hint",
	## "interstitial:level_complete", "privacy_options".
	var shown: Array[String] = []
	## The card on screen, if any.
	var card: Control

	func start() -> void:
		consent_changed.emit.call_deferred()

	func is_rewarded_ready() -> bool:
		return true

	func is_interstitial_ready() -> bool:
		return true

	func is_privacy_options_required() -> bool:
		return privacy_required

	func show_rewarded(placement: String) -> void:
		shown.append("rewarded:" + placement)
		if auto:
			rewarded_finished.emit.call_deferred(earn, "" if earn else "cancelled")
		else:
			_cover("Rewarded video", VIDEO_SECONDS, func(watched: bool) -> void:
				rewarded_finished.emit(watched, "" if watched else "cancelled"))

	func show_interstitial(placement: String) -> void:
		shown.append("interstitial:" + placement)
		if auto:
			interstitial_finished.emit.call_deferred(true, "")
		else:
			_cover("Interstitial", 0, func(_watched: bool) -> void: interstitial_finished.emit(true, ""))

	func show_privacy_options() -> void:
		shown.append("privacy_options")
		privacy_options_closed.emit.call_deferred("")

	## A dark card over everything, like the ad would be, that pauses the game
	## while it shows and calls [param closed] with whether its [param seconds]
	## ran out before it was closed.
	func _cover(kind: String, seconds: int, closed: Callable) -> void:
		var tree := Engine.get_main_loop() as SceneTree
		var was_paused: bool = tree.paused
		tree.paused = true
		var layer := CanvasLayer.new()
		layer.name = "AdPreview"
		layer.layer = 200
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(layer)
		card = ColorRect.new()
		card.name = "Card"
		(card as ColorRect).color = Color("#202028")
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		layer.add_child(card)
		var middle := CenterContainer.new()
		middle.set_anchors_preset(Control.PRESET_FULL_RECT)
		middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(middle)
		var lines := VBoxContainer.new()
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_theme_constant_override(&"separation", 18)
		middle.add_child(lines)
		lines.add_child(_text("Test ad", 64, Color.WHITE))
		lines.add_child(_text(kind + " (preview)", 30, Color(1.0, 1.0, 1.0, 0.6)))
		var count: Label = _text("", 26, Color(1.0, 1.0, 1.0, 0.6))
		lines.add_child(count)
		var close := TouchButton.new(Vector2(96.0, 96.0))
		close.name = "Close"
		close.text = "X"
		close.color = Color(1.0, 1.0, 1.0, 0.85)
		close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		close.offset_left = -140.0
		close.offset_right = -44.0
		close.offset_top = 60.0
		close.offset_bottom = 156.0
		card.add_child(close)
		var left: Array[int] = [seconds]
		var tick: Callable = func() -> void:
			if seconds == 0:
				count.text = "Close it to carry on"
			else:
				count.text = "Reward in %d s" % left[0] if left[0] > 0 else "Reward earned"
		tick.call()
		var timer := Timer.new()
		timer.process_mode = Node.PROCESS_MODE_ALWAYS
		layer.add_child(timer)
		timer.timeout.connect(func() -> void:
			left[0] = maxi(left[0] - 1, 0)
			tick.call())
		timer.start(1.0)
		close.pressed.connect(func() -> void:
			layer.queue_free()
			card = null
			tree.paused = was_paused
			closed.call(left[0] == 0))

	static func _text(text: String, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.text = text
		label.label_settings = Ui.label_settings(font_size, color)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return label
