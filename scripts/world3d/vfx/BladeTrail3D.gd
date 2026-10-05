class_name BladeTrail3D
extends MeshInstance3D
## Scia di una lama: nastro tra base e punta della lama negli ultimi `duration` secondi.
## Segue una mesh d'arma (WarriorVisual.blade_segment): finché `emitting` è vero aggiunge un campione a
## ogni frame (più campioni intermedi quando la lama gira veloce), poi la coda svanisce da sola.
## Ogni accensione apre un tratto nuovo (i fendenti di fila non si uniscono) senza cancellare la coda
## del precedente. `strength` (0..1) rende il tratto più largo e luminoso (fendente potente).

const SHADER := preload("res://shaders/world3d/vfx/vfx_trail.gdshader")

## Durata della coda (secondi)
@export var duration: float = 0.16
## Distanza massima tra due campioni della punta: oltre, si aggiungono campioni interpolati
@export var max_step: float = 0.06
## Forza dei campioni che si aggiungono adesso (0 normale, 1 potente: nastro allungato oltre punta e base)
var strength: float = 0.0

var emitting: bool = false:
	set(v):
		if v and not emitting:
			_segment += 1
		emitting = v

var _blade_node: Node3D
var _base_local: Vector3
var _tip_local: Vector3
var _samples: Array = []   # [tempo, base, punta, forza, tratto] in coordinate del mondo
var _segment: int = 0
var _imesh: ImmediateMesh
var _mat: ShaderMaterial


func _init(edge: Color = Color(0.72, 0.9, 1.0), tip: Color = Color(0.85, 1.0, 0.95)) -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imesh = ImmediateMesh.new()
	mesh = _imesh
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("edge_color", edge)
	_mat.set_shader_parameter("tip_color", tip)
	material_override = _mat
	extra_cull_margin = 4.0


func set_colors(edge: Color, tip: Color) -> void:
	_mat.set_shader_parameter("edge_color", edge)
	_mat.set_shader_parameter("tip_color", tip)


## Aspetto della scia: edge, tip, rim (bordo deciso), rim_width, opacity, brightness
func set_style(style: Dictionary) -> void:
	var names := {"edge": "edge_color", "tip": "tip_color", "rim": "rim_color", "rim_width": "rim_width",
		"opacity": "opacity", "brightness": "brightness"}
	for k in names:
		if style.has(k):
			_mat.set_shader_parameter(names[k], style[k])


## Lama da seguire: punti nello spazio del nodo dell'arma
func set_blade(node: Node3D, base_local: Vector3, tip_local: Vector3) -> void:
	_blade_node = node
	_base_local = base_local
	_tip_local = tip_local


func has_blade() -> bool:
	return is_instance_valid(_blade_node)


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var now := Time.get_ticks_msec() / 1000.0
	if emitting and is_instance_valid(_blade_node) and _blade_node.is_visible_in_tree():
		var xf := _blade_node.global_transform
		var b := xf * _base_local
		var t := xf * _tip_local
		# fendente potente: il nastro va un po' oltre la punta e verso l'impugnatura
		var ax := t - b
		t += ax * 0.18 * strength
		b -= ax * 0.12 * strength
		if not _samples.is_empty():
			var last: Array = _samples[_samples.size() - 1]
			if int(last[4]) == _segment:
				var gap: float = (t - (last[2] as Vector3)).length()
				var n := mini(int(gap / max_step), 8)
				for i in range(1, n + 1):
					var f := float(i) / float(n + 1)
					_samples.append([lerpf(last[0], now, f), (last[1] as Vector3).lerp(b, f),
						_slerp_point(last[2], t, b, last[1], f), lerpf(last[3], strength, f), _segment])
		_samples.append([now, b, t, strength, _segment])
	while not _samples.is_empty() and now - float(_samples[0][0]) > duration:
		_samples.pop_front()
	_rebuild(now)


## Interpola la punta seguendo l'arco (la lama ruota attorno alla base): niente corde dritte nei giri veloci
func _slerp_point(t0: Vector3, t1: Vector3, b1: Vector3, b0: Vector3, f: float) -> Vector3:
	var base := b0.lerp(b1, f)
	var r0: Vector3 = t0 - b0
	var r1: Vector3 = t1 - b1
	var rl := lerpf(r0.length(), r1.length(), f)
	if r0.length() < 0.001 or r1.length() < 0.001:
		return t0.lerp(t1, f)
	return base + r0.normalized().slerp(r1.normalized(), f) * rl


func _rebuild(now: float) -> void:
	_imesh.clear_surfaces()
	var i := _samples.size() - 1
	while i >= 0:
		# un tratto (accensione) alla volta, dal più recente
		var seg := int(_samples[i][4])
		var j := i
		while j >= 0 and int(_samples[j][4]) == seg:
			j -= 1
		if i - j >= 2:
			_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for k in range(i, j, -1):
				var s: Array = _samples[k]
				var age := clampf((now - float(s[0])) / duration, 0.0, 1.0)
				_imesh.surface_set_color(Color(float(s[3]), 1, 1, 1))
				_imesh.surface_set_uv(Vector2(age, 0.0))
				_imesh.surface_add_vertex(s[1])
				_imesh.surface_set_uv(Vector2(age, 1.0))
				_imesh.surface_add_vertex(s[2])
			_imesh.surface_end()
		i = j
