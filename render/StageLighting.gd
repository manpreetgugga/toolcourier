class_name StageLighting
extends Node3D
## Owns the WorldEnvironment, gradient sky and key light for a diorama scene.
##
## Warm key light + cool ambient fill, filmic-style tonemapping, glow reserved
## for emissive accents. Uses only features supported by the Mobile renderer
## (no SSAO/SSIL/SDFGI/SSR). Call [method fit_to_bounds] after building a level
## so shadow distance and tilt-shift focus hug the diorama.

const SKY_SHADER: Shader = preload("res://shaders/sky_gradient.gdshader")

const SUN_ROTATION_DEG: Vector3 = Vector3(-50.0, -35.0, 0.0)
const TILT_SHIFT_AMOUNT: float = 0.045

@export var theme_name: StringName = Palette.DEFAULT_THEME
@export var tilt_shift_enabled: bool = true

var environment: Environment
var sun: DirectionalLight3D
## Assign to the active Camera3D's `attributes` so tilt-shift DOF applies.
var camera_attributes: CameraAttributesPractical

var _world_environment: WorldEnvironment
var _sky_material: ShaderMaterial


func _ready() -> void:
	_build()
	apply_theme(theme_name)


func apply_theme(new_theme: StringName) -> void:
	theme_name = new_theme
	var t: Dictionary = Palette.theme(new_theme)
	_sky_material.set_shader_parameter(&"top_color", t["sky_top"])
	_sky_material.set_shader_parameter(&"horizon_color", t["sky_horizon"])
	_sky_material.set_shader_parameter(&"ground_color", t["sky_ground"])
	_sky_material.set_shader_parameter(&"cloud_amount", t["clouds"])
	_sky_material.set_shader_parameter(&"cloud_color", t["cloud_color"])
	# Soft penumbrae suit the clay look.
	sun.shadow_blur = t["shadow_blur"]
	# Block and water shaders tint their rim/fresnel with the sky.
	var sky: Color = (t["sky_top"] as Color).srgb_to_linear()
	RenderingServer.global_shader_parameter_set(&"sky_tint", Vector3(sky.r, sky.g, sky.b))
	environment.ambient_light_color = t["ambient_color"]
	environment.ambient_light_energy = t["ambient_energy"]
	sun.light_color = t["sun_color"]
	sun.light_energy = t["sun_energy"]


## Tunes shadow range and depth of field to a diorama of the given bounds,
## viewed from [param camera_distance] metres away.
func fit_to_bounds(bounds: AABB, camera_distance: float) -> void:
	var radius: float = bounds.size.length() * 0.5
	# Everything visible sits within camera_distance +- radius; keep the
	# shadow frustum just past the far edge so texel density stays high.
	sun.directional_shadow_max_distance = camera_distance + radius * 1.2
	sun.directional_shadow_split_1 = clampf((camera_distance - radius * 0.2) / sun.directional_shadow_max_distance, 0.2, 0.8)
	sun.directional_shadow_pancake_size = maxf(radius * 4.0, 10.0)
	set_tilt_shift(tilt_shift_enabled, camera_distance, radius)


func set_tilt_shift(enabled: bool, focus_distance: float, radius: float) -> void:
	tilt_shift_enabled = enabled
	camera_attributes.dof_blur_far_enabled = enabled
	camera_attributes.dof_blur_near_enabled = enabled
	camera_attributes.dof_blur_amount = TILT_SHIFT_AMOUNT
	# Keep the front of the diorama sharp and let only its far side soften.
	# Far blur ramps up after far_distance; near blur ramps up *towards the
	# camera* and is full at near_distance, so that ramp ends before the
	# diorama's nearest point.
	camera_attributes.dof_blur_far_distance = focus_distance + radius * 0.6
	camera_attributes.dof_blur_far_transition = radius * 1.5
	camera_attributes.dof_blur_near_transition = radius * 0.8
	camera_attributes.dof_blur_near_distance = maxf(focus_distance - radius * 1.8, 0.1)


func _build() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER

	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.tonemap_agx_white = 6.0
	environment.tonemap_agx_contrast = 1.1

	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0

	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.05

	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	_world_environment.environment = environment
	add_child(_world_environment)

	camera_attributes = CameraAttributesPractical.new()
	_world_environment.camera_attributes = camera_attributes

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	# Unit cubes: a small constant bias plus moderate normal bias removes acne
	# on flat tops without detaching contact shadows (peter-panning).
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
