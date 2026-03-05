shader_type canvas_item;

// +7 Enhancement: "Controlled Energy"
// L'arma sembra carica di energia, come una brace viva
// Pulsazione lenta e costante, aura sottile ma visibile

uniform vec4 energy_color : source_color = vec4(1.0, 0.4, 0.0, 1.0); // Arancione brace
uniform float pulse_speed : hint_range(0.5, 3.0) = 1.5;
uniform float aura_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float edge_glow : hint_range(0.0, 0.5) = 0.15;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Pulsazione lenta e costante (heartbeat)
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	pulse = smoothstep(0.3, 0.7, pulse); // Pulsazione morbida

	// Aura sui bordi dell'arma
	float alpha_edge = tex.a * (1.0 - tex.a); // Massimo sui bordi
	vec4 edge_aura = energy_color * alpha_edge * edge_glow * pulse;

	// Overlay di energia sull'arma stessa
	vec4 energy_overlay = energy_color * tex.a * aura_intensity * pulse * 0.5;

	// Combina texture originale + aura + overlay
	vec4 result = tex + edge_aura + energy_overlay;

	COLOR = result;
}
