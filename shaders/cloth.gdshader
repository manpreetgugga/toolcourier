// A small waving pennant: a subdivided quad (PlaneMesh facing +Z, attached
// to its pole along the -X edge) rippled in the vertex shader, with a stripe
// across the middle. With wave at 0 it hangs limp and droops.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/clay_common.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 stripe_color : source_color = vec4(0.878, 0.478, 0.373, 1.0);
// Length of the cloth from the pole, matching the mesh width.
uniform float width = 0.36;
uniform float wave : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float from_pole = clamp((VERTEX.x + width * 0.5) / width, 0.0, 1.0);
	float phase = TIME * 5.0 - from_pole * 6.0;
	VERTEX.z += sin(phase) * 0.05 * from_pole * wave;
	VERTEX.y += cos(phase * 0.8) * 0.015 * from_pole * wave - (1.0 - wave) * from_pole * 0.12;
	NORMAL = normalize(vec3(cos(phase) * 0.8 * from_pole * wave, 0.0, 1.0));
}

void fragment() {
	float stripe = step(0.36, UV.y) * step(UV.y, 0.64);
	ALBEDO = mix(albedo.rgb, stripe_color.rgb, stripe);
	// Both sides are visible; light the back face from behind.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = 0.8;
	EMISSION = sky_rim(NORMAL, VIEW);
}
