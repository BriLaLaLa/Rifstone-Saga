# scripts/combat/Enemy2D.gd
# Nemico del sistema combat top-down (CharacterBody2D).
# State machine: IDLE → CHASING → ATTACKING → DEAD.
# Rilevato dal player tramite gruppo "enemies" + collision_layer 4.
# I dati vengono da EnemyDatabase.get_enemy_stats(id, level).
# NOTE Step 2: aggro + inseguimento. Il danno reale (skill del player → take_damage,
# attacco nemico → player) viene cablato nello Step 3.

extends CharacterBody2D
class_name Enemy2D

signal died(enemy: Enemy2D)

enum EnemyState { IDLE, CHASING, ATTACKING, DEAD }

# ==================== EXPORT ====================

@export var aggro_range: float  = 220.0
@export var attack_range: float = 48.0
@export var move_speed: float   = 80.0

# ==================== NODES ====================

@onready var sprite: Sprite2D = $Sprite2D
@onready var _hp_bar: ProgressBar = $HPBar
@onready var _aggro_mark: Label = $AggroMark

var _base_modulate: Color = Color.WHITE

# ==================== DATA ====================

var enemy_id: String = ""
var stats: Dictionary = {}
var level: int = 1
var max_hp: float = 1.0
var current_hp: float = 1.0
var attack_damage: float = 1.0
var attack_speed: float = 2.0

# ==================== STATE ====================

var state: EnemyState = EnemyState.IDLE
var _player: Node2D = null
var _attack_cooldown: float = 0.0

# Mob statico (es. pietra Metin): non insegue né attacca, sta fermo e prende danno.
var is_static: bool = false
# Metin: emette segnali a soglie HP e alla morte (gestiti dal controller per le ondate)
var is_metin: bool = false
signal hp_threshold_crossed(enemy, fraction: float)
var _thresholds_left: Array = []  # frazioni HP rimaste da attraversare (es. [0.75,0.5,0.25])

const FALLBACK_ICON := "res://icon.svg"
const DAMAGE_NUMBER := preload("res://scripts/battle/DamageNumber.gd")

# ==================== SETUP ====================

func setup(p_enemy_id: String, p_level: int, p_player: Node2D) -> void:
	enemy_id = p_enemy_id
	level    = p_level
	_player  = p_player

	stats         = EnemyDatabase.get_enemy_stats(enemy_id, level)
	max_hp        = float(stats.get("hp", 100))
	current_hp    = max_hp
	attack_damage = float(stats.get("attack", 5.0))
	attack_speed  = float(stats.get("attack_speed", 2.0))

	if is_instance_valid(_hp_bar):
		_hp_bar.max_value = max_hp
		_hp_bar.value = current_hp

	_apply_sprite(stats.get("icon", ""))

func _apply_sprite(icon_path: String) -> void:
	if not is_instance_valid(sprite):
		return
	var tex: Texture2D = null
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path)
	if tex == null:
		tex = load(FALLBACK_ICON)
		sprite.modulate = Color(1.0, 0.4, 0.4)  # rosso = nemico fallback
	sprite.texture = tex
	_base_modulate = sprite.modulate
	# Normalizza a ~36px di lato
	var tsize: Vector2 = tex.get_size()
	if tsize.x > 0.0 and tsize.y > 0.0:
		var target := 36.0
		sprite.scale = Vector2(target / tsize.x, target / tsize.y)

# ==================== PHYSICS ====================

func _physics_process(delta: float) -> void:
	if state == EnemyState.DEAD or not is_instance_valid(_player):
		return
	# Se la zona non è visibile (back to map / cambio scheda), congela:
	# niente movimento né attacchi in background.
	if not is_visible_in_tree():
		velocity = Vector2.ZERO
		return

	# Mob statico (pietra Metin): non si muove e non attacca, fa solo da bersaglio.
	if is_static:
		velocity = Vector2.ZERO
		return

	var dist: float = global_position.distance_to(_player.global_position)

	match state:
		EnemyState.IDLE:
			if dist <= aggro_range:
				_set_state(EnemyState.CHASING)

		EnemyState.CHASING:
			if dist <= attack_range:
				velocity = Vector2.ZERO
				_set_state(EnemyState.ATTACKING)
			else:
				var dir := (_player.global_position - global_position).normalized()
				velocity = dir * move_speed
				move_and_slide()
				if sprite and dir.x != 0.0:
					sprite.flip_h = dir.x < 0.0

		EnemyState.ATTACKING:
			velocity = Vector2.ZERO
			if dist > attack_range:
				_set_state(EnemyState.CHASING)
				return
			_attack_cooldown = max(0.0, _attack_cooldown - delta)
			if _attack_cooldown <= 0.0:
				_attack_cooldown = max(0.5, attack_speed)
				_deal_damage_to_player()

func _deal_damage_to_player() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var stats = gs.get("character_stats")
	if stats and stats.has_method("take_damage"):
		stats.take_damage(attack_damage)
		if GameLogger.ENABLED:
			print("[Enemy2D:%s] colpisce il player per %.0f" % [enemy_id, attack_damage])

# ==================== DAMAGE / DEATH ====================

func take_damage(amount: float) -> void:
	if state == EnemyState.DEAD:
		return
	current_hp -= amount
	if is_instance_valid(_hp_bar):
		_hp_bar.value = current_hp
	_flash_hit()
	_show_damage_number(int(round(amount)))

	# Metin: emetti segnale quando l'HP scende sotto le soglie (per ondate di adds)
	if is_metin and not _thresholds_left.is_empty():
		var frac := current_hp / max_hp
		while not _thresholds_left.is_empty() and frac <= _thresholds_left[0]:
			var t: float = _thresholds_left.pop_front()
			hp_threshold_crossed.emit(self, t)

	if current_hp <= 0.0:
		_die()

func setup_metin(thresholds: Array = [0.75, 0.5, 0.25]) -> void:
	"""Configura questo nemico come pietra Metin: statico + soglie HP per ondate."""
	is_metin = true
	is_static = true
	_thresholds_left = thresholds.duplicate()

func _flash_hit() -> void:
	if not is_instance_valid(sprite):
		return
	sprite.modulate = Color(2.0, 2.0, 2.0)  # flash bianco
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", _base_modulate, 0.14)

func _show_damage_number(dmg: int) -> void:
	# Aggiunta al parent (ActiveEnemies) così sopravvive alla morte del nemico.
	var parent := get_parent()
	if parent:
		DAMAGE_NUMBER.create_at_position(parent, position + Vector2(0, -20), dmg, false, false)

func is_alive() -> bool:
	return state != EnemyState.DEAD and current_hp > 0.0

func _die() -> void:
	state = EnemyState.DEAD
	current_hp = 0.0
	died.emit(self)
	queue_free()

# ==================== HELPERS ====================

func _set_state(s: EnemyState) -> void:
	if state == s:
		return
	state = s
	# Indicatore di aggro: visibile mentre insegue/attacca il player
	if is_instance_valid(_aggro_mark):
		_aggro_mark.visible = (s == EnemyState.CHASING or s == EnemyState.ATTACKING)
	if GameLogger.ENABLED:
		print("[Enemy2D:%s] → %s" % [enemy_id, EnemyState.keys()[s]])

func get_enemy_name() -> String:
	return str(stats.get("name", enemy_id))
