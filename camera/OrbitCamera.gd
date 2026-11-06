class_name OrbitCamera
extends Camera3D
## Orbits a diorama. One-finger drag rotates it (yaw free, pitch clamped) with
## inertia, pinch or mouse wheel zooms, moving two fingers together pans the
## view (kept over the diorama), and presses that stay within
## [constant TAP_SLOP_PX] are reported as taps.
##
## Call [method frame_bounds] after building a level. The distance is fitted
## so the diorama fills [member fill_fraction] of the shorter screen axis from
## every yaw at the current pitch (so orbiting never clips it), then divided
## by the zoom.

signal tapped(screen_position: Vector2)
## Emitted (after [signal tapped]) for a second tap close to the previous one.
signal double_tapped(screen_position: Vector2)
## The camera distance moved by more than 2%; drives shadow range and focus.
signal distance_changed(distance: float)
## A grabbed drag (see [member grab_filter]) moved or ended.
signal grab_moved(screen_position: Vector2)
signal grab_released(screen_position: Vector2)

const FOV_DEG: float = 30.0
const TAP_SLOP_PX: float = 12.0
const DOUBLE_TAP_MSEC: int = 300
const DOUBLE_TAP_SLOP_PX: float = 40.0
const PITCH_MIN: float = 15.0
const PITCH_MAX: float = 70.0
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 2.5
const WHEEL_ZOOM_STEP: float = 1.06
## How strongly a pinch zooms: the zoom follows the fingers' spread raised to
## this power, so doubling the spread zooms about 1.5x rather than 2x.
const PINCH_RESPONSE: float = 0.6
## Degrees turned by a drag across the shorter screen axis.
const YAW_PER_SCREEN: float = 270.0
const PITCH_PER_SCREEN: float = 140.0
## How quickly the view catches up with its target (1/s).
const FOLLOW_RATE: float = 14.0
## Decay of the fling velocity after release (1/s).
const INERTIA_DAMPING: float = 4.5
const MAX_FLING_SPEED: float = 540.0
## A finger resting this long before lifting cancels the fling.
const FLING_REST_MSEC: int = 80
const RESET_DURATION: float = 0.6
const FIT_YAW_SAMPLES: int = 16

@export var default_yaw: float = 40.0
@export var default_pitch: float = 32.0
@export_range(0.3, 1.0) var fill_fraction: float = 0.75
## Slow automatic orbit in degrees per second while nobody touches the
## screen (main menu background); 0 turns it off.
@export var idle_orbit_speed: float = 0.0

## Called with the press position when a one-finger drag starts; returning
## true hands the gesture to [signal grab_moved] / [signal grab_released]
## (for dragging a slider) instead of orbiting.
var grab_filter: Callable
## Pinch, wheel and two-finger pan; off, a drag only turns the view.
var zoom_enabled: bool = true

## Current (smoothed) view, in degrees and zoom factor.
var yaw: float
var pitch: float
var zoom: float = 1.0
## Offset of the orbit centre from the middle of the diorama.
var pan := Vector3.ZERO

var _target_yaw: float
var _target_pitch: float
var _target_zoom: float = 1.0
var _target_pan := Vector3.ZERO
## Fling velocity in degrees per second (x = yaw, y = pitch).
var _velocity := Vector2.ZERO
var _bounds := AABB(Vector3.ZERO, Vector3.ONE)
var _reset_tween: Tween

## Active touches: index -> latest position.
var _touches: Dictionary = {}
var _press_position := Vector2.ZERO
## The gesture left the tap slop or used more than one finger.
var _gesture_is_drag: bool = false
## The gesture was handed to the grab signals.
var _grabbing: bool = false
var _gesture_fingers: int = 0
var _last_drag_usec: int = 0
var _pinch_start_distance: float = 1.0
var _pinch_start_zoom: float = 1.0
var _pinch_midpoint := Vector2.ZERO
var _last_tap_msec: int = -100000
var _last_tap_position := Vector2.ZERO

var _fit_pitch: float = -1000.0
var _fit_viewport := Vector2.ZERO
var _fit_distance: float = 10.0
var _reported_distance: float = 0.0


func _init() -> void:
	fov = FOV_DEG
	near = 0.25
	far = 300.0
	yaw = default_yaw
	pitch = default_pitch
	_target_yaw = yaw
	_target_pitch = pitch


## Centres the orbit on [param bounds] and refits the distance. With
## [param reset] the view also jumps back to the default angle and zoom.
func frame_bounds(bounds: AABB, reset: bool = true) -> void:
	_bounds = bounds
	if reset:
		_stop_motion()
		yaw = default_yaw
		pitch = default_pitch
		zoom = 1.0
		pan = Vector3.ZERO
		_target_yaw = yaw
		_target_pitch = pitch
		_target_zoom = zoom
		_target_pan = pan
	_fit_pitch = -1000.0
	_reported_distance = 0.0
	_update_transform()


## Eases back to the default angle and zoom, centred again.
func reset_view() -> void:
	_stop_motion()
	var to_yaw: float = _target_yaw + wrapf(default_yaw - _target_yaw, -180.0, 180.0)
	_reset_tween = create_tween().set_parallel()
	_reset_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_reset_tween.tween_property(self, "_target_yaw", to_yaw, RESET_DURATION)
	_reset_tween.tween_property(self, "_target_pitch", default_pitch, RESET_DURATION)
	_reset_tween.tween_property(self, "_target_zoom", 1.0, RESET_DURATION)
	_reset_tween.tween_property(self, "_target_pan", Vector3.ZERO, RESET_DURATION)


## Current distance from the orbit centre.
func get_distance() -> float:
	return _fitted_distance() / zoom


func _process(delta: float) -> void:
	if _touches.is_empty():
		if not _velocity.is_zero_approx():
			_target_yaw += _velocity.x * delta
			_target_pitch += _velocity.y * delta
			_velocity *= exp(-INERTIA_DAMPING * delta)
			if _velocity.length() < 1.0:
				_velocity = Vector2.ZERO
		elif idle_orbit_speed != 0.0 and not _is_resetting():
			_target_yaw += idle_orbit_speed * delta
	_target_pitch = clampf(_target_pitch, PITCH_MIN, PITCH_MAX)
	if _target_pitch == PITCH_MIN or _target_pitch == PITCH_MAX:
		_velocity.y = 0.0

	# Keep the angles small without a visible jump.
	if absf(_target_yaw) > 720.0:
		var wrap: float = 360.0 * roundf(_target_yaw / 360.0)
		_target_yaw -= wrap
		yaw -= wrap

	var follow: float = 1.0 - exp(-FOLLOW_RATE * delta)
	yaw = lerpf(yaw, _target_yaw, follow)
	pitch = lerpf(pitch, _target_pitch, follow)
	zoom = lerpf(zoom, _target_zoom, follow)
	pan = pan.lerp(_target_pan, follow)
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif not zoom_enabled:
		return
	elif event is InputEventMouseButton and event.pressed:
		var button: MouseButton = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_target_zoom * WHEEL_ZOOM_STEP)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_target_zoom / WHEEL_ZOOM_STEP)
	elif event is InputEventMagnifyGesture:
		_set_zoom(_target_zoom * pow((event as InputEventMagnifyGesture).factor, PINCH_RESPONSE))


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touches.is_empty():
			_stop_motion()
			_press_position = event.position
			_gesture_is_drag = false
			_grabbing = false
			_gesture_fingers = 0
		elif _grabbing:
			# Extra fingers are ignored while dragging a part.
			get_viewport().set_input_as_handled()
			return
		_touches[event.index] = event.position
		_gesture_fingers = maxi(_gesture_fingers, _touches.size())
		if _touches.size() > 1:
			_gesture_is_drag = true
		if _touches.size() == 2:
			_begin_pinch()
	else:
		if not _touches.has(event.index):
			return
		_touches.erase(event.index)
		if _touches.size() == 2:
			_begin_pinch()
		if _touches.is_empty():
			if _grabbing:
				_grabbing = false
				_velocity = Vector2.ZERO
				grab_released.emit(event.position)
			elif not _gesture_is_drag:
				_register_tap(event.position)
			elif _gesture_fingers > 1 or Time.get_ticks_usec() - _last_drag_usec > FLING_REST_MSEC * 1000:
				_velocity = Vector2.ZERO
	get_viewport().set_input_as_handled()


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var previous: Vector2 = _touches[event.index]
	_touches[event.index] = event.position
	get_viewport().set_input_as_handled()
	if _grabbing:
		grab_moved.emit(event.position)
		return
	if _touches.size() >= 2:
		if zoom_enabled:
			_update_pinch()
		return
	if not _gesture_is_drag:
		if event.position.distance_to(_press_position) < TAP_SLOP_PX:
			return
		_gesture_is_drag = true
		if grab_filter.is_valid() and grab_filter.call(_press_position):
			_grabbing = true
			grab_moved.emit(event.position)
			return
		previous = _press_position

	var short_side: float = _short_side()
	var turn := Vector2(
		-(event.position.x - previous.x) / short_side * YAW_PER_SCREEN,
		(event.position.y - previous.y) / short_side * PITCH_PER_SCREEN)
	_target_yaw += turn.x
	_target_pitch = clampf(_target_pitch + turn.y, PITCH_MIN, PITCH_MAX)

	var now: int = Time.get_ticks_usec()
	var dt: float = maxf((now - _last_drag_usec) / 1000000.0, 0.001)
	if now - _last_drag_usec > FLING_REST_MSEC * 1000:
		_velocity = Vector2.ZERO
	_velocity = _velocity.lerp(turn / dt, 0.5).limit_length(MAX_FLING_SPEED)
	_last_drag_usec = now


func _begin_pinch() -> void:
	var points: Array = _touches.values()
	_pinch_start_distance = maxf((points[0] as Vector2).distance_to(points[1]), 1.0)
	_pinch_start_zoom = _target_zoom
	_pinch_midpoint = ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5


func _update_pinch() -> void:
	var points: Array = _touches.values()
	var spread: float = (points[0] as Vector2).distance_to(points[1])
	_set_zoom(_pinch_start_zoom * pow(spread / _pinch_start_distance, PINCH_RESPONSE))
	var midpoint: Vector2 = ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
	_pan_by(midpoint - _pinch_midpoint)
	_pinch_midpoint = midpoint


## Slides the view over the ground so the diorama follows the fingers'
## midpoint by [param screen_delta] pixels, keeping the orbit centre over the
## diorama.
func _pan_by(screen_delta: Vector2) -> void:
	var view: Basis = _orbit_basis(_target_yaw, _target_pitch)
	# World units per pixel at the orbit centre (the FOV spans the short side);
	# the ground is foreshortened along the view by the pitch.
	var scale: float = 2.0 * get_distance() * tan(deg_to_rad(fov) * 0.5) / _short_side()
	var away := Vector3(-view.z.x, 0.0, -view.z.z).normalized()
	var moved: Vector3 = _target_pan - view.x * screen_delta.x * scale 		+ away * screen_delta.y * scale / maxf(sin(deg_to_rad(_target_pitch)), 0.4)
	var half: Vector3 = _bounds.size * 0.5
	_target_pan = Vector3(clampf(moved.x, -half.x, half.x), 0.0, clampf(moved.z, -half.z, half.z))


func _register_tap(at: Vector2) -> void:
	tapped.emit(at)
	var now: int = Time.get_ticks_msec()
	if now - _last_tap_msec <= DOUBLE_TAP_MSEC and at.distance_to(_last_tap_position) <= DOUBLE_TAP_SLOP_PX:
		_last_tap_msec = -100000
		double_tapped.emit(at)
	else:
		_last_tap_msec = now
		_last_tap_position = at


func _set_zoom(value: float) -> void:
	_kill_reset()
	_target_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func _stop_motion() -> void:
	_velocity = Vector2.ZERO
	_kill_reset()


func _kill_reset() -> void:
	if _reset_tween:
		_reset_tween.kill()
		_reset_tween = null


func _is_resetting() -> bool:
	return _reset_tween != null and _reset_tween.is_running()


func _update_transform() -> void:
	var view: Basis = _orbit_basis(yaw, pitch)
	var distance: float = get_distance()
	transform = Transform3D(view, _bounds.get_center() + pan + view.z * distance)
	if absf(distance - _reported_distance) > _reported_distance * 0.02:
		_reported_distance = distance
		distance_changed.emit(distance)


## Distance at zoom 1, cached until the pitch or viewport changes.
func _fitted_distance() -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if absf(pitch - _fit_pitch) > 0.05 or size != _fit_viewport:
		_fit_pitch = pitch
		_fit_viewport = size
		# FOV spans the shorter screen axis so the fit holds in any orientation.
		keep_aspect = KEEP_WIDTH if size.x <= size.y else KEEP_HEIGHT
		_fit_distance = _compute_fit(pitch, size)
	return _fit_distance


## Backs off until every bounds corner fits inside the fill frame, for each
## sampled yaw, and returns the largest distance needed.
func _compute_fit(at_pitch: float, size: Vector2) -> float:
	var portrait: bool = size.x <= size.y
	var aspect: float = maxf(size.x, size.y) / maxf(minf(size.x, size.y), 1.0)
	var tan_short: float = tan(deg_to_rad(fov) * 0.5) * fill_fraction
	var tan_x: float = tan_short if portrait else tan_short * aspect
	var tan_y: float = tan_short * aspect if portrait else tan_short
	var center: Vector3 = _bounds.get_center()
	var needed: float = 0.0
	for sample in FIT_YAW_SAMPLES:
		var view: Basis = _orbit_basis(360.0 * sample / FIT_YAW_SAMPLES, at_pitch)
		for corner in 8:
			var offset: Vector3 = _bounds.get_endpoint(corner) - center
			var lateral: float = maxf(absf(offset.dot(view.x)) / tan_x, absf(offset.dot(view.y)) / tan_y)
			needed = maxf(needed, lateral + offset.dot(view.z))
	return needed


func _short_side() -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return maxf(minf(size.x, size.y), 1.0)


## Camera basis for a yaw/pitch in degrees; z points from the centre to the camera.
static func _orbit_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	var y: float = deg_to_rad(yaw_deg)
	var p: float = deg_to_rad(pitch_deg)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	var right: Vector3 = Vector3.UP.cross(back).normalized()
	return Basis(right, back.cross(right), back)
