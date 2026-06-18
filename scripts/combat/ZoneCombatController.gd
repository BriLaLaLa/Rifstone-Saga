# scripts/combat/ZoneCombatController.gd
# Root controller della scena combat top-down.
# Il mondo 2D vive dentro un SubViewport fisso 800×600 — il SubViewportContainer
# lo scala sulla UI automaticamente. Nessuna logica di resize necessaria.

extends Control
class_name ZoneCombatController

# ==================== SIGNALS ====================

signal zone_exited()
signal combat_started()
signal combat_ended()

# ==================== SCENE REFS (configurati nel .tscn) ====================

@onready var path_display: Node2D       = $SubViewportContainer/SubViewport/GameWorld/PathDisplay
@onready var enemy_spawn_points: Node2D = $SubViewportContainer/SubViewport/GameWorld/EnemySpawnPoints
@onready var active_enemies: Node2D     = $SubViewportContainer/SubViewport/GameWorld/ActiveEnemies
@onready var player: PlayerCharacter    = $SubViewportContainer/SubViewport/GameWorld/PlayerCharacter
@onready var game_world: Node2D         = $SubViewportContainer/SubViewport/GameWorld

@onready var _exit_button: Button = $HudBar/HudInner/ExitButton
@onready var _state_label: Label  = $HudBar/HudInner/StateLabel
@onready var _zone_label: Label   = $HudBar/HudInner/ZoneLabel
@onready var _route_option: OptionButton = $HudBar/HudInner/RouteOption
@onready var _draw_button: Button = $HudBar/HudInner/DrawButton
@onready var _save_route_button: Button = $HudBar/HudInner/SaveRouteButton
@onready var _cancel_route_button: Button = $HudBar/HudInner/CancelRouteButton
@onready var _draw_overlay: Control = $DrawOverlay

# ==================== DATA ====================

const ENEMY_SCENE := preload("res://scenes/combat/Enemy2D.tscn")
const RouteManagerScript := preload("res://scripts/combat/RouteManager.gd")
const GATHERING_NODE2D_SCENE := preload("res://scenes/combat/GatheringNode2D.tscn")

# Gathering: quanti nodi tenere vivi nella zona e cooldown di respawn
const GATHERING_MAX_NODES := 2
const GATHERING_RESPAWN_DELAY := 8.0

# Mondo fisso 800×600 — i nemici spawnano dentro questi margini.
const WORLD_SIZE := Vector2(800.0, 600.0)
const SPAWN_MARGIN := 80.0
const WAVE_COUNT_MIN := 3
const WAVE_COUNT_MAX := 6
# Distanza minima dal player allo spawn (per non aggro-are istantaneamente)
const SPAWN_MIN_DIST_FROM_PLAYER := 200.0
# Raggio entro cui le skill del player possono colpire (gating: le skill partono
# solo quando il player è davvero vicino ai nemici = sta ingaggiando)
const COMBAT_RADIUS := 160.0

var zone_data: Dictionary     = {}
var current_route: Dictionary = {}
var zone_id: String           = ""

var _enemies: Array = []  # di Enemy2D (untyped per non dipendere dal class cache)

var _route_manager = RouteManagerScript.new()
var _available_routes: Array = []

# Disegno route custom
var _draw_mode: bool = false
var _draft: Array[Vector2] = []

# Nodi di gathering vivi nel mondo
var _gathering_nodes: Array = []

# ==================== INIT ====================

func _ready() -> void:
	_exit_button.pressed.connect(func(): zone_exited.emit())
	_route_option.item_selected.connect(_on_route_selected)
	_draw_button.pressed.connect(_toggle_draw_mode)
	_save_route_button.pressed.connect(_save_draft_route)
	_cancel_route_button.pressed.connect(_cancel_draw)
	_draw_overlay.gui_input.connect(_on_overlay_input)
	_build_boundary_walls()

func setup(zone: Dictionary, route: Dictionary) -> void:
	zone_data = zone
	zone_id   = str(zone.get("id", ""))
	if _zone_label:
		_zone_label.text = zone.get("name", "")

	# Costruisci la lista route (default della zona + custom salvate)
	_available_routes = _route_manager.get_routes(zone_id, zone.get("default_routes", []))
	if _available_routes.is_empty():
		# Fallback: usa la route passata dal chiamante
		_available_routes = [route]

	# Determina la route selezionata (ricordata, altrimenti la prima)
	var sel_idx := _selected_route_index()
	current_route = _available_routes[sel_idx]

	_populate_route_dropdown(sel_idx)
	_connect_player()
	_apply_route(true)  # start: posiziona il player a inizio rotta
	if GameLogger.ENABLED:
		print("[ZoneCombatController] Zone '%s' — route '%s' (%d wp), %d route disponibili" % [
			zone.get("name", "?"),
			current_route.get("name", "?"),
			current_route.get("waypoints", []).size(),
			_available_routes.size()
		])
	_spawn_wave()
	_populate_gathering_nodes()

# ==================== ROUTE SELECTION ====================

func _selected_route_index() -> int:
	var sel_id := _route_manager.get_selected_route_id(zone_id)
	if sel_id != "":
		for i in range(_available_routes.size()):
			if str(_available_routes[i].get("id", "")) == sel_id:
				return i
	return 0

func _populate_route_dropdown(selected_idx: int) -> void:
	_route_option.clear()
	for r in _available_routes:
		_route_option.add_item(str(r.get("name", "Route")))
	if selected_idx >= 0 and selected_idx < _available_routes.size():
		_route_option.select(selected_idx)

func _on_route_selected(idx: int) -> void:
	if idx < 0 or idx >= _available_routes.size():
		return
	current_route = _available_routes[idx]
	_route_manager.set_selected_route_id(zone_id, str(current_route.get("id", "")))
	_apply_route()
	if GameLogger.ENABLED:
		print("[ZoneCombatController] Route cambiata → '%s'" % current_route.get("name", "?"))

# ==================== ROUTE DRAWING (custom) ====================

func _toggle_draw_mode() -> void:
	if _draw_mode:
		_exit_draw_mode()
	else:
		_enter_draw_mode()

func _enter_draw_mode() -> void:
	_draw_mode = true
	_draft.clear()
	_draw_overlay.visible = true
	_draw_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_route_button.visible = true
	_cancel_route_button.visible = true
	_draw_button.text = "✏ Disegnando…"
	_route_option.disabled = true
	_clear_path_display()  # nascondi la rotta attiva, mostra solo il draft

func _exit_draw_mode() -> void:
	_draw_mode = false
	_draw_overlay.visible = false
	_draw_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_route_button.visible = false
	_cancel_route_button.visible = false
	_draw_button.text = "✏ Disegna"
	_route_option.disabled = false

func _on_overlay_input(event: InputEvent) -> void:
	if not _draw_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world := _screen_to_world(event.position)
		_draft.append(world)
		_draw_path(_draft, false)  # preview (non-loop mentre disegni)

func _cancel_draw() -> void:
	_exit_draw_mode()
	_redraw_active_path()

func _save_draft_route() -> void:
	if _draft.size() < 2:
		# Pochi punti: annulla
		_cancel_draw()
		return

	var wps: Array = []
	for p in _draft:
		wps.append({"x": p.x, "y": p.y})

	var custom_count := 0
	for r in _available_routes:
		if r.get("is_custom", false):
			custom_count += 1

	var route := {
		"id":        "custom_%d" % Time.get_ticks_msec(),
		"name":      "Rotta Custom %d" % (custom_count + 1),
		"loop":      true,
		"waypoints": wps,
	}
	_route_manager.save_custom_route(zone_id, route)

	var norm := {
		"id":        route["id"],
		"name":      route["name"],
		"loop":      true,
		"waypoints": wps,
		"is_custom": true,
	}
	_available_routes.append(norm)

	_exit_draw_mode()

	# Seleziona e applica la nuova rotta (il player ci cammina, no teleport)
	_populate_route_dropdown(_available_routes.size() - 1)
	current_route = norm
	_route_manager.set_selected_route_id(zone_id, str(norm["id"]))
	_apply_route()

	if GameLogger.ENABLED:
		print("[ZoneCombatController] Rotta custom salvata: '%s' (%d wp)" % [norm["name"], wps.size()])

# Converte una posizione locale dell'overlay (= pixel arena) in coordinate mondo.
func _screen_to_world(local_pos: Vector2) -> Vector2:
	var svc := get_node_or_null("SubViewportContainer") as Control
	var sub := get_node_or_null("SubViewportContainer/SubViewport") as SubViewport
	if svc == null or sub == null or svc.size.x == 0.0 or svc.size.y == 0.0:
		return local_pos
	return local_pos * (Vector2(sub.size) / svc.size)

func _clear_path_display() -> void:
	if path_display:
		for c in path_display.get_children():
			c.queue_free()

func _redraw_active_path() -> void:
	_draw_path(_route_to_path(current_route), bool(current_route.get("loop", true)))

# ==================== ENEMY SPAWNING ====================

func _spawn_wave() -> void:
	_clear_enemies()

	var pool: Array = zone_data.get("enemies", [])
	if pool.is_empty():
		push_warning("[ZoneCombatController] Zone senza enemy pool — nessun nemico spawnato")
		return

	var lvl_range: Array = zone_data.get("level_range", [1, 1])
	var lvl_min: int = int(lvl_range[0])
	var lvl_max: int = int(lvl_range[lvl_range.size() - 1])

	var count: int = randi_range(WAVE_COUNT_MIN, WAVE_COUNT_MAX)
	for i in range(count):
		var enemy_id: String = str(pool.pick_random())
		var lvl: int = randi_range(lvl_min, lvl_max)
		_spawn_enemy(enemy_id, lvl)

	if GameLogger.ENABLED:
		print("[ZoneCombatController] Ondata: %d nemici spawnati (%d vivi)" % [count, _enemies.size()])

func _spawn_enemy(enemy_id: String, lvl: int) -> void:
	var enemy = ENEMY_SCENE.instantiate()
	active_enemies.add_child(enemy)
	enemy.position = _random_spawn_pos()
	enemy.setup(enemy_id, lvl, player)
	enemy.died.connect(_on_enemy_died)
	_enemies.append(enemy)

func _random_spawn_pos() -> Vector2:
	var player_pos: Vector2 = player.position if is_instance_valid(player) else WORLD_SIZE * 0.5
	for _attempt in range(20):
		var p := Vector2(
			randf_range(SPAWN_MARGIN, WORLD_SIZE.x - SPAWN_MARGIN),
			randf_range(SPAWN_MARGIN, WORLD_SIZE.y - SPAWN_MARGIN)
		)
		if p.distance_to(player_pos) >= SPAWN_MIN_DIST_FROM_PLAYER:
			return p
	# Fallback: angolo opposto al player
	return WORLD_SIZE - player_pos

func _on_enemy_died(enemy) -> void:
	# L'enemy è ancora valido qui (queue_free è differito): leggo dati + posizione.
	if is_instance_valid(enemy):
		_spawn_reward_orbs(enemy)
	_enemies.erase(enemy)
	if GameLogger.ENABLED:
		print("[ZoneCombatController] Nemico morto — rimasti: %d" % _enemies.size())
	if _enemies.is_empty():
		_on_wave_cleared()

# ==================== REWARDS (orb XP/Gold/Loot) ====================

func _spawn_reward_orbs(enemy) -> void:
	var drops: Dictionary = EnemyDatabase.calculate_drops(enemy.enemy_id, enemy.level)
	var screen_pos: Vector2 = _world_to_screen(enemy.global_position)

	var xp_mgr   = get_node_or_null("/root/XpOrbManager")
	var gold_mgr = get_node_or_null("/root/GoldOrbManager")
	var loot_mgr = get_node_or_null("/root/LootOrbManager")

	if xp_mgr and int(drops.get("xp", 0)) > 0:
		xp_mgr.spawn_xp_orbs(int(drops["xp"]), screen_pos)
	if gold_mgr and int(drops.get("gold", 0)) > 0:
		gold_mgr.spawn_gold_orbs(int(drops["gold"]), screen_pos)
	if loot_mgr:
		for item_id in drops.get("items", []):
			var item_data: Dictionary = _get_item_data(str(item_id))
			if not item_data.is_empty():
				loot_mgr.spawn_orb(item_data, screen_pos, str(item_data.get("rarity", "common")))

func _get_item_data(item_id: String) -> Dictionary:
	var idata = get_node_or_null("/root/IData")
	if idata and idata.has_method("get_item_data"):
		var d: Dictionary = idata.get_item_data(item_id)
		if not d.is_empty():
			var copy := d.duplicate(true)
			copy["id"] = item_id
			return copy
	return {}

# ==================== GATHERING (nodi nel mondo) ====================

func _populate_gathering_nodes() -> void:
	"""Riempie la zona fino a GATHERING_MAX_NODES nodi di raccolta."""
	while _gathering_nodes.size() < GATHERING_MAX_NODES:
		if not _spawn_gathering_node():
			break

func _spawn_gathering_node() -> bool:
	"""Spawna un singolo nodo di gathering vicino alla rotta. Ritorna false se non possibile."""
	var db = get_node_or_null("/root/GatheringDatabase")
	if db == null:
		return false

	var node_type := _pick_gathering_node_type(db)
	if node_type == "":
		return false

	var node_data: Dictionary = db.get_node_data(node_type)
	if node_data.is_empty():
		return false

	var gn = GATHERING_NODE2D_SCENE.instantiate()
	game_world.add_child(gn)
	gn.position = _gathering_spawn_pos()
	gn.setup(node_data, player)
	gn.depleted.connect(_on_gathering_node_depleted)
	_gathering_nodes.append(gn)

	if GameLogger.ENABLED:
		print("[ZoneCombatController] 🌿 Gathering node spawnato: %s @ %s" % [node_type, gn.position])
	return true

func _pick_gathering_node_type(db) -> String:
	"""Tipo di nodo: preferisce i tipi configurati per la zona, altrimenti pesi del DB."""
	var zone_types: Array = zone_data.get("gathering_node_types", [])
	if not zone_types.is_empty():
		return str(zone_types.pick_random())
	return db.get_random_node_type()

func _gathering_spawn_pos() -> Vector2:
	"""Posizione vicino a un waypoint della rotta (così il player ci passa)."""
	var path: Array[Vector2] = _route_to_path(current_route)
	var base: Vector2
	if path.is_empty():
		base = WORLD_SIZE * 0.5
	else:
		base = path.pick_random()
	# Offset casuale attorno al waypoint, poi clamp dentro i margini del mondo
	var offset := Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))
	var pos := base + offset
	pos.x = clampf(pos.x, SPAWN_MARGIN, WORLD_SIZE.x - SPAWN_MARGIN)
	pos.y = clampf(pos.y, SPAWN_MARGIN, WORLD_SIZE.y - SPAWN_MARGIN)
	return pos

func _on_gathering_node_depleted(node) -> void:
	_gathering_nodes.erase(node)
	if GameLogger.ENABLED:
		print("[ZoneCombatController] 🌿 Gathering node esaurito — respawn tra %.0fs" % GATHERING_RESPAWN_DELAY)
	# Respawn dopo un cooldown
	await get_tree().create_timer(GATHERING_RESPAWN_DELAY).timeout
	if is_inside_tree() and visible:
		_populate_gathering_nodes()

func _clear_gathering_nodes() -> void:
	for gn in _gathering_nodes:
		if is_instance_valid(gn):
			gn.queue_free()
	_gathering_nodes.clear()

# Converte una posizione del mondo (spazio SubViewport 800×600) in coordinate
# schermo, tenendo conto dello scaling del SubViewportContainer.
func _world_to_screen(world_pos: Vector2) -> Vector2:
	var svc := get_node_or_null("SubViewportContainer") as Control
	var sub := get_node_or_null("SubViewportContainer/SubViewport") as SubViewport
	if svc == null or sub == null:
		return world_pos
	var vp_size := Vector2(sub.size)
	if vp_size.x == 0.0 or vp_size.y == 0.0:
		return svc.global_position + world_pos
	var s := svc.size / vp_size
	return svc.global_position + world_pos * s

# ==================== TARGETING (interfaccia per SkillCastController) ====================
# SkillCastController interroga questi metodi come faceva con SlotManager.
# Restituiamo SOLO i nemici vivi entro COMBAT_RADIUS dal player → le skill
# partono solo quando il player sta effettivamente ingaggiando.

func _alive_enemies_near_player() -> Array:
	var result: Array = []
	if not is_instance_valid(player):
		return result
	for e in _enemies:
		if is_instance_valid(e) and e.is_alive() and e.global_position.distance_to(player.global_position) <= COMBAT_RADIUS:
			result.append(e)
	return result

func get_alive_enemy_count() -> int:
	return _alive_enemies_near_player().size()

func get_random_alive_enemy():
	var near := _alive_enemies_near_player()
	if near.is_empty():
		return null
	return near.pick_random()

func get_all_alive_enemies() -> Array:
	return _alive_enemies_near_player()

func _on_wave_cleared() -> void:
	combat_ended.emit()
	if is_instance_valid(player):
		player.on_all_enemies_dead()
	# Respawn della prossima ondata dopo una breve pausa
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree() and visible:
		_spawn_wave()

func _clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()

# Pulizia esterna quando si abbandona la zona (chiamata da BattleTab).
func clear_combat() -> void:
	_clear_enemies()
	_clear_gathering_nodes()

func get_alive_enemies() -> Array:
	var alive: Array = []
	for e in _enemies:
		if is_instance_valid(e) and e.is_alive():
			alive.append(e)
	return alive

# ==================== BOUNDARY WALLS (fissi 800×600 — costruiti una volta sola) ====================

func _build_boundary_walls() -> void:
	var t    = 20.0
	var w    = 800.0
	var h    = 600.0

	# [cx, cy, half_w, half_h]
	var defs = [
		[w * 0.5, -t * 0.5,      w * 0.5 + t, t * 0.5],  # top
		[w * 0.5,  h + t * 0.5,  w * 0.5 + t, t * 0.5],  # bottom
		[-t * 0.5,     h * 0.5,  t * 0.5, h * 0.5 + t],  # left
		[w + t * 0.5,  h * 0.5,  t * 0.5, h * 0.5 + t],  # right
	]

	var body = StaticBody2D.new()
	body.name            = "BoundaryWalls"
	body.collision_layer = 2
	body.collision_mask  = 0

	for d in defs:
		var cs   = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size   = Vector2(d[2] * 2.0, d[3] * 2.0)
		cs.shape    = rect
		cs.position = Vector2(d[0], d[1])
		body.add_child(cs)

	game_world.add_child(body)

# ==================== PLAYER ====================

func _connect_player() -> void:
	if not player:
		push_error("[ZoneCombatController] PlayerCharacter non trovato!")
		return
	if not player.state_changed.is_connected(_on_player_state_changed):
		player.state_changed.connect(_on_player_state_changed)
	if not player.entered_combat.is_connected(_on_entered_combat):
		player.entered_combat.connect(_on_entered_combat)
	if not player.exited_combat.is_connected(_on_exited_combat):
		player.exited_combat.connect(_on_exited_combat)

# teleport=true → posiziona il player al primo waypoint (solo allo start della zona).
# teleport=false → cambio rotta a caldo: il player ci cammina, senza interrompere
# l'eventuale combattimento in corso.
# Estrae i waypoint di una route come Array[Vector2] (gestisce Vector2/Array/Dict).
func _route_to_path(route: Dictionary) -> Array[Vector2]:
	var path: Array[Vector2] = []
	for wp in route.get("waypoints", []):
		if wp is Vector2:
			path.append(wp)
		elif wp is Array and wp.size() >= 2:
			path.append(Vector2(float(wp[0]), float(wp[1])))
		elif wp is Dictionary:
			path.append(Vector2(float(wp.get("x", 0.0)), float(wp.get("y", 0.0))))
	return path

func _apply_route(teleport: bool = false) -> void:
	if not player:
		return
	var path: Array[Vector2] = _route_to_path(current_route)
	if path.is_empty():
		push_warning("[ZoneCombatController] Route senza waypoints")
		return

	var loop: bool = current_route.get("loop", true)

	if teleport:
		if path.size() > 0:
			player.position = path[0]
		player.set_path(path, loop)
	else:
		player.change_path(path, loop)

	_draw_path(path, loop)

	if GameLogger.ENABLED:
		print("[ZoneCombatController] Path: %d waypoint (teleport=%s)" % [path.size(), teleport])

# ==================== PATH DISPLAY ====================

func _draw_path(waypoints: Array[Vector2], loop: bool) -> void:
	if not path_display:
		return
	for c in path_display.get_children():
		c.queue_free()

	var count = waypoints.size()
	for i in range(count):
		var a = waypoints[i]
		var b = waypoints[(i + 1) % count]

		if i + 1 < count or loop:
			var line = Line2D.new()
			line.add_point(a)
			line.add_point(b)
			line.width         = 2.0
			line.default_color = Color(0.3, 0.85, 0.4, 0.4)
			line.z_index       = -1
			path_display.add_child(line)

		var dot = ColorRect.new()
		dot.color               = Color(0.2, 0.9, 0.3, 0.85)
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size                = Vector2(10, 10)
		dot.position            = a - Vector2(5.0, 5.0)
		path_display.add_child(dot)

# ==================== CALLBACKS ====================

func _on_player_state_changed(s: PlayerCharacter.PlayerState) -> void:
	if _state_label:
		_state_label.text = "Player: %s" % PlayerCharacter.PlayerState.keys()[s]

func _on_entered_combat(_enemy: Node2D) -> void:
	combat_started.emit()

func _on_exited_combat() -> void:
	combat_ended.emit()

# ==================== ROUTE ====================

func change_route(route: Dictionary) -> void:
	current_route = route
	_apply_route()
