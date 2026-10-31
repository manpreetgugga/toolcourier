class_name Haptics
extends RefCounted
## Short vibration ticks on phones: a light one for a tap on a button or the
## diorama, a firmer one when a mechanism snaps into place. Silent when the
## player turns haptics off, and on desktops. Every tick asked for is kept
## in [member history] (tests read it).

## Milliseconds and strength (0 to 1).
const TAP_MS: int = 12
const TAP_STRENGTH: float = 0.35
const SNAP_MS: int = 28
const SNAP_STRENGTH: float = 0.7
## Ticks closer together than this merge into one.
const MIN_GAP_MSEC: int = 40

## The last ticks asked for, as {"kind": &"tap" or &"snap", "ms": int,
## "on": whether it was let through (haptics on, not too soon after the
## last)}. Only phones then really vibrate.
static var history: Array[Dictionary] = []

static var _last_msec: int = -100000


static func tap() -> void:
	_tick(&"tap", TAP_MS, TAP_STRENGTH)


static func snap() -> void:
	_tick(&"snap", SNAP_MS, SNAP_STRENGTH)


static func _tick(kind: StringName, duration_ms: int, strength: float) -> void:
	Settings.ensure_loaded()
	var now: int = Time.get_ticks_msec()
	var on: bool = Settings.haptics and now - _last_msec >= MIN_GAP_MSEC
	history.append({"kind": kind, "ms": duration_ms, "on": on})
	if history.size() > 32:
		history.pop_front()
	if not on:
		return
	_last_msec = now
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms, strength)
