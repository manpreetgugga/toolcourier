// Tiny Courier water block.
//
// Open water swells gently (vertex), with fine procedural ripples, drifting
// caustic highlights, a fresnel sky tint and soft foam along the shore. The
// shore term comes from BlockMesher, which stores the surface's ambient
// occlusion in the vertex colour alpha. No textures.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Linear sky colour, set per world by StageLighting.
global uniform vec3 sky_tint;

uniform vec4 water_color : source_color = vec4(0.373, 0.659, 0.788, 1.0);
uniform vec4 deep_color : source_color = vec4(0.204, 0.455, 0.596, 1.0);
uniform vec4 foam_color : source_color = vec4(0.945, 0.969, 0.976, 1.0);
uniform float swell_height = 0.025;
uniform float ripple_strength = 0.09;
uniform float caustic_strength = 0.12;
uniform float foam_strength = 0.6;

varying vec3 world_pos;
// 1 on the open surface, 0 on the sides.
varying float surface;

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

float swell(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.1) * 0.6 + sin(p.y * 2.3 - t * 0.8) * 0.4;
}

// Two ripple layers drifting in different directions.
float ripples(vec2 p, float t) {
	return noise(p * 3.0 + vec2(t * 0.30, t * 0.17)) * 0.6
		+ noise(p * 5.3 + vec2(-t * 0.22, t * 0.35)) * 0.4;
}

// A thin bright web where two drifting noise layers take the same value.
float caustics(vec2 p, float t) {
	float a = noise(p * 2.6 + vec2(t * 0.21, -t * 0.13));
	float b = noise(p * 3.4 + vec2(-t * 0.17, t * 0.19) + 11.7);
	float web = 1.0 - clamp(abs(a - b) * 4.0, 0.0, 1.0);
	return web * web * web;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface = smoothstep(0.75, 0.98, NORMAL.y);
	VERTEX.y += swell(world_pos.xz, TIME) * swell_height * surface;
}

void fragment() {
	// Wrap time so the noise inputs keep their precision on long sessions.
	float t = mod(TIME, 900.0);
	vec2 p = world_pos.xz;

	float e = 0.04;
	float h0 = ripples(p, t);
	float dx = (ripples(p + vec2(e, 0.0), t) - h0) / e;
	float dz = (ripples(p + vec2(0.0, e), t) - h0) / e;
	vec3 ripple_normal = normalize(vec3(-dx * ripple_strength, 1.0, -dz * ripple_strength));
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(ripple_normal, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, view_normal, surface));

	// Sides deepen towards the bottom of each cell, like looking into the water.
	float depth = 1.0 - fract(world_pos.y - 0.002);
	vec3 side = mix(water_color.rgb * 0.85, deep_color.rgb, smoothstep(0.0, 0.9, depth));
	vec3 col = mix(side, water_color.rgb, surface);
	col += caustics(p, t) * caustic_strength * surface;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_tint, fresnel * 0.3 * surface);

	float shore = 1.0 - smoothstep(0.5, 0.95, COLOR.a);
	float breakup = noise(p * 6.0 + vec2(t * 0.4, -t * 0.3));
	float foam = smoothstep(0.45, 0.6, shore * (0.65 + 0.7 * breakup)) * surface;
	col = mix(col, foam_color.rgb, foam * foam_strength);

	// The baked shade is a perceptual brightness stored at half scale;
	// apply it in linear space.
	ALBEDO = col * pow(COLOR.rgb * 2.0, vec3(2.2));
	ROUGHNESS = mix(0.6, 0.22, surface * (1.0 - foam));
	SPECULAR = 0.4;
}
