shader_type spatial;
// Painted lighting: half-Lambert warped through an artist ramp, the Team
// Fortress 2 recipe from the painterly research (#12). Came from the style test
// (#14); foliage.gdshader and terrain_splat.gdshader share its light().
// Not vertex_lighting: light() does not run with it.
render_mode diffuse_burley, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D ramp : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
// How far the shadow side is pulled toward the ramp's warm end. 1 = full ramp.
uniform float ramp_strength : hint_range(0.0, 1.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.12;
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);

varying vec3 view_normal;

void vertex() {
	view_normal = NORMAL;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	// Half-Lambert: never fully black, so form still reads in shadow.
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	vec3 warped = texture(ramp, vec2(half_lambert, 0.0)).rgb;
	vec3 lit = mix(vec3(half_lambert), warped, ramp_strength);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * lit * ATTENUATION;

	// A soft rim instead of a specular highlight: TF2 picks silhouettes out with
	// light, and it keeps characters readable against dark foliage from above.
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	DIFFUSE_LIGHT += rim_color.rgb * rim * rim_strength * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0);
}
