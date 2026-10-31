class_name MechanismConveyor
extends MechanismNode
## A belt: dark blocks with accent chevrons that stream along its direction
## while it runs and ease to a stop when it is switched off.

const BELT_COLOR := Color("#5E5868")
## Chevron speed in cells per second while running.
const SPEED: float = 1.2
const BLOCK_SHADER: Shader = preload("res://shaders/block.gdshader")

var _material: ShaderMaterial
var _belt: MeshInstance3D
var _tween: Tween


func _ready() -> void:
	var cells: Dictionary = {}
	for cell: Vector3i in mechanism.cells:
		cells[cell] = LevelState.CONVEYOR_BLOCK
	_material = ShaderMaterial.new()
	_material.shader = BLOCK_SHADER
	_material.set_shader_parameter(&"albedo", BELT_COLOR)
	_material.set_shader_parameter(&"side_color", Palette.ACCENT)
	_material.set_shader_parameter(&"pattern", BlockMaterials.Pattern.BELT)
	_material.set_shader_parameter(&"belt_dir", Vector2(mechanism.axis.x, mechanism.axis.z))
	_belt = MeshInstance3D.new()
	_belt.name = "Belt"
	_belt.mesh = BlockMesher.build(cells, build_delays)
	_belt.material_override = _material
	add_child(_belt)
	show_value(value, false)


func build_meshes() -> Array[GeometryInstance3D]:
	return [_belt]


func show_value(new_value: int, animate: bool = true) -> float:
	value = new_value
	var speed: float = SPEED if new_value == 1 else 0.0
	if _tween:
		_tween.kill()
	if not animate:
		_material.set_shader_parameter(&"belt_speed", speed)
		return 0.0
	var current: float = _material.get_shader_parameter(&"belt_speed")
	_tween = create_tween()
	_tween.tween_method(func(s: float) -> void: _material.set_shader_parameter(&"belt_speed", s), current, speed, 0.4)
	return 0.4
