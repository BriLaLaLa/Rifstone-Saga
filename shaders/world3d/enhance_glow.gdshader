shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// Bagliore +7/+8/+9 sugli equip 3D (material_overlay). Stesso linguaggio degli shader icone
// shaders/enhancement_plus7/8/9.gdshader: +7 brace pulsante, +8 viola instabile, +9 ciano con onda di energia.
// La maschera è il colore per vertice (COLOR.r) esportato da Blender: 1 metallo, 0.5 cuoio, 0 fessure.

uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.05, 1.0);
uniform float intensity = 1.0;
uniform float pulse_speed = 1.5;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float sweep : hint_range(0.0, 2.0) = 0.0;
uniform float rim_power = 2.0;
uniform float mask_min : hint_range(0.0, 1.0) = 0.4;
uniform float base_glow : hint_range(0.0, 1.0) = 0.3;

varying vec3 local_pos;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	float mask = smoothstep(mask_min, 1.0, COLOR.r);
	float pulse = mix(1.0, 0.5 + 0.5 * sin(TIME * pulse_speed), pulse_amount);
	float fl = mix(1.0, 0.35 + 0.65 * hash(floor(TIME * 14.0)), flicker);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float band = smoothstep(0.82, 1.0, fract(local_pos.y * 1.6 - TIME * 0.7)) * sweep;
	float e = mask * intensity * (base_glow + fres * 1.3 + band) * pulse * fl;
	ALBEDO = glow_color.rgb * e;
}
