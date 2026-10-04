class_name TrainingDummy3D
extends Node3D
## Manichino di paglia per il prototipo 3D. Segnaposto: i nemici veri arriveranno da Blender.

signal died(dummy: TrainingDummy3D)

@export var max_hp: int = 30

var hp: int = 0
var alive: bool = true

var _body: Node3D
var _parts: Array[GeometryInstance3D] = []
var _wobble: float = 0.0
var _wobble_vel: float = 0.0
var _flash: float = 0.0

const WOOD := Color(0.55, 0.38, 0.25)
const WOOD_DARK := Color(0.42, 0.29, 0.2)
const STRAW := Color(0.93, 0.8, 0.48)
const CLOTH := Color(0.82, 0.27, 0.24)


func _ready() -> void:
	hp = max_hp
	_body = Node3D.new()
	add_child(_body)
	var base := CylinderMesh.new()
	base.top_radius = 0.24
	base.bottom_radius = 0.3
	base.height = 0.08
	base.radial_segments = 10
	_add_part(base, WOOD_DARK, Vector3(0, 0.04, 0))
	var post := CylinderMesh.new()
	post.top_radius = 0.06
	post.bottom_radius = 0.07
	post.height = 0.5
	post.radial_segments = 6
	_add_part(post, WOOD, Vector3(0, 0.3, 0))
	var torso := CapsuleMesh.new()
	torso.radius = 0.26
	torso.height = 0.78
	torso.radial_segments = 10
	torso.rings = 4
	_add_part(torso, STRAW, Vector3(0, 0.82, 0))
	var arms := BoxMesh.new()
	arms.size = Vector3(0.95, 0.11, 0.11)
	_add_part(arms, STRAW, Vector3(0, 0.98, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.275
	band.bottom_radius = 0.275
	band.height = 0.1
	band.radial_segments = 10
	_add_part(band, CLOTH, Vector3(0, 0.78, 0))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	head.radial_segments = 10
	head.rings = 6
	_add_part(head, STRAW, Vector3(0, 1.38, 0))


func _add_part(mesh: Mesh, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ToonMaterials.get_material(color)
	mi.position = pos
	_body.add_child(mi)
	_parts.append(mi)


func _process(delta: float) -> void:
	# molla smorzata: il manichino oscilla dopo il colpo
	_wobble_vel += (-_wobble * 90.0 - _wobble_vel * 7.0) * delta
	_wobble += _wobble_vel * delta
	if alive:
		_body.rotation.x = _wobble
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		for p in _parts:
			p.set_instance_shader_parameter("flash", _flash)


func take_hit(amount: int, from_dir: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 0.8
	if Vector2(from_dir.x, from_dir.z).length() > 0.001:
		rotation.y = atan2(from_dir.x, from_dir.z)
	_wobble_vel += 4.5
	_spawn_number(amount)
	if hp <= 0:
		_die()


func _spawn_number(amount: int) -> void:
	var l := Label3D.new()
	l.text = str(amount)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 72
	l.outline_size = 18
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.92, 0.35)
	l.outline_modulate = Color(0.2, 0.08, 0.05)
	l.position = Vector3(randf_range(-0.2, 0.2), 1.75, 0)
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 2.4, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


func _die() -> void:
	alive = false
	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", PI * 0.5, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.5)
	tw.tween_property(_body, "position:y", -1.0, 0.5)
	tw.tween_callback(func() -> void: died.emit(self))


func respawn_at(pos: Vector3) -> void:
	position = pos
	hp = max_hp
	alive = true
	_wobble = 0.0
	_wobble_vel = 0.0
	_body.rotation = Vector3.ZERO
	_body.position = Vector3.ZERO
	scale = Vector3.ONE * 0.2
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
