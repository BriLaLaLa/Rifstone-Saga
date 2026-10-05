shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// Immagine fantasma (afterimage) dello scatto di Sibilare: sagoma luminosa del warrior che svanisce.

uniform vec4 ghost_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float rim_power = 1.6;
instance uniform float fade = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = ghost_color.rgb * (0.16 + fres * 0.9) * fade;
}
