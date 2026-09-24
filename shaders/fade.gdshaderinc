// See-through occluders: foliage and high terrain that stand between the camera
// and an actor are dithered away in a soft-edged cylinder along the line from the
// camera to that actor. occluder_fade.gd fills the actor list every frame.
//
// World space rather than screen space, so it reads the same on every backend,
// and discard rather than blending, so it stays in the opaque pass: no sorting,
// and depth stays right.

// xyz: the actor's chest, w: the cylinder's radius in metres.
uniform vec4 fade_actors[8];
uniform int fade_count = 0;
// Only fragments above this height fade (terrain: keep the floor under actors).
uniform float fade_min_height = -1000.0;
// Anything this close to the camera dithers away too: canopies right under the
// lens would otherwise fill the screen. Fully gone at fade_near * 0.6.
uniform float fade_near = 7.0;

float fade_bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	// 4x4 Bayer matrix, row by row.
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

// How much of this fragment to cut away, 0..1.
float fade_amount(vec3 frag_world, vec3 cam) {
	if (frag_world.y < fade_min_height) {
		return 0.0;
	}
	float cut = 1.0 - smoothstep(fade_near * 0.6, fade_near, distance(frag_world, cam));
	for (int i = 0; i < fade_count; i++) {
		vec3 a = fade_actors[i].xyz;
		vec3 seg = a - cam;
		float len2 = dot(seg, seg);
		float t = dot(frag_world - cam, seg) / len2;
		// Only between the camera and the actor, and not right on top of it.
		if (t <= 0.0 || t >= 0.96) {
			continue;
		}
		float d = length(frag_world - (cam + seg * t));
		float r = fade_actors[i].w;
		cut = max(cut, 1.0 - smoothstep(r * 0.55, r, d));
	}
	return cut;
}

// Call at the end of fragment(). Leaves shadows whole: the shadow pass draws
// from the light, where this cylinder means nothing.
void fade_apply(vec3 frag_world, vec3 cam, vec2 frag_px, bool shadow_pass) {
	if (!shadow_pass && fade_amount(frag_world, cam) > fade_bayer4(frag_px)) {
		discard;
	}
}
