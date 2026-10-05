extends Control
class_name ZoneCombatController3D
## Controller della zona di combattimento 3D (port di ZoneCombatController, stessa API pubblica e
## stessi segnali, così BattleTab e SkillCastController lo usano allo stesso modo).
## Il mondo 3D vive nel SubViewport; le rotte restano salvate in pixel (1 m = 64 px), condivise col 2D.

signal zone_exited()
signal combat_started()
signal combat_ended()

const PX := 64.0
const DEFAULT_ZONE_SCENE := "res://scenes/world3d/zones/red_plains_3d.tscn"
const RouteManagerScript := preload("res://scripts/world3d/combat/RouteManager.gd")
const PATH_COLOR := Color(0.3, 0.95, 0.45, 0.55)

const GATHERING_MAX_NODES := 2
const GATHERING_RESPAWN_DELAY := 8.0
const GATHERING_ATTRACT_RANGE := 170.0 / PX
const WAVE_COUNT_MIN := 3
const WAVE_COUNT_MAX := 6
const SPAWN_MAX_DIST_FROM_PLAYER := 520.0 / PX
const SPAWN_MIN_DIST_FROM_PLAYER := 200.0 / PX
## Le skill partono solo con nemici entro questo raggio (il player sta davvero ingaggiando)
const COMBAT_RADIUS := 160.0 / PX

@onready var _exit_button: Button = $HudBar/HudInner/ExitButton
@onready var _state_label: Label = $HudBar/HudInner/StateLabel
@onready var _zone_label: Label = $HudBar/HudInner/ZoneLabel
@onready var _route_option: OptionButton = $HudBar/HudInner/RouteOption
@onready var _draw_button: Button = $HudBar/HudInner/DrawButton
@onready var _save_route_button: Button = $HudBar/HudInner/SaveRouteButton
@onready var _cancel_route_button: Button = $HudBar/HudInner/CancelRouteButton
@onready var _follow_check: CheckBox = $HudBar/HudInner/FollowCheck
@onready var _draw_overlay: Control = $DrawOverlay
@onready var _sub_viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var _sub_container: SubViewportContainer = $SubViewportContainer
@onready var world: Node3D = $SubViewportContainer/SubViewport/World

var zone_data: Dictionary = {}
var current_route: Dictionary = {}
var zone_id: String = ""

var zone: Zone3D
var player: PlayerCharacter3D
var camera_rig: CameraRig3D
var active_enemies: Node3D
var path_display: Node3D

var _enemies: Array = []
var _route_manager = RouteManagerScript.new()
var _available_routes: Array = []
var _draw_mode: bool = false
var _draft: Array[Vector3] = []
var _gathering_nodes: Array = []
var _spawn_points: Array = []
var _use_spawn_points: bool = false
var _sp_entities: Dictionary = {}
var _skill_controller = null


func _ready() -> void:
	_exit_button.pressed.connect(func() -> void: zone_exited.emit())
	_route_option.item_selected.connect(_on_route_selected)
	_draw_button.pressed.connect(_toggle_draw_mode)
	_save_route_button.pressed.connect(_save_draft_route)
	_cancel_route_button.pressed.connect(_cancel_draw)
	_draw_overlay.gui_input.connect(_on_overlay_input)
	_follow_check.toggled.connect(_on_follow_toggled)
	active_enemies = Node3D.new()
	active_enemies.name = "ActiveEnemies"
	world.add_child(active_enemies)
	path_display = Node3D.new()
	path_display.name = "PathDisplay"
	world.add_child(path_display)
	player = PlayerCharacter3D.new()
	player.name = "Player"
	world.add_child(player)
	camera_rig = CameraRig3D.new()
	camera_rig.target = player
	world.add_child(camera_rig)
	camera_rig.follow = _follow_check.button_pressed
	camera_rig.pan_started.connect(func() -> void: _set_follow(false))


func _process(_delta: float) -> void:
	_maybe_attract_to_gathering()


# ==================== SETUP ====================

func setup(p_zone: Dictionary, route: Dictionary) -> void:
	zone_data = p_zone
	zone_id = str(p_zone.get("id", ""))
	if _zone_label:
		_zone_label.text = p_zone.get("name", "")
	var map := world.get_world_3d().navigation_map
	var iteration_before := NavigationServer3D.map_get_iteration_id(map)
	var scene_path := str(p_zone.get("scene_3d", ""))
	_load_zone(scene_path if scene_path != "" and ResourceLoader.exists(scene_path) else DEFAULT_ZONE_SCENE)
	camera_rig.bounds = zone.land_rect()
	await _wait_navigation(iteration_before)

	_available_routes = _route_manager.get_routes(zone_id, p_zone.get("default_routes", []))
	if _available_routes.is_empty():
		_available_routes = [route]
	var sel_idx := _selected_route_index()
	current_route = _available_routes[sel_idx]
	_populate_route_dropdown(sel_idx)
	_connect_player()
	_apply_route(true)
	if GameLogger.ENABLED:
		print("[ZoneCombat3D] Zona '%s' — rotta '%s', %d rotte" % [p_zone.get("name", "?"), current_route.get("name", "?"), _available_routes.size()])
	_setup_spawn_points()
	if not _use_spawn_points:
		_spawn_wave()
		_populate_gathering_nodes()


func _load_zone(path: String) -> void:
	if zone and is_instance_valid(zone):
		zone.queue_free()
	zone = (load(path) as PackedScene).instantiate()
	world.add_child(zone)
	world.move_child(zone, 0)


## Aspetta che la mappa di navigazione contenga la navmesh della zona appena caricata
## (si costruisce in Zone3D._ready e il server la sincronizza al frame di fisica successivo)
func _wait_navigation(iteration_before: int) -> void:
	var map := world.get_world_3d().navigation_map
	var cells := zone.terrain().land_cells()
	var probe := Vector3.ZERO
	if not cells.is_empty():
		probe = Vector3(cells[0].x + 0.5, 0.0, cells[0].y + 0.5)
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) <= iteration_before:
			continue
		# pronta quando un punto sull'erba si trova davvero sulla navmesh
		var q := NavigationServer3D.map_get_closest_point(map, probe)
		if Vector2(q.x - probe.x, q.z - probe.z).length() < 0.75:
			return
	push_warning("[ZoneCombat3D] Navigazione non pronta dopo 120 frame")


## Collega il sistema di skill automatiche: quando lancia una skill parte l'animazione del warrior
func set_skill_cast_controller(scc) -> void:
	if _skill_controller and _skill_controller.skill_cast_started.is_connected(_on_skill_cast_started):
		_skill_controller.skill_cast_started.disconnect(_on_skill_cast_started)
	_skill_controller = scc
	if scc:
		scc.skill_cast_started.connect(_on_skill_cast_started)


func _on_skill_cast_started(skill) -> void:
	if is_instance_valid(player) and visible:
		player.play_cast(str(skill.id))


# ==================== CAMERA ====================

func _on_follow_toggled(pressed: bool) -> void:
	camera_rig.follow = pressed
	if pressed:
		camera_rig.reset_pan()


func _set_follow(on: bool) -> void:
	camera_rig.follow = on
	if is_instance_valid(_follow_check):
		_follow_check.set_pressed_no_signal(on)


# ==================== ROTTE ====================

func _selected_route_index() -> int:
	var sel_id: String = _route_manager.get_selected_route_id(zone_id)
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


func change_route(route: Dictionary) -> void:
	current_route = route
	_apply_route()


## Waypoint della rotta in metri (le rotte sono salvate in pixel come nel 2D), agganciati alla navmesh
func _route_to_path(route: Dictionary) -> Array[Vector3]:
	var path: Array[Vector3] = []
	for wp in route.get("waypoints", []):
		var p2 := Vector2.ZERO
		if wp is Vector2:
			p2 = wp
		elif wp is Array and wp.size() >= 2:
			p2 = Vector2(float(wp[0]), float(wp[1]))
		elif wp is Dictionary:
			p2 = Vector2(float(wp.get("x", 0.0)), float(wp.get("y", 0.0)))
		path.append(_snap_to_nav(Vector3(p2.x / PX, 0.0, p2.y / PX)))
	return path


func _snap_to_nav(p: Vector3) -> Vector3:
	var map := world.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var q := NavigationServer3D.map_get_closest_point(map, p)
		return Vector3(q.x, 0.0, q.z)
	return p


func _apply_route(teleport: bool = false) -> void:
	var path := _route_to_path(current_route)
	if path.is_empty():
		push_warning("[ZoneCombat3D] Rotta senza waypoint")
		return
	var loop: bool = current_route.get("loop", true)
	if teleport:
		player.global_position = path[0]
		player.set_path(path, loop)
	else:
		player.change_path(path, loop)
	_draw_path(path, loop)


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
	_clear_path_display()


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
		var hit = _screen_to_ground((event as InputEventMouseButton).position)
		if hit != null:
			_draft.append(hit)
			_draw_path(_draft, false)


func _cancel_draw() -> void:
	_exit_draw_mode()
	_draw_path(_route_to_path(current_route), bool(current_route.get("loop", true)))


func _save_draft_route() -> void:
	if _draft.size() < 2:
		_cancel_draw()
		return
	var wps: Array = []
	for p in _draft:
		wps.append({"x": p.x * PX, "y": p.z * PX})
	var custom_count := 0
	for r in _available_routes:
		if r.get("is_custom", false):
			custom_count += 1
	var route := {"id": "custom_%d" % Time.get_ticks_msec(), "name": "Rotta Custom %d" % (custom_count + 1), "loop": true, "waypoints": wps}
	_route_manager.save_custom_route(zone_id, route)
	var norm := route.duplicate()
	norm["is_custom"] = true
	_available_routes.append(norm)
	_exit_draw_mode()
	_populate_route_dropdown(_available_routes.size() - 1)
	current_route = norm
	_route_manager.set_selected_route_id(zone_id, str(norm["id"]))
	_apply_route()


## Punto sul terreno (Y = 0) sotto una posizione dell'overlay, null se il raggio non lo tocca
func _screen_to_ground(local_pos: Vector2) -> Variant:
	if _sub_container.size.x == 0.0 or _sub_container.size.y == 0.0:
		return null
	var vp_pos := local_pos * (Vector2(_sub_viewport.size) / _sub_container.size)
	var cam := camera_rig.camera
	var origin := cam.project_ray_origin(vp_pos)
	var dir := cam.project_ray_normal(vp_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


## Posizione schermo (coordinate globali della UI) di un punto del mondo 3D, per gli orb di loot/xp/oro
func _world_to_screen(world_pos: Vector3) -> Vector2:
	var vp_size := Vector2(_sub_viewport.size)
	if vp_size.x == 0.0 or vp_size.y == 0.0:
		return _sub_container.global_position
	var vp_pos := camera_rig.camera.unproject_position(world_pos)
	return _sub_container.global_position + vp_pos * (_sub_container.size / vp_size)


func _clear_path_display() -> void:
	for c in path_display.get_children():
		c.queue_free()


func _draw_path(waypoints: Array[Vector3], loop: bool) -> void:
	_clear_path_display()
	if waypoints.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = PATH_COLOR
	mat.no_depth_test = true
	var im := ImmediateMesh.new()
	if waypoints.size() > 1:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for p in waypoints:
			im.surface_add_vertex(p + Vector3(0, 0.05, 0))
		if loop:
			im.surface_add_vertex(waypoints[0] + Vector3(0, 0.05, 0))
		im.surface_end()
		var lines := MeshInstance3D.new()
		lines.mesh = im
		lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		path_display.add_child(lines)
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.12
	dot_mesh.bottom_radius = 0.12
	dot_mesh.height = 0.02
	dot_mesh.radial_segments = 12
	for p in waypoints:
		var dot := MeshInstance3D.new()
		dot.mesh = dot_mesh
		dot.material_override = mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.position = p + Vector3(0, 0.04, 0)
		path_display.add_child(dot)


# ==================== SPAWN A ONDATE (zone senza spawn point) ====================

func _spawn_wave() -> void:
	_clear_enemies()
	var pool: Array = zone_data.get("enemies", [])
	if pool.is_empty():
		push_warning("[ZoneCombat3D] Zona senza nemici")
		return
	var lvl_range: Array = zone_data.get("level_range", [1, 1])
	for i in range(randi_range(WAVE_COUNT_MIN, WAVE_COUNT_MAX)):
		_spawn_enemy(str(pool.pick_random()), randi_range(int(lvl_range[0]), int(lvl_range[lvl_range.size() - 1])), _random_spawn_pos())


func _spawn_enemy(enemy_id: String, lvl: int, pos: Vector3) -> Enemy3D:
	var enemy := Enemy3D.new()
	active_enemies.add_child(enemy)
	enemy.global_position = pos
	enemy.setup(enemy_id, lvl, player)
	enemy.died.connect(_on_enemy_died)
	_enemies.append(enemy)
	return enemy


func _random_spawn_pos() -> Vector3:
	var pp := player.global_position
	for _attempt in range(40):
		var ang := randf() * TAU
		var p := pp + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(SPAWN_MIN_DIST_FROM_PLAYER, SPAWN_MAX_DIST_FROM_PLAYER)
		if _is_on_land(p):
			return _snap_to_nav(p)
	return _snap_to_nav(pp + Vector3(SPAWN_MIN_DIST_FROM_PLAYER, 0, 0))


func _is_on_land(p: Vector3) -> bool:
	return zone.terrain().is_land(Vector2i(floori(p.x), floori(p.z)))


# ==================== SPAWN POINT (stile Metin2) ====================

func _setup_spawn_points() -> void:
	_spawn_points = zone.spawn_points()
	_sp_entities.clear()
	_use_spawn_points = not _spawn_points.is_empty()
	for sp in _spawn_points:
		_activate_spawn_point(sp)


func _sp_random_pos(sp: SpawnPoint3D) -> Vector3:
	for _i in range(24):
		var ang := randf() * TAU
		var p := sp.global_position + Vector3(cos(ang), 0.0, sin(ang)) * sqrt(randf()) * sp.spawn_radius
		if _is_on_land(p):
			return _snap_to_nav(p)
	return _snap_to_nav(sp.global_position)


func _activate_spawn_point(sp: SpawnPoint3D) -> void:
	if not is_instance_valid(sp):
		return
	match sp.kind:
		SpawnPoint3D.Kind.MOB: _sp_spawn_mob_group(sp)
		SpawnPoint3D.Kind.METIN: _sp_spawn_metin(sp)
		SpawnPoint3D.Kind.RESOURCE: _sp_spawn_resource(sp)


func _sp_spawn_mob_group(sp: SpawnPoint3D) -> void:
	var arr: Array = []
	var pool: Array = sp.enemy_ids if not sp.enemy_ids.is_empty() else ["lupo"]
	for _i in range(max(1, sp.count)):
		var e := _spawn_enemy(str(pool.pick_random()), randi_range(sp.level_min, sp.level_max), _sp_random_pos(sp))
		e.set_meta("spawn_point", sp)
		arr.append(e)
	_sp_entities[sp] = arr


func _sp_spawn_metin(sp: SpawnPoint3D) -> void:
	var metin := _spawn_enemy(sp.metin_id, randi_range(sp.level_min, sp.level_max), _snap_to_nav(sp.global_position))
	metin.setup_metin()
	metin.set_meta("spawn_point", sp)
	metin.hp_threshold_crossed.connect(_on_metin_threshold)
	_sp_entities[sp] = [metin]


func _on_metin_threshold(metin, _fraction: float) -> void:
	if not metin.has_meta("spawn_point"):
		return
	var sp: SpawnPoint3D = metin.get_meta("spawn_point")
	var pool: Array = sp.metin_adds_ids if not sp.metin_adds_ids.is_empty() else ["lupo"]
	for _i in range(max(1, sp.metin_adds_count)):
		_spawn_enemy(str(pool.pick_random()), randi_range(sp.level_min, sp.level_max), _sp_random_pos(sp))


func _sp_spawn_resource(sp: SpawnPoint3D) -> void:
	var gn := _spawn_gathering_node(sp.resource_node_id, _snap_to_nav(sp.global_position))
	if gn == null:
		return
	gn.set_meta("spawn_point", sp)
	gn.depleted.connect(_on_sp_resource_depleted)
	_sp_entities[sp] = [gn]


func _on_sp_resource_depleted(node) -> void:
	_gathering_nodes.erase(node)
	if node.has_meta("spawn_point"):
		var sp = node.get_meta("spawn_point")
		_sp_entities.erase(sp)
		_schedule_sp_respawn(sp)


func _on_sp_entity_removed(sp, entity) -> void:
	if not _sp_entities.has(sp):
		return
	var arr: Array = _sp_entities[sp]
	arr.erase(entity)
	if arr.is_empty():
		_sp_entities.erase(sp)
		_schedule_sp_respawn(sp)


func _schedule_sp_respawn(sp) -> void:
	if not is_instance_valid(sp):
		return
	await get_tree().create_timer(maxf(1.0, sp.respawn_time)).timeout
	if is_inside_tree() and visible and is_instance_valid(sp):
		_activate_spawn_point(sp)


func _on_enemy_died(enemy) -> void:
	if is_instance_valid(enemy):
		_spawn_reward_orbs(enemy)
	_enemies.erase(enemy)
	if _use_spawn_points and enemy.has_meta("spawn_point"):
		_on_sp_entity_removed(enemy.get_meta("spawn_point"), enemy)
		return
	if _enemies.is_empty():
		_on_wave_cleared()


# ==================== RICOMPENSE (orb XP/oro/loot, gli stessi del 2D) ====================

func _spawn_reward_orbs(enemy) -> void:
	var drops: Dictionary = EnemyDatabase.calculate_drops(enemy.enemy_id, enemy.level)
	var screen_pos := _world_to_screen(enemy.global_position + Vector3(0, 0.6, 0))
	var xp_mgr = get_node_or_null("/root/XpOrbManager")
	var gold_mgr = get_node_or_null("/root/GoldOrbManager")
	var loot_mgr = get_node_or_null("/root/LootOrbManager")
	if xp_mgr and int(drops.get("xp", 0)) > 0:
		xp_mgr.spawn_xp_orbs(int(drops["xp"]), screen_pos)
	if gold_mgr and int(drops.get("gold", 0)) > 0:
		gold_mgr.spawn_gold_orbs(int(drops["gold"]), screen_pos)
	if loot_mgr:
		for item_id in drops.get("items", []):
			var item_data := _get_item_data(str(item_id))
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


# ==================== RACCOLTA ====================

func _maybe_attract_to_gathering() -> void:
	if not visible or not is_instance_valid(player) or _gathering_nodes.is_empty():
		return
	var st := player.get_state()
	if st != PlayerCharacter3D.PlayerState.FOLLOWING_PATH and st != PlayerCharacter3D.PlayerState.RETURNING:
		return
	var nearest = null
	var best := INF
	for gn in _gathering_nodes:
		if not is_instance_valid(gn) or gn.is_depleted():
			continue
		var d := Vector2(gn.global_position.x - player.global_position.x, gn.global_position.z - player.global_position.z).length()
		if d <= GATHERING_ATTRACT_RANGE and d < best:
			best = d
			nearest = gn
	if nearest != null:
		player.try_gather(nearest)


func _spawn_gathering_node(node_type: String, pos: Vector3) -> GatheringNode3D:
	var db = get_node_or_null("/root/GatheringDatabase")
	if db == null:
		return null
	var node_data: Dictionary = db.get_node_data(node_type)
	if node_data.is_empty():
		return null
	var gn := GatheringNode3D.new()
	world.add_child(gn)
	gn.global_position = pos
	gn.setup(node_data, player)
	_gathering_nodes.append(gn)
	return gn


func _populate_gathering_nodes() -> void:
	var db = get_node_or_null("/root/GatheringDatabase")
	if db == null:
		return
	while _gathering_nodes.size() < GATHERING_MAX_NODES:
		var types: Array = zone_data.get("gathering_node_types", [])
		var t: String = str(types.pick_random()) if not types.is_empty() else db.get_random_node_type()
		var path := _route_to_path(current_route)
		var base: Vector3 = path.pick_random() if not path.is_empty() else player.global_position
		var pos := _snap_to_nav(base + Vector3(randf_range(-1.4, 1.4), 0, randf_range(-1.4, 1.4)))
		var gn := _spawn_gathering_node(t, pos)
		if gn == null:
			break
		gn.depleted.connect(_on_gathering_node_depleted)


func _on_gathering_node_depleted(node) -> void:
	_gathering_nodes.erase(node)
	await get_tree().create_timer(GATHERING_RESPAWN_DELAY).timeout
	if is_inside_tree() and visible:
		_populate_gathering_nodes()


func _clear_gathering_nodes() -> void:
	for gn in _gathering_nodes:
		if is_instance_valid(gn):
			gn.queue_free()
	_gathering_nodes.clear()


# ==================== BERSAGLI (interfaccia per SkillCastController) ====================

func _alive_enemies_near_player() -> Array:
	var result: Array = []
	if not is_instance_valid(player):
		return result
	for e in _enemies:
		if is_instance_valid(e) and e.is_alive():
			var d := Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()
			if d <= COMBAT_RADIUS:
				result.append(e)
	return result


func get_alive_enemy_count() -> int:
	return _alive_enemies_near_player().size()


func get_random_alive_enemy():
	var near := _alive_enemies_near_player()
	return null if near.is_empty() else near.pick_random()


func get_all_alive_enemies() -> Array:
	return _alive_enemies_near_player()


func get_alive_enemies() -> Array:
	var alive: Array = []
	for e in _enemies:
		if is_instance_valid(e) and e.is_alive():
			alive.append(e)
	return alive


func _on_wave_cleared() -> void:
	combat_ended.emit()
	if is_instance_valid(player):
		player.on_all_enemies_dead()
	if _use_spawn_points:
		return
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree() and visible:
		_spawn_wave()


func _clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()


func clear_combat() -> void:
	_clear_enemies()
	_clear_gathering_nodes()


# ==================== PLAYER ====================

func _connect_player() -> void:
	if not player.state_changed.is_connected(_on_player_state_changed):
		player.state_changed.connect(_on_player_state_changed)
		player.entered_combat.connect(func(_e) -> void: combat_started.emit())
		player.exited_combat.connect(func() -> void: combat_ended.emit())


func _on_player_state_changed(s: PlayerCharacter3D.PlayerState) -> void:
	if _state_label:
		_state_label.text = "Player: %s" % PlayerCharacter3D.PlayerState.keys()[s]
