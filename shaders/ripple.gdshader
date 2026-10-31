// Tap feedback: a ring that expands across a block face and fades out,
// over a soft disc that flashes at the start. Drawn on a unit quad.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
// 0 at the tap, 1 when the ripple has faded.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float grow = 1.0 - pow(1.0 - progress, 3.0);
	float radius = mix(0.15, 0.9, grow);
	float width = mix(0.16, 0.05, grow);
	float aa = fwidth(r);
	float edge = abs(r - radius);
	float ring = 1.0 - smoothstep(width * 0.5, width * 0.5 + aa, edge);
	float glow = (1.0 - smoothstep(0.0, width * 1.6, edge)) * 0.35;
	float disc = (1.0 - smoothstep(radius * 0.5, radius, r)) * 0.3 * (1.0 - grow);
	float fade = 1.0 - smoothstep(0.5, 1.0, progress);
	// A light core keeps the ring readable on surfaces of a similar hue.
	float core = 1.0 - smoothstep(width * 0.15, width * 0.15 + aa, edge);
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.55);
	ALPHA = clamp(ring * 0.85 + glow + disc, 0.0, 1.0) * fade * color.a;
}
