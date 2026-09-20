shader_type spatial;
// PROTOTYPE (style test, #14). Inverted-hull outline, applied as material_overlay
// on character meshes only. Adapted from eldskald/godot4-cel-shader (MIT),
// per the painterly research (#12): extrude in clip space so the width stays
// constant in pixels whatever the camera distance.
//
// Split normals crack this. The Knight has 5328 verts over 3004 positions, so it
// will crack until tools/smooth_normals_import.gd bakes averaged normals into
// CUSTOM0. use_custom_normal switches between the two.
render_mode cull_front, unshaded, depth_draw_never, shadows_disabled;

uniform float width : hint_range(0.0, 8.0) = 1.8;      // pixels
uniform vec4 line_color : source_color = vec4(0.16, 0.10, 0.07, 1.0); // warm dark brown
uniform bool use_custom_normal = false;

void vertex() {
	vec3 n = use_custom_normal ? normalize(CUSTOM0.xyz * 2.0 - 1.0) : NORMAL;
	vec4 clip_pos = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * n);
	vec2 offset = normalize(clip_normal.xy) / VIEWPORT_SIZE * width * clip_pos.w * 2.0;
	clip_pos.xy += offset;
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
