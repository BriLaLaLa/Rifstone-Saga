shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Scia della lama (BladeTrail3D): nastro tra base e punta della lama negli ultimi istanti.
// UV.x = età del campione (0 adesso, 1 il più vecchio), UV.y = lungo la lama (0 base, 1 punta).
// Bianco-argento con alone colorato; la punta tende al colore "tip" (verdognolo nel Vortice).
// COLOR.r = forza del fendente (0 normale, 1 colpo potente: più luminoso e coprente).
// rim_width > 0 disegna un bordo deciso sul lato della punta (leggibile sull'erba).

uniform vec4 edge_color : source_color = vec4(0.72, 0.9, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.85, 1.0, 0.95, 1.0);
uniform vec4 rim_color : source_color = vec4(0.22, 0.5, 0.95, 1.0);
uniform float rim_width : hint_range(0.0, 0.5) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float brightness = 1.0;

void fragment() {
	float strong = COLOR.r;
	float age = clamp(UV.x, 0.0, 1.0);
	float along = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - age, mix(1.4, 0.9, strong));
	// bordo morbido verso la base, pieno verso la punta
	float shape = smoothstep(0.0, mix(0.35, 0.2, strong), along) * (1.0 - smoothstep(0.97, 1.0, along) * 0.5);
	// nucleo bianco vicino alla lama appena passata, alone colorato nella coda
	float core = (1.0 - smoothstep(0.0, 0.45, age)) * smoothstep(0.35, 0.9, along);
	vec3 col = mix(edge_color.rgb, vec3(1.0), core);
	col = mix(col, tip_color.rgb, smoothstep(0.8, 1.0, along) * 0.6);
	// bordo deciso verso la punta
	float rim = rim_width > 0.0 ? smoothstep(1.0 - rim_width, 1.0 - rim_width * 0.35, along) : 0.0;
	col = mix(col, rim_color.rgb, rim * 0.85);
	ALBEDO = col * brightness * (1.0 + 0.3 * strong);
	ALPHA = clamp(fade * max(shape, rim) * opacity * (1.0 + 0.25 * strong) * COLOR.a, 0.0, 1.0);
}
