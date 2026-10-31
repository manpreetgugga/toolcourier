class_name ExitFlag
extends Node3D
## The exit: a round mat with a post and pennant at its back corner. The
## pennant hangs limp low on the post while parcels remain, and runs up and
## waves once every pad is filled; the mat glows then too.

const MAT_COLOR := Color("#FFF1DC")
const RING_COLOR := Color("#E9C46A")
const POST_COLOR := Color("#3A3550")
const CLOTH_WIDTH: float = 0.46
const CLOTH_HEIGHT: float = 0.28
const POST_HEIGHT: float = 1.2
const LOWERED: float = 0.4
const RAISED: float = 1.12
const CLOTH_SHADER: Shader = preload("res://shaders/cloth.gdshader")

var open: bool = false

var _cloth_pivot: Node3D
var _cloth_material: ShaderMaterial
var _ring_material: ShaderMaterial


func _ready() -> void:
	var mat := MeshInstance3D.new()
	mat.mesh = _disc(0.36, 0.04)
	mat.material_override = ClayShapes.material(MAT_COLOR)
	mat.position.y = 0.02
	add_child(mat)
	_ring_material = ClayShapes.material(RING_COLOR).duplicate()
	var ring := MeshInstance3D.new()
	ring.mesh = _disc(0.26, 0.05)
	ring.material_override = _ring_material
	ring.position.y = 0.025
	add_child(ring)

	# Post at the back-left corner so the courier can stand on the mat.
	var post_base := Vector3(-0.3, 0.0, -0.3)
	var post := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.028
	pole.bottom_radius = 0.034
	pole.height = POST_HEIGHT
	pole.radial_segments = 10
	pole.rings = 1
	post.mesh = pole
	post.material_override = ClayShapes.material(POST_COLOR)
	post.position = post_base + Vector3(0.0, POST_HEIGHT * 0.5, 0.0)
	add_child(post)
	var knob := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	ball.radial_segments = 12
	ball.rings = 6
	knob.mesh = ball
	knob.material_override = ClayShapes.material(RING_COLOR)
	knob.position = post_base + Vector3(0.0, POST_HEIGHT + 0.02, 0.0)
	add_child(knob)

	_cloth_pivot = Node3D.new()
	_cloth_pivot.position = post_base + Vector3(0.0, LOWERED, 0.0)
	# Let the pennant fly out diagonally across the mat.
	_cloth_pivot.rotation.y = -PI * 0.25
	add_child(_cloth_pivot)
	var cloth := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CLOTH_WIDTH, CLOTH_HEIGHT)
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 8
	plane.subdivide_depth = 2
	cloth.mesh = plane
	_cloth_material = ShaderMaterial.new()
	_cloth_material.shader = CLOTH_SHADER
	_cloth_material.set_shader_parameter(&"albedo", MAT_COLOR)
	_cloth_material.set_shader_parameter(&"width", CLOTH_WIDTH)
	_cloth_material.set_shader_parameter(&"wave", 0.0)
	cloth.material_override = _cloth_material
	cloth.position = Vector3(CLOTH_WIDTH * 0.5 + 0.03, -CLOTH_HEIGHT * 0.5, 0.0)
	_cloth_pivot.add_child(cloth)
	_set_ring_glow(0.0)


## Raises the pennant and lights the mat once the exit can be used.
func set_open(value: bool, animate: bool = true) -> void:
	open = value
	var height: float = RAISED if value else LOWERED
	var wave: float = 1.0 if value else 0.0
	var glow: float = 0.45 if value else 0.0
	if not animate:
		_cloth_pivot.position.y = height
		_cloth_material.set_shader_parameter(&"wave", wave)
		_set_ring_glow(glow)
		return
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(_cloth_pivot, "position:y", height, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(w: float) -> void: _cloth_material.set_shader_parameter(&"wave", w), 1.0 - wave, wave, 0.5)
	tween.tween_method(_set_ring_glow, 0.45 - glow, glow, 0.5)


func _set_ring_glow(value: float) -> void:
	_ring_material.set_shader_parameter(&"glow", value)


static func _disc(radius: float, height: float) -> CylinderMesh:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = height
	disc.radial_segments = 24
	disc.rings = 1
	return disc
