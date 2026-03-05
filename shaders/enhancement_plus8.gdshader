shader_type canvas_item;

// +8 Enhancement: "Unstable Energy"
// L'energia si muove da sola, l'arma vibra e pulsa irregolarmente
// Sensazione di tensione, come se stesse lottando per contenerla

uniform vec4 energy_color : source_color = vec4(0.8, 0.2, 1.0, 1.0); // Viola elettrico
uniform float instability : hint_range(0.0, 1.0) = 0.6;
uniform float vibration_speed : hint_range(3.0, 10.0) = 6.0;
uniform float flicker_speed : hint_range(5.0, 15.0) = 10.0;
uniform float aura_reach : hint_range(0.0, 0.8) = 0.4;

// Noise function per irregolarità
float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Vibrazione irregolare (jitter)
	float vibration = sin(TIME * vibration_speed + random(UV) * 10.0) * instability * 0.02;
	vec2 distorted_uv = UV + vec2(vibration, -vibration * 0.5);
	vec4 distorted_tex = texture(TEXTURE, distorted_uv);

	// Flicker irregolare dell'energia
	float flicker = random(vec2(TIME * flicker_speed, UV.y));
	flicker = smoothstep(0.3, 0.8, flicker);

	// Pulsazione rapida e irregolare
	float pulse = sin(TIME * 4.0 + random(UV) * 3.14) * 0.5 + 0.5;
	pulse = mix(pulse, flicker, 0.5);

	// Aura espansa e instabile
	float alpha_edge = tex.a * (1.0 - tex.a);
	float expanded_alpha = smoothstep(0.0, aura_reach, alpha_edge);
	vec4 unstable_aura = energy_color * expanded_alpha * pulse * instability;

	// Energy veins (venature di energia sull'arma)
	float veins = random(UV + vec2(TIME * 0.5, 0.0));
	veins = smoothstep(0.7, 0.9, veins);
	vec4 vein_energy = energy_color * tex.a * veins * flicker * 0.6;

	// Combina tutto con distorsione
	vec4 result = mix(tex, distorted_tex, instability * 0.3) + unstable_aura + vein_energy;

	COLOR = result;
}
