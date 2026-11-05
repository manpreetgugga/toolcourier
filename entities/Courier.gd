class_name Courier
extends Node3D
## The walking mailbox. Walks cell to cell along paths from a Pathfinder and
## animates procedurally: breathing while idle, a waddling walk with swinging
## legs, a wobbly glide over ice, a grinning arc off a spring, a squash on
## landings, a puzzled tilt, a happy hop-and-spin, the odd blink, and a
## little emote when tapped.
##
## Faces -Z in local space; the root sits on the floor of its current cell.

signal step_finished(cell: Vector3i)
signal arrived(cell: Vector3i)

## Seconds per cell walked, per cell carried by a belt and per cell slid
## over ice.
const STEP_TIME: float = 0.28
const RIDE_TIME: float = 0.22
const SLIDE_TIME: float = 0.17
## A bounce off a spring: how far it sinks into the spring and how fast, how
## long it flies, and how far above the spring's level its feet stay from a
## fifth to four fifths of the way (clear of a wall in the cell it passes).
const BOUNCE_DIP: float = 0.22
const BOUNCE_DIP_TIME: float = 0.08
const BOUNCE_TIME: float = 0.55
const BOUNCE_CLEAR: float = 1.05
## Side-to-side wobble while sliding (radians) and its rate.
const SLIDE_WOBBLE: float = 0.08
const SLIDE_WOBBLE_RATE: float = 11.0
const TURN_RATE: float = 16.0
const BOB_HEIGHT: float = 0.04
const LEAN: float = 0.13
const SWAY: float = 0.07
const LEG_SWING: float = 0.65
const BREATH: float = 0.03
const BREATH_PERIOD: float = 2.0
const DOOR_OPEN: float = -1.3
## The sphere a tap has to hit to count as a tap on the courier.
const TAP_HEIGHT: float = 0.3
const TAP_RADIUS: float = 0.38
## Emotes, played in turn on each tap, and the sparkle tint of each.
const EMOTES: Array[StringName] = [&"wave", &"hop", &"chatter", &"wiggle"]
const EMOTE_TINTS: Array[Color] = [Color("#F3C623"), Color("#F27D6B"), Color("#6FA8DC"), Color("#B48ED8")]
## How long it keeps looking at the camera after an emote.
const EMOTE_LOOK_TIME: float = 1.4

var pathfinder: Pathfinder
## The cell the courier stands in (or last finished stepping into).
var cell: Vector3i

var _rig: CourierBuilder.Rig
var _queue: Array[Vector3i] = []
var _stepping: bool = false
## The current step is a belt carrying it, not a walk.
var _riding: bool = false
## The current step is a slide over ice (onto it, along it or off it).
var _sliding: bool = false
## The current step is a bounce off a spring.
var _bouncing: bool = false
var _slide_blend: float = 0.0
## The heading of the last step (to tell a slide carrying on from a turn).
var _heading: Vector3i
var _step_target: Vector3i
var _step_tween: Tween
var _facing_yaw: float = PI
var _phase: float = 0.0
var _walk_blend: float = 0.0
var _time: float = 0.0
var _blink_in: float = 2.5
var _happy_tween: Tween
var _tilt_tween: Tween
var _emote_tween: Tween
var _next_emote: int = 0
var _carrying: bool = false
## Offsets driven by tweens and combined each frame in _process.
var _squash := Vector3.ONE
var _tilt: float = 0.0
var _hop: float = 0.0
var _spin: float = 0.0


func _ready() -> void:
	_rig = CourierBuilder.build(self)
	rotation.y = _facing_yaw
	_next_emote = randi() % EMOTES.size()


## Puts the courier on [param at], facing [param facing] (a horizontal
## direction), dropping any walk at once (the step in progress too).
func place(at: Vector3i, facing: Vector3i = Vector3i(0, 0, 1)) -> void:
	_queue.clear()
	if _step_tween:
		_step_tween.kill()
	_stepping = false
	_riding = false
	_sliding = false
	_bouncing = false
	_heading = Vector3i.ZERO
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


## How far along the ray from [param origin] in [param direction] (a unit
## vector) it meets the courier, or -1 when it misses.
func ray_distance(origin: Vector3, direction: Vector3) -> float:
	var to_centre: Vector3 = global_position + Vector3.UP * TAP_HEIGHT - origin
	var along: float = to_centre.dot(direction)
	if along < 0.0 or to_centre.length_squared() - along * along > TAP_RADIUS * TAP_RADIUS:
		return -1.0
	return along


## Plays the next emote, turned towards [param look_at] (the camera) for a
## moment: a wave of the flag, a happy hop, a chattering door or a wiggle,
## each with a puff of sparkles. Returns the emote's name.
func emote(look_at: Vector3) -> StringName:
	var index: int = _next_emote
	_next_emote = (_next_emote + 1) % EMOTES.size()
	if _emote_tween:
		_emote_tween.kill()
	var heading: float = _facing_yaw
	_face(look_at - global_position)
	_emote_tween = create_tween()
	match EMOTES[index]:
		&"wave":
			var flag: Node3D = _rig.flag_pivot
			_emote_tween.tween_property(flag, "rotation:x", -0.35, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			for i in 3:
				_emote_tween.tween_property(flag, "rotation:x", 0.35, 0.12).set_trans(Tween.TRANS_SINE)
				_emote_tween.tween_property(flag, "rotation:x", -0.35, 0.12).set_trans(Tween.TRANS_SINE)
			_emote_tween.tween_callback(func() -> void:
				create_tween().tween_property(flag, "rotation:x", 0.0 if _carrying else CourierBuilder.FLAG_LOWERED, 0.25))
		&"hop":
			celebrate()
			# The celebration has its own tween; this one just spans it.
			_emote_tween.tween_interval(1.0)
		&"chatter":
			_set_happy_eyes(true)
			for i in 3:
				_emote_tween.tween_property(_rig.door_hinge, "rotation:x", DOOR_OPEN * 0.6, 0.09)
				_emote_tween.tween_property(_rig.door_hinge, "rotation:x", 0.0, 0.11)
			_emote_tween.tween_interval(0.3)
			_emote_tween.tween_callback(_set_happy_eyes.bind(false))
		&"wiggle":
			for side: float in [0.22, -0.22, 0.22, -0.22]:
				_emote_tween.tween_property(self, "_tilt", side, 0.12).set_trans(Tween.TRANS_SINE)
				_emote_tween.parallel().tween_property(self, "_hop", 0.06 if side > 0.0 else 0.0, 0.12)
			_emote_tween.tween_property(self, "_tilt", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
			_emote_tween.parallel().tween_property(self, "_hop", 0.0, 0.14)
	var sparkles: CPUParticles3D = Effects.sparkles(EMOTE_TINTS[index])
	sparkles.amount = 14
	sparkles.position = Vector3.UP * 0.6
	add_child(sparkles)
	sparkles.restart()
	# Tweens rather than timers, so nothing fires once the courier is gone.
	var after: Tween = create_tween()
	after.tween_interval(EMOTE_LOOK_TIME)
	# Look back the way it was going unless it has set off since.
	after.tween_callback(func() -> void:
		if not _stepping:
			_facing_yaw = heading)
	after.tween_interval(0.4)
	after.tween_callback(sparkles.queue_free)
	return EMOTES[index]


## Drops the rest of the current path; the step in progress still finishes.
func stop() -> void:
	_queue.clear()


## Ends a celebration or a puzzled tilt at once and lands with a little
## squash (after undo or restart puts it somewhere new).
func reset_pose() -> void:
	for tween: Tween in [_happy_tween, _tilt_tween, _emote_tween]:
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
	_carrying = carrying
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
		# A bounce has landed already (see _finish_step).
		if not _bouncing:
			_land(0.5)
		_stepping = false
		_riding = false
		_sliding = false
		_bouncing = false
		_heading = Vector3i.ZERO
		arrived.emit(cell)
		return
	var next: Vector3i = _queue.pop_front()
	_stepping = true
	_riding = pathfinder.is_belt(cell)
	var heading: Vector3i = Pathfinder.heading(cell, next)
	_bouncing = Pathfinder.is_bounce(cell, next)
	_sliding = not _riding and not _bouncing \
			and (pathfinder.is_ice(next) or (pathfinder.is_ice(cell) and heading == _heading))
	_heading = heading
	_step_target = next
	var from: Vector3 = position
	var to: Vector3 = pathfinder.floor_position(next)
	if not _riding:
		_face(to - from)
	_step_tween = create_tween()
	if _bouncing:
		_bounce(from, to)
	else:
		_step_tween.tween_property(self, "position", to, RIDE_TIME if _riding else SLIDE_TIME if _sliding else STEP_TIME)
	_step_tween.tween_callback(_finish_step.bind(next, to.y - from.y))


## Sinks into the spring, then flies from [param from] to [param to] in an
## arc, stretched out and grinning (on the step's tween).
func _bounce(from: Vector3, to: Vector3) -> void:
	var low: Vector3 = from + Vector3.DOWN * BOUNCE_DIP
	# High enough that its feet stay BOUNCE_CLEAR above the spring's level
	# from a fifth to four fifths of the way, where 4t(1 - t) is 0.64.
	var lowest: float = minf(lerpf(low.y, to.y, 0.2), lerpf(low.y, to.y, 0.8))
	var lift: float = (from.y + BOUNCE_CLEAR - lowest) / 0.64
	_step_tween.tween_property(self, "position", low, BOUNCE_DIP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_step_tween.parallel().tween_property(self, "_squash", Vector3(1.18, 0.74, 1.18), BOUNCE_DIP_TIME)
	_step_tween.tween_callback(_set_happy_eyes.bind(true))
	_step_tween.tween_method(_fly.bind(low, to, lift), 0.0, 1.0, BOUNCE_TIME)
	_step_tween.parallel().tween_property(self, "_squash", Vector3(0.88, 1.16, 0.88), 0.12)
	_step_tween.parallel().tween_property(self, "_squash", Vector3.ONE, 0.25).set_delay(0.2)


## Puts the courier [param t] of the way along a bounce from [param from] to
## [param to] that rises [param lift] above the straight line halfway.
func _fly(t: float, from: Vector3, to: Vector3, lift: float) -> void:
	position = from.lerp(to, t) + Vector3.UP * 4.0 * lift * t * (1.0 - t)


func _finish_step(next: Vector3i, rise: float) -> void:
	cell = next
	# A bounce lands for good unless another spring throws it straight on.
	var landing: bool = _bouncing and (_queue.is_empty() or not Pathfinder.is_bounce(cell, _queue[0]))
	if landing:
		_set_happy_eyes(false)
	step_finished.emit(cell)
	if landing:
		_land(1.0)
	# Settle with a little squash when coming off a climb onto flat ground.
	elif absf(rise) > 0.2 and (_queue.is_empty() or is_equal_approx(pathfinder.floor_position(_queue[0]).y, position.y)):
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
	var walking: bool = _stepping and not _riding and not _sliding and not _bouncing
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 7.0)
	_slide_blend = move_toward(_slide_blend, 1.0 if _stepping and _sliding else 0.0, delta * 6.0)
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
	var wobble: float = sin(_time * SLIDE_WOBBLE_RATE) * SLIDE_WOBBLE * _slide_blend
	body.rotation = Vector3(-LEAN * _walk_blend + LEAN * 0.5 * _slide_blend, 0.0, swing * SWAY + _tilt + wobble)
	body.scale = Vector3(1.0 - breath * 0.5, 1.0 + breath, 1.0 - breath * 0.5) * _squash

	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.5, 5.5)
		for eye: Node3D in _rig.eyes:
			var blink: Tween = create_tween()
			blink.tween_property(eye, "scale:y", 0.12, 0.06)
			blink.tween_property(eye, "scale:y", 1.0, 0.08)
