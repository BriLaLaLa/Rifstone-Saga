shader_type spatial;
render_mode cull_back, specular_disabled;

// Toon a due bande per il mondo 3D: luce piena / ombra azzurrata, come i render del warrior in Blender.
// Il contorno lo disegna il post-process (outline_post.gdshader), non questo materiale.

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.68, 0.95, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.45;
uniform float band_center : hint_range(0.0, 1.0) = 0.52;
uniform float band_soft : hint_range(0.0, 0.2) = 0.03;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.12;

// Lampeggio quando colpito (per istanza, i materiali restano condivisi)
instance uniform float flash = 0.0;

// Chiome degli alberi: diventano trasparenti (retinatura) quando il player ci passa dietro.
// La posizione del player arriva da una global uniform aggiornata da PlayerCharacter3D.
uniform bool fade_occluder = false;
uniform float fade_radius = 0.95;
global uniform vec3 player_world_pos;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	if (fade_occluder) {
		vec3 pv = (VIEW_MATRIX * vec4(player_world_pos + vec3(0.0, 0.6, 0.0), 1.0)).xyz;
		// solo se il frammento sta davanti al player (più vicino alla camera)
		if (VERTEX.z > pv.z + 0.3 && pv.z < 0.0) {
			vec2 at_player_depth = VERTEX.xy * (pv.z / VERTEX.z);
			float d = length(at_player_depth - pv.xy);
			float alpha = smoothstep(fade_radius * 0.82, fade_radius, d);
			if (alpha < 1.0 && bayer4(FRAGCOORD.xy) > alpha) {
				discard;
			}
		}
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = vec3(flash);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// sole: due bande, il lato in ombra resta colorato (azzurrato) invece che nero
		float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
		float lit = smoothstep(band_center - band_soft, band_center + band_soft, ndl);
		lit = min(lit, smoothstep(0.35, 0.65, ATTENUATION));
		vec3 shade = mix(shadow_tint.rgb * (1.0 - shadow_strength), vec3(1.0), lit);
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * rim_amount * lit;
		DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
	} else {
		// luci locali (es. bagliore delle armi): morbide e limitate al loro raggio
		float l = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
		DIFFUSE_LIGHT += smoothstep(0.0, 0.3, l) * LIGHT_COLOR / PI * 0.6;
	}
}
