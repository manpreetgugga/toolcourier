// Clay surface for props and characters: the shared clay lighting with
// mottling and shallow dents, but no baked vertex shade. Detail is computed
// in object space so it stays put on moving parts.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/clay_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
// Depth (metres) and frequency of the dents.
uniform float dent_depth = 0.004;
uniform float dent_scale = 9.0;
// Self-illumination, for eye glints and similar highlights.
uniform float glow : hint_range(0.0, 2.0) = 0.0;
// Peak emission of the interactive-part pulse (0 = no pulse).
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_period = 1.6;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	float mottle = surface_noise(local_pos * dent_scale * 0.6 + 3.7, local_normal);
	ALBEDO = albedo.rgb * (0.95 + 0.1 * mottle);
	vec3 dents = surface_noise_grad(local_pos, local_normal, dent_scale);
	NORMAL = bumped_view_normal(local_normal, dents, dent_depth, VIEW_MATRIX * MODEL_MATRIX);
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	float pulse = pulse_strength * (0.5 - 0.5 * cos(TIME * TAU / pulse_period));
	EMISSION = sky_rim(NORMAL, VIEW) + albedo.rgb * (glow + pulse);
}
