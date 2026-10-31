// Shared inputs and helpers for the block shaders.
//
// BlockMesher bakes a shade (ambient occlusion, top/bottom tint, per-block
// jitter) into vertex colour at half scale, and per-type data into its alpha:
// the open-top flag for grass. UV is face-planar world position.

// Linear sky colour, set per world by StageLighting.
global uniform vec3 sky_tint;

uniform vec4 albedo : source_color = vec4(0.725, 0.706, 0.667, 1.0);
// 0 = plain, 1 = wood planks, 2 = grass top over side_color.
uniform int pattern : hint_range(0, 2) = 0;
uniform vec4 side_color : source_color = vec4(0.647, 0.490, 0.353, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
// Peak emission of the interactive-part pulse (0 = no pulse).
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_period = 1.6;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Planar noise on the plane facing the dominant normal axis, so every face
// gets detail without UVs or textures.
float surface_noise(vec3 p, vec3 n) {
	vec3 a = abs(n);
	vec2 uv = a.y > max(a.x, a.z) ? p.xz : (a.x > a.z ? p.zy : p.xy);
	return noise(uv);
}

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
// whose top is open; lip_start is the cell height where the lip begins.
vec3 grass(vec3 top, vec3 side, float top_open, float lip_start) {
	float height = fract(world_pos.y - 0.002);
	vec2 p = world_pos.xz;
	float wobble = 0.045 * sin(p.x * 9.0 + p.y * 7.0) + 0.025 * sin((p.x - p.y) * 19.0);
	float lip = smoothstep(lip_start + wobble, lip_start + 0.015 + wobble, height) * step(-0.3, world_normal.y);
	float cover = max(smoothstep(0.55, 0.7, world_normal.y), lip) * top_open;
	return mix(side, top, cover);
}

vec3 block_base(vec2 uv, float aux, float lip_start) {
	if (pattern == 1) {
		return wood(albedo.rgb, uv);
	} else if (pattern == 2) {
		return grass(albedo.rgb, side_color.rgb, aux, lip_start);
	}
	return albedo.rgb;
}

// The baked shade is a perceptual brightness stored at half scale.
vec3 block_shade(vec4 color) {
	return pow(color.rgb * 2.0, vec3(2.2));
}

// Sky-tinted rim plus the accent pulse.
vec3 block_emission(vec3 normal, vec3 view, float time) {
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0) * rim_strength;
	float pulse = pulse_strength * (0.5 - 0.5 * cos(time * TAU / pulse_period));
	return sky_tint * rim + albedo.rgb * pulse;
}

// Value noise with its analytic gradient: (value, d/dx, d/dy).
vec3 noise_grad(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
		du * vec2(b - a + k * u.y, c - a + k * u.x));
}

// World-space gradient of surface_noise(p * freq, n), for bump mapping
// without tangents or screen derivatives.
vec3 surface_noise_grad(vec3 p, vec3 n, float freq) {
	vec3 a = abs(n);
	if (a.y > max(a.x, a.z)) {
		vec3 g = noise_grad(p.xz * freq);
		return vec3(g.y, 0.0, g.z) * freq;
	} else if (a.x > a.z) {
		vec3 g = noise_grad(p.zy * freq);
		return vec3(0.0, g.z, g.y) * freq;
	}
	vec3 g = noise_grad(p.xy * freq);
	return vec3(g.y, g.z, 0.0) * freq;
}

// Tilts world normal n against a height gradient scaled by depth (metres),
// and returns it in view space ready for NORMAL.
vec3 bumped_view_normal(vec3 n, vec3 grad, float depth, mat4 view_matrix) {
	n = normalize(n);
	vec3 bumped = normalize(n - depth * (grad - dot(grad, n) * n));
	return normalize((view_matrix * vec4(bumped, 0.0)).xyz);
}
