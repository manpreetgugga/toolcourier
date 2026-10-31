class_name Pad
extends Node3D
## A delivery pad: a cream frame around a tile in a parcel colour. Pulses
## softly while it waits and lights up with a burst of sparkles when its
## parcel arrives.

const FRAME_COLOR := Color("#FFF1DC")
## Peak glow of the waiting pulse, and the glow once filled.
const WAIT_GLOW: float = 0.14
const FILLED_GLOW: float = 0.35
const PULSE_PERIOD: float = 1.8
## Height of the pad's top surface above the floor.
const TOP: float = 0.06
## Where a delivered parcel rests (a back corner, clear of the courier) and
## how big it is there.
const PARCEL_SPOT := Vector3(0.24, TOP, -0.24)
const PARCEL_SIZE: float = 0.75

var color: StringName
var filled: bool = false

var _tile_material: ShaderMaterial
var _sparkles: CPUParticles3D
var _time: float = 0.0
var _glow_tween: Tween


static func create(pad_color: StringName) -> Pad:
	var pad := Pad.new()
	pad.name = "Pad"
	pad.color = pad_color
	return pad


func _ready() -> void:
	var frame := MeshInstance3D.new()
	frame.mesh = ClayShapes.rounded_box(Vector3(0.84, 0.05, 0.84), 0.025)
	frame.material_override = ClayShapes.material(FRAME_COLOR)
	frame.position.y = 0.025
	add_child(frame)

	# The tile gets its own material so its glow is independent of other pads.
	_tile_material = ClayShapes.material(Palette.PACKAGE[color]).duplicate()
	var tile := MeshInstance3D.new()
	tile.mesh = ClayShapes.rounded_box(Vector3(0.62, 0.06, 0.62), 0.03)
	tile.material_override = _tile_material
	tile.position.y = 0.03
	add_child(tile)

	_sparkles = _make_sparkles(Palette.PACKAGE[color])
	_sparkles.position.y = 0.15
	add_child(_sparkles)


func _process(delta: float) -> void:
	if not filled:
		_time += delta
		_set_glow(WAIT_GLOW * (0.5 - 0.5 * cos(_time * TAU / PULSE_PERIOD)))


## Marks the pad filled; with [param animate] it flares up and sparkles.
func set_filled(value: bool, animate: bool = true) -> void:
	filled = value
	if _glow_tween:
		_glow_tween.kill()
	if not value:
		_set_glow(0.0)
		return
	if not animate:
		_set_glow(FILLED_GLOW)
		return
	_sparkles.restart()
	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow, 0.0, 1.0, 0.12)
	_glow_tween.tween_method(_set_glow, 1.0, FILLED_GLOW, 0.6).set_trans(Tween.TRANS_SINE)


func _set_glow(value: float) -> void:
	_tile_material.set_shader_parameter(&"glow", value)


static func _make_sparkles(tint: Color) -> CPUParticles3D:
	var sparkles := CPUParticles3D.new()
	sparkles.name = "Sparkles"
	sparkles.emitting = false
	sparkles.one_shot = true
	sparkles.amount = 28
	sparkles.lifetime = 0.9
	sparkles.explosiveness = 0.9
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 0.25
	sparkles.direction = Vector3.UP
	sparkles.spread = 35.0
	sparkles.initial_velocity_min = 1.2
	sparkles.initial_velocity_max = 2.2
	sparkles.gravity = Vector3(0.0, -2.5, 0.0)
	sparkles.scale_amount_min = 0.55
	sparkles.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(tint, 0.0))
	sparkles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Billboards drop the particle scale unless told to keep it.
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	sparkles.mesh = quad
	return sparkles
