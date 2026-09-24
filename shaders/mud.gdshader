shader_type spatial;
// The wet surface of the mud clearing, laid just below ground level: dark wet
// brown with a slow ripple and a sheen where the sun catches it. Painted-ramp
// diffuse like the ground around it.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D ramp : source_color, filter_linear;
uniform vec4 deep : source_color = vec4(0.22, 0.17, 0.12, 1.0);
uniform vec4 shallow : source_color = vec4(0.30, 0.24, 0.17, 1.0);
uniform float ripple_speed = 0.05;
uniform float ramp_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * ripple_speed;
	float n = vnoise(p * 0.45 + vec2(t, -t * 0.7)) * 0.6 + vnoise(p * 1.3 - vec2(t * 1.3, t)) * 0.4;
	ALBEDO = mix(deep.rgb, shallow.rgb, n);
	// A slow wobble in the normal gives the sheen something to catch.
	vec2 slope = vec2(vnoise(p * 1.7 + t) - 0.5, vnoise(p * 1.7 - t + 7.0) - 0.5) * 0.12;
	NORMAL = normalize((VIEW_MATRIX * vec4(slope.x, 1.0, slope.y, 0.0)).xyz);
	ROUGHNESS = 0.28;
	SPECULAR = 0.1;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	vec3 warped = texture(ramp, vec2(half_lambert, 0.0)).rgb;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * mix(vec3(half_lambert), warped, ramp_strength) * ATTENUATION;
	// A small, soft highlight: wet, not glossy.
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += LIGHT_COLOR * pow(max(dot(NORMAL, h), 0.0), 180.0) * 0.12 * ATTENUATION;
}
