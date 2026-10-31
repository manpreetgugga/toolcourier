class_name Weather
extends RefCounted
## Gentle weather over a diorama, built from code: autumn leaves tumbling
## down, or winter snow drifting. Summer has none.

## Particles per square metre of sky over the diorama.
const LEAF_DENSITY: float = 0.5
const SNOW_DENSITY: float = 2.2
## How far past the diorama's edges it falls.
const MARGIN: float = 1.5


## Leaves or snow falling over [param bounds] for [param season] (see
## [method Palette.season]), or null for none.
static func create(season: StringName, bounds: AABB) -> CPUParticles3D:
	match season:
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
	return null


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

	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _soft_dot()
	quad.material = material
	fall.mesh = quad
	return fall


## A white disc with a soft edge.
static func _soft_dot() -> GradientTexture2D:
	var edge := Gradient.new()
	edge.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	edge.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var dot := GradientTexture2D.new()
	dot.gradient = edge
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	return dot
