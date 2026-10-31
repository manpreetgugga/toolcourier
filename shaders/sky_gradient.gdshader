// Tiny Courier background.
//
// The camera always looks down at the diorama, so a world-space gradient
// would only ever show the lower hemisphere. The visible background therefore
// uses a screen-space gradient (top of screen -> horizon colour at the bottom)
// with a faint radial vignette. The radiance/ambient cubemap pass uses a
// direction-based version of the same colours so reflections stay coherent.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.561, 0.722, 0.871);
uniform vec3 horizon_color : source_color = vec3(0.961, 0.902, 0.827);
uniform vec3 ground_color : source_color = vec3(0.788, 0.761, 0.706);
// Shapes the screen gradient: >1 keeps more of the horizon colour low on screen.
uniform float gradient_curve : hint_range(0.3, 3.0) = 1.35;
// Darkening at the screen corners (0 = off).
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.10;
// Overall background brightness before tonemapping.
uniform float energy : hint_range(0.0, 2.0) = 1.0;

vec3 direction_gradient(vec3 dir) {
	float h = dir.y;
	if (h >= 0.0) {
		return mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.6));
	}
	return mix(horizon_color, ground_color, pow(clamp(-h, 0.0, 1.0), 0.7));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = direction_gradient(EYEDIR) * energy;
	} else {
		// SCREEN_UV.y is 0 at the top of the screen.
		float t = pow(clamp(1.0 - SCREEN_UV.y, 0.0, 1.0), gradient_curve);
		vec3 col = mix(horizon_color, top_color, t);
		vec2 centered = SCREEN_UV - vec2(0.5);
		float v = smoothstep(0.35, 0.95, length(centered * vec2(1.0, 0.8)) * 1.25);
		col *= 1.0 - vignette_strength * v;
		COLOR = col * energy;
	}
}
