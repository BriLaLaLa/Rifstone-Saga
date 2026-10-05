shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Scia della lama (BladeTrail3D): nastro tra base e punta della lama negli ultimi istanti.
// UV.x = età del campione (0 adesso, 1 il più vecchio), UV.y = lungo la lama (0 base, 1 punta).
// Bianco-argento con alone colorato; la punta tende al colore "tip" (verdognolo nel Vortice).

uniform vec4 edge_color : source_color = vec4(0.72, 0.9, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.85, 1.0, 0.95, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float brightness = 1.0;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float along = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - age, 1.4);
	// bordo morbido verso la base, pieno verso la punta
	float shape = smoothstep(0.0, 0.35, along) * (1.0 - smoothstep(0.97, 1.0, along) * 0.5);
	// nucleo bianco vicino alla lama appena passata, alone colorato nella coda
	float core = (1.0 - smoothstep(0.0, 0.45, age)) * smoothstep(0.35, 0.9, along);
	vec3 col = mix(edge_color.rgb, vec3(1.0), core);
	col = mix(col, tip_color.rgb, smoothstep(0.8, 1.0, along) * 0.6);
	ALBEDO = col * brightness;
	ALPHA = clamp(fade * shape * opacity * COLOR.a, 0.0, 1.0);
}
