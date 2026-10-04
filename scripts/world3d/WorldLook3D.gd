@tool
class_name WorldLook3D
extends RefCounted
## Ambiente e luce condivisi del mondo 3D (prototipo e zone): sfondo color acqua, luce ambiente
## piatta, sole con ombre, bagliore per gli effetti del potenziamento, nebbia leggerissima.

const WATER := Color(0.28, 0.66, 0.66)


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = WATER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.9, 0.92)
	env.fog_density = 0.002
	env.fog_sky_affect = 0.0
	return env


static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	return sun
