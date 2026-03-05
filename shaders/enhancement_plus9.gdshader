shader_type canvas_item;

// +9 Enhancement: "Manifested Artifact"
// L'arma non sembra più forgiata ma manifestata
// Distorsione dello spazio, effetto soprannaturale, energia che vuole uscire

uniform vec4 energy_color : source_color = vec4(0.0, 0.8, 1.0, 1.0); // Ciano elettrico
uniform vec4 distortion_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Bianco puro
uniform float reality_distortion : hint_range(0.0, 1.0) = 0.8;
uniform float emanation_speed : hint_range(1.0, 5.0) = 2.5;
uniform float space_warp : hint_range(0.0, 0.15) = 0.08;
uniform float aura_explosion : hint_range(0.5, 1.5) = 1.0;

// Advanced noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Distorsione dello spazio intorno all'arma
	vec2 center = vec2(0.5, 0.5);
	vec2 to_center = UV - center;
	float dist = length(to_center);

	// Warping pulsante
	float warp_pulse = sin(TIME * emanation_speed) * 0.5 + 0.5;
	vec2 warped_uv = UV + to_center * space_warp * warp_pulse * noise(UV * 5.0 + TIME);

	vec4 tex = texture(TEXTURE, warped_uv);

	// Emanazione di energia (waves che partono dall'arma)
	float wave = sin(dist * 20.0 - TIME * 5.0) * 0.5 + 0.5;
	wave *= smoothstep(0.0, 0.3, dist) * smoothstep(1.0, 0.5, dist);

	// Reality fracture (fratture nella realtà)
	float fracture = noise(UV * 10.0 + TIME * 0.5);
	fracture = step(0.85, fracture);
	vec4 fracture_flash = distortion_color * fracture * tex.a;

	// Aura esplosiva e caotica
	float alpha_gradient = 1.0 - dist * 2.0;
	float chaos = noise(UV * 8.0 + TIME * 2.0);
	chaos = smoothstep(0.4, 0.7, chaos);

	vec4 explosive_aura = energy_color * alpha_gradient * chaos * aura_explosion * tex.a;
	explosive_aura *= smoothstep(0.0, 0.5, dist); // Solo fuori dall'arma

	// Glow sovrannaturale sull'arma stessa
	float supernatural_glow = sin(TIME * 3.0 + noise(UV * 4.0) * 6.28) * 0.5 + 0.5;
	vec4 inner_glow = mix(energy_color, distortion_color, supernatural_glow) * tex.a * 0.7;

	// Edge distortion (i bordi sembrano dissolversi)
	float edge = tex.a * (1.0 - tex.a) * 4.0;
	vec4 dissolving_edge = distortion_color * edge * warp_pulse * 0.8;

	// Combina tutti gli effetti
	vec4 result = tex + explosive_aura + inner_glow + dissolving_edge + fracture_flash;
	result.a = max(tex.a, explosive_aura.a * 0.5); // Mantieni alpha espansa

	COLOR = result;
}
