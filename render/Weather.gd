class_name Weather
extends RefCounted
## Gentle weather over a diorama, built from code: spring petals or autumn
## leaves tumbling down, winter snow drifting, in summer a few motes of dust
## hanging in the light, or dandelion seeds floating by on the breeze.

## Particles per square metre of sky over the diorama.
const LEAF_DENSITY: float = 0.5
const PETAL_DENSITY: float = 0.4
const SNOW_DENSITY: float = 2.2
## Motes per cubic metre of air around the diorama, and seeds per square
## metre of ground.
const MOTE_DENSITY: float = 0.05
const SEED_DENSITY: float = 0.12
## How far past the diorama's edges it falls.
const MARGIN: float = 1.5


## Petals, leaves, snow, motes or seeds over [param bounds] for
## [param weather] (see [method Palette.weather]).
static func create(weather: StringName, bounds: AABB) -> CPUParticles3D:
	match weather:
		&"spring":
			var petals: CPUParticles3D = _fall(bounds, PETAL_DENSITY, Vector2(0.11, 0.08), 0.3, 0.5)
			petals.name = "Petals"
			var colors := Gradient.new()
			colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			colors.offsets = PackedFloat32Array([0.0, 0.34, 0.67])
			colors.colors = PackedColorArray(PropFactory.BLOSSOMS)
			petals.color_initial_ramp = colors
			# Fluttering as they go.
			petals.angle_min = -180.0
			petals.angle_max = 180.0
			petals.angular_velocity_min = -120.0
			petals.angular_velocity_max = 120.0
			return petals
		&"autumn":
			var leaves: CPUParticles3D = _fall(bounds, LEAF_DENSITY, Vector2(0.17, 0.1), 0.45, 0.7)
			leaves.name = "Leaves"
			var colors := Gradient.new()
			colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			colors.offsets = PackedFloat32Array([0.0, 0.34, 0.67])
			colors.colors = PackedColorArray(PropFactory.AUTUMN_LEAVES)
			leaves.color_initial_ramp = colors
			# Tumbling as they go.
			leaves.angle_min = -180.0
			leaves.angle_max = 180.0
			leaves.angular_velocity_min = -160.0
			leaves.angular_velocity_max = 160.0
			return leaves
		&"winter":
			var snow: CPUParticles3D = _fall(bounds, SNOW_DENSITY, Vector2(0.1, 0.1), 0.35, 0.6)
			snow.name = "Snow"
			snow.color = Color("#F7FAFF")
			return snow
		&"seeds":
			return _seeds(bounds)
	return _motes(bounds)


## Dandelion seeds drifting across on a warm breeze, slowly turning.
static func _seeds(bounds: AABB) -> CPUParticles3D:
	var box: Vector3 = bounds.size + Vector3(MARGIN, 1.0, MARGIN) * 2.0
	var seeds := CPUParticles3D.new()
	seeds.name = "Seeds"
	seeds.amount = clampi(roundi(box.x * box.z * SEED_DENSITY), 8, 28)
	seeds.lifetime = 14.0
	seeds.preprocess = seeds.lifetime
	seeds.position = bounds.get_center() + Vector3(0.0, 0.75, 0.0)
	seeds.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	seeds.emission_box_extents = box * 0.5
	seeds.direction = Vector3(1.0, 0.15, 0.35)
	seeds.spread = 25.0
	# Lifting a little on the warm air.
	seeds.gravity = Vector3(0.0, 0.012, 0.0)
	seeds.initial_velocity_min = 0.1
	seeds.initial_velocity_max = 0.22
	seeds.angle_min = -180.0
	seeds.angle_max = 180.0
	seeds.angular_velocity_min = -25.0
	seeds.angular_velocity_max = 25.0
	seeds.scale_amount_min = 0.7
	seeds.scale_amount_max = 1.0
	seeds.color = Color(1.0, 0.99, 0.94, 0.9)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	seeds.color_ramp = fade
	var quad: QuadMesh = _dot_quad(Vector2(0.15, 0.15))
	(quad.material as StandardMaterial3D).albedo_texture = Effects.seed_texture()
	seeds.mesh = quad
	return seeds


## Sparse, slow specks of warm light drifting about in the air.
static func _motes(bounds: AABB) -> CPUParticles3D:
	var box: Vector3 = bounds.size + Vector3(MARGIN, 1.5, MARGIN) * 2.0
	var motes := CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = clampi(roundi(box.x * box.y * box.z * MOTE_DENSITY), 10, 40)
	motes.lifetime = 9.0
	motes.preprocess = motes.lifetime
	motes.position = bounds.get_center() + Vector3(0.0, 0.75, 0.0)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = box * 0.5
	motes.direction = Vector3(0.2, 1.0, 0.1)
	motes.spread = 180.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.03
	motes.initial_velocity_max = 0.09
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.0
	motes.color = Color(1.0, 0.96, 0.84, 0.5)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	motes.color_ramp = fade
	motes.mesh = _dot_quad(Vector2(0.06, 0.06))
	return motes


## Soft-edged flakes of [param size] falling from above [param bounds] at
## [param speed_min] to [param speed_max] metres per second, slanting with a
## light breeze. Already falling when it appears.
static func _fall(bounds: AABB, density: float, size: Vector2, speed_min: float, speed_max: float) -> CPUParticles3D:
	var area := Vector2(bounds.size.x, bounds.size.z) + Vector2.ONE * MARGIN * 2.0
	var top: float = bounds.end.y + 2.5
	var fall := CPUParticles3D.new()
	fall.amount = maxi(12, roundi(area.x * area.y * density))
	fall.lifetime = (top - bounds.position.y + 1.0) / (speed_min * 0.9)
	fall.preprocess = fall.lifetime
	fall.position = Vector3(bounds.get_center().x, top, bounds.get_center().z)
	fall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fall.emission_box_extents = Vector3(area.x * 0.5, 0.2, area.y * 0.5)
	fall.direction = Vector3(0.3, -1.0, 0.15)
	fall.spread = 14.0
	fall.gravity = Vector3.ZERO
	fall.initial_velocity_min = speed_min
	fall.initial_velocity_max = speed_max
	fall.scale_amount_min = 0.6
	fall.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.06, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	fall.color_ramp = fade
	fall.mesh = _dot_quad(size)
	return fall


## A billboard of [param size] showing a soft white dot, tinted per particle.
static func _dot_quad(size: Vector2) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = Effects.soft_dot()
	quad.material = material
	return quad
