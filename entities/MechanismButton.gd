class_name MechanismButton
extends MechanismNode
## A pressure plate: a dark ring with an accent cap. Stepping on it toggles
## it; while on, the cap sits pressed down and glows.

const UP_HEIGHT: float = 0.08
const DOWN_HEIGHT: float = 0.045
const ON_GLOW: float = 0.6

var _cap: MeshInstance3D
var _cap_material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	position = Vector3(mechanism.cells[0]) + Vector3(0.5, 0.0, 0.5)
	var ring := MeshInstance3D.new()
	ring.mesh = ClayShapes.rounded_box(Vector3(0.66, 0.05, 0.66), 0.025)
	ring.material_override = ClayShapes.material(PropFactory.POST)
	ring.position.y = 0.025
	add_child(ring)
	_cap_material = ClayShapes.accent_material().duplicate()
	_cap = MeshInstance3D.new()
	_cap.mesh = ClayShapes.rounded_box(Vector3(0.46, 0.08, 0.46), 0.035)
	_cap.material_override = _cap_material
	add_child(_cap)
	show_value(value, false)


func show_value(new_value: int, animate: bool = true) -> float:
	value = new_value
	var height: float = DOWN_HEIGHT if new_value == 1 else UP_HEIGHT
	var glow: float = ON_GLOW if new_value == 1 else 0.0
	if _tween:
		_tween.kill()
	if not animate:
		_cap.position.y = height
		_cap_material.set_shader_parameter(&"glow", glow)
		return 0.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_cap, "position:y", height, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(g: float) -> void: _cap_material.set_shader_parameter(&"glow", g),
		ON_GLOW - glow, glow, 0.25)
	return 0.25
