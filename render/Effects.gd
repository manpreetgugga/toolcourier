class_name Effects
extends RefCounted
## One-shot particle bursts, built from code. Call restart() on the returned
## emitter to fire it.


## Bright sparkles that shoot up and fade to [param tint] (pads filling).
static func sparkles(tint: Color) -> CPUParticles3D:
	var burst := _burst(28, 0.9, 0.075, true)
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
## coming to rest).
static func dust(size: Vector3) -> CPUParticles3D:
	var burst := _burst(18, 0.7, 0.11, false)
	burst.name = "Dust"
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	burst.emission_box_extents = size * 0.5
	burst.direction = Vector3.UP
	burst.spread = 80.0
	burst.initial_velocity_min = 0.3
	burst.initial_velocity_max = 0.8
	burst.gravity = Vector3(0.0, -0.4, 0.0)
	burst.damping_min = 1.0
	burst.damping_max = 2.0
	burst.color_ramp = _ramp(Color(0.95, 0.9, 0.82, 0.7), Color(0.95, 0.9, 0.82, 0.0))
	return burst


static func _burst(amount: int, lifetime: float, size: float, additive: bool) -> CPUParticles3D:
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
