class_name BlockMaterials
extends RefCounted
## Shared block materials, one per block type, created on first use.
##
## Every solid type uses the clay block shader with its palette colour; wood
## and grass switch on a procedural pattern, and the accent type pulses so
## interactive parts stand out. Water has its own shader.

const BLOCK_SHADER: Shader = preload("res://shaders/block.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/water.gdshader")

const ACCENT: StringName = &"accent"
## Peak emission of the accent pulse.
const ACCENT_PULSE: float = 0.25

enum Pattern { PLAIN, WOOD, GRASS }

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
		&"grass":
			mat.set_shader_parameter(&"albedo", Palette.block_color(&"grass"))
			mat.set_shader_parameter(&"side_color", Palette.block_color(&"dirt"))
			mat.set_shader_parameter(&"pattern", Pattern.GRASS)
		_:
			mat.set_shader_parameter(&"albedo", Palette.block_color(block_type))
	return mat
