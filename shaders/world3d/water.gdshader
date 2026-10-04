shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

// Acqua toon: colore chiaro vicino alla riva e più profondo al largo, schiuma bianca ondulata
// dove l'acqua tocca scogliere e scogli (dalla differenza di profondità), increspature che scorrono.

uniform vec4 shallow_color : source_color = vec4(0.45, 0.82, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.28, 0.66, 0.66, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.99, 0.97, 1.0);
uniform float foam_width : hint_range(0.0, 1.0) = 0.2;
uniform float shallow_range : hint_range(0.1, 4.0) = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float diff = (-v.z / v.w) - (-VERTEX.z);
	float wave = sin(world_pos.x * 2.6 + TIME * 1.4) * 0.5 + sin(world_pos.z * 3.1 - TIME * 1.1) * 0.5;
	float foam = 1.0 - smoothstep(foam_width * 0.75, foam_width, diff + wave * 0.05);
	float ripple = step(0.97, sin(world_pos.x * 1.3 + world_pos.z * 0.7 + TIME * 0.8) * sin(world_pos.z * 1.1 - TIME * 0.5));
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, shallow_range, diff));
	col = mix(col, foam_color.rgb, max(foam, ripple * 0.3));
	ALBEDO = col;
	ALPHA = 0.96;
}
