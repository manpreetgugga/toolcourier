class_name Analytics
extends RefCounted
## Statistics and crash reports on Android, through Google's Firebase:
## Google Analytics for how the game is played, and Crashlytics for crashes.
##
## The game reports each go at a level (level_start, then level_end with
## whether it was finished, the moves, stars, seconds played, hints, undos
## and restarts), the hint video offer (hint_video), the screens (menu,
## worlds, map, level, settings), and the settings and progress as user
## properties. The reminders plugin counts reminders shown and opened, and
## Google's ads library its ads. Analytics adds what it collects itself
## (sessions, the phone's model, system and language, a rough location from
## the connection). Crashlytics reports crashes, the engine's own included,
## and this side adds script and engine errors the game survived (a few a
## launch, see [constant MOST_ERRORS]), with the level being played.
##
## Nothing is sent without the player's leave where the law asks for it:
## in the European Economic Area, the UK and Switzerland ([method
## region_needs_consent], from the phone's SIM, network, language and time
## zone) the menu asks once (see StatisticsCard), and until then nothing is
## collected. Elsewhere it is on from the start. Either way the player turns
## it off in Settings ([member Settings.statistics]). The advertising ID is
## used only where no consent is needed, and Analytics data never
## personalizes ads.
##
## The TinyCourierFirebase plugin (android-firebase/, added to Android
## exports by addons/tiny_courier_firebase) does the sending. Elsewhere there
## is none, unless a test puts a stand-in in its place ([method
## use_provider]). Everything is static.

## Where the player is asked first, by ISO country code: the European
## Economic Area (with the EU's outlying regions and Aland), the UK (with
## Gibraltar and the Crown dependencies) and Switzerland.
const CONSENT_COUNTRIES: Array[String] = [
	"AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE", "IT", "LT", "LU",
	"LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "IS", "LI", "NO", "GB", "CH",
	"AX", "GF", "GP", "MQ", "RE", "YT", "MF", "GI", "GG", "JE", "IM",
]
## The time zones of those places (and of the small states among them).
const CONSENT_ZONES: Array[String] = [
	"Europe/Amsterdam", "Europe/Andorra", "Europe/Athens", "Europe/Belfast", "Europe/Berlin", "Europe/Bratislava",
	"Europe/Brussels", "Europe/Bucharest", "Europe/Budapest", "Europe/Busingen", "Europe/Copenhagen", "Europe/Dublin",
	"Europe/Gibraltar", "Europe/Guernsey", "Europe/Helsinki", "Europe/Isle_of_Man", "Europe/Jersey", "Europe/Lisbon",
	"Europe/Ljubljana", "Europe/London", "Europe/Luxembourg", "Europe/Madrid", "Europe/Malta", "Europe/Mariehamn",
	"Europe/Monaco", "Europe/Nicosia", "Europe/Oslo", "Europe/Paris", "Europe/Prague", "Europe/Riga", "Europe/Rome",
	"Europe/San_Marino", "Europe/Sofia", "Europe/Stockholm", "Europe/Tallinn", "Europe/Vaduz", "Europe/Vatican",
	"Europe/Vienna", "Europe/Vilnius", "Europe/Warsaw", "Europe/Zagreb", "Europe/Zurich",
	"Atlantic/Azores", "Atlantic/Canary", "Atlantic/Faroe", "Atlantic/Jan_Mayen", "Atlantic/Madeira",
	"Atlantic/Reykjavik", "Arctic/Longyearbyen", "Asia/Famagusta", "Asia/Nicosia", "Africa/Ceuta",
	"America/Cayenne", "America/Guadeloupe", "America/Marigot", "America/Martinique", "Indian/Mayotte",
	"Indian/Reunion", "Eire", "GB", "GB-Eire", "Iceland", "Poland", "Portugal",
]
## Errors the game survived that are reported in a launch, at most (each
## place once).
const MOST_ERRORS: int = 5

## Emits changed() when whether statistics are collected may have changed.
static var events := Events.new()

## The plugin's singleton, a stand-in, or null (no statistics).
static var _provider: Object
static var _provider_found: bool = false
static var _started: bool = false
## Whether the player must be asked first: -1 until worked out.
static var _consent_region: int = -1
## User properties as last set, so a change of setting sends only what changed.
static var _sent: Dictionary = {}
## The errors reported this launch, by place and message.
static var _errors: Dictionary = {}
static var _logger: _ErrorLogger


class Events:
	extends RefCounted
	signal changed


## Puts [param provider] behind the statistics (a stand-in in the tests; null
## for none). It is configured at once if they have started.
static func use_provider(provider: Object) -> void:
	_provider_found = true
	_provider = provider
	_consent_region = -1
	_sent.clear()
	_errors.clear()
	if _provider == null and _logger:
		OS.remove_logger(_logger)
		_logger = null
	if _started:
		_configure()


## Starts or stops collecting as Settings and the player's region say, and
## follows Settings from then on. Once a launch; the menu and the levels
## call it.
static func start() -> void:
	if _started:
		return
	_find_provider_once()
	_started = true
	Settings.events.changed.connect(_on_setting_changed)
	Reminders.events.changed.connect(_update_properties)
	_configure()


## Whether this phone has statistics (the Settings row shows only then).
static func is_supported() -> bool:
	_find_provider_once()
	return _provider != null


## Whether statistics and crash reports are being collected: they're on in
## Settings, and where the player must be asked first, they were.
static func is_collecting() -> bool:
	if not is_supported():
		return false
	Settings.ensure_loaded()
	return Settings.statistics and (Settings.statistics_asked or not in_consent_region())


## Whether the menu should ask the player (see StatisticsCard): they must be
## asked first, and haven't been.
static func needs_consent() -> bool:
	if not is_supported():
		return false
	Settings.ensure_loaded()
	return not Settings.statistics_asked and in_consent_region()


## Whether the player must be asked before anything is collected, from what
## the phone says about where it is (worked out once a launch).
static func in_consent_region() -> bool:
	if _consent_region < 0:
		_consent_region = 0
		if is_supported():
			var parsed: Variant = JSON.parse_string(str(_provider.call(&"region_signals")))
			_consent_region = 1 if parsed is Dictionary and region_needs_consent(parsed) else 0
	return _consent_region == 1


## Whether [param signals] ({"sim", "network", "locale": country codes,
## "zone": a time zone}, any of them empty or missing) put the phone where
## the player must be asked first: any one of them is enough.
static func region_needs_consent(signals: Dictionary) -> bool:
	for key: String in ["sim", "network", "locale"]:
		if str(signals.get(key, "")).to_upper() in CONSENT_COUNTRIES:
			return true
	return str(signals.get("zone", "")) in CONSENT_ZONES


## Logs the Analytics event [param event_name], with [param params] (numbers,
## true or false, and strings of up to 100 characters).
static func event(event_name: String, params: Dictionary = {}) -> void:
	if is_collecting():
		_provider.call(&"log_event", event_name, JSON.stringify(params))


## The player is now on [param screen_name].
static func screen(screen_name: String) -> void:
	if is_collecting():
		_provider.call(&"set_crash_key", "screen", screen_name)
	event("screen_view", {"screen_name": screen_name, "screen_class": screen_name})


## A go at the level at [param level_path] began: it was opened ([param
## resumed] when a game in progress was picked up), or played again after a
## finish ([param replay]).
static func level_started(level_path: String, resumed: bool, replay: bool) -> void:
	if not is_collecting():
		return
	var id: String = Progress.level_id(level_path)
	_provider.call(&"set_crash_key", "level", id)
	_provider.call(&"crash_log", "%s %s" % [id, "replayed" if replay else ("resumed" if resumed else "started")])
	var params: Dictionary = _level_params(level_path)
	params.merge({"resumed": resumed, "replay": replay})
	event("level_start", params)


## A go at the level at [param level_path] ended: [param result] says
## whether it was finished ("success"), with the "moves", "stars",
## "seconds" played, and the "hints", "undos" and "restarts" in it.
static func level_ended(level_path: String, result: Dictionary) -> void:
	if not is_collecting():
		return
	var id: String = Progress.level_id(level_path)
	_provider.call(&"crash_log", "%s %s in %d moves" % [id, "finished" if result.get("success") else "left", result.get("moves", 0)])
	var params: Dictionary = _level_params(level_path)
	params.merge(result)
	event("level_end", params)
	if result.get("success"):
		_update_progress()


## How the hint video offer in the level at [param level_path] went:
## "declined", "earned" (watched to the end), "cancelled" (closed early) or
## why no video played.
static func hint_video(level_path: String, outcome: String) -> void:
	var params: Dictionary = _level_params(level_path)
	params["result"] = outcome.left(100)
	event("hint_video", params)


static func _level_params(level_path: String) -> Dictionary:
	return {
		"level_name": Progress.level_id(level_path),
		"world": LevelCatalog.world_of(level_path),
		"level": LevelCatalog.number_of(level_path),
		"level_index": LevelCatalog.all().find(level_path) + 1,
	}


static func _configure() -> void:
	if _provider == null:
		return
	var collecting: bool = is_collecting()
	_provider.call(&"configure", collecting, collecting and not in_consent_region())
	if collecting:
		_sent.clear()
		_update_properties()
		_update_progress()
		if _logger == null:
			_logger = _ErrorLogger.new()
			OS.add_logger(_logger)


static func _on_setting_changed(key: StringName) -> void:
	if key == &"statistics":
		_configure()
		events.changed.emit()
	else:
		_update_properties()


## The settings, as user properties (each sent when it changes) and with
## any crash report.
static func _update_properties() -> void:
	if not is_collecting():
		return
	var quality: String = Settings.QUALITY_NAMES[Settings.quality].to_lower()
	_set_property("quality", quality)
	_set_property("music", _on_off(Settings.music > 0.001))
	_set_property("sounds", _on_off(Settings.sfx > 0.001))
	_set_property("haptics", _on_off(Settings.haptics))
	_set_property("tilt_shift", _on_off(Settings.tilt_shift))
	_set_property("reminders", _on_off(Reminders.is_on()))
	if _sent.get("crash_quality") != quality:
		_sent["crash_quality"] = quality
		_provider.call(&"set_crash_key", "quality", quality)


## How far the player has got: the levels finished, and the world of the
## next one to play.
static func _update_progress() -> void:
	if not is_collecting():
		return
	var finished: int = 0
	for world: int in LevelCatalog.worlds():
		finished += LevelCatalog.world_finished(world)
	_set_property("levels_done", str(finished))
	_set_property("world", str(LevelCatalog.world_of(LevelCatalog.next_to_play())))


static func _set_property(property: String, value: String) -> void:
	if _sent.get(property) == value:
		return
	_sent[property] = value
	_provider.call(&"set_user_property", property, value)


static func _on_off(on: bool) -> String:
	return "on" if on else "off"


## Reports an error the game survived, once per place and message, and no
## more than [constant MOST_ERRORS] a launch. [param frames] are
## {"function", "file", "line"}, innermost first.
static func _report_error(message: String, frames: Array) -> void:
	if not is_collecting() or frames.is_empty():
		return
	var key: String = "%s:%s %s" % [frames[0].get("file", ""), frames[0].get("line", 0), message]
	if _errors.has(key) or _errors.size() >= MOST_ERRORS:
		return
	_errors[key] = true
	_provider.call(&"record_error", message.left(1000), JSON.stringify(frames))


static func _find_provider_once() -> void:
	if _provider_found:
		return
	_provider_found = true
	if Engine.has_singleton("TinyCourierFirebase"):
		use_provider(Engine.get_singleton("TinyCourierFirebase"))


## Hears the engine's errors (script errors among them) and passes them to
## [method _report_error] on the main thread. Warnings are left out.
class _ErrorLogger:
	extends Logger

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var frames: Array = []
		for backtrace: ScriptBacktrace in script_backtraces:
			for i in backtrace.get_frame_count():
				frames.append({"function": backtrace.get_frame_function(i), "file": backtrace.get_frame_file(i),
					"line": backtrace.get_frame_line(i)})
		if frames.is_empty():
			frames.append({"function": function, "file": file, "line": line})
		var message: String = code if rationale.is_empty() else "%s %s" % [code, rationale]
		Analytics._report_error.call_deferred(message, frames)
