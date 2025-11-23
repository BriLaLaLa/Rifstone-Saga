# File: res://scripts/battle/BattleArea.gd
# Gestisce i 7 enemy slots usando spawn points visuali

extends Control
class_name BattleArea

# const LOG removed - using GameLogger

const ENEMY_SLOT_SCENE_PATH := "res://scenes/battle/EnemySlot.tscn"
const GridLayoutManager = preload("res://scripts/battle/GridLayoutManager.gd")

var enemy_slot_scene: PackedScene = null

@onready var spawn_points: Control = $SpawnPoints

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Slot Sizes")
@export var normal_slot_size: Vector2 = Vector2(120, 140)
@export var boss_slot_size: Vector2 = Vector2(180, 200)

# Grid layout configuration
@export_group("Grid Layout")
@export var use_grid_layout: bool = true
@export var grid_rows: int = 2
@export var grid_cols: int = 3
var grid_manager: GridLayoutManager = null

var enemy_slots: Array[EnemySlot] = []
var current_target_slot: EnemySlot = null

signal enemy_targeted(slot: EnemySlot)
signal enemy_killed(slot: EnemySlot)
signal all_enemies_dead()

var slots_created: bool = false

func _ready() -> void:
	if not _load_enemy_slot_scene():
		push_error("[BattleArea] Impossibile caricare EnemySlot scene!")
		return

	# Initialize grid layout manager (usa valori dall'Inspector)
	if use_grid_layout:
		grid_manager = GridLayoutManager.new(grid_rows, grid_cols, normal_slot_size)
		# Wait for the control to be properly sized
		await get_tree().process_frame
		_update_grid_layout()

	_connect_to_gamestate()

	# Connect resize signal for responsive grid
	if use_grid_layout:
		resized.connect(_on_resized)

	print("[BattleArea] Ready")

func _initialize_slots() -> void:
	if slots_created:
		return

	print("\n[BattleArea] === INITIALIZING SLOTS ===")

	if use_grid_layout and grid_manager:
		await _create_enemy_slots_grid()
	else:
		await _create_enemy_slots_from_spawn_points()

	slots_created = true
	print("[BattleArea] ✅ %d slots created\n" % enemy_slots.size())

func _update_grid_layout() -> void:
	if not grid_manager:
		return

	var container_size = size
	if container_size == Vector2.ZERO:
		container_size = get_viewport_rect().size

	grid_manager.set_container_size(container_size)
	grid_manager.auto_adjust_spacing(Vector2(30, 30), Vector2(80, 80))

	if GameLogger.ENABLED:
		print("[BattleArea] Grid layout updated for size: %s" % container_size)
		var info = grid_manager.get_grid_info()
		print("[BattleArea] Grid: %dx%d, offset: %s" % [info.rows, info.cols, info.grid_offset])

func _load_enemy_slot_scene() -> bool:
	if not ResourceLoader.exists(ENEMY_SLOT_SCENE_PATH):
		push_error("[BattleArea] EnemySlot.tscn non trovata")
		return false

	enemy_slot_scene = load(ENEMY_SLOT_SCENE_PATH)
	return enemy_slot_scene != null

func _create_enemy_slots_grid() -> void:
	if not grid_manager:
		push_error("[BattleArea] Grid manager not initialized!")
		return

	var positions = grid_manager.get_all_positions()
	var total_slots = positions.size()

	if GameLogger.ENABLED:
		print("[BattleArea] Creating %d slots using grid layout" % total_slots)

	for i in range(total_slots):
		var slot_num = i + 1
		# Last slot is reserved for boss
		var is_boss = (slot_num == total_slots)

		var slot: EnemySlot = enemy_slot_scene.instantiate() as EnemySlot
		if slot == null:
			push_error("[BattleArea] Failed to instantiate slot %d" % slot_num)
			continue

		var slot_size: Vector2 = boss_slot_size if is_boss else normal_slot_size
		var target_pos = positions[i]

		# Setup completo PRIMA di add_child
		slot.size = slot_size
		slot.custom_minimum_size = slot_size

		# Usa offset per posizionamento manuale
		slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
		slot.anchor_left = 0
		slot.anchor_top = 0
		slot.anchor_right = 0
		slot.anchor_bottom = 0

		slot.offset_left = target_pos.x
		slot.offset_top = target_pos.y
		slot.offset_right = target_pos.x + slot_size.x
		slot.offset_bottom = target_pos.y + slot_size.y

		slot.z_index = 10

		if GameLogger.ENABLED:
			print("[BattleArea] Creating slot %d at grid pos %s" % [slot_num, target_pos])

		add_child(slot)
		await get_tree().process_frame

		if GameLogger.ENABLED:
			print("[BattleArea] Slot %d positioned: pos=%s, global=%s" % [slot_num, slot.position, slot.global_position])

		slot.enemy_clicked.connect(_on_enemy_clicked)
		slot.enemy_died.connect(_on_enemy_died)

		enemy_slots.append(slot)

func _create_enemy_slots_from_spawn_points() -> void:
	if spawn_points == null:
		push_error("[BattleArea] SpawnPoints NOT FOUND!")
		return
	
	var markers = spawn_points.get_children()
	if markers.is_empty():
		push_warning("[BattleArea] No spawn points!")
		return
	
	markers.sort_custom(func(a, b): return a.name < b.name)
	
	for i in range(markers.size()):
		var marker = markers[i] as Control
		var slot_num = i + 1
		var is_boss = (slot_num == markers.size() or "boss" in marker.name.to_lower() or marker.name == "SpawnPoint7")

		var slot: EnemySlot = enemy_slot_scene.instantiate() as EnemySlot
		if slot == null:
			push_error("[BattleArea] Failed to instantiate slot %d" % slot_num)
			continue

		var slot_size: Vector2 = boss_slot_size if is_boss else normal_slot_size
		var target_pos = marker.position
		
		# Setup completo PRIMA di add_child
		slot.size = slot_size
		slot.custom_minimum_size = slot_size
		
		# Usa offset per posizionamento manuale
		slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
		slot.anchor_left = 0
		slot.anchor_top = 0
		slot.anchor_right = 0
		slot.anchor_bottom = 0
		
		slot.offset_left = target_pos.x
		slot.offset_top = target_pos.y
		slot.offset_right = target_pos.x + slot_size.x
		slot.offset_bottom = target_pos.y + slot_size.y
		
		slot.z_index = 10
		
		if GameLogger.ENABLED:
			print("[BattleArea] Creating slot %d at marker pos %s" % [slot_num, target_pos])
		
		add_child(slot)
		await get_tree().process_frame
		
		if GameLogger.ENABLED:
			print("[BattleArea] Slot %d AFTER frame: pos=%s, global=%s" % [slot_num, slot.position, slot.global_position])
		
		slot.enemy_clicked.connect(_on_enemy_clicked)
		slot.enemy_died.connect(_on_enemy_died)
		
		enemy_slots.append(slot)

func _on_resized() -> void:
	if not use_grid_layout or not grid_manager or not slots_created:
		return

	_update_grid_layout()

	# Reposition all existing slots
	var positions = grid_manager.get_all_positions()
	for i in range(min(enemy_slots.size(), positions.size())):
		var slot = enemy_slots[i]
		var new_pos = positions[i]

		slot.offset_left = new_pos.x
		slot.offset_top = new_pos.y
		slot.offset_right = new_pos.x + slot.size.x
		slot.offset_bottom = new_pos.y + slot.size.y

		if GameLogger.ENABLED:
			print("[BattleArea] Repositioned slot %d to %s" % [i, new_pos])

func _connect_to_gamestate() -> void:
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has_signal("on_combat_event"):
			if not gs.on_combat_event.is_connected(_on_gamestate_combat_event):
				gs.on_combat_event.connect(_on_gamestate_combat_event)

# ==================== SPAWN NEMICI ====================

func spawn_wave(mob_ids: Array) -> void:
	if not slots_created:
		push_error("[BattleArea] Cannot spawn: slots not initialized!")
		return
	
	clear_all_slots()
	
	var slot_index = 0
	for mob_id in mob_ids:
		if slot_index >= enemy_slots.size():
			break
		
		var mob_data = _get_mob_data(mob_id)
		if mob_data.is_empty():
			continue
		
		var slot = enemy_slots[slot_index]
		slot.spawn_enemy(mob_id, mob_data)
		
		slot_index += 1
	
	_auto_target_first_alive()

func spawn_single_enemy(mob_id: String, slot_index: int = 0) -> void:
	if not slots_created or slot_index < 0 or slot_index >= enemy_slots.size():
		return
	
	var mob_data = _get_mob_data(mob_id)
	if mob_data.is_empty():
		return
	
	enemy_slots[slot_index].spawn_enemy(mob_id, mob_data)

func spawn_boss(boss_id: String) -> void:
	if not slots_created or enemy_slots.is_empty():
		return
	
	var boss_data = _get_mob_data(boss_id)
	if boss_data.is_empty():
		return
	
	boss_data["is_boss"] = true
	enemy_slots[-1].spawn_enemy(boss_id, boss_data)

func _get_mob_data(mob_id: String) -> Dictionary:
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has("data") and gs.data.has("mobs"):
			return gs.data.mobs.get(mob_id, {})
	return {}

# ==================== TARGETING ====================

func _on_enemy_clicked(slot: EnemySlot) -> void:
	if not slot.is_enemy_alive():
		return
	
	if current_target_slot and current_target_slot != slot:
		current_target_slot.set_targeted(false)
	
	current_target_slot = slot
	current_target_slot.set_targeted(true)
	_update_gamestate_target(slot.get_enemy_id())
	enemy_targeted.emit(slot)

func _auto_target_first_alive() -> void:
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			_on_enemy_clicked(slot)
			return

func get_current_target() -> EnemySlot:
	return current_target_slot

func _update_gamestate_target(enemy_id: String) -> void:
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has("current_target_enemy"):
			gs.set("current_target_enemy", enemy_id)

# ==================== DAMAGE ====================

func damage_current_target(amount: float) -> void:
	if current_target_slot and current_target_slot.is_enemy_alive():
		current_target_slot.take_damage(amount)

func damage_slot(slot_index: int, amount: float) -> void:
	if slot_index >= 0 and slot_index < enemy_slots.size():
		if enemy_slots[slot_index].is_enemy_alive():
			enemy_slots[slot_index].take_damage(amount)

func damage_all_enemies(amount: float) -> void:
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			slot.take_damage(amount)

# ==================== ENEMY DEATH ====================

func _on_enemy_died(slot: EnemySlot) -> void:
	if current_target_slot == slot:
		current_target_slot = null
		_auto_target_first_alive()
	
	enemy_killed.emit(slot)
	
	if _all_enemies_dead():
		all_enemies_dead.emit()

func _all_enemies_dead() -> bool:
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			return false
	return true

# ==================== CLEAR ====================

func clear_all_slots() -> void:
	if not slots_created:
		return
	
	current_target_slot = null
	for slot in enemy_slots:
		slot.clear()

# ==================== QUERY ====================

func get_alive_enemy_count() -> int:
	var count = 0
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			count += 1
	return count

func get_alive_enemies() -> Array[EnemySlot]:
	var alive: Array[EnemySlot] = []
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			alive.append(slot)
	return alive

func get_enemy_slot(slot_index: int) -> EnemySlot:
	if slot_index >= 0 and slot_index < enemy_slots.size():
		return enemy_slots[slot_index]
	return null

func _on_gamestate_combat_event(msg: String) -> void:
	pass

# ==================== TEST/DEBUG ====================

func spawn_test_wave() -> void:
	if not slots_created:
		push_error("[BattleArea] Cannot spawn test wave!")
		return
	
	print("\n[BattleArea] === SPAWNING TEST WAVE - FILLING ALL SLOTS ===")
	
	# SPAWNA UN NEMICO IN OGNI SLOT!
	for i in range(enemy_slots.size()):
		var slot = enemy_slots[i]
		
		# Determina se è un boss
		var is_boss = (i == enemy_slots.size() - 1 or i == 0)  # Primo e ultimo slot = boss
		
		var enemy_data = {
			"name": "TEST BOSS %d" % (i + 1) if is_boss else "Enemy %d" % (i + 1),
			"hp": 500.0 if is_boss else (100.0 + (i * 30)),
			"is_boss": is_boss
		}
		
		slot.spawn_enemy("enemy_%d" % i, enemy_data)
		
		if GameLogger.ENABLED:
			print("[BattleArea] Spawned '%s' in slot %d at pos=%s" % [enemy_data["name"], i, slot.position])
	
	_auto_target_first_alive()
	
	print("[BattleArea] ✅ Test wave complete - %d enemies spawned\n" % enemy_slots.size())

func get_all_enemy_slots() -> Array[EnemySlot]:
	"""Restituisce tutti gli slot nemici (vivi o morti)"""
	var result: Array[EnemySlot] = []
	for slot in enemy_slots:
		if slot != null and is_instance_valid(slot):
			result.append(slot)
	return result

# ==================== SKILL SYSTEM SUPPORT ====================

func get_random_alive_enemy():
	"""Get a random alive enemy (for single-target skills)"""
	var alive = get_alive_enemies()
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]

func get_all_alive_enemies() -> Array:
	"""Get all alive enemies (for AOE skills)"""
	var alive_array: Array = []
	for slot in get_alive_enemies():
		alive_array.append(slot)
	return alive_array

func damage_enemy(enemy, amount: float, ignore_defense: bool = false) -> void:
	"""Damage a specific enemy (for skills)"""
	if enemy and enemy.is_enemy_alive():
		# For now, EnemySlot.take_damage doesn't support ignore_defense
		# We'll just apply the damage directly
		enemy.take_damage(amount)
