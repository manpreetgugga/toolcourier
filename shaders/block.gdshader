// Tiny Courier block surface: soft clay.
//
// BlockMesher merges and rounds the blocks so a level reads as one sculpted
// lump. Wrap lighting with a warm scatter band at the terminator, a soft
// sheen, hand-pressed colour mottling and shallow thumb dents.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/block_common.gdshaderinc"

uniform float wrap : hint_range(0.0, 1.0) = 0.3;
uniform vec3 scatter_color : source_color = vec3(1.0, 0.5, 0.35);
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.3;
uniform float sheen : hint_range(0.0, 1.0) = 0.14;
// Depth of the thumb dents in metres.
uniform float dent_depth = 0.02;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = block_base(UV, COLOR.a, 0.74);
	float mottle = surface_noise(world_pos * 2.1 + 3.7, world_normal);
	base *= 0.94 + 0.12 * mottle;
	ALBEDO = base * block_shade(COLOR);

	vec3 dents = surface_noise_grad(world_pos, world_normal, 3.3)
		+ 0.5 * surface_noise_grad(world_pos + 11.0, world_normal, 7.9);
	NORMAL = bumped_view_normal(world_normal, dents, dent_depth, VIEW_MATRIX);
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	EMISSION = block_emission(NORMAL, VIEW, TIME);
}

void light() {
	float diff = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
	float terminator = diff * (1.0 - diff) * 4.0;
	vec3 lit = vec3(diff) + scatter_color * terminator * scatter_strength;
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_vector = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, half_vector), 0.0), 18.0) * sheen;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR / PI;
}
