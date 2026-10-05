shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Anello a terra che si allarga e svanisce (onda d'urto, impatto, battito del piede).
// Disegnato su un piano orizzontale; progress va da 0 a 1 (Vfx3D lo anima per istanza).

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width = 0.16;
uniform float fill = 0.0;        // disco interno pieno (lampo)
uniform float start_radius = 0.15;
uniform float brightness = 0.75;
instance uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float r = mix(start_radius, 0.94, 1.0 - pow(1.0 - progress, 2.0));
	float w = width * (1.0 - progress * 0.5);
	float ring = 1.0 - smoothstep(0.0, w, abs(d - r));
	float inner = fill * (1.0 - smoothstep(r - w, r, d)) * 0.45;
	float a = (ring + inner) * (1.0 - smoothstep(0.55, 1.0, progress)) * step(d, 1.0);
	ALBEDO = color.rgb * brightness * a * color.a;
}
