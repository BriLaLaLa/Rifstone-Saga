# File: res://scripts/battle/SlotManager.gd
# Manages 12 normal enemy slots + 1 boss slot
# Handles dynamic slot visibility and enemy spawning

extends Node
class_name SlotManager

# ==================== CONFIGURATION ====================

# Slot layout: 3 rows x 2 columns = 6 normal slots (reduced to avoid overlap)
const NORMAL_SLOT_ROWS: int = 3
const NORMAL_SLOT_COLS: int = 2
const MAX_NORMAL_SLOTS: int = 6  # Reduced from 12 to prevent overlap
const MAX_BOSS_SLOTS: int = 1

# Slot size and spacing (UPDATED to match new EnemySlot size)
const SLOT_SIZE: Vector2 = Vector2(180, 220)  # Match EnemySlot dimensions
const SLOT_SPACING: Vector2 = Vector2(20, 20)  # More space between slots

# ==================== SLOTS ====================

# Slot arrays
var normal_slots: Array[Panel] = []
var boss_slot: Panel = null

# Slot occupancy
var normal_slot_enemies: Array = []  # Array of EnemySlot nodes
var boss_slot_enemy = null  # EnemySlot node

# ==================== REFERENCES ====================

var container: Control = null  # Parent container
var spawn_positions: Dictionary = {}  # Spawn point positions from background scene

# Track enemy death positions for loot orb spawning
var last_enemy_death_positions: Array[Vector2] = []

# ==================== SIGNALS ====================

signal slot_clicked(slot_index: int, is_boss: bool)
signal all_enemies_cleared()
signal enemy_killed(enemy_data: Dictionary, death_position: Vector2)  # Emitted when each enemy dies

# ==================== INITIALIZATION ====================

func _init():
	pass

func setup(parent_container: Control, spawn_points: Dictionary = {}) -> void:
	"""
	Setup slot manager with parent container and optional spawn points
	spawn_points format: {
		"normal": [Vector2, Vector2, ...],  # Spawn1-Spawn11
		"boss": Vector2 or null              # BossSpawn
	}
	"""
	container = parent_container
	spawn_positions = spawn_points

	if GameLogger.ENABLED:
		print("[SlotManager] Setting up slots in container: %s" % container.name)
		if not spawn_positions.is_empty():
			print("[SlotManager] Using %d spawn points from background scene" % spawn_positions.get("normal", []).size())
		else:
			print("[SlotManager] Using default hardcoded positions (no spawn points provided)")

	_create_slots()

	if GameLogger.ENABLED:
		print("[SlotManager] Created %d normal slots + %d boss slot" % [normal_slots.size(), 1])

func _create_slots() -> void:
	"""Create all slot UI elements"""
	if not container:
		push_error("[SlotManager] No container set!")
		return

	# Create boss slot (top center)
	_create_boss_slot()

	# Create normal slots (grid below boss)
	_create_normal_slots()

# ==================== BOSS SLOT ====================

func _create_boss_slot() -> void:
	"""Create the single boss slot (larger, centered)"""
	boss_slot = Panel.new()
	boss_slot.name = "BossSlot"
	boss_slot.custom_minimum_size = SLOT_SIZE * 1.5  # 50% larger than normal slots
	boss_slot.visible = false  # Hidden by default

	# Style - Completely invisible (no background, no border)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent background
	style.border_width_left = 0  # No border
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	boss_slot.add_theme_stylebox_override("panel", style)

	# Position: use spawn point if available, otherwise default to top center
	if spawn_positions.has("boss") and spawn_positions.boss != null:
		boss_slot.position = spawn_positions.boss
		if GameLogger.ENABLED:
			print("[SlotManager] Boss slot using spawn point position: %s" % boss_slot.position)
	else:
		boss_slot.position = Vector2(
			(NORMAL_SLOT_COLS * (SLOT_SIZE.x + SLOT_SPACING.x)) / 2 - (SLOT_SIZE.x * 1.5) / 2,
			0
		)
		if GameLogger.ENABLED:
			print("[SlotManager] Boss slot using default position: %s" % boss_slot.position)

	container.add_child(boss_slot)

	if GameLogger.ENABLED:
		print("[SlotManager] Boss slot created at position: %s" % boss_slot.position)

# ==================== NORMAL SLOTS ====================

func _create_normal_slots() -> void:
	"""Create 6 normal slots with scattered/depth layout (updated for 180x220 slots)"""

	# Check if we have spawn points from background scene
	var use_spawn_points = spawn_positions.has("normal") and not spawn_positions.normal.is_empty()

	# 🚨 WARNING if no spawn points (Thursday Bug Detection)
	if not use_spawn_points:
		push_warning("[SlotManager] ⚠️⚠️⚠️ NO SPAWN POINTS RECEIVED!")
		push_warning("[SlotManager] This is the 'Thursday Bug' - BattleArea didn't provide spawn points")
		push_warning("[SlotManager] Falling back to hardcoded positions")
		if GameLogger.ENABLED:
			print("[SlotManager] 🐛 DEBUG: spawn_positions = ", spawn_positions)

	var positions_to_use = []

	if use_spawn_points:
		# Use spawn points from background scene (limit to MAX_NORMAL_SLOTS)
		positions_to_use = spawn_positions.normal.slice(0, MAX_NORMAL_SLOTS)
		if GameLogger.ENABLED:
			print("[SlotManager] ✅ Using %d spawn points from background scene" % positions_to_use.size())
	else:
		# Fallback to hardcoded scattered positions
		positions_to_use = [
			# Front row (larger, bottom) - 2 slots
			Vector2(80, 340),   # Left front
			Vector2(440, 340),  # Right front

			# Mid row (medium size, middle) - 2 slots
			Vector2(50, 180),   # Left mid
			Vector2(380, 180),  # Right mid

			# Back row (smaller, top) - 2 slots
			Vector2(150, 40),   # Left back
			Vector2(340, 40)    # Right back
		]
		if GameLogger.ENABLED:
			print("[SlotManager] ⚠️ Using default hardcoded positions")

	# Define sizes based on depth (front = larger, back = smaller)
	# If using spawn points, use uniform size; if default, use depth effect
	var slot_sizes = []
	if use_spawn_points:
		# Uniform size when using spawn points
		for i in range(positions_to_use.size()):
			slot_sizes.append(SLOT_SIZE * 1.0)
	else:
		# Depth effect for default positions
		slot_sizes = [
			SLOT_SIZE * 1.0,   # Front row
			SLOT_SIZE * 1.0,
			SLOT_SIZE * 0.85,  # Mid row
			SLOT_SIZE * 0.85,
			SLOT_SIZE * 0.70,  # Back row
			SLOT_SIZE * 0.70
		]

	for i in range(positions_to_use.size()):
		var slot = Panel.new()
		slot.name = "NormalSlot_%d" % i
		slot.custom_minimum_size = slot_sizes[i]
		slot.visible = false  # Hidden by default

		# Style - Completely invisible (no background, no border)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent background
		style.border_width_left = 0  # No border
		style.border_width_right = 0
		style.border_width_top = 0
		style.border_width_bottom = 0
		slot.add_theme_stylebox_override("panel", style)

		# Position from spawn points or default
		slot.position = positions_to_use[i]

		# Z-index for depth (front = higher z, back = lower z)
		if i < 4:
			slot.z_index = 30  # Front row
		elif i < 8:
			slot.z_index = 20  # Mid row
		else:
			slot.z_index = 10  # Back row

		container.add_child(slot)
		normal_slots.append(slot)

		if GameLogger.ENABLED:
			print("[SlotManager] Created slot %d at position: %s" % [i, slot.position])

	if GameLogger.ENABLED:
		print("[SlotManager] Created %d normal slots" % normal_slots.size())

# ==================== ENCOUNTER SPAWNING ====================

func spawn_encounter(encounter: Dictionary) -> void:
	"""Spawn enemies based on encounter type"""
	# Clear existing enemies first
	clear_all_slots()
	clear_enemy_positions()  # ADDITION: Clear old death positions

	match encounter["type"]:
		"normal":
			_spawn_normal_encounter(encounter)
		"miniboss":
			_spawn_miniboss_encounter(encounter)
		"metin":
			_spawn_metin_encounter(encounter)
		_:
			push_error("[SlotManager] Invalid encounter type: %s" % encounter["type"])

func _spawn_normal_encounter(encounter: Dictionary) -> void:
	"""Spawn normal encounter: 3-12 enemies in normal slots"""
	var enemies = encounter.get("enemies", [])

	if GameLogger.ENABLED:
		print("[SlotManager] Spawning normal encounter: %d enemies" % enemies.size())

	# Boss slot stays hidden
	boss_slot.visible = false

	# Spawn enemies in normal slots (left to right, top to bottom)
	for i in range(min(enemies.size(), MAX_NORMAL_SLOTS)):
		var enemy_data = enemies[i]
		_spawn_enemy_in_normal_slot(i, enemy_data)

func _spawn_miniboss_encounter(encounter: Dictionary) -> void:
	"""Spawn miniboss encounter: 1 boss + 1-3 companions"""
	var boss = encounter.get("boss", null)
	var companions = encounter.get("companions", [])

	if GameLogger.ENABLED:
		print("[SlotManager] Spawning miniboss encounter: 1 boss + %d companions" % companions.size())

	# Spawn boss in boss slot
	if boss:
		_spawn_enemy_in_boss_slot(boss)

	# Spawn companions in normal slots
	for i in range(min(companions.size(), MAX_NORMAL_SLOTS)):
		var companion_data = companions[i]
		_spawn_enemy_in_normal_slot(i, companion_data)

func _spawn_metin_encounter(encounter: Dictionary) -> void:
	"""Spawn metin encounter: 1 metin only"""
	var metin = encounter.get("metin", null)

	if GameLogger.ENABLED:
		print("[SlotManager] Spawning metin encounter: Solo metin")

	# Spawn metin in boss slot
	if metin:
		_spawn_enemy_in_boss_slot(metin)

	# All normal slots stay hidden (no companions)

# ==================== ENEMY SPAWNING ====================

func _spawn_enemy_in_normal_slot(slot_index: int, enemy_data: Dictionary) -> void:
	"""Spawn enemy in a specific normal slot"""
	if slot_index < 0 or slot_index >= normal_slots.size():
		push_error("[SlotManager] Invalid normal slot index: %d" % slot_index)
		return

	var slot = normal_slots[slot_index]
	slot.visible = true

	# Create enemy slot (reuse existing EnemySlot class)
	var enemy_slot = _create_enemy_slot(enemy_data, false)

	# NO anchors - use direct positioning instead
	enemy_slot.position = Vector2.ZERO
	enemy_slot.size = slot.custom_minimum_size

	slot.add_child(enemy_slot)

	# Store reference
	if normal_slot_enemies.size() <= slot_index:
		normal_slot_enemies.resize(slot_index + 1)
	normal_slot_enemies[slot_index] = enemy_slot

	# Connect enemy_died signal (connect after add_child so it's in tree)
	if enemy_slot.has_signal("enemy_died"):
		enemy_slot.enemy_died.connect(_on_enemy_died_in_slot.bind(slot_index, false))

	if GameLogger.ENABLED:
		print("[SlotManager] Spawned %s (Lv%d) in normal slot %d" %
			[enemy_data.get("type", "unknown"), enemy_data.get("level", 1), slot_index])

func _spawn_enemy_in_boss_slot(enemy_data: Dictionary) -> void:
	"""Spawn enemy in boss slot"""
	boss_slot.visible = true

	# Create enemy slot
	var enemy_slot = _create_enemy_slot(enemy_data, true)

	# NO anchors - use direct positioning instead
	enemy_slot.position = Vector2.ZERO
	enemy_slot.size = boss_slot.custom_minimum_size

	boss_slot.add_child(enemy_slot)

	# Store reference
	boss_slot_enemy = enemy_slot

	# Connect enemy_died signal (connect after add_child so it's in tree)
	if enemy_slot.has_signal("enemy_died"):
		enemy_slot.enemy_died.connect(_on_enemy_died_in_slot.bind(-1, true))

	if GameLogger.ENABLED:
		print("[SlotManager] Spawned %s (Lv%d) in BOSS slot" %
			[enemy_data.get("type", "unknown"), enemy_data.get("level", 1)])

func _create_enemy_slot(enemy_data: Dictionary, is_boss: bool) -> Control:
	"""Create enemy slot UI using existing EnemySlot class"""

	# Load EnemySlot scene
	var enemy_slot_scene = load("res://scenes/battle/EnemySlot.tscn")
	if not enemy_slot_scene:
		push_error("[SlotManager] Failed to load EnemySlot scene!")
		# Fallback to simple label
		var label = Label.new()
		label.text = "%s\nLv %d" % [enemy_data.get("type", "???"), enemy_data.get("level", 1)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return label

	# Instance EnemySlot
	var enemy_slot = enemy_slot_scene.instantiate()

	# Get complete stats from EnemyDatabase
	var enemy_type = enemy_data.get("type", "Unknown")
	var enemy_level = enemy_data.get("level", 1)

	# Fetch full stats from database
	var stats = EnemyDatabase.get_enemy_stats(enemy_type, enemy_level)

	# Store spawn data in metadata to be used after _ready()
	var mob_data = {
		"name": stats.get("name", enemy_type),
		"hp": stats.get("hp", 100),
		"attack": stats.get("attack", 5.0),
		"attack_speed": stats.get("attack_speed", 2.0),
		"icon": stats.get("icon", ""),
		"level": enemy_level,
		"is_boss": stats.get("is_boss", is_boss),
		"is_metin": stats.get("is_metin", false),
		"special_mechanics": stats.get("special_mechanics", {}),
		"drops": stats.get("drops", {})
	}

	enemy_slot.set_meta("enemy_data", enemy_data)
	enemy_slot.set_meta("mob_data", mob_data)
	enemy_slot.set_meta("mob_id", enemy_type)
	enemy_slot.set_meta("needs_spawn", true)

	# Connect Metin spawn signal if this is a Metin
	if stats.get("is_metin", false):
		enemy_slot.metin_spawn_request.connect(_on_metin_spawn_request)
		if GameLogger.ENABLED:
			print("[SlotManager] Connected Metin spawn signal for %s" % enemy_type)

	return enemy_slot

# ==================== SLOT CLEARING ====================

func clear_all_slots() -> void:
	"""Clear all slots and hide empty ones"""
	if GameLogger.ENABLED:
		print("[SlotManager] 🧹 Clearing all slots...")

	# Clear boss slot
	if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
		# CRITICAL: Call clear() to stop enemy attacks BEFORE queue_free()
		if boss_slot_enemy.has_method("clear"):
			boss_slot_enemy.clear()
			if GameLogger.ENABLED:
				print("[SlotManager] Called clear() on boss enemy")
		boss_slot_enemy.queue_free()
	boss_slot_enemy = null
	boss_slot.visible = false

	# Clear normal slots
	for i in range(normal_slot_enemies.size()):
		var enemy = normal_slot_enemies[i]
		if enemy and is_instance_valid(enemy):
			# CRITICAL: Call clear() to stop enemy attacks BEFORE queue_free()
			if enemy.has_method("clear"):
				enemy.clear()
				if GameLogger.ENABLED:
					print("[SlotManager] Called clear() on normal enemy in slot %d" % i)
			enemy.queue_free()
		normal_slot_enemies[i] = null

	# Hide all normal slots
	for slot in normal_slots:
		slot.visible = false

	if GameLogger.ENABLED:
		print("[SlotManager] ✅ All slots cleared and enemies stopped")

func _on_enemy_died_in_slot(enemy_slot, slot_index: int, is_boss: bool) -> void:
	"""Callback when an enemy dies (connected to enemy_died signal)"""
	if GameLogger.ENABLED:
		print("[SlotManager] Enemy died signal received - slot: %d, boss: %s" % [slot_index, is_boss])

	# ADDITION: Store death position for loot orb spawning
	if enemy_slot and is_instance_valid(enemy_slot) and enemy_slot.has_method("get_center_position"):
		var death_pos = enemy_slot.get_center_position()
		last_enemy_death_positions.append(death_pos)
		if GameLogger.ENABLED:
			print("[SlotManager] 📍 Stored death position: %s" % death_pos)

	# Award combat experience based on enemy level
	if enemy_slot and is_instance_valid(enemy_slot):
		# Get enemy level from database using enemy_id
		var enemy_level = 1  # Default
		var full_enemy_data = {}
		if enemy_slot.enemy_id != "":
			full_enemy_data = EnemyDatabase.get_enemy_data(enemy_slot.enemy_id)
			if not full_enemy_data.is_empty():
				enemy_level = int(full_enemy_data.get("level", 1))

		# OLD SYSTEM DISABLED: XP is now awarded via visual XP orbs
		# var exp_amount = enemy_level * 10  # Formula: level * 10
		# var gs = get_node_or_null("/root/GameState")
		# if gs and gs.character_stats:
		#     gs.character_stats.add_combat_exp(exp_amount)
		#     if GameLogger.ENABLED:
		#         print("[SlotManager] 💫 Awarded %d EXP for defeating level %d enemy (%s)" % [exp_amount, enemy_level, enemy_slot.enemy_id])

		# EMIT SIGNAL: Enemy killed (for immediate loot orb spawning)
		if not full_enemy_data.is_empty() and last_enemy_death_positions.size() > 0:
			var death_pos = last_enemy_death_positions[-1]  # Last stored position
			enemy_killed.emit(full_enemy_data, death_pos)
			if GameLogger.ENABLED:
				print("[SlotManager] 🎯 Emitted enemy_killed signal for %s at %s" % [full_enemy_data.get("type", "unknown"), death_pos])

	# Don't queue_free here - let the death animation finish
	# Just mark as null in our tracking
	if is_boss:
		boss_slot_enemy = null
		# Hide after animation (EnemySlot already handles fade-out)
		if GameLogger.ENABLED:
			print("[SlotManager] Boss defeated")
	else:
		if slot_index >= 0 and slot_index < normal_slot_enemies.size():
			normal_slot_enemies[slot_index] = null
			if GameLogger.ENABLED:
				print("[SlotManager] Enemy defeated in slot %d" % slot_index)

	# Check if all enemies defeated
	_check_all_enemies_cleared()

func _on_metin_spawn_request(spawn_count: int, spawn_types: Array) -> void:
	"""Handle Metin mob spawn requests (at 75%, 50%, 25% HP thresholds)"""
	if GameLogger.ENABLED:
		print("[SlotManager] 🔮 METIN SPAWNING %d MOBS!" % spawn_count)

	# Find available normal slots
	var available_slots = []
	for i in range(normal_slot_enemies.size()):
		if normal_slot_enemies[i] == null or not is_instance_valid(normal_slot_enemies[i]):
			available_slots.append(i)

	# Spawn mobs in available slots (up to spawn_count or available slots)
	var spawned = 0
	for slot_idx in available_slots:
		if spawned >= spawn_count:
			break

		# Pick random mob type from spawn_types
		if spawn_types.is_empty():
			continue

		var mob_type = spawn_types.pick_random()

		# Get current zone level for level-scaled spawns
		var zone_level = 1
		var game_state = get_node_or_null("/root/GameState")
		if game_state and "selected_zone_level" in game_state:
			zone_level = game_state.selected_zone_level

		# Create enemy data for the add
		var enemy_data = {
			"type": mob_type,
			"level": zone_level
		}

		# Spawn the mob in this slot
		_spawn_enemy_in_normal_slot(slot_idx, enemy_data)
		spawned += 1

		if GameLogger.ENABLED:
			print("[SlotManager] Spawned %s in slot %d" % [mob_type, slot_idx])

	if GameLogger.ENABLED:
		print("[SlotManager] ✅ Spawned %d/%d mobs from Metin" % [spawned, spawn_count])

func remove_enemy_from_slot(slot_index: int, is_boss: bool) -> void:
	"""Remove enemy from specific slot (manual removal, not death)"""
	if is_boss:
		if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
			boss_slot_enemy.queue_free()
		boss_slot_enemy = null
		boss_slot.visible = false

		if GameLogger.ENABLED:
			print("[SlotManager] Boss removed")
	else:
		if slot_index >= 0 and slot_index < normal_slot_enemies.size():
			var enemy = normal_slot_enemies[slot_index]
			if enemy and is_instance_valid(enemy):
				enemy.queue_free()
			normal_slot_enemies[slot_index] = null

			if GameLogger.ENABLED:
				print("[SlotManager] Enemy removed from slot %d" % slot_index)

	# Check if all enemies defeated
	_check_all_enemies_cleared()

func _check_all_enemies_cleared() -> void:
	"""Check if all enemies are defeated"""
	# Check boss
	if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
		return

	# Check normal slots
	for enemy in normal_slot_enemies:
		if enemy and is_instance_valid(enemy):
			return

	# All cleared!
	if GameLogger.ENABLED:
		print("[SlotManager] ✅ All enemies defeated!")

	all_enemies_cleared.emit()

# ==================== QUERIES ====================

func get_alive_enemy_count() -> int:
	"""Get count of alive enemies"""
	var count = 0

	# Count boss
	if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
		count += 1

	# Count normal enemies
	for enemy in normal_slot_enemies:
		if enemy and is_instance_valid(enemy):
			count += 1

	return count

func get_random_alive_enemy():
	"""Get random alive enemy for targeting"""
	var alive_enemies = []

	# Add boss
	if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
		alive_enemies.append(boss_slot_enemy)

	# Add normal enemies
	for enemy in normal_slot_enemies:
		if enemy and is_instance_valid(enemy):
			alive_enemies.append(enemy)

	if alive_enemies.is_empty():
		return null

	return alive_enemies.pick_random()

func get_all_alive_enemies() -> Array:
	"""Get all alive enemies"""
	var alive_enemies = []

	# Add boss
	if boss_slot_enemy and is_instance_valid(boss_slot_enemy):
		alive_enemies.append(boss_slot_enemy)

	# Add normal enemies
	for enemy in normal_slot_enemies:
		if enemy and is_instance_valid(enemy):
			alive_enemies.append(enemy)

	return alive_enemies

# ==================== DEBUG ====================

func get_debug_info() -> String:
	"""Get formatted debug info"""
	return """[SlotManager Debug]
Boss Slot: %s
Normal Slots Used: %d/%d
Alive Enemies: %d
""" % [
		"Occupied" if boss_slot_enemy else "Empty",
		_count_occupied_normal_slots(),
		MAX_NORMAL_SLOTS,
		get_alive_enemy_count()
	]

func _count_occupied_normal_slots() -> int:
	"""Count occupied normal slots"""
	var count = 0
	for enemy in normal_slot_enemies:
		if enemy and is_instance_valid(enemy):
			count += 1
	return count

# ==================== LOOT ORB POSITION TRACKING ====================

func get_last_enemy_positions() -> Array[Vector2]:
	"""Get positions of last defeated enemies (for orb spawning)"""
	return last_enemy_death_positions

func clear_enemy_positions() -> void:
	"""Clear cached enemy positions (call when starting new encounter)"""
	last_enemy_death_positions.clear()
