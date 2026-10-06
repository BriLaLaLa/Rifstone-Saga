shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// Contorno scuro a schermo intero: bordi dove cambia la profondità (sagome) o la normale (spigoli marcati).
// Va su un QuadMesh 2x2 figlio della camera. Richiede il renderer Forward+ (normal_roughness texture).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.13, 0.11, 0.17, 1.0);
uniform float thickness : hint_range(0.5, 4.0) = 2.0;
uniform float depth_threshold : hint_range(0.0, 0.5) = 0.035;
uniform float normal_threshold : hint_range(0.0, 2.0) = 0.6;
// Con la camera lontana i contorni si alleggeriscono: oggetti piccoli e dettagli non diventano rumore
uniform float fade_start = 18.0;
uniform float fade_end = 40.0;
uniform float far_alpha : hint_range(0.0, 1.0) = 0.8;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 o = thickness / VIEWPORT_SIZE;
	float d0 = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 n0 = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	vec2 offs[4] = vec2[](vec2(o.x, 0.0), vec2(-o.x, 0.0), vec2(0.0, o.y), vec2(0.0, -o.y));
	float edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offs[i];
		float d = linear_depth(uv, INV_PROJECTION_MATRIX);
		vec3 n = texture(normal_tex, uv).xyz * 2.0 - 1.0;
		// sagoma: il vicino è più lontano -> la linea cade sull'oggetto davanti
		edge = max(edge, step(depth_threshold * d0, d - d0));
		// spigolo: normali molto diverse alla stessa profondità
		edge = max(edge, step(normal_threshold, 1.0 - dot(n0, n)) * step(abs(d - d0), d0 * 0.05));
	}
	ALBEDO = line_color.rgb;
	ALPHA = edge * line_color.a * mix(1.0, far_alpha, smoothstep(fade_start, fade_end, d0));
}
