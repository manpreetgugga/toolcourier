class_name Courier
extends Node3D
## The walking mailbox. Walks cell to cell along paths from a Pathfinder and
## animates procedurally: breathing while idle, a waddling walk with swinging
## legs, a squash on landings, a puzzled tilt, a happy hop-and-spin and the
## odd blink.
##
## Faces -Z in local space; the root sits on the floor of its current cell.

signal step_finished(cell: Vector3i)
signal arrived(cell: Vector3i)

## Seconds per cell walked, and per cell carried by a belt.
const STEP_TIME: float = 0.28
const RIDE_TIME: float = 0.22
const TURN_RATE: float = 16.0
const BOB_HEIGHT: float = 0.04
const LEAN: float = 0.13
const SWAY: float = 0.07
const LEG_SWING: float = 0.65
const BREATH: float = 0.03
const BREATH_PERIOD: float = 2.0
const DOOR_OPEN: float = -1.3

var pathfinder: Pathfinder
## The cell the courier stands in (or last finished stepping into).
var cell: Vector3i

var _rig: CourierBuilder.Rig
var _queue: Array[Vector3i] = []
var _stepping: bool = false
## The current step is a belt carrying it, not a walk.
var _riding: bool = false
var _step_target: Vector3i
var _step_tween: Tween
var _facing_yaw: float = PI
var _phase: float = 0.0
var _walk_blend: float = 0.0
var _time: float = 0.0
var _blink_in: float = 2.5
var _happy_tween: Tween
var _tilt_tween: Tween
## Offsets driven by tweens and combined each frame in _process.
var _squash := Vector3.ONE
var _tilt: float = 0.0
var _hop: float = 0.0
var _spin: float = 0.0


func _ready() -> void:
	_rig = CourierBuilder.build(self)
	rotation.y = _facing_yaw


## Puts the courier on [param at], facing [param facing] (a horizontal
## direction), dropping any walk at once (the step in progress too).
func place(at: Vector3i, facing: Vector3i = Vector3i(0, 0, 1)) -> void:
	_queue.clear()
	if _step_tween:
		_step_tween.kill()
	_stepping = false
	_riding = false
	cell = at
	position = pathfinder.floor_position(at)
	_face(Vector3(facing))
	rotation.y = _facing_yaw


func is_moving() -> bool:
	return _stepping


## The horizontal direction it faces (or is turning to face).
func facing() -> Vector3i:
	return Vector3i(roundi(-sin(_facing_yaw)), 0, roundi(-cos(_facing_yaw)))


## Where a new path should start: the cell being stepped into, or the
## current one when standing still.
func path_origin() -> Vector3i:
	return _step_target if _stepping else cell


## Walks [param path] (cells after [method path_origin]). Replaces any
## remaining path; a step in progress finishes first.
func walk(path: Array[Vector3i]) -> void:
	_queue = path.duplicate()
	if not _stepping:
		_next_step()


## Head tilt for "I can't get there".
func puzzled() -> void:
	if _tilt_tween:
		_tilt_tween.kill()
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(self, "_tilt", 0.28, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tilt_tween.tween_interval(0.3)
	_tilt_tween.tween_property(self, "_tilt", 0.0, 0.22).set_trans(Tween.TRANS_SINE)


## Happy hop and spin with "^ ^" eyes, for a finished level.
func celebrate() -> void:
	if _happy_tween:
		_happy_tween.kill()
	_set_happy_eyes(true)
	_spin = 0.0
	_happy_tween = create_tween()
	_happy_tween.tween_property(self, "_squash", Vector3(1.12, 0.85, 1.12), 0.1)
	_happy_tween.tween_property(self, "_squash", Vector3(0.92, 1.12, 0.92), 0.08)
	_happy_tween.set_parallel()
	_happy_tween.tween_property(self, "_hop", 0.32, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_happy_tween.tween_property(self, "_spin", TAU, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_happy_tween.chain().tween_property(self, "_hop", 0.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_happy_tween.chain().tween_callback(_land.bind(1.0))
	_happy_tween.tween_interval(1.2)
	_happy_tween.chain().tween_callback(_set_happy_eyes.bind(false))


## Drops the rest of the current path; the step in progress still finishes.
func stop() -> void:
	_queue.clear()


## Ends a celebration or a puzzled tilt at once and lands with a little
## squash (after undo or restart puts it somewhere new).
func reset_pose() -> void:
	for tween: Tween in [_happy_tween, _tilt_tween]:
		if tween:
			tween.kill()
	_set_happy_eyes(false)
	_hop = 0.0
	_spin = 0.0
	_tilt = 0.0
	_squash = Vector3.ONE
	_rig.door_hinge.rotation.x = 0.0
	_land(0.8)


## Shows what is carried: the flag goes up in the colour of the next parcel
## to deliver, and down again when there is nothing left.
func set_carried(colors: Array[StringName]) -> void:
	var carrying: bool = not colors.is_empty()
	if carrying:
		_rig.flag.material_override = ClayShapes.material(Palette.PACKAGE[colors[0]])
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_rig.flag_pivot, "rotation:x", 0.0 if carrying else CourierBuilder.FLAG_LOWERED, 0.3)
	if not carrying:
		tween.tween_callback(func() -> void: _rig.flag.material_override = ClayShapes.material(CourierBuilder.FLAG_COLOR))


func set_door_open(open: bool) -> void:
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_rig.door_hinge, "rotation:x", DOOR_OPEN if open else 0.0, 0.25)


## Flaps the door open and shut, for parcels going in or out.
func flap_door(open_time: float = 0.35) -> void:
	set_door_open(true)
	get_tree().create_timer(open_time).timeout.connect(set_door_open.bind(false))


## World point just in front of the door, where parcels go in and come out.
func door_anchor() -> Vector3:
	return _rig.door_hinge.global_transform * Vector3(0.0, 0.14, -0.06)


func _next_step() -> void:
	if _queue.is_empty():
		_stepping = false
		_riding = false
		_land(0.5)
		arrived.emit(cell)
		return
	var next: Vector3i = _queue.pop_front()
	_stepping = true
	_riding = pathfinder.is_belt(cell)
	_step_target = next
	var from: Vector3 = position
	var to: Vector3 = pathfinder.floor_position(next)
	if not _riding:
		_face(to - from)
	_step_tween = create_tween()
	_step_tween.tween_property(self, "position", to, RIDE_TIME if _riding else STEP_TIME)
	_step_tween.tween_callback(_finish_step.bind(next, to.y - from.y))


func _finish_step(next: Vector3i, rise: float) -> void:
	cell = next
	step_finished.emit(cell)
	# Settle with a little squash when coming off a climb onto flat ground.
	if absf(rise) > 0.2 and (_queue.is_empty() or is_equal_approx(pathfinder.floor_position(_queue[0]).y, position.y)):
		_land(0.7)
	_next_step()


func _land(strength: float) -> void:
	var squash := Vector3(1.0 + 0.1 * strength, 1.0 - 0.14 * strength, 1.0 + 0.1 * strength)
	var tween: Tween = create_tween()
	tween.tween_property(self, "_squash", squash, 0.07)
	tween.tween_property(self, "_squash", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		_facing_yaw = atan2(-direction.x, -direction.z)


func _set_happy_eyes(happy: bool) -> void:
	for eye: Node3D in _rig.open_eyes:
		eye.visible = not happy
	for eye: Node3D in _rig.happy_eyes:
		eye.visible = happy


func _process(delta: float) -> void:
	_time += delta
	var walking: bool = _stepping and not _riding
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 7.0)
	if walking:
		_phase += delta / STEP_TIME * PI
	elif _walk_blend == 0.0:
		_phase = 0.0
	rotation.y = lerp_angle(rotation.y, _facing_yaw, 1.0 - exp(-TURN_RATE * delta))

	var swing: float = sin(_phase) * _walk_blend
	_rig.leg_left.rotation.x = swing * LEG_SWING
	_rig.leg_right.rotation.x = -swing * LEG_SWING
	_rig.root.position.y = _hop
	_rig.root.rotation.y = _spin

	var body: Node3D = _rig.body
	var breath: float = sin(_time * TAU / BREATH_PERIOD) * BREATH * (1.0 - _walk_blend)
	body.position.y = absf(sin(_phase)) * BOB_HEIGHT * _walk_blend
	body.rotation = Vector3(-LEAN * _walk_blend, 0.0, swing * SWAY + _tilt)
	body.scale = Vector3(1.0 - breath * 0.5, 1.0 + breath, 1.0 - breath * 0.5) * _squash

	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.5, 5.5)
		for eye: Node3D in _rig.eyes:
			var blink: Tween = create_tween()
			blink.tween_property(eye, "scale:y", 0.12, 0.06)
			blink.tween_property(eye, "scale:y", 1.0, 0.08)
