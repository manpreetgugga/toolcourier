class_name BlockMaterials
extends RefCounted
## Shared block materials, one per block type, created on first use.
##
## Every solid type uses the clay block shader with its palette colour; wood,
## the capped types (grass, autumn grass, snow) and ice switch on a
## procedural pattern, and the accent type pulses so interactive parts stand
## out. Water has its own shader.

const BLOCK_SHADER: Shader = preload("res://shaders/block.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/water.gdshader")

const ACCENT: StringName = &"accent"
## Peak emission of the accent pulse.
const ACCENT_PULSE: float = 0.25

enum Pattern { PLAIN, WOOD, GRASS, BELT, ICE }

## Types with a cap on top and another colour down the sides: type -> the
## type whose colour the sides take.
const CAPPED: Dictionary = {&"grass": &"dirt", &"autumn_grass": &"dirt", &"snow": &"slate"}

static var _cache: Dictionary = {}


static func get_material(block_type: StringName) -> ShaderMaterial:
	var mat: ShaderMaterial = _cache.get(block_type)
	if mat == null:
		mat = _create(block_type)
		_cache[block_type] = mat
	return mat


static func _create(block_type: StringName) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if block_type == &"water":
		mat.shader = WATER_SHADER
		var water: Color = Palette.block_color(&"water")
		mat.set_shader_parameter(&"water_color", water)
		mat.set_shader_parameter(&"deep_color", water.darkened(0.45))
		return mat

	mat.shader = BLOCK_SHADER
	match block_type:
		ACCENT:
			mat.set_shader_parameter(&"albedo", Palette.ACCENT)
			mat.set_shader_parameter(&"pulse_strength", ACCENT_PULSE)
		&"wood":
			mat.set_shader_parameter(&"albedo", Palette.block_color(&"wood"))
			mat.set_shader_parameter(&"pattern", Pattern.WOOD)
		&"grass", &"autumn_grass", &"snow":
			mat.set_shader_parameter(&"albedo", Palette.block_color(block_type))
			mat.set_shader_parameter(&"side_color", Palette.block_color(CAPPED[block_type]))
			mat.set_shader_parameter(&"pattern", Pattern.GRASS)
		&"ice", &"glacier":
			mat.set_shader_parameter(&"albedo", Palette.block_color(block_type))
			mat.set_shader_parameter(&"pattern", Pattern.ICE)
			mat.set_shader_parameter(&"roughness", 0.22)
			mat.set_shader_parameter(&"specular", 0.6)
		_:
			mat.set_shader_parameter(&"albedo", Palette.block_color(block_type))
	return mat
