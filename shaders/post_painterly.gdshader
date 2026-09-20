shader_type spatial;
// PROTOTYPE (style test, #14). One full-screen quad carrying the painterly finish:
// generalized (8-sector) Kuwahara, UV wobble and paper grain. Spatial, not canvas,
// so it runs at scaling_3d_scale (about 0.6) rather than full window resolution —
// the whole point of the research's cost note (#12).
//
// Quad setup: 2x2 QuadMesh, flip_faces on, a large extra_cull_margin, and this
// POSITION write pins it to the screen.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int kuwahara_radius : hint_range(0, 4) = 2;   // 0 = off
uniform float wobble_px : hint_range(0.0, 4.0) = 1.2; // 0 = off
uniform float grain_amount : hint_range(0.0, 1.0) = 0.12;
uniform float grain_scale = 320.0;
uniform sampler2D wobble_noise : hint_default_black, filter_linear;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Cheap value noise, so the prototype needs no extra texture import.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
	vec2 uv = SCREEN_UV;

	// Wobble: a low-frequency offset so straight polygon edges read hand-drawn.
	if (wobble_px > 0.0) {
		float nx = value_noise(uv * 6.0) - 0.5;
		float ny = value_noise(uv * 6.0 + vec2(13.7, 4.3)) - 0.5;
		uv += vec2(nx, ny) * texel * wobble_px * 2.0;
	}

	vec3 col;
	if (kuwahara_radius <= 0) {
		col = texture(screen_tex, uv).rgb;
	} else {
		// Generalized Kuwahara: every tap is weighted into 8 overlapping sectors by
		// its angle, and the sector with the lowest variance wins. Keeps edges and
		// corners crisp while flattening the inside into painted patches.
		const int SECTORS = 8;
		vec3 sum[SECTORS];
		vec3 sum2[SECTORS];
		float weight[SECTORS];
		for (int s = 0; s < SECTORS; s++) {
			sum[s] = vec3(0.0);
			sum2[s] = vec3(0.0);
			weight[s] = 0.0;
		}
		int r = kuwahara_radius;
		for (int y = -4; y <= 4; y++) {
			if (y < -r || y > r) { continue; }
			for (int x = -4; x <= 4; x++) {
				if (x < -r || x > r) { continue; }
				vec2 off = vec2(float(x), float(y));
				vec3 c = texture(screen_tex, uv + off * texel).rgb;
				float d2 = dot(off, off);
				// Gaussian falloff by distance, so far taps matter less.
				float w = exp(-d2 / (2.0 * float(r) * float(r) + 0.5));
				float ang = atan(off.y, off.x);           // -PI..PI
				float sector = (ang + PI) / (2.0 * PI) * float(SECTORS);
				int s0 = int(floor(sector)) % SECTORS;
				int s1 = (s0 + 1) % SECTORS;
				float frac_s = fract(sector);
				// Split each tap across two neighbouring sectors: overlapping sectors
				// are what stop the 4-quadrant version's blocky artefacts.
				for (int s = 0; s < SECTORS; s++) {
					float sw = 0.0;
					if (s == s0) { sw = 1.0 - frac_s; }
					if (s == s1) { sw = frac_s; }
					if (sw > 0.0) {
						float ww = w * sw;
						sum[s] += c * ww;
						sum2[s] += c * c * ww;
						weight[s] += ww;
					}
				}
			}
		}
		float best = 1e9;
		col = texture(screen_tex, uv).rgb;
		for (int s = 0; s < SECTORS; s++) {
			if (weight[s] <= 0.0) { continue; }
			vec3 mean = sum[s] / weight[s];
			vec3 var = max(sum2[s] / weight[s] - mean * mean, vec3(0.0));
			float v = var.r + var.g + var.b;
			if (v < best) {
				best = v;
				col = mean;
			}
		}
	}

	// Paper grain, screen-locked: world-locked grain swims as the camera moves.
	if (grain_amount > 0.0) {
		float g = value_noise(SCREEN_UV * grain_scale);
		col *= mix(1.0, 0.6 + g * 0.8, grain_amount);
	}

	ALBEDO = col;
}
