// Tiny Courier block surface: soft clay.
//
// BlockMesher merges and rounds the blocks so a level reads as one sculpted
// lump, and bakes a shade (ambient occlusion, top/bottom tint, per-block
// jitter) into vertex colour at half scale, with per-type data in its alpha
// (the open-top flag for grass). UV is face-planar world position. On top of
// the shared clay lighting: hand-pressed colour mottling, shallow thumb
// dents, wood planks, a grass cap and the accent pulse.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/clay_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.725, 0.706, 0.667, 1.0);
// 0 = plain, 1 = wood planks, 2 = grass top over side_color,
// 3 = conveyor belt with side_color chevrons.
uniform int pattern : hint_range(0, 3) = 0;
uniform vec4 side_color : source_color = vec4(0.647, 0.490, 0.353, 1.0);
// Belt direction (world x, z) and chevron speed in cells per second.
uniform vec2 belt_dir = vec2(1.0, 0.0);
uniform float belt_speed = 0.0;
// Peak emission of the interactive-part pulse (0 = no pulse).
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_period = 1.6;
// Depth of the thumb dents in metres.
uniform float dent_depth = 0.02;

varying vec3 world_pos;
varying vec3 world_normal;

// Three planks per block running along uv.x, with thin dark seams.
vec3 wood(vec3 base, vec2 uv) {
	float v = uv.y * 3.0;
	float row = floor(v);
	float seam_dist = abs(fract(v + 0.5) - 0.5);
	float seam = 1.0 - smoothstep(0.035, 0.035 + fwidth(v) * 1.5, seam_dist);
	float tone = hash(vec2(row, floor(uv.x * 0.5 + row * 0.37)));
	float grain = sin(uv.x * 23.0 + sin(uv.x * 3.1 + row * 5.0) * 2.0 + row * 7.0);
	vec3 col = base * (0.94 + 0.1 * tone) * (1.0 - 0.025 * grain);
	return col * (1.0 - 0.3 * seam);
}

// Grass on top faces with a wavy lip hanging over the dirt sides of blocks
// whose top is open.
vec3 grass(vec3 top, vec3 side, float top_open) {
	float height = fract(world_pos.y - 0.002);
	vec2 p = world_pos.xz;
	float wobble = 0.045 * sin(p.x * 9.0 + p.y * 7.0) + 0.025 * sin((p.x - p.y) * 19.0);
	float lip = smoothstep(0.74 + wobble, 0.755 + wobble, height) * step(-0.3, world_normal.y);
	float cover = max(smoothstep(0.55, 0.7, world_normal.y), lip) * top_open;
	return mix(side, top, cover);
}

// Chevrons pointing along the belt on its top faces, streaming with time.
vec3 belt(vec3 base, vec3 chevron_color, float time) {
	vec2 along_dir = normalize(belt_dir);
	vec2 across_dir = vec2(-along_dir.y, along_dir.x);
	float along = dot(world_pos.xz, along_dir) - time * belt_speed;
	float across = abs(fract(dot(world_pos.xz, across_dir)) - 0.5);
	float v = fract((along - across * 0.8) * 2.0);
	float chevron = smoothstep(0.0, 0.06, v) * (1.0 - smoothstep(0.3, 0.36, v)) * step(across, 0.34);
	return mix(base, chevron_color, chevron * smoothstep(0.6, 0.9, world_normal.y));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (pattern == 1) {
		base = wood(base, UV);
	} else if (pattern == 2) {
		base = grass(base, side_color.rgb, COLOR.a);
	} else if (pattern == 3) {
		base = belt(base, side_color.rgb, TIME);
	}
	float mottle = surface_noise(world_pos * 2.1 + 3.7, world_normal);
	base *= 0.94 + 0.12 * mottle;
	// The baked shade is a perceptual brightness stored at half scale.
	ALBEDO = base * pow(COLOR.rgb * 2.0, vec3(2.2));

	vec3 dents = surface_noise_grad(world_pos, world_normal, 3.3)
		+ 0.5 * surface_noise_grad(world_pos + 11.0, world_normal, 7.9);
	NORMAL = bumped_view_normal(world_normal, dents, dent_depth, VIEW_MATRIX);
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	float pulse = pulse_strength * (0.5 - 0.5 * cos(TIME * TAU / pulse_period));
	EMISSION = sky_rim(NORMAL, VIEW) + albedo.rgb * pulse;
}
