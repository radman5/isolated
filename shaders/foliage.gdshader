shader_type spatial;
// Trees, bushes, ferns and grass: painted-ramp lighting (painted_ramp.gdshader),
// alpha-cut leaf cards, a little wind, and the see-through fade.
render_mode diffuse_burley, specular_disabled, cull_disabled;

#include "res://shaders/fade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D ramp : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
// 0 = solid (bark, rock). Leaf cards cut below this alpha.
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.0;
// Metres of sway per metre of height above the model's base, squared falloff.
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.3;
uniform float ramp_strength : hint_range(0.0, 1.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.08;
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);

varying vec3 world_pos;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = TIME * wind_speed + base.x * 0.37 + base.z * 0.23;
	vec2 sway = vec2(sin(phase), cos(phase * 0.8)) * wind_strength * h * h * 0.1;
	VERTEX.xz += sway;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (alpha_cut > 0.0 && c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb;
	ROUGHNESS = 1.0;
	// Two-sided leaf cards: light the back face from its own side.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	fade_apply(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, IN_SHADOW_PASS);
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	vec3 warped = texture(ramp, vec2(half_lambert, 0.0)).rgb;
	vec3 lit = mix(vec3(half_lambert), warped, ramp_strength);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit * ATTENUATION;
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	DIFFUSE_LIGHT += rim_color.rgb * rim * rim_strength * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0);
}
