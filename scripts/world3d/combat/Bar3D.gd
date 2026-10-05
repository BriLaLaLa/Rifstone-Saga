class_name Bar3D
extends MeshInstance3D
## Barra billboard sopra la testa (vita, avanzamento). Un materiale condiviso per colore.

const BAR_SHADER := preload("res://shaders/world3d/billboard_bar.gdshader")

static var _materials: Dictionary = {}


static func create(color: Color, width: float = 0.6, height: float = 0.08) -> Bar3D:
	var bar := Bar3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	bar.mesh = quad
	var key := color.to_html()
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = BAR_SHADER
		mat.set_shader_parameter("fill_color", color)
		_materials[key] = mat
	bar.material_override = _materials[key]
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar


func set_fraction(f: float) -> void:
	set_instance_shader_parameter("fill", clampf(f, 0.0, 1.0))
