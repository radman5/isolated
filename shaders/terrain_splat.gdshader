shader_type spatial;
// The route's ground: grass as the base, with worn dirt, mud and leaf litter
// painted on top by vertex colour (route_terrain.gd), and cliff rock wherever the
// ground is steep. Painted-ramp lighting like everything else. Five samplers:
// well inside WebGL2's 16.
render_mode diffuse_burley, specular_disabled;

#include "res://shaders/fade.gdshaderinc"

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaves_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ramp : source_color, filter_linear;

// Metres per texture repeat.
uniform float grass_size = 4.0;
uniform float dirt_size = 3.0;
uniform float leaves_size = 3.5;
uniform float cliff_size = 6.0;
// Tints pull each photo-ish texture onto the muted palette.
uniform vec4 grass_tint : source_color = vec4(0.6, 0.6, 0.45, 1.0);
uniform vec4 path_tint : source_color = vec4(0.78, 0.72, 0.64, 1.0);
uniform vec4 mud_tint : source_color = vec4(0.62, 0.54, 0.46, 1.0);
uniform vec4 leaves_tint : source_color = vec4(0.56, 0.5, 0.42, 1.0);
uniform vec4 cliff_tint : source_color = vec4(0.72, 0.66, 0.60, 1.0);
// Ground steeper than this (1 - normal.y) turns to cliff rock.
uniform float cliff_from = 0.32;
uniform float cliff_full = 0.55;
// How ragged the painted edges are.
uniform float edge_noise = 0.45;
uniform float ramp_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A painted mask: pushes a soft vertex-colour blend into a ragged brushy edge.
float paint(float w, float n) {
	return smoothstep(0.35, 0.65, w + (n - 0.5) * edge_noise);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 grass = texture(grass_tex, p / grass_size).rgb * grass_tint.rgb;
	vec3 leaves = texture(leaves_tex, p / leaves_size).rgb * leaves_tint.rgb;
	vec3 dirt_s = texture(dirt_tex, p / dirt_size).rgb;
	vec3 path = dirt_s * path_tint.rgb;
	vec3 mud = texture(dirt_tex, p / (dirt_size * 0.6) + 0.37).rgb * mud_tint.rgb;
	// The leaf texture's brightness doubles as the brush noise.
	float n = dot(texture(leaves_tex, p / 7.0).rgb, vec3(0.333));

	vec3 col = grass;
	col = mix(col, leaves, paint(COLOR.b, n));
	col = mix(col, path, paint(COLOR.r, 1.0 - n));
	col = mix(col, mud, paint(COLOR.g, n));

	// Triplanar cliff rock on steep ground, so banks and the ravine don't smear.
	vec3 an = abs(world_normal);
	an /= (an.x + an.y + an.z);
	vec3 cliff = (texture(cliff_tex, world_pos.zy / cliff_size).rgb * an.x
		+ texture(cliff_tex, world_pos.xz / cliff_size).rgb * an.y
		+ texture(cliff_tex, world_pos.xy / cliff_size).rgb * an.z) * cliff_tint.rgb;
	float slope = 1.0 - world_normal.y;
	col = mix(col, cliff, smoothstep(cliff_from, cliff_full, slope + (n - 0.5) * 0.1));

	ALBEDO = col;
	ROUGHNESS = 1.0;
	fade_apply(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, IN_SHADOW_PASS);
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	vec3 warped = texture(ramp, vec2(half_lambert, 0.0)).rgb;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * mix(vec3(half_lambert), warped, ramp_strength) * ATTENUATION;
}
