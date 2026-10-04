@tool
class_name ToonMaterials
extends RefCounted
## Cache dei materiali toon condivisi: un ShaderMaterial per colore, riusato da tutte le istanze.

const TOON_SHADER := preload("res://shaders/world3d/toon.gdshader")

static var _cache: Dictionary = {}


static func get_material(color: Color) -> ShaderMaterial:
	var key := color.to_html(true)
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", color)
	_cache[key] = mat
	return mat


## Sostituisce i materiali importati (colore piatto) con il toon dello stesso colore, moltiplicato per tint.
static func apply_to_mesh(mi: MeshInstance3D, tint: Color = Color.WHITE) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s)
		var col := Color.WHITE
		if src is BaseMaterial3D:
			col = (src as BaseMaterial3D).albedo_color
		mi.set_surface_override_material(s, get_material(col * tint))
