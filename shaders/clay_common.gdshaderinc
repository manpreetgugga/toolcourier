// The shared clay surface: noise helpers, bump mapping without tangents, a
// sky-tinted rim, and the clay lighting model (wrap diffuse with a warm
// scatter band at the shadow line, plus a soft sheen). Included by the block
// and prop shaders, so it defines their light() function.

// Linear sky colour, set per world by StageLighting.
global uniform vec3 sky_tint;

uniform float wrap : hint_range(0.0, 1.0) = 0.3;
uniform vec3 scatter_color : source_color = vec3(1.0, 0.5, 0.35);
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.3;
uniform float sheen : hint_range(0.0, 1.0) = 0.14;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;

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

// Planar noise on the plane facing the dominant normal axis, so every face
// gets detail without UVs or textures.
float surface_noise(vec3 p, vec3 n) {
	vec3 a = abs(n);
	vec2 uv = a.y > max(a.x, a.z) ? p.xz : (a.x > a.z ? p.zy : p.xy);
	return noise(uv);
}

// Gradient of surface_noise(p * freq, n), for bump mapping without tangents
// or screen derivatives.
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

// Tilts normal n against a height gradient scaled by depth (metres), both in
// the space that to_view maps to view space, and returns it ready for NORMAL.
vec3 bumped_view_normal(vec3 n, vec3 grad, float depth, mat4 to_view) {
	n = normalize(n);
	vec3 bumped = normalize(n - depth * (grad - dot(grad, n) * n));
	return normalize((to_view * vec4(bumped, 0.0)).xyz);
}

// Faint sky-coloured rim that lifts silhouettes off the background.
vec3 sky_rim(vec3 normal, vec3 view) {
	return sky_tint * pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0) * rim_strength;
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
