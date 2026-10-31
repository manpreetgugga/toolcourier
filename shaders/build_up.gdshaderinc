// The build-up a level opens and closes with: every block and prop pops up
// from below into its place, one after another. BlockMesher and PropFactory
// store, in CUSTOM0, each vertex's anchor (the centre of its block, or the
// foot of its prop) and the moment it starts (seconds). Assembly runs
// build_time on each mesh; at the default every part simply stands in place,
// and meshes without CUSTOM0 are never touched.

instance uniform float build_time = 1000.0;

// Seconds a part takes to pop in, and how far below its place it starts.
const float BUILD_POP = 0.42;
const float BUILD_DROP = 1.4;

vec3 build_up(vec3 vertex, vec4 anchor) {
	float t = clamp((build_time - anchor.w) / BUILD_POP, 0.0, 1.0);
	float u = t - 1.0;
	// Back ease out: grows past full size and settles.
	float s = 1.0 + 2.70158 * u * u * u + 1.70158 * u * u;
	vec3 p = anchor.xyz + (vertex - anchor.xyz) * s;
	p.y -= u * u * BUILD_DROP;
	return p;
}
