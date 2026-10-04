class_name Enhancement3D
extends RefCounted
## Effetti visivi del potenziamento +7/+8/+9 su un pezzo di equip 3D:
## overlay luminoso limitato al metallo (maschera COLOR.r) + scintille e luce per armi e scudi.

const GLOW_SHADER := preload("res://shaders/world3d/enhance_glow.gdshader")
const SPARK_SHADER := preload("res://shaders/world3d/spark.gdshader")
const FX_META := &"enhancement_fx"

## Le armature brillano meno delle armi: coprono molta superficie e "bruciano" il colore
const ARMOR_INTENSITY := 0.4
const ARMOR_BASE_GLOW := 0.08

## Colori e ritmo presi dagli shader delle icone (shaders/enhancement_plus7/8/9.gdshader)
const PRESETS := {
	7: {"color": Color(1.0, 0.42, 0.05), "intensity": 1.3, "pulse_speed": 1.5, "pulse_amount": 0.6,
		"flicker": 0.0, "sweep": 0.0, "rim_power": 2.0, "sparks": 10, "light": 0.0},
	8: {"color": Color(0.78, 0.25, 1.0), "intensity": 1.9, "pulse_speed": 6.0, "pulse_amount": 0.4,
		"flicker": 0.6, "sweep": 0.0, "rim_power": 1.6, "sparks": 26, "light": 0.5},
	9: {"color": Color(0.1, 0.85, 1.0), "intensity": 2.6, "pulse_speed": 2.5, "pulse_amount": 0.3,
		"flicker": 0.15, "sweep": 1.2, "rim_power": 1.3, "sparks": 50, "light": 0.9},
}

static var _glow_cache: Dictionary = {}
static var _spark_mesh: QuadMesh


static func apply(mi: MeshInstance3D, level: int, with_sparks: bool) -> void:
	for c in mi.get_children():
		if c.has_meta(FX_META):
			mi.remove_child(c)
			c.queue_free()
	if not PRESETS.has(level):
		mi.material_overlay = null
		return
	var p: Dictionary = PRESETS[level]
	mi.material_overlay = _glow_material(level, p, with_sparks)
	if with_sparks:
		mi.add_child(_make_sparks(mi.get_aabb(), p))
		if p["light"] > 0.0:
			var light := OmniLight3D.new()
			light.set_meta(FX_META, true)
			light.light_color = p["color"]
			light.light_energy = p["light"]
			light.omni_range = 1.2
			light.position = mi.get_aabb().get_center()
			mi.add_child(light)


static func _glow_material(level: int, p: Dictionary, weapon: bool) -> ShaderMaterial:
	var key := "%d_%s" % [level, "weapon" if weapon else "armor"]
	if _glow_cache.has(key):
		return _glow_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	for param in ["pulse_speed", "pulse_amount", "flicker", "sweep", "rim_power"]:
		mat.set_shader_parameter(param, p[param])
	mat.set_shader_parameter("glow_color", p["color"])
	mat.set_shader_parameter("intensity", p["intensity"] * (1.0 if weapon else ARMOR_INTENSITY))
	if not weapon:
		mat.set_shader_parameter("base_glow", ARMOR_BASE_GLOW)
	_glow_cache[key] = mat
	return mat


static func _make_sparks(aabb: AABB, p: Dictionary) -> GPUParticles3D:
	var parts := GPUParticles3D.new()
	parts.set_meta(FX_META, true)
	parts.amount = p["sparks"]
	parts.lifetime = 0.9
	parts.local_coords = false
	parts.position = aabb.get_center()
	parts.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = aabb.size * 0.5
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0, 0.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	pm.scale_curve = fade_tex
	var ramp := Gradient.new()
	var col: Color = p["color"]
	ramp.set_color(0, Color(1, 1, 1, 1).lerp(col, 0.4))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	parts.process_material = pm

	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.05, 0.05)
		var sm := ShaderMaterial.new()
		sm.shader = SPARK_SHADER
		_spark_mesh.material = sm
	parts.draw_pass_1 = _spark_mesh
	return parts
