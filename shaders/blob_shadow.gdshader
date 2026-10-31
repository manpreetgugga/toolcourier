// Soft round contact shadow under characters and parcels, on a unit quad.
// Grounds them even where the real shadow falls elsewhere.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.15, 0.28, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.38;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = color.rgb;
	ALPHA = (1.0 - smoothstep(0.2, 1.0, r)) * strength;
}
