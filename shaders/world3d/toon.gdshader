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

void fragment() {
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
