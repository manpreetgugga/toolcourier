// Tiny Courier background.
//
// The camera always looks down at the diorama, so a world-space gradient
// would only ever show the lower hemisphere. The visible background therefore
// uses a screen-space gradient (top of screen -> horizon colour at the bottom)
// with a faint radial vignette and a sea of clouds below the diorama
// (projected from the view direction, so it turns with the camera). The
// radiance/ambient cubemap pass uses a direction-based version of the same
// colours so reflections stay coherent.
//
// No TIME: an animated sky would force the radiance map to update every frame.
// The clouds are worked out for every pixel: the quarter-resolution sky pass
// (QUARTER_RES_COLOR) would be cheaper, but the Mobile renderer does not run
// it and the sky comes out blank.
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
// Coverage of the cloud sea below the diorama (0 = none).
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float cloud_scale = 3.0;
// OpenGL (the Compatibility renderer: phones without Vulkan, and safe mode,
// see core/SafeBoot.gd): SCREEN_UV is not usable in the sky pass there, so
// the screen gradient is rebuilt from the view direction's elevation, in
// radians, from view_bottom (bottom edge of the screen) to view_top (top
// edge). StageLighting keeps both in step with the camera.
uniform bool view_gradient = false;
uniform float view_bottom = -1.2;
uniform float view_top = -0.3;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// Gradient noise around 0.5; rounder than value noise, so thresholded
// clouds don't show the lattice.
float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float ga = hash(i) * TAU;
	float gb = hash(i + vec2(1.0, 0.0)) * TAU;
	float gc = hash(i + vec2(0.0, 1.0)) * TAU;
	float gd = hash(i + vec2(1.0, 1.0)) * TAU;
	float a = dot(vec2(cos(ga), sin(ga)), f);
	float b = dot(vec2(cos(gb), sin(gb)), f - vec2(1.0, 0.0));
	float c = dot(vec2(cos(gc), sin(gc)), f - vec2(0.0, 1.0));
	float d = dot(vec2(cos(gd), sin(gd)), f - vec2(1.0, 1.0));
	return 0.5 + 0.7 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octaves are rotated against each other to hide axis alignment.
float fbm(vec2 p) {
	const mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += gradient_noise(p) * amp;
		p = turn * p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

vec3 direction_gradient(vec3 dir) {
	float h = dir.y;
	if (h >= 0.0) {
		return mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.6));
	}
	return mix(horizon_color, ground_color, pow(clamp(-h, 0.0, 1.0), 0.7));
}

// Puffy cloud tops on a plane below the camera, fading into haze towards
// the horizon.
vec3 cloud_sea(vec3 dir, vec3 col) {
	if (cloud_amount <= 0.0 || dir.y > -0.01) {
		return col;
	}
	vec2 p = dir.xz / -dir.y * cloud_scale;
	float n = fbm(p);
	float threshold = 0.6 - 0.16 * cloud_amount;
	float body = smoothstep(threshold, threshold + 0.1, n);
	// Lighter crowns, slightly shaded undersides.
	float crown = smoothstep(threshold + 0.05, threshold + 0.2, n);
	vec3 cloud = cloud_color * mix(0.86, 1.04, crown);
	float haze = smoothstep(0.15, 0.5, -dir.y);
	return mix(col, cloud, body * haze * 0.9);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = direction_gradient(EYEDIR) * energy;
	} else if (view_gradient) {
		float e = asin(clamp(EYEDIR.y, -1.0, 1.0));
		float t = pow(clamp((e - view_bottom) / (view_top - view_bottom), 0.0, 1.0), gradient_curve);
		vec3 col = mix(horizon_color, top_color, t);
		COLOR = cloud_sea(EYEDIR, col) * energy;
	} else {
		// SCREEN_UV.y is 0 at the top of the screen.
		float t = pow(clamp(1.0 - SCREEN_UV.y, 0.0, 1.0), gradient_curve);
		vec3 col = mix(horizon_color, top_color, t);
		col = cloud_sea(EYEDIR, col);
		vec2 centered = SCREEN_UV - vec2(0.5);
		float v = smoothstep(0.35, 0.95, length(centered * vec2(1.0, 0.8)) * 1.25);
		col *= 1.0 - vignette_strength * v;
		COLOR = col * energy;
	}
}
