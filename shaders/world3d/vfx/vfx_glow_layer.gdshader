shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// Strato luminoso sopra una mesh del warrior (copia della mesh, gonfiata di poco): aura ciano della spada,
// rabbia rosso-arancio di Estasi, carica bianco-gialla di Volontà di Vivere. È un'istanza a parte, così
// si somma al bagliore +7/+8/+9 (material_overlay di Enhancement3D) invece di sostituirlo.

uniform vec4 glow_color : source_color = vec4(0.25, 0.95, 1.0, 1.0);
uniform float inflate = 0.012;
uniform float rim_power = 2.0;
uniform float base_glow = 0.25;
uniform float flow_speed = 1.0;   // bande che salgono
uniform float flow_scale = 9.0;
uniform float flow_amount : hint_range(0.0, 1.0) = 0.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float metal_mask : hint_range(0.0, 1.0) = 0.0;  // 1 = solo le parti metalliche (COLOR.r, come il potenziamento)
instance uniform float intensity = 1.0;

varying vec3 world_pos;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	VERTEX += NORMAL * inflate;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float flow = 0.5 + 0.5 * sin(world_pos.y * flow_scale - TIME * flow_speed * 6.0 + sin(world_pos.x * 7.0 + world_pos.z * 5.0) * 1.5);
	float fl = mix(1.0, 0.6 + 0.4 * hash(floor(TIME * 18.0)), flicker);
	float mask = mix(1.0, smoothstep(0.4, 1.0, COLOR.r), metal_mask);
	float e = (base_glow + fres * 1.6) * mix(1.0, flow, flow_amount) * fl * intensity * mask;
	ALBEDO = glow_color.rgb * e;
}
