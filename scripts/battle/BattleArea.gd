# File: res://scripts/battle/BattleArea.gd
# Gestisce i 7 enemy slots usando spawn points visuali

extends Control
class_name BattleArea

# const LOG removed - using GameLogger

const ENEMY_SLOT_SCENE_PATH := "res://scenes/battle/EnemySlot.tscn"
const GridLayoutManager = preload("res://scripts/battle/GridLayoutManager.gd")
const BackgroundManager = preload("res://scripts/battle/BackgroundManager.gd")

var enemy_slot_scene: PackedScene = null
var background_manager: BackgroundManager = null
var current_battlefield: Control = null  # The instantiated battlefield scene

@onready var spawn_points: Control = $SpawnPoints
@onready var background_texture: TextureRect = $BackgroundTexture

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

# Background system configuration
@export_group("Background System")
@export var use_background_system: bool = true
@export var debug_background_key: String = ""  # Leave empty for random, or specify "m1_z1_1" to test specific background

var enemy_slots: Array[EnemySlot] = []
var current_target_slot: EnemySlot = null

signal enemy_targeted(slot: EnemySlot)
signal enemy_killed(slot: EnemySlot)
signal all_enemies_dead()

var slots_created: bool = false

func _ready() -> void:
	print("[BattleArea] 🟢 === INITIALIZATION START ===")
	print("[BattleArea] _ready() - BattleArea size: ", size)

	# Safety check for @onready nodes (might be null in tests)
	if background_texture:
		print("[BattleArea] _ready() - BackgroundTexture size: ", background_texture.size)
		print("[BattleArea] _ready() - BackgroundTexture expand_mode: ", background_texture.expand_mode)
		print("[BattleArea] _ready() - BackgroundTexture stretch_mode: ", background_texture.stretch_mode)
	else:
		push_warning("[BattleArea] BackgroundTexture node not found (test environment?)")

	print("[BattleArea] use_background_system: ", use_background_system)
	print("[BattleArea] use_grid_layout: ", use_grid_layout)

	if not _load_enemy_slot_scene():
		push_error("[BattleArea] Impossibile caricare EnemySlot scene!")
		return

	# Initialize background system
	if use_background_system:
		background_manager = BackgroundManager.new()
		add_child(background_manager)
		await get_tree().process_frame
		_setup_random_background()

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

	# Initialize enemy slots after background is loaded
	if not slots_created:
		await _initialize_slots()

	print("[BattleArea] 🟢 === INITIALIZATION COMPLETE ===")
	print("[BattleArea] slots_created: ", slots_created)
	print("[BattleArea] enemy_slots.size(): ", enemy_slots.size())
	print("[BattleArea] current_battlefield: ", current_battlefield != null)
	print("[BattleArea] background_manager: ", background_manager != null)
	print("[BattleArea] Ready")

func _setup_random_background() -> void:
	"""Setup random background by loading its battlefield scene"""
	if not background_manager:
		push_error("[BattleArea] Background manager not found!")
		return

	# Select background (random or specific for debug)
	var bg_config: Dictionary
	if debug_background_key != "":
		bg_config = background_manager.get_background_by_key(debug_background_key)
		if GameLogger.ENABLED:
			print("[BattleArea] Using DEBUG background: %s" % debug_background_key)
	else:
		bg_config = background_manager.get_random_background()

	if bg_config.is_empty():
		push_error("[BattleArea] Failed to load background configuration!")
		return

	# Load battlefield scene (contains spawn points)
	current_battlefield = background_manager.load_battlefield_scene()
	if not current_battlefield:
		push_error("[BattleArea] Failed to load battlefield scene!")
		return

	# Load and set background texture
	var texture_path = bg_config.get("texture_path", "")
	if texture_path != "" and ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		if texture:
			background_texture.texture = texture
			print("[BattleArea] ✅ Background loaded: %s" % bg_config.get("key", "unknown"))
			print("[BattleArea] → %s" % bg_config.get("description", ""))
		else:
			push_error("[BattleArea] Failed to load texture: %s" % texture_path)
	else:
		push_warning("[BattleArea] No valid texture_path in background config")

	if GameLogger.ENABLED:
		print("[BattleArea] ✅ Battlefield loaded with spawn points")

func _initialize_slots() -> void:
	if slots_created:
		print("[BattleArea] Slots already created, skipping")
		return

	print("\n[BattleArea] === INITIALIZING SLOTS ===")
	print("[BattleArea] use_background_system: ", use_background_system)
	print("[BattleArea] background_manager: ", background_manager)
	print("[BattleArea] current_battlefield: ", current_battlefield)
	print("[BattleArea] use_grid_layout: ", use_grid_layout)
	print("[BattleArea] grid_manager: ", grid_manager)

	# Use background spawn points if background system is enabled
	if use_background_system and background_manager:
		print("[BattleArea] → Using background spawn points")
		await _create_enemy_slots_from_background()
	elif use_grid_layout and grid_manager:
		print("[BattleArea] → Using grid layout")
		await _create_enemy_slots_grid()
	else:
		print("[BattleArea] → Using fallback spawn points")
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

func _create_enemy_slots_from_background() -> void:
	"""Create enemy slots using spawn points from battlefield scene"""
	print("[BattleArea] _create_enemy_slots_from_background() called")
	print("[BattleArea] current_battlefield: ", current_battlefield)

	if not current_battlefield:
		push_error("[BattleArea] No battlefield loaded!")
		return

	# Get SpawnPoints container from battlefield scene
	var spawn_points_container = current_battlefield.get_node_or_null("SpawnPoints")
	print("[BattleArea] spawn_points_container: ", spawn_points_container)

	if not spawn_points_container:
		push_error("[BattleArea] SpawnPoints node not found in battlefield scene!")
		print("[BattleArea] Available children in current_battlefield:")
		for child in current_battlefield.get_children():
			print("[BattleArea]   - ", child.name, " (", child.get_class(), ")")
		return

	# Collect spawn point nodes
	var spawn_nodes: Array = []

	# Boss spawn first
	var boss_spawn = spawn_points_container.get_node_or_null("BossSpawn")
	if boss_spawn:
		print("[BattleArea] Found BossSpawn at: ", boss_spawn.position)
		spawn_nodes.append({"node": boss_spawn, "is_boss": true})

	# Then normal spawns (Spawn1 through Spawn11)
	print("[BattleArea] Looking for normal spawn points...")
	for i in range(1, 12):  # Spawn1 to Spawn11
		var spawn_node = spawn_points_container.get_node_or_null("Spawn%d" % i)
		if spawn_node:
			print("[BattleArea] Found Spawn%d at: %s" % [i, spawn_node.position])
			spawn_nodes.append({"node": spawn_node, "is_boss": false})

	print("[BattleArea] Total spawn nodes found: ", spawn_nodes.size())

	if spawn_nodes.is_empty():
		push_error("[BattleArea] No spawn nodes found in battlefield!")
		print("[BattleArea] Available children in SpawnPoints:")
		for child in spawn_points_container.get_children():
			print("[BattleArea]   - ", child.name, " (", child.get_class(), ")")
		return

	if GameLogger.ENABLED:
		print("[BattleArea] Creating %d slots from battlefield spawn points" % spawn_nodes.size())

	# Create enemy slots at spawn point positions
	for i in range(spawn_nodes.size()):
		var spawn_data = spawn_nodes[i]
		var spawn_node = spawn_data.node as Control
		var is_boss = spawn_data.is_boss

		var slot: EnemySlot = enemy_slot_scene.instantiate() as EnemySlot
		if slot == null:
			push_error("[BattleArea] Failed to instantiate slot %d" % (i + 1))
			continue

		var slot_size: Vector2 = boss_slot_size if is_boss else normal_slot_size

		# Get global position of spawn point, convert to local
		var target_pos = spawn_node.global_position

		# Adjust position to center the slot on the spawn point
		target_pos.x -= slot_size.x / 2
		target_pos.y -= slot_size.y / 2

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
			var slot_type = "BOSS" if is_boss else "Normal"
			print("[BattleArea] Creating %s slot %d at spawn pos %s" % [slot_type, i + 1, target_pos])

		add_child(slot)
		await get_tree().process_frame

		if GameLogger.ENABLED:
			print("[BattleArea] Slot %d positioned: pos=%s, global=%s" % [i + 1, slot.position, slot.global_position])

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
	print("[BattleArea] _on_resized() - New BattleArea size: ", size)
	print("[BattleArea] _on_resized() - BackgroundTexture size: ", background_texture.size)

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
	print("[BattleArea] 💀 ENEMY DIED - Starting XP orb spawn")  # FORCED LOG

	if current_target_slot == slot:
		current_target_slot = null
		_auto_target_first_alive()

	# Spawn XP orbs from dead enemy
	_spawn_xp_orbs_from_enemy(slot)

	enemy_killed.emit(slot)

	if _all_enemies_dead():
		all_enemies_dead.emit()

func _all_enemies_dead() -> bool:
	for slot in enemy_slots:
		if slot.is_enemy_alive():
			return false
	return true

func _spawn_xp_orbs_from_enemy(slot: EnemySlot) -> void:
	"""Spawn XP orbs from defeated enemy"""
	print("[BattleArea] 🔧 _spawn_xp_orbs_from_enemy() CALLED")  # FORCED LOG

	if not slot or not is_instance_valid(slot):
		print("[BattleArea] ❌ Slot is null or invalid!")  # FORCED LOG
		return

	# Get death position
	var death_position = slot.global_position + Vector2(slot.slot_width / 2, slot.slot_height / 2)

	# Calculate XP based on enemy level
	var enemy_level = slot.enemy_level if slot.enemy_level > 0 else 1
	var base_xp = enemy_level * 15
	var bonus_xp = randi_range(int(enemy_level * 3), int(enemy_level * 8))
	var total_xp = base_xp + bonus_xp

	# Boss bonus (if applicable)
	if slot.enemy_name.contains("Boss") or slot.enemy_name.contains("King") or slot.enemy_name.contains("Alpha"):
		total_xp = int(total_xp * 1.5)

	print("[BattleArea] 💚 Spawning %d XP orbs at %s (enemy: %s, level: %d)" % [total_xp, death_position, slot.enemy_name, enemy_level])  # FORCED LOG

	# Spawn XP orbs via XpOrbManager
	var xp_orb_manager = get_node_or_null("/root/XpOrbManager")
	if xp_orb_manager:
		print("[BattleArea] ✅ XpOrbManager found, calling spawn_xp_orbs()")  # FORCED LOG
		xp_orb_manager.spawn_xp_orbs(total_xp, death_position)
	else:
		print("[BattleArea] ⚠️ XpOrbManager NOT FOUND! Using fallback")  # FORCED LOG
		# Fallback: add XP directly
		var gs = get_node_or_null("/root/GameState")
		if gs and gs.character_stats and gs.character_stats.level_system:
			gs.character_stats.level_system.add_exp(total_xp)
			print("[BattleArea] ✅ Added XP directly via fallback: %d" % total_xp)  # FORCED LOG

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

# ==================== BACKGROUND SYSTEM ====================

func change_background(background_key: String = "") -> void:
	"""
	Change to a new background (random if empty key)
	Note: This will NOT recreate enemy slots, only change the visual background
	"""
	print("[BattleArea] change_background called with key: '", background_key, "'")
	print("[BattleArea] use_background_system: ", use_background_system)
	print("[BattleArea] background_manager: ", background_manager)

	if not use_background_system or not background_manager:
		push_warning("[BattleArea] Background system not enabled!")
		return

	var bg_config: Dictionary
	if background_key != "":
		print("[BattleArea] Getting background by key: ", background_key)
		bg_config = background_manager.get_background_by_key(background_key)
	else:
		print("[BattleArea] Getting random background")
		bg_config = background_manager.get_random_background()

	print("[BattleArea] bg_config: ", bg_config)
	print("[BattleArea] bg_config.is_empty(): ", bg_config.is_empty())

	if bg_config.is_empty():
		push_error("[BattleArea] Failed to load background: %s" % background_key)
		return

	# Load and apply new background texture
	var texture_path = bg_config.get("texture_path", "")
	print("[BattleArea] texture_path: ", texture_path)
	print("[BattleArea] ResourceLoader.exists: ", ResourceLoader.exists(texture_path) if texture_path != "" else false)

	if texture_path != "" and ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		if texture:
			background_texture.texture = texture
			print("[BattleArea] Background texture loaded: %s" % bg_config.get("key", "unknown"))
			print("[BattleArea] Texture size: ", texture.get_size())
			print("[BattleArea] BackgroundTexture rect size: ", background_texture.size)
			print("[BattleArea] BattleArea size: ", size)

			# Also load the battlefield scene for spawn points
			var scene_path = bg_config.get("scene_path", "")
			if scene_path != "" and ResourceLoader.exists(scene_path):
				print("[BattleArea] Loading battlefield scene: ", scene_path)
				current_battlefield = background_manager.load_battlefield_scene()
				if current_battlefield:
					print("[BattleArea] ✅ Battlefield scene loaded successfully")

					# Clear existing slots and recreate from new background
					if slots_created:
						print("[BattleArea] Clearing old slots and recreating from new background...")
						clear_all_slots()
						await _create_enemy_slots_from_background()
						slots_created = true
						print("[BattleArea] ✅ Slots recreated from new background")
				else:
					push_warning("[BattleArea] Failed to load battlefield scene: %s" % scene_path)
			else:
				push_warning("[BattleArea] No valid scene_path in background config")

			if GameLogger.ENABLED:
				print("[BattleArea] Background changed to: %s" % bg_config.get("key", "unknown"))
		else:
			push_error("[BattleArea] Failed to load texture: %s" % texture_path)

func get_current_background_key() -> String:
	"""Get the key of currently displayed background"""
	if not background_manager:
		return ""
	var config = background_manager.get_current_background()
	return config.get("key", "")

func get_spawn_point_positions() -> Dictionary:
	"""
	Extract spawn point positions from current battlefield scene
	Returns: {
		"normal": [Vector2, Vector2, ...],  # Spawn1-Spawn11
		"boss": Vector2 or null              # BossSpawn
	}
	"""
	var result = {
		"normal": [],
		"boss": null
	}

	if not current_battlefield:
		if GameLogger.ENABLED:
			print("[BattleArea] No battlefield loaded, cannot extract spawn points")
		return result

	var spawn_points_container = current_battlefield.get_node_or_null("SpawnPoints")
	if not spawn_points_container:
		push_error("[BattleArea] No SpawnPoints container in battlefield scene!")
		return result

	# Extract normal spawn points (Spawn1-Spawn11)
	for i in range(1, 12):
		var spawn_node = spawn_points_container.get_node_or_null("Spawn%d" % i)
		if spawn_node:
			result.normal.append(spawn_node.position)
			if GameLogger.ENABLED:
				print("[BattleArea] Found Spawn%d at: %s" % [i, spawn_node.position])

	# Extract boss spawn point
	var boss_spawn = spawn_points_container.get_node_or_null("BossSpawn")
	if boss_spawn:
		result.boss = boss_spawn.position
		if GameLogger.ENABLED:
			print("[BattleArea] Found BossSpawn at: %s" % boss_spawn.position)

	if GameLogger.ENABLED:
		print("[BattleArea] Extracted %d normal spawn points, boss: %s" % [result.normal.size(), "yes" if result.boss else "no"])

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
