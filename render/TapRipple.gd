class_name TapRipple
extends MeshInstance3D
## A ring that ripples across a tapped block face, then frees itself. Valid
## targets get a soft white ring; unreachable ones a red ring with a shake.

const SHADER: Shader = preload("res://shaders/ripple.gdshader")
const DURATION: float = 0.55
const VALID_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const BLOCKED_COLOR := Color("#E4572E")
## Lift off the face so the ring never z-fights with it.
const LIFT: float = 0.015
const SHAKE_DISTANCE: float = 0.06
const SHAKE_TIME: float = 0.05

static var _quad: QuadMesh


## Spawns a ripple centred at [param center] on a face with outward
## [param normal] (an axis direction).
static func spawn(parent: Node3D, center: Vector3, normal: Vector3, reachable: bool = true) -> TapRipple:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var ripple := TapRipple.new()
	ripple.mesh = _quad
	ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"color", VALID_COLOR if reachable else BLOCKED_COLOR)
	ripple.material_override = mat
	# QuadMesh faces +Z; turn it to face along the normal.
	var facing := Basis(Quaternion(Vector3.BACK, normal)) if normal.dot(Vector3.BACK) > -0.5 else Basis(Vector3.UP, PI)
	ripple.transform = Transform3D(facing, center + normal * LIFT)
	parent.add_child(ripple)
	ripple._play(reachable)
	return ripple


func _play(reachable: bool) -> void:
	var tween: Tween = create_tween()
	tween.tween_method(_set_progress, 0.0, 1.0, DURATION)
	tween.tween_callback(queue_free)
	if not reachable:
		var side: Vector3 = basis.x * SHAKE_DISTANCE
		var home: Vector3 = position
		var shake: Tween = create_tween()
		for offset: Vector3 in [side, -side, side * 0.6, -side * 0.6, Vector3.ZERO]:
			shake.tween_property(self, "position", home + offset, SHAKE_TIME)


func _set_progress(value: float) -> void:
	(material_override as ShaderMaterial).set_shader_parameter(&"progress", value)
