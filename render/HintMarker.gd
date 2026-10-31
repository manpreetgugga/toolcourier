class_name HintMarker
extends Node3D
## Shows a hint in the diorama: a glowing arrow bobbing over the spot to tap
## or the part to work, an optional trail of dots along the way there, and
## an optional see-through ghost of a part where it should go. Pops in with
## the dots appearing in order; [method dismiss] shrinks it away.

const COLOR := Color("#FFC93C")
const BOB_HEIGHT: float = 0.1
const BOB_PERIOD: float = 0.9
const DOT_RADIUS: float = 0.07
## Seconds between dots popping in.
const DOT_STAGGER: float = 0.05

var _arrow: Node3D
var _arrow_home := Vector3.ZERO
var _material: ShaderMaterial
var _time: float = 0.0
var _dismissed: bool = false


## A marker with its arrow over [param point] (a world position the arrow
## tip points down at, from high enough to clear a parcel there).
static func pointing_at(point: Vector3) -> HintMarker:
	var marker := HintMarker.new()
	marker.name = "Hint"
	marker._arrow_home = point + Vector3(0.0, 0.55, 0.0)
	return marker


## Adds dots at [param points] (floor positions, in order).
func add_trail(points: Array[Vector3]) -> void:
	for i in points.size():
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = DOT_RADIUS
		sphere.height = DOT_RADIUS * 1.6
		sphere.radial_segments = 12
		sphere.rings = 6
		dot.mesh = sphere
		dot.material_override = _glow_material()
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.position = points[i] + Vector3(0.0, 0.05, 0.0)
		dot.scale = Vector3.ZERO
		add_child(dot)
		var tween: Tween = dot.create_tween()
		tween.tween_interval(DOT_STAGGER * i)
		tween.tween_property(dot, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Adds a see-through copy of [param mesh] placed by [param where].
func add_ghost(mesh: Mesh, where: Transform3D) -> void:
	var ghost := MeshInstance3D.new()
	ghost.name = "Ghost"
	ghost.mesh = mesh
	ghost.transform = where
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR, 0.38)
	ghost.material_override = material
	add_child(ghost)


## Shrinks away and frees itself.
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.0, 1.0), 0.15)
	tween.tween_callback(queue_free)


func _ready() -> void:
	_arrow = Node3D.new()
	_arrow.name = "Arrow"
	add_child(_arrow)
	var cone := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.22
	shape.bottom_radius = 0.0
	shape.height = 0.36
	shape.radial_segments = 16
	shape.rings = 1
	cone.mesh = shape
	cone.material_override = _glow_material()
	cone.position.y = 0.18
	_arrow.add_child(cone)
	var cap := MeshInstance3D.new()
	cap.mesh = ClayShapes.rounded_box(Vector3(0.16, 0.26, 0.16), 0.06)
	cap.material_override = _glow_material()
	cap.position.y = 0.48
	_arrow.add_child(cap)
	_arrow.position = _arrow_home
	_arrow.scale = Vector3.ZERO
	_arrow.create_tween().tween_property(_arrow, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	var wave: float = 0.5 + 0.5 * sin(_time * TAU / BOB_PERIOD)
	_arrow.position = _arrow_home + Vector3(0.0, BOB_HEIGHT * wave, 0.0)
	_arrow.rotation.y = _time * 1.4
	_glow_material().set_shader_parameter(&"glow", 0.5 + 0.35 * wave)


## One clay material for every part of this marker, so they pulse together.
func _glow_material() -> ShaderMaterial:
	if _material == null:
		_material = ClayShapes.material(COLOR).duplicate()
	return _material
