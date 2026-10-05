class_name Enemy3D
extends Node3D
## Nemico del combattimento 3D (port di Enemy2D, stessa API pubblica).
## Stati: IDLE → CHASING → ATTACKING → DEAD. Dati da EnemyDatabase.get_enemy_stats(id, level).
## Modelli Blender per id (lupo, metin); id senza modello → lupo ricolorato (segnaposto).
## Il colpo al player parte nel momento del morso dell'animazione, non all'inizio.

signal died(enemy)
signal hp_threshold_crossed(enemy, fraction: float)

enum EnemyState { IDLE, CHASING, ATTACKING, DEAD }

const PX := 64.0
const MODELS := {
	"lupo": {"scene": "res://assets/3d/enemies/lupo.glb", "hit_time": 0.43, "bar_height": 1.05, "radius": 0.42},
	"metin": {"scene": "res://assets/3d/enemies/metin.glb", "hit_time": 0.0, "bar_height": 2.35, "radius": 0.7},
}
## Nemici senza modello: lupo ricolorato e scalato finché Blender non fa il loro
const PLACEHOLDERS := {"cinghiale": {"tint": Color(0.72, 0.52, 0.38), "scale": 1.2}}
const GLOW_SHADER := preload("res://shaders/world3d/enhance_glow.gdshader")
const LOOPING := ["idle", "run"]
## Spazio minimo tra il nemico e il player (non gli entra dentro)
const PLAYER_SPACE := 0.3

@export var aggro_range: float = 220.0 / PX
@export var attack_range: float = 1.15
@export var move_speed: float = 80.0 / PX

var enemy_id: String = ""
var stats: Dictionary = {}
var level: int = 1
var max_hp: float = 1.0
var current_hp: float = 1.0
var attack_damage: float = 1.0
var attack_speed: float = 2.0

var state: EnemyState = EnemyState.IDLE
## Mob statico (pietra Metin): non insegue né attacca, fa solo da bersaglio
var is_static: bool = false
var is_metin: bool = false

var _player: Node3D = null
var _attack_cooldown: float = 0.0
var _attack_pending: bool = false
var _attack_t: float = 0.0
var _stun_time: float = 0.0
var _thresholds_left: Array = []
var _model_info: Dictionary = {}
var _model: Node3D
var _anim: AnimationPlayer
var _meshes: Array[GeometryInstance3D] = []
var _hp_bar: Bar3D
var _aggro_mark: Label3D
var _stun_mark: Label3D
var _flash: float = 0.0
var _target_yaw: float = 0.0
var _rune_mat: ShaderMaterial


func setup(p_enemy_id: String, p_level: int, p_player: Node3D) -> void:
	enemy_id = p_enemy_id
	level = p_level
	_player = p_player
	stats = EnemyDatabase.get_enemy_stats(enemy_id, level)
	max_hp = float(stats.get("hp", 100))
	current_hp = max_hp
	attack_damage = float(stats.get("attack", 5.0))
	attack_speed = float(stats.get("attack_speed", 2.0))
	add_to_group("enemies")
	_build_visual()


func setup_metin(thresholds: Array = [0.75, 0.5, 0.25]) -> void:
	is_metin = true
	is_static = true
	_thresholds_left = thresholds.duplicate()
	_add_rune_glow()


# ==================== VISUALE ====================

func _build_visual() -> void:
	if _model:
		_model.queue_free()
	_meshes.clear()
	var tint := Color.WHITE
	var s := 1.0
	_model_info = MODELS.get(enemy_id, {})
	if _model_info.is_empty():
		var ph: Dictionary = PLACEHOLDERS.get(enemy_id, {"tint": Color(1.0, 0.6, 0.6), "scale": 1.0})
		tint = ph["tint"]
		s = ph["scale"]
		_model_info = MODELS["lupo"]
	_model = (load(_model_info["scene"]) as PackedScene).instantiate()
	_model.scale = Vector3.ONE * s
	add_child(_model)
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		ToonMaterials.apply_to_mesh(n, tint)
		_meshes.append(n)
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		for a in LOOPING:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(_on_anim_finished)
		_play("idle")
	var h: float = _model_info["bar_height"] * s
	_hp_bar = Bar3D.create(Color(0.88, 0.24, 0.2), 0.7 if not is_metin else 1.1)
	_hp_bar.position = Vector3(0, h, 0)
	_hp_bar.visible = false
	add_child(_hp_bar)
	_hp_bar.set_fraction(1.0)
	_aggro_mark = _make_mark("!", Color(1.0, 0.3, 0.25), h + 0.25)
	_stun_mark = _make_mark("✦ ✦ ✦", Color(1.0, 0.9, 0.3), h + 0.2)
	_target_yaw = randf() * TAU
	rotation.y = _target_yaw


func _make_mark(text: String, color: Color, height: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80
	l.outline_size = 16
	l.pixel_size = 0.004
	l.modulate = color
	l.position = Vector3(0, height, 0)
	l.visible = false
	add_child(l)
	return l


## Rune e crepe della pietra Metin che pulsano (maschera COLOR_0 del modello); più veloci quando la vita cala
func _add_rune_glow() -> void:
	_rune_mat = ShaderMaterial.new()
	_rune_mat.shader = GLOW_SHADER
	_rune_mat.set_shader_parameter("glow_color", Color(1.0, 0.32, 0.12))
	_rune_mat.set_shader_parameter("intensity", 1.6)
	_rune_mat.set_shader_parameter("pulse_speed", 2.0)
	_rune_mat.set_shader_parameter("pulse_amount", 0.6)
	_rune_mat.set_shader_parameter("base_glow", 0.9)
	_rune_mat.set_shader_parameter("mask_min", 0.5)
	for m in _meshes:
		m.material_overlay = _rune_mat


func _play(anim_name: String, restart: bool = false) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if not restart and _anim.current_animation == anim_name:
		return
	if restart:
		_anim.stop()
	_anim.play(anim_name, 0.1)


func _on_anim_finished(anim_name: StringName) -> void:
	if state != EnemyState.DEAD and (anim_name == &"attack" or anim_name == &"hit"):
		_play("idle")


func _process(delta: float) -> void:
	if state == EnemyState.DEAD or _model == null:
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-10.0 * delta))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		for m in _meshes:
			m.set_instance_shader_parameter("flash", _flash)
	if _stun_mark.visible:
		_stun_mark.rotation.y += delta * 4.0


# ==================== COMPORTAMENTO ====================

func _physics_process(delta: float) -> void:
	if state == EnemyState.DEAD or not is_instance_valid(_player) or _model == null:
		return
	if not is_visible_in_tree() or is_static:
		return
	if _stun_time > 0.0:
		_stun_time -= delta
		_stun_mark.visible = _stun_time > 0.0
		_attack_pending = false
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	match state:
		EnemyState.IDLE:
			_play("idle")
			if dist <= aggro_range:
				_set_state(EnemyState.CHASING)
		EnemyState.CHASING:
			if dist <= attack_range:
				_set_state(EnemyState.ATTACKING)
			else:
				_face(to)
				_move(_chase_dir(to) * move_speed * delta)
				_play("run")
		EnemyState.ATTACKING:
			_face(to)
			if not _attack_pending and dist > attack_range * 1.25:
				_set_state(EnemyState.CHASING)
				return
			_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
			if not _attack_pending and _attack_cooldown <= 0.0:
				_attack_cooldown = maxf(0.5, attack_speed)
				_attack_pending = true
				_attack_t = 0.0
				_play("attack", true)
			if _attack_pending:
				_attack_t += delta
				if _attack_t >= float(_model_info.get("hit_time", 0.3)):
					_attack_pending = false
					if dist <= attack_range * 1.4:
						_deal_damage_to_player()
			elif _anim and _anim.current_animation != "attack" and _anim.current_animation != "hit":
				_play("idle")
	_separate(delta)


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		_target_yaw = atan2(dir.x, dir.z)


## Movimento agganciato alla navmesh: il nemico scivola lungo i bordi invece di finire in acqua
func _move(step: Vector3) -> void:
	var wanted := global_position + step
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var p := NavigationServer3D.map_get_closest_point(map, wanted)
		wanted = Vector3(p.x, 0.0, p.z)
	global_position = wanted


## Direzione d'inseguimento: verso il player, ma girando attorno ai compagni già vicini a lui,
## così il branco lo circonda invece di ammucchiarsi tutto dallo stesso lato
func _chase_dir(to_player: Vector3) -> Vector3:
	var dir := to_player.normalized()
	if to_player.length() > attack_range * 2.5:
		return dir
	var side := Vector3(-dir.z, 0.0, dir.x)
	var push := 0.0
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Enemy3D):
			continue
		var d := (other as Node3D).global_position - global_position
		d.y = 0.0
		if d.length() < 1.2 and d.dot(dir) > 0.0:
			push += -signf(d.dot(side)) if absf(d.dot(side)) > 0.01 else (1.0 if get_instance_id() % 2 == 0 else -1.0)
	return (dir + side * clampf(push, -1.0, 1.0) * 0.8).normalized()


## Evita sovrapposizioni: i nemici si spingono via a vicenda e non entrano dentro il player
func _separate(delta: float) -> void:
	if is_static:
		return
	var r: float = _model_info.get("radius", 0.3)
	var k := minf(1.0, delta * 10.0)
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Enemy3D):
			continue
		var d := global_position - (other as Node3D).global_position
		d.y = 0.0
		var min_d: float = r + float((other as Enemy3D)._model_info.get("radius", 0.3))
		var l := d.length()
		if l < min_d and l > 0.0001:
			_move(d / l * (min_d - l) * k)
	var dp := global_position - _player.global_position
	dp.y = 0.0
	var min_p := r + PLAYER_SPACE
	if dp.length() < min_p and dp.length() > 0.0001:
		_move(dp.normalized() * (min_p - dp.length()) * k)


func _deal_damage_to_player() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var cs = gs.get("character_stats")
	if cs and cs.has_method("take_damage"):
		cs.take_damage(attack_damage)
	if _player.has_method("on_hit_taken"):
		_player.on_hit_taken(attack_damage)


# ==================== DANNO / MORTE ====================

func take_damage(amount: float) -> void:
	if state == EnemyState.DEAD:
		return
	current_hp -= amount
	_hp_bar.visible = true
	_hp_bar.set_fraction(current_hp / max_hp)
	_flash = 0.85
	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, float(_model_info["bar_height"]) + 0.15, 0), str(int(round(amount))))
	if is_static:
		_punch()
	elif not _attack_pending:
		_play("hit", true)
	if is_metin:
		if _rune_mat:
			_rune_mat.set_shader_parameter("pulse_speed", lerpf(6.0, 2.0, clampf(current_hp / max_hp, 0.0, 1.0)))
		var frac := current_hp / max_hp
		while not _thresholds_left.is_empty() and frac <= _thresholds_left[0]:
			hp_threshold_crossed.emit(self, _thresholds_left.pop_front())
	if current_hp <= 0.0:
		_die()


## Stordimento (Sibilare): fermo, niente attacchi, stelline sopra la testa
func stun(duration: float) -> void:
	if state == EnemyState.DEAD or is_static:
		return
	_stun_time = maxf(_stun_time, duration)
	_stun_mark.visible = true
	_play("hit", true)


func _punch() -> void:
	var tw := _model.create_tween()
	tw.tween_property(_model, "scale", Vector3(1.06, 0.95, 1.06), 0.05)
	tw.tween_property(_model, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func is_alive() -> bool:
	return state != EnemyState.DEAD and current_hp > 0.0


func _die() -> void:
	state = EnemyState.DEAD
	current_hp = 0.0
	remove_from_group("enemies")
	_hp_bar.visible = false
	_aggro_mark.visible = false
	_stun_mark.visible = false
	died.emit(self)
	var tw := create_tween()
	if is_metin:
		tw.tween_property(_model, "scale", Vector3(1.15, 0.2, 1.15), 0.5).set_ease(Tween.EASE_IN)
	else:
		_play("death", true)
		tw.tween_interval(1.6)
		tw.tween_property(_model, "position:y", -0.8, 0.6)
	tw.tween_callback(queue_free)


func _set_state(s: EnemyState) -> void:
	if state == s:
		return
	state = s
	_aggro_mark.visible = s == EnemyState.CHASING or s == EnemyState.ATTACKING
	if s == EnemyState.CHASING or s == EnemyState.ATTACKING:
		_hp_bar.visible = true
	if GameLogger.ENABLED:
		print("[Enemy3D:%s] → %s" % [enemy_id, EnemyState.keys()[s]])


## Raggio d'ingombro (il player si ferma a questa distanza in più dal centro)
func get_radius() -> float:
	return float(_model_info.get("radius", 0.3)) * (_model.scale.x if _model else 1.0)


func get_enemy_name() -> String:
	return str(stats.get("name", enemy_id))
