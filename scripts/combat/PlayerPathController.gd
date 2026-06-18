# scripts/combat/PlayerPathController.gd
# Corpo fisico del player nel sistema combat top-down.
# State machine: IDLE → FOLLOWING_PATH → DEVIATING → ENGAGING → RETURNING
# Coordinate: tutto in LOCAL space (relativo a GameWorld) — resize-proof.
# La DetectionArea e CombatRangeArea sono configurate nel .tscn.

extends CharacterBody2D
class_name PlayerCharacter

enum PlayerState {
	IDLE,
	FOLLOWING_PATH,
	DEVIATING,
	ENGAGING,
	RETURNING,
	GATHERING
}

signal state_changed(new_state: PlayerState)
signal entered_combat(enemy: Node2D)
signal exited_combat()

# ==================== EXPORT ====================

@export var move_speed: float          = 150.0
@export var waypoint_reach_dist: float = 20.0
# Distanza a cui il player si ferma davanti al nodo per raccogliere
@export var gather_stop_dist: float    = 60.0

# ==================== NODES (configurati nel .tscn) ====================

@onready var sprite: Sprite2D         = $PlayerSprite
@onready var detection_area: Area2D   = $DetectionArea
@onready var combat_range_area: Area2D = $CombatRangeArea
# NavigationAgent2D presente ma NON usato per il path (Step 1 — riservato Step 2 ostacoli)
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# ==================== STATE ====================

var state: PlayerState = PlayerState.IDLE

# ==================== PATH ====================

var _path: Array[Vector2] = []
var _path_index: int      = 0
var _path_loop: bool      = true
var _target: Vector2      = Vector2.ZERO   # waypoint corrente o posizione nemico (LOCAL space)

# ==================== AGGRO ====================

var _target_enemy: Node2D = null

# ==================== GATHERING ====================

var _gather_node: Node2D = null

# ==================== INIT ====================

func _ready() -> void:
	# Collision layer/mask già settati nel .tscn — solo signal connections qui
	detection_area.body_entered.connect(_on_detect_enter)
	detection_area.body_exited.connect(_on_detect_exit)

# ==================== PHYSICS ====================

func _physics_process(_delta: float) -> void:
	match state:
		PlayerState.FOLLOWING_PATH: _tick_follow()
		PlayerState.DEVIATING:      _tick_deviate()
		PlayerState.ENGAGING:       _tick_engage()
		PlayerState.RETURNING:      _tick_return()
		PlayerState.GATHERING:      _tick_gather()
		_:
			velocity = Vector2.ZERO

# ==================== FOLLOWING PATH ====================

func set_path(waypoints: Array[Vector2], loop: bool = true) -> void:
	if waypoints.is_empty():
		return
	_path       = waypoints
	_path_loop  = loop
	_path_index = _nearest_wp_index()
	_set_target(_path[_path_index])
	_set_state(PlayerState.FOLLOWING_PATH)

# Cambia la rotta SENZA teletrasporto e SENZA interrompere il combattimento.
# - Se sta seguendo/tornando al path: ridirige verso il waypoint più vicino della nuova rotta.
# - Se sta combattendo (DEVIATING/ENGAGING): non tocca nulla; la nuova rotta entra
#   in vigore quando il player torna a seguire il path (dopo aver finito i nemici).
func change_path(waypoints: Array[Vector2], loop: bool = true) -> void:
	if waypoints.is_empty():
		return
	_path       = waypoints
	_path_loop  = loop
	_path_index = _nearest_wp_index()
	if state == PlayerState.FOLLOWING_PATH or state == PlayerState.RETURNING:
		_set_target(_path[_path_index])

func _tick_follow() -> void:
	if _path.is_empty():
		return
	if _reached():
		_advance_wp()
		return
	_move_toward_target()

func _advance_wp() -> void:
	_path_index += 1
	if _path_index >= _path.size():
		if _path_loop:
			_path_index = 0
		else:
			_set_state(PlayerState.IDLE)
			return
	_set_target(_path[_path_index])

# ==================== DEVIATING (aggro) ====================

func _on_detect_enter(body: Node2D) -> void:
	if not body.is_in_group("enemies"):
		return
	if state == PlayerState.ENGAGING or state == PlayerState.DEVIATING:
		return
	# I nemici hanno priorità: interrompe l'eventuale raccolta in corso
	_gather_node = null
	_target_enemy = body
	# Converti posizione del nemico in LOCAL space (relativo a GameWorld = parent del player)
	_set_target((get_parent() as Node2D).to_local(body.global_position))
	_set_state(PlayerState.DEVIATING)
	entered_combat.emit(body)

func _on_detect_exit(body: Node2D) -> void:
	if body != _target_enemy:
		return
	if state == PlayerState.DEVIATING or state == PlayerState.ENGAGING:
		_retarget_or_return()

func _tick_deviate() -> void:
	if not _is_target_valid():
		_retarget_or_return()
		return
	# Aggiorna target ogni frame (il nemico può muoversi) — LOCAL space
	_set_target((get_parent() as Node2D).to_local(_target_enemy.global_position))
	if _reached():
		velocity = Vector2.ZERO
		_set_state(PlayerState.ENGAGING)
		return
	_move_toward_target()

# ==================== ENGAGING ====================

func _tick_engage() -> void:
	velocity = Vector2.ZERO
	# Se il bersaglio è morto/sparito, passa al prossimo nemico ancora aggrato
	# (altrimenti il player resterebbe fermo finché non ne entra uno nuovo).
	if not _is_target_valid():
		_retarget_or_return()

func on_all_enemies_dead() -> void:
	_target_enemy = null
	_begin_return()
	exited_combat.emit()

# ==================== RE-TARGETING ====================

func _is_target_valid() -> bool:
	if not is_instance_valid(_target_enemy):
		return false
	if _target_enemy.has_method("is_alive") and not _target_enemy.is_alive():
		return false
	return true

# Sceglie il prossimo nemico ancora dentro l'area di aggro; se nessuno, torna al path.
func _retarget_or_return() -> void:
	var next := _nearest_enemy_in_detection()
	if next != null:
		_target_enemy = next
		_set_target((get_parent() as Node2D).to_local(next.global_position))
		_set_state(PlayerState.DEVIATING)
		entered_combat.emit(next)
	else:
		_target_enemy = null
		exited_combat.emit()
		_begin_return()

func _nearest_enemy_in_detection() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for b in detection_area.get_overlapping_bodies():
		if not is_instance_valid(b) or not b.is_in_group("enemies"):
			continue
		if b == _target_enemy:
			continue
		if b.has_method("is_alive") and not b.is_alive():
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best

# ==================== GATHERING ====================

# Chiamato dal controller quando il player è libero e c'è un nodo nelle vicinanze.
# I nemici hanno priorità: non si raccoglie mentre si combatte.
func try_gather(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if state != PlayerState.FOLLOWING_PATH and state != PlayerState.RETURNING:
		return
	_gather_node = node
	_set_state(PlayerState.GATHERING)

func is_gathering() -> bool:
	return state == PlayerState.GATHERING

func get_gather_target() -> Node2D:
	return _gather_node

func _tick_gather() -> void:
	# Nodo sparito (esaurito) → torna alla rotta
	if not is_instance_valid(_gather_node):
		_gather_node = null
		_begin_return()
		return

	var node_pos: Vector2 = (get_parent() as Node2D).to_local(_gather_node.global_position)
	var dist: float = position.distance_to(node_pos)

	if dist > gather_stop_dist:
		# Avvicìnati al nodo
		_set_target(node_pos)
		_move_toward_target()
	else:
		# Fermo davanti al nodo: il GatheringNode2D raccoglie da solo per prossimità
		velocity = Vector2.ZERO

# ==================== RETURNING ====================

func _begin_return() -> void:
	if _path.is_empty():
		_set_state(PlayerState.IDLE)
		return
	var nearest = _nearest_wp_index()
	_path_index = nearest
	_set_target(_path[nearest])
	_set_state(PlayerState.RETURNING)

func _tick_return() -> void:
	if _path.is_empty():
		return
	if _reached():
		_set_state(PlayerState.FOLLOWING_PATH)
		_advance_wp()
		return
	_move_toward_target()

# ==================== MOVIMENTO (LOCAL space) ====================

func _set_target(t: Vector2) -> void:
	_target = t

func _reached() -> bool:
	# Confronto in LOCAL space: position è relativa a GameWorld, _target anche
	return position.distance_to(_target) <= waypoint_reach_dist

func _move_toward_target() -> void:
	# Usa il NavigationAgent2D per girare attorno ad acqua/ostacoli (nav-mesh).
	# Fallback in linea retta se la nav non è pronta / nessun percorso valido.
	var dir: Vector2
	if nav_agent != null and _nav_usable():
		nav_agent.target_position = (get_parent() as Node2D).to_global(_target)
		if not nav_agent.is_navigation_finished():
			var next_g := nav_agent.get_next_path_position()
			dir = (next_g - global_position).normalized()
		else:
			dir = (_target - position).normalized()
	else:
		# direction in LOCAL space = GLOBAL (GameWorld non ha rotazione/scala)
		dir = (_target - position).normalized()
	velocity = dir * move_speed
	move_and_slide()
	if sprite and dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0

func _nav_usable() -> bool:
	# La nav è utilizzabile se esiste una mappa di navigazione attiva con regioni.
	var map := nav_agent.get_navigation_map()
	return map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0

# ==================== HELPERS ====================

func _nearest_wp_index() -> int:
	if _path.is_empty():
		return 0
	var best_i    = 0
	var best_dist = position.distance_to(_path[0])
	for i in range(1, _path.size()):
		var d = position.distance_to(_path[i])
		if d < best_dist:
			best_dist = d
			best_i    = i
	return best_i

func _set_state(s: PlayerState) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
	if GameLogger.ENABLED:
		print("[Player] → %s" % PlayerState.keys()[s])

# ==================== PUBLIC ====================

func get_state() -> PlayerState:
	return state

func is_in_combat() -> bool:
	return state == PlayerState.ENGAGING or state == PlayerState.DEVIATING

func get_path_copy() -> Array[Vector2]:
	return _path.duplicate()
