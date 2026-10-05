shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// Barra sopra la testa (vita dei nemici, avanzamento raccolta): sempre rivolta alla camera e sempre visibile.

uniform vec4 fill_color : source_color = vec4(0.85, 0.22, 0.2, 1.0);
uniform vec4 back_color : source_color = vec4(0.12, 0.1, 0.14, 0.85);
uniform vec4 border_color : source_color = vec4(0.05, 0.04, 0.07, 1.0);
instance uniform float fill = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 px = fwidth(UV) * 1.5;
	float border = max(max(step(UV.x, px.x), step(1.0 - px.x, UV.x)), max(step(UV.y, px.y * 1.5), step(1.0 - px.y * 1.5, UV.y)));
	vec3 col = UV.x < fill ? fill_color.rgb : back_color.rgb;
	ALBEDO = mix(col, border_color.rgb, border);
	ALPHA = UV.x < fill ? 1.0 : back_color.a;
}
