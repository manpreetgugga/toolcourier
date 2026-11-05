class_name Reminders
extends RefCounted
## Daily reminders on Android: a notification in the morning, the afternoon
## and the evening ([constant TIMES], the phone's own time), titled for the
## time of day and carrying one of the 200 messages in [ReminderMessages],
## picked at random (every one shows before any comes round again). English
## only. They keep quiet while the game is open and for two hours after it
## closes, skip one the phone slept through by more than two hours, and stop
## once the game hasn't been opened for a week, until it is. A tap opens the
## game, and opening it clears a reminder still showing.
##
## The player turns them off and on in Settings ([member Settings.reminders]).
## Android 13 and up must ask the player before any notification shows: the
## game asks the first time a level is finished, and again when the player
## turns the reminders on in Settings (where Android won't ask again, its
## notification settings for the game open instead).
##
## The TinyCourierReminders plugin (android-reminders/, added to Android
## exports by addons/tiny_courier_reminders) keeps the reminders and sets
## their alarms, so they show with the game closed. Elsewhere there are
## none, unless a test puts a stand-in in its place ([method use_provider]).
## Everything is static.

## Minutes after midnight: 9:00, 14:00 and 19:30.
const TIMES: Array[int] = [540, 840, 1170]
const TITLES: Array[String] = ["Good morning", "Good afternoon", "Good evening"]
## No reminder while the game is open, or this soon after it closed.
const QUIET_MINUTES: int = 120
## A reminder this late (the phone slept through its time) is skipped.
const LATE_MINUTES: int = 120
## The reminders stop once the game hasn't been opened for this long.
const IDLE_DAYS: int = 7
## How long after a level is finished Android's question comes, so the
## finish card is up first.
const ASK_DELAY: float = 1.6

## Emits changed() when whether reminders can show may have changed (the
## player's answer to Android's question, or the setting).
static var events := Events.new()

## The plugin's singleton, a stand-in, or null (no reminders).
static var _provider: Object
static var _provider_found: bool = false
static var _started: bool = false


class Events:
	extends RefCounted
	signal changed


## Puts [param provider] behind the reminders (a stand-in in the tests; null
## for none). It is handed the reminders at once if they have started.
static func use_provider(provider: Object) -> void:
	_provider_found = true
	if _provider and _provider.is_connected(&"permission_result", _on_permission_result):
		_provider.disconnect(&"permission_result", _on_permission_result)
	_provider = provider
	if _provider:
		_provider.connect(&"permission_result", _on_permission_result)
	if _started:
		_configure()


## Hands the reminders to Android, on or off as Settings says, and follows
## Settings from then on. Once a launch; the menu and the levels call it.
static func start() -> void:
	if _started:
		return
	_find_provider_once()
	_started = true
	Settings.events.changed.connect(_on_setting_changed)
	_configure()


## Whether this phone has reminders (the Settings row shows only then).
static func is_supported() -> bool:
	_find_provider_once()
	return _provider != null


## Whether reminders will show: they're on in Settings, and Android allows
## them.
static func is_on() -> bool:
	return is_supported() and Settings.get_value(&"reminders") and bool(_provider.call(&"can_notify"))


## A level was just finished. The first time, on Android 13 and up, Android
## asks the player whether the game may notify, once the finish card is up.
static func level_finished() -> void:
	if not is_supported() or not Settings.get_value(&"reminders") or not bool(_provider.call(&"can_ask")):
		return
	await (Engine.get_main_loop() as SceneTree).create_timer(ASK_DELAY).timeout
	# Not over an ad; the next finish asks instead.
	if not Ads.is_showing() and bool(_provider.call(&"can_ask")):
		_provider.call(&"request_permission", false)


## What the Android side is given, as JSON.
static func config(enabled: bool) -> Dictionary:
	return {
		"enabled": enabled,
		"times": TIMES,
		"titles": TITLES,
		"messages": ReminderMessages.ALL,
		"quiet_minutes": QUIET_MINUTES,
		"late_minutes": LATE_MINUTES,
		"idle_days": IDLE_DAYS,
	}


static func _configure() -> void:
	if _provider:
		_provider.call(&"configure", JSON.stringify(config(Settings.get_value(&"reminders"))))


static func _on_setting_changed(key: StringName) -> void:
	if key != &"reminders" or _provider == null:
		return
	_configure()
	# Turned on by the player while Android doesn't allow them: ask (or open
	# Android's settings for the game), and changed() follows the answer.
	if Settings.get_value(&"reminders") and not bool(_provider.call(&"can_notify")):
		_provider.call(&"request_permission", true)
	else:
		events.changed.emit()


static func _on_permission_result(_allowed: bool) -> void:
	events.changed.emit()


static func _find_provider_once() -> void:
	if _provider_found:
		return
	_provider_found = true
	if Engine.has_singleton("TinyCourierReminders"):
		use_provider(Engine.get_singleton("TinyCourierReminders"))
