class_name Effects
extends RefCounted
## One-shot particle bursts, built from code. Call restart() on the returned
## emitter to fire it.

## Bright confetti colours, one picked per piece.
const CONFETTI: Array[Color] = [
	Color("#F27D6B"), Color("#F6C445"), Color("#6CC3A0"), Color("#6FA8DC"), Color("#B48ED8"), Color("#FFF4E0"),
]

static var _dot: GradientTexture2D
static var _puff: GradientTexture2D


## Bright sparkles that shoot up and fade to [param tint] (pads filling).
static func sparkles(tint: Color) -> CPUParticles3D:
	var burst := _burst(28, 0.9, 0.09, true, soft_dot())
	burst.name = "Sparkles"
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.25
	burst.direction = Vector3.UP
	burst.spread = 35.0
	burst.initial_velocity_min = 1.2
	burst.initial_velocity_max = 2.2
	burst.gravity = Vector3(0.0, -2.5, 0.0)
	burst.color_ramp = _ramp(Color(1.0, 1.0, 1.0, 1.0), Color(tint, 0.0))
	return burst


## Soft dust puffing out sideways from a box of [param size] (mechanisms
## coming to rest): a few round puffs that swell and thin away.
static func dust(size: Vector3) -> CPUParticles3D:
	var burst := _burst(12, 0.9, 0.26, false, _puff_texture())
	burst.name = "Dust"
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	burst.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.z * 0.5)
	burst.direction = Vector3.UP
	burst.spread = 85.0
	burst.initial_velocity_min = 0.35
	burst.initial_velocity_max = 0.7
	burst.gravity = Vector3(0.0, 0.15, 0.0)
	burst.damping_min = 1.2
	burst.damping_max = 1.8
	burst.angle_min = -180.0
	burst.angle_max = 180.0
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.45))
	swell.add_point(Vector2(1.0, 1.0), 0.6, 0.0)
	burst.scale_amount_curve = swell
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(0.96, 0.92, 0.85, 0.0), Color(0.96, 0.92, 0.85, 0.5), Color(0.96, 0.92, 0.85, 0.0)])
	burst.color_ramp = fade
	return burst


## Paper confetti bursting up and fluttering down (a level finished). Lives
## [member CPUParticles3D.lifetime] seconds.
static func confetti() -> CPUParticles3D:
	var burst := _burst(90, 2.2, 0.18, false)
	burst.name = "Confetti"
	(burst.mesh as QuadMesh).size = Vector2(0.18, 0.11)
	burst.explosiveness = 0.95
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.15
	burst.direction = Vector3.UP
	burst.spread = 38.0
	burst.initial_velocity_min = 3.4
	burst.initial_velocity_max = 5.2
	burst.gravity = Vector3(0.0, -4.0, 0.0)
	burst.damping_min = 1.6
	burst.damping_max = 2.4
	burst.angle_min = -180.0
	burst.angle_max = 180.0
	burst.angular_velocity_min = -420.0
	burst.angular_velocity_max = 420.0
	burst.scale_amount_min = 0.8
	burst.scale_amount_max = 1.2
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in CONFETTI.size():
		offsets.append(float(i) / CONFETTI.size())
	colors.offsets = offsets
	colors.colors = PackedColorArray(CONFETTI)
	burst.color_initial_ramp = colors
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	burst.color_ramp = fade
	return burst


## A white disc with a soft edge (shared by sparkles, snow and motes).
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		_dot = _radial([0.0, 0.6, 1.0], [Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)], 32)
	return _dot


## A cloudy puff, dense in the middle and fading all the way out.
static func _puff_texture() -> GradientTexture2D:
	if _puff == null:
		_puff = _radial([0.0, 0.35, 1.0], [Color.WHITE, Color(1.0, 1.0, 1.0, 0.7), Color(1.0, 1.0, 1.0, 0.0)], 64)
	return _puff


static func _radial(offsets: Array[float], colors: Array[Color], size: int) -> GradientTexture2D:
	var edge := Gradient.new()
	edge.offsets = PackedFloat32Array(offsets)
	edge.colors = PackedColorArray(colors)
	var dot := GradientTexture2D.new()
	dot.gradient = edge
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = size
	dot.height = size
	return dot


static func _burst(amount: int, lifetime: float, size: float, additive: bool, texture: Texture2D = null) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = amount
	burst.lifetime = lifetime
	burst.explosiveness = 0.9
	burst.scale_amount_min = 0.55
	burst.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Billboards drop the particle scale unless told to keep it.
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	burst.mesh = quad
	return burst


static func _ramp(from: Color, to: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, from)
	ramp.set_color(1, to)
	return ramp
