class_name StunStars3D
extends Node3D
## Stelline che girano sopra la testa di un nemico stordito (Sibilare), con un anello sottile.
## show_for(secondi) le accende; si spengono da sole.

const STAR_COUNT := 3
const RADIUS := 0.26
const COLOR := Color(1.0, 0.88, 0.3)

var _time_left: float = 0.0
var _spin: Node3D
var _stars: Array[Label3D] = []


func _ready() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	for i in STAR_COUNT:
		var l := Label3D.new()
		l.text = "★"
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 64
		l.outline_size = 12
		l.pixel_size = 0.004
		l.modulate = COLOR
		l.outline_modulate = Color(0.35, 0.2, 0.05)
		var a := TAU * i / STAR_COUNT
		l.position = Vector3(sin(a) * RADIUS, 0.0, cos(a) * RADIUS)
		_spin.add_child(l)
		_stars.append(l)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS - 0.015
	tm.outer_radius = RADIUS + 0.015
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.45, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(ring)
	visible = false


func show_for(seconds: float) -> void:
	_time_left = maxf(_time_left, seconds)
	visible = true


func hide_now() -> void:
	_time_left = 0.0
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false
		return
	_spin.rotation.y += delta * 4.5
	for i in _stars.size():
		var s := 1.0 + 0.18 * sin(Time.get_ticks_msec() / 1000.0 * 8.0 + i * 2.0)
		_stars[i].scale = Vector3.ONE * s
