shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Arco luminoso del Vortice della Spada attorno al warrior: corona circolare con la "testa" brillante
// (dove passa la lama) e la coda che sfuma girando. UV.x = angolo (0 testa, 1 giro completo dietro),
// UV.y = raggio (0 interno, 1 esterno). La testa ha la punta verdognola, la coda è bianco-argento.

uniform vec4 body_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 1.0, 0.7, 1.0);
uniform float tail = 0.55;       // frazione di giro coperta dalla coda
uniform float brightness = 0.6;
instance uniform float strength = 1.0;

void fragment() {
	float ang = UV.x;
	float rad = UV.y;
	float along = 1.0 - smoothstep(0.0, tail, ang);
	float band = smoothstep(0.0, 0.35, rad) * (1.0 - smoothstep(0.75, 1.0, rad));
	float head = 1.0 - smoothstep(0.0, 0.08, ang);
	vec3 col = mix(body_color.rgb, tip_color.rgb, head * smoothstep(0.4, 1.0, rad));
	col = mix(col, vec3(1.0), head * 0.5);
	float a = pow(along, 1.6) * band * strength;
	ALBEDO = col * brightness * a;
}
