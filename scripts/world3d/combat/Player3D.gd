class_name PlayerCharacter3D
extends Node3D
## Player del combattimento 3D (port di PlayerPathController, stessa API e stessi stati).
## IDLE → FOLLOWING_PATH → DEVIATING → ENGAGING → RETURNING, più GATHERING.
## Muove con la navigazione 3D; la parte visiva è WarriorVisual. Le animazioni di attacco/skill
## partono quando SkillCastController lancia una skill (play_cast), come nel gioco 2D i danni.
## Fa anche da esecutore degli eventi delle skill (gruppo "skill_event_driver"): danni, stordimento, buff
## e cure partono negli eventi dell'animazione (SkillFx3D + SkillEvents3D), con i loro effetti visivi.

enum PlayerState {
	IDLE,
	FOLLOWING_PATH,
	DEVIATING,
	ENGAGING,
	RETURNING,
	GATHERING
}

signal state_changed(new_state: PlayerState)
signal entered_combat(enemy: Node3D)
signal exited_combat()

const PX := 64.0
## skill del database -> animazione (Guardia e Grido di Battaglia dei loadout vecchi usano quelle del nuovo set)
const SKILL_ANIMS := SkillEvents3D.SKILL_ANIMS
## Avanzamento durante il giro del Vortice della Spada
const VORTEX_ADVANCE := 0.8
## Sibilare: distanza dal bordo del bersaglio a cui si ferma lo scatto, e lunghezza massima
const DASH_GAP := 0.3
const DASH_MAX := 4.0
## Se il combattimento lancia una skill ma l'animazione non parte (scena nascosta), gli eventi si applicano subito
const EVENTS_FALLBACK_MS := 250

@export var move_speed: float = 150.0 / PX
@export var waypoint_reach_dist: float = 20.0 / PX
@export var gather_stop_dist: float = 60.0 / PX
## Raggio di aggro (DetectionArea del 2D: 180 px)
@export var detection_radius: float = 180.0 / PX
## Distanza dal bordo del nemico a cui si ferma per combattere (si somma al raggio del nemico)
@export var engage_dist: float = 0.6

var state: PlayerState = PlayerState.IDLE
var visual: WarriorVisual
var nav_agent: NavigationAgent3D

var _path: Array[Vector3] = []
var _path_index: int = 0
var _path_loop: bool = true
var _target: Vector3 = Vector3.ZERO
var _target_enemy: Node3D = null
var _gather_node: Node3D = null
var _action_lock: bool = false
var _lock_until_ms: int = 0
var _attack_flip: bool = false
var _moving: bool = false


## Il warrior indossa l'equipaggiamento del gioco (GameState) e si aggiorna quando cambia
@export var sync_with_game_state: bool = true

var equipment_sync: EquipmentSync3D
## Effetti delle skill sincronizzati con le animazioni
var fx: SkillFx3D

var _queued: Dictionary = {}   # skill in arrivo da SkillCastController: skill_id, targets, callback, ms
var _run: Dictionary = {}      # skill in corso: skill_id, anim, targets, callback
var _dash_active: bool = false
var _dash_from: Vector3
var _dash_to: Vector3
var _spin_active: bool = false
var _spin_from: Vector3
var _spin_dir: Vector3


func _ready() -> void:
	visual = WarriorVisual.new()
	var use_game_state := sync_with_game_state and get_node_or_null("/root/GameState") != null
	visual.equip_defaults = not use_game_state
	add_child(visual)
	if use_game_state:
		equipment_sync = EquipmentSync3D.new(visual)
		add_child(equipment_sync)
	visual.animation_done.connect(_on_visual_animation_done)
	fx = SkillFx3D.new()
	fx.name = "SkillFx"
	fx.setup(visual, get_parent() as Node3D)
	visual.add_child(fx)
	fx.skill_event.connect(_on_skill_event)
	add_to_group(SkillCastController.EVENT_DRIVER_GROUP)
	nav_agent = NavigationAgent3D.new()
	nav_agent.radius = 0.25
	nav_agent.path_desired_distance = 0.3
	nav_agent.target_desired_distance = 0.3
	add_child(nav_agent)


func _process(_delta: float) -> void:
	# posizione per lo shader delle chiome trasparenti (toon.gdshader, fade_occluder)
	RenderingServer.global_shader_parameter_set("player_world_pos", global_position)
	if not _queued.is_empty() and Time.get_ticks_msec() - int(_queued["ms"]) > EVENTS_FALLBACK_MS:
		_apply_queued_now()


func _physics_process(delta: float) -> void:
	_moving = false
	if not is_visible_in_tree():
		return
	_scan_aggro()
	match state:
		PlayerState.FOLLOWING_PATH: _tick_follow(delta)
		PlayerState.DEVIATING: _tick_deviate(delta)
		PlayerState.ENGAGING: _tick_engage()
		PlayerState.RETURNING: _tick_return(delta)
		PlayerState.GATHERING: _tick_gather(delta)
	_apply_skill_motion()
	_update_animation()


# ==================== FOLLOWING PATH ====================

func set_path(waypoints: Array[Vector3], loop: bool = true) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_loop = loop
	_path_index = _nearest_wp_index()
	_set_target(_path[_path_index])
	_set_state(PlayerState.FOLLOWING_PATH)


## Cambia rotta senza teletrasporto e senza interrompere il combattimento (come nel 2D)
func change_path(waypoints: Array[Vector3], loop: bool = true) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_loop = loop
	_path_index = _nearest_wp_index()
	if state == PlayerState.FOLLOWING_PATH or state == PlayerState.RETURNING:
		_set_target(_path[_path_index])


func _tick_follow(delta: float) -> void:
	if _path.is_empty():
		return
	if _reached(waypoint_reach_dist):
		_advance_wp()
		return
	_move_toward_target(delta)


func _advance_wp() -> void:
	_path_index += 1
	if _path_index >= _path.size():
		if _path_loop:
			_path_index = 0
		else:
			_set_state(PlayerState.IDLE)
			return
	_set_target(_path[_path_index])


# ==================== AGGRO (DetectionArea del 2D) ====================

func _scan_aggro() -> void:
	if state == PlayerState.ENGAGING or state == PlayerState.DEVIATING:
		if is_instance_valid(_target_enemy) and _flat_dist(_target_enemy.global_position) > detection_radius * 1.1:
			_retarget_or_return()
		return
	if state == PlayerState.IDLE and _path.is_empty():
		return
	var e := _nearest_enemy_in_detection(null)
	if e != null:
		# I nemici hanno priorità: interrompe la raccolta
		_gather_node = null
		_target_enemy = e
		_set_target(e.global_position)
		_set_state(PlayerState.DEVIATING)
		entered_combat.emit(e)


func _tick_deviate(delta: float) -> void:
	if not _is_target_valid():
		_retarget_or_return()
		return
	_set_target(_target_enemy.global_position)
	if _reached(_engage_reach()):
		_set_state(PlayerState.ENGAGING)
		return
	_move_toward_target(delta)


func _tick_engage() -> void:
	if not _is_target_valid():
		_retarget_or_return()
		return
	# se il nemico si allontana un po', lo raggiunge di nuovo
	if _flat_dist(_target_enemy.global_position) > _engage_reach() * 1.5:
		_set_state(PlayerState.DEVIATING)
		return
	visual.face_direction(_target_enemy.global_position - global_position)


func _engage_reach() -> float:
	var r := 0.4
	if is_instance_valid(_target_enemy) and _target_enemy.has_method("get_radius"):
		r = _target_enemy.get_radius()
	return engage_dist + r


func on_all_enemies_dead() -> void:
	_target_enemy = null
	_begin_return()
	exited_combat.emit()


func _is_target_valid() -> bool:
	if not is_instance_valid(_target_enemy):
		return false
	if _target_enemy.has_method("is_alive") and not _target_enemy.is_alive():
		return false
	return true


func _retarget_or_return() -> void:
	var next := _nearest_enemy_in_detection(_target_enemy)
	if next != null:
		_target_enemy = next
		_set_target(next.global_position)
		_set_state(PlayerState.DEVIATING)
		entered_combat.emit(next)
	else:
		_target_enemy = null
		exited_combat.emit()
		_begin_return()


func _nearest_enemy_in_detection(exclude: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(b) or b == exclude:
			continue
		if b.has_method("is_alive") and not b.is_alive():
			continue
		var d := _flat_dist((b as Node3D).global_position)
		if d <= detection_radius and d < best_d:
			best_d = d
			best = b
	return best


# ==================== GATHERING ====================

func try_gather(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if state != PlayerState.FOLLOWING_PATH and state != PlayerState.RETURNING:
		return
	_gather_node = node
	_set_state(PlayerState.GATHERING)


func is_gathering() -> bool:
	return state == PlayerState.GATHERING


func get_gather_target() -> Node3D:
	return _gather_node


func _tick_gather(delta: float) -> void:
	if not is_instance_valid(_gather_node) or (_gather_node.has_method("is_depleted") and _gather_node.is_depleted()):
		_gather_node = null
		_begin_return()
		return
	if _flat_dist(_gather_node.global_position) > gather_stop_dist:
		_set_target(_gather_node.global_position)
		_move_toward_target(delta)
	else:
		visual.face_direction(_gather_node.global_position - global_position)


# ==================== RETURNING ====================

func _begin_return() -> void:
	if _path.is_empty():
		_set_state(PlayerState.IDLE)
		return
	_path_index = _nearest_wp_index()
	_set_target(_path[_path_index])
	_set_state(PlayerState.RETURNING)


func _tick_return(delta: float) -> void:
	if _path.is_empty():
		return
	if _reached(waypoint_reach_dist):
		_set_state(PlayerState.FOLLOWING_PATH)
		_advance_wp()
		return
	_move_toward_target(delta)


# ==================== MOVIMENTO ====================

func _set_target(t: Vector3) -> void:
	_target = Vector3(t.x, 0.0, t.z)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _reached(dist: float) -> bool:
	return _flat_dist(_target) <= dist


func _move_toward_target(delta: float) -> void:
	var dir: Vector3
	if _nav_usable():
		nav_agent.target_position = _target
		if not nav_agent.is_navigation_finished():
			dir = nav_agent.get_next_path_position() - global_position
		else:
			dir = _target - global_position
	else:
		dir = _target - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		# nessun percorso dalla navigazione: va dritto come nel 2D
		dir = _target - global_position
		dir.y = 0.0
	if dir.length() < 0.0001:
		return
	var speed := move_speed * (fx.move_speed_multiplier() if fx else 1.0)
	var step := minf(speed * delta, dir.length())
	global_position += dir.normalized() * step
	global_position.y = 0.0
	visual.face_direction(dir)
	_moving = true


func _nav_usable() -> bool:
	var map := nav_agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0


# ==================== ANIMAZIONE ====================

## Chiamato quando SkillCastController lancia una skill: parte l'animazione corrispondente
func play_cast(skill_id: String) -> void:
	var anim := ""
	if skill_id == "basic_attack":
		anim = "attack2" if _attack_flip else "attack1"
		_attack_flip = not _attack_flip
	else:
		anim = SKILL_ANIMS.get(skill_id, "attack1")
	_lock(2500)
	# prima l'animazione (gli eventi rimasti della skill precedente partono con la loro callback), poi la nuova skill
	visual.play(anim, 0.08, true)
	_dash_active = false
	_spin_active = false
	if not _queued.is_empty() and str(_queued["skill_id"]) == skill_id:
		_run = {"skill_id": skill_id, "anim": anim, "targets": _queued["targets"], "callback": _queued["callback"]}
		_queued = {}
	else:
		_run = {"skill_id": skill_id, "anim": anim, "targets": [], "callback": Callable()}
	if skill_id == "hiss" and _run_target() != null:
		visual.face_direction(_run_target().global_position - global_position)


# ==================== EVENTI DELLE SKILL (esecutore per SkillCastController) ====================

## SkillCastController usa questo player per applicare danni/buff/cure negli eventi delle animazioni
func accepts_skill_events() -> bool:
	return is_inside_tree() and is_visible_in_tree() and fx != null


## Skill appena lanciata: la callback applica il gameplay di un evento e restituisce il risultato
func queue_skill_events(skill_id: String, targets: Array, callback: Callable) -> void:
	if not _queued.is_empty():
		_apply_queued_now()
	_queued = {"skill_id": skill_id, "targets": targets, "callback": callback, "ms": Time.get_ticks_msec()}


func _on_skill_event(anim_base: String, event_name: String, index: int) -> void:
	var result := {}
	if not _run.is_empty() and str(_run["anim"]) == anim_base:
		var cb: Callable = _run["callback"]
		if cb.is_valid():
			result = cb.call(event_name, index)
	if fx:
		fx.on_event_result(anim_base, event_name, index, result)


## L'animazione non è partita (scena nascosta, nessun play_cast): applica subito tutti gli eventi
func _apply_queued_now() -> void:
	var q := _queued
	_queued = {}
	var cb: Callable = q.get("callback", Callable())
	if not cb.is_valid():
		return
	var skill_id := str(q["skill_id"])
	var anim := visual.styled_animation("attack1" if skill_id == "basic_attack" else SkillEvents3D.anim_for_skill(skill_id))
	for ev in SkillEvents3D.events(anim):
		cb.call(ev[1], ev[2])


## Volontà di Vivere: nemici nel cono davanti al warrior, i più vicini per primi
func filter_cone_targets(candidates: Array, cone_range: float, cone_angle_deg: float, max_targets: int) -> Array:
	var fwd := fx.forward() if fx else Vector3.FORWARD
	var half := deg_to_rad(cone_angle_deg) * 0.5
	var picked: Array = []
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		var d := (c as Node3D).global_position - global_position
		d.y = 0.0
		var r: float = c.get_radius() if c.has_method("get_radius") else 0.3
		if d.length() > cone_range + r:
			continue
		if d.length() > r + 0.2 and absf(fwd.angle_to(d.normalized())) > half:
			continue
		picked.append(c)
	picked.sort_custom(func(a, b) -> bool:
		return _flat_dist((a as Node3D).global_position) < _flat_dist((b as Node3D).global_position))
	return picked.slice(0, max_targets)


func _run_target() -> Node3D:
	if _run.is_empty():
		return null
	for t in _run["targets"]:
		if is_instance_valid(t) and t is Node3D and (not t.has_method("is_alive") or t.is_alive()):
			return t
	return null


## Spostamenti delle skill: scatto di Sibilare sul bersaglio, avanzamento del Vortice (sempre sulla navmesh)
func _apply_skill_motion() -> void:
	if fx == null:
		return
	var dash := fx.window_progress("dash")
	var target := _run_target()
	if dash >= 0.0 and target != null:
		if not _dash_active:
			_dash_active = true
			_dash_from = global_position
			var to := target.global_position - global_position
			to.y = 0.0
			var r: float = target.get_radius() if target.has_method("get_radius") else 0.3
			var dist := clampf(to.length() - r - DASH_GAP, 0.0, DASH_MAX)
			_dash_to = global_position + (to.normalized() * dist if to.length() > 0.001 else Vector3.ZERO)
		visual.face_direction(target.global_position - global_position)
		_move_safely(_dash_from.lerp(_dash_to, ease(dash, 0.6)))
	else:
		_dash_active = false
	var spin := fx.window_progress("spin")
	if spin >= 0.0:
		if not _spin_active:
			_spin_active = true
			_spin_from = global_position
			_spin_dir = fx.forward()
		_move_safely(_spin_from + _spin_dir * VORTEX_ADVANCE * smoothstep(0.0, 1.0, spin))
	else:
		_spin_active = false


## Sposta il warrior solo dove si può camminare: niente acqua né fuori dalla navmesh
func _move_safely(p: Vector3) -> void:
	p.y = 0.0
	if _nav_usable():
		var q := NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), p)
		if Vector2(q.x - p.x, q.z - p.z).length() > 0.3:
			return
		p = Vector3(q.x, 0.0, q.z)
	global_position = p


## Colpo ricevuto: piccola reazione se non sta già facendo un'azione
func on_hit_taken(amount: float) -> void:
	FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.5, 0), "-%d" % int(round(amount)), FloatingText3D.PLAYER_DAMAGE, 56)
	if not _action_lock and state == PlayerState.ENGAGING:
		_lock(1000)
		visual.play("hit", 0.05, true)


## Blocca le animazioni di movimento finché l'azione non finisce (con scadenza di sicurezza)
func _lock(max_ms: int) -> void:
	_action_lock = true
	_lock_until_ms = Time.get_ticks_msec() + max_ms


func _on_visual_animation_done(_anim_name: String) -> void:
	_action_lock = false


func _update_animation() -> void:
	if _action_lock and Time.get_ticks_msec() < _lock_until_ms:
		return
	_action_lock = false
	if _moving:
		visual.play("run")
	elif state == PlayerState.GATHERING and is_instance_valid(_gather_node):
		visual.play("gather")
	else:
		visual.play("idle")


# ==================== HELPERS / PUBBLICO ====================

func _nearest_wp_index() -> int:
	if _path.is_empty():
		return 0
	var best_i := 0
	var best_d := _flat_dist(_path[0])
	for i in range(1, _path.size()):
		var d := _flat_dist(_path[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _set_state(s: PlayerState) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
	if GameLogger.ENABLED:
		print("[Player3D] → %s" % PlayerState.keys()[s])


func get_state() -> PlayerState:
	return state


func is_in_combat() -> bool:
	return state == PlayerState.ENGAGING or state == PlayerState.DEVIATING


func get_path_copy() -> Array[Vector3]:
	return _path.duplicate()
