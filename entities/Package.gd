class_name Package
extends Node3D
## A parcel. Waits on the floor bobbing gently, flies into the courier's door
## when picked up, and pops out onto its pad when delivered.

const HOVER: float = 0.04
const BOB_HEIGHT: float = 0.025
const BOB_PERIOD: float = 1.8
const FLY_TIME: float = 0.38
const DROP_TIME: float = 0.42

var color: StringName

var _visual: MeshInstance3D
var _blob: MeshInstance3D
var _bobbing: bool = true
var _time: float = 0.0


static func create(parcel_color: StringName) -> Package:
	var package := Package.new()
	package.name = "Package"
	package.color = parcel_color
	return package


func _ready() -> void:
	_visual = MeshInstance3D.new()
	_visual.mesh = PropFactory.parcel(color)
	add_child(_visual)
	_blob = PropFactory.blob_shadow(0.5)
	add_child(_blob)
	_time = randf() * BOB_PERIOD


func _process(delta: float) -> void:
	if _bobbing:
		_time += delta
		_visual.position.y = HOVER + sin(_time * TAU / BOB_PERIOD) * BOB_HEIGHT


## Flies along an arc into the point [param target] returns (read every
## frame, so it can chase a walking courier), shrinking, then hides.
func fly_into(target: Callable) -> void:
	_bobbing = false
	_blob.visible = false
	var tween: Tween = create_tween()
	tween.tween_method(_fly_step.bind(global_position, target), 0.0, 1.0, FLY_TIME)
	tween.tween_callback(hide)


## Pops out at [param from] and lands on [param to] with a bounce, ending at
## [param size] times its normal size.
func drop_onto(from: Vector3, to: Vector3, size: float = 1.0) -> void:
	show()
	_bobbing = false
	_visual.position.y = 0.0
	global_position = from
	scale = Vector3.ONE * 0.25
	var tween: Tween = create_tween()
	tween.tween_method(_drop_step.bind(from, to, size), 0.0, 1.0, DROP_TIME)
	tween.tween_property(self, "scale", Vector3(1.15, 0.8, 1.15) * size, 0.07)
	tween.tween_property(self, "scale", Vector3.ONE * size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _blob.visible = true)


## Glides along the floor to [param target] (pushed by a belt); returns how
## long it takes.
func slide_to(target: Vector3) -> float:
	var duration: float = 0.1 + 0.25 * position.distance_to(target)
	create_tween().tween_property(self, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return duration


func _fly_step(t: float, from: Vector3, target: Callable) -> void:
	var to: Vector3 = target.call()
	global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.45
	scale = Vector3.ONE * lerpf(1.0, 0.2, t * t)


func _drop_step(t: float, from: Vector3, to: Vector3, size: float) -> void:
	global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.35
	scale = Vector3.ONE * lerpf(0.25, size, 1.0 - (1.0 - t) * (1.0 - t))
