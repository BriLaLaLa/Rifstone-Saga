# File: res://scripts/battle/ExplorationCombatController.gd
# Main controller for Exploration -> Combat cycle
# Integrates all systems: PitySystem, EncounterGenerator, CombatStateManager, SlotManager, UI

extends Node
class_name ExplorationCombatController

# const LOG removed - using GameLogger

# ==================== PRELOADS ====================

const PitySystem = preload("res://scripts/battle/PitySystem.gd")
const EncounterGenerator = preload("res://scripts/battle/EncounterGenerator.gd")
const CombatStateManager = preload("res://scripts/battle/CombatStateManager.gd")
const SlotManager = preload("res://scripts/battle/SlotManager.gd")
const ExplorationUI = preload("res://scripts/battle/ExplorationUI.gd")
const TransitionUI = preload("res://scripts/battle/TransitionUI.gd")

# ==================== COMPONENTS ====================

var pity_system: PitySystem = null
var encounter_generator: EncounterGenerator = null
var state_manager: CombatStateManager = null
var slot_manager: SlotManager = null

# UI
var exploration_ui: ExplorationUI = null
var transition_ui: TransitionUI = null

# ==================== REFERENCES ====================

var battle_tab = null  # Reference to BattleTab
var battle_area = null  # Reference to BattleArea
var skill_cast_controller = null  # Reference to SkillCastController

# ==================== ZONE DATA ====================

var current_zone_data: Dictionary = {}

# ==================== SIGNALS ====================

signal exploration_started()
signal combat_started()
signal combat_ended()
signal zone_exited()

# ==================== INITIALIZATION ====================

func _init():
	# Create core systems
	pity_system = PitySystem.new()
	encounter_generator = EncounterGenerator.new()
	state_manager = CombatStateManager.new()

	# Connect generator to pity
	encounter_generator.set_pity_system(pity_system)

	# Setup state manager
	state_manager.setup(encounter_generator, pity_system)

func _ready() -> void:
	# Add systems as children for processing
	add_child(pity_system)
	add_child(encounter_generator)
	add_child(state_manager)

	# Connect state manager signals
	_connect_state_signals()

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Initialized")

func setup(battle_tab_ref, battle_area_ref, skill_controller_ref) -> void:
	"""Setup with references from BattleTab"""
	battle_tab = battle_tab_ref
	battle_area = battle_area_ref
	skill_cast_controller = skill_controller_ref

	# Create slot manager
	if battle_area:
		# 🔧 FIX: WAIT for BattleArea to complete initialization
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] Waiting for BattleArea initialization...")

		# Wait for slots to be created (max 10 frames)
		var max_wait_frames = 10
		var waited = 0
		while not battle_area.slots_created and waited < max_wait_frames:
			await get_tree().process_frame
			waited += 1
			if GameLogger.ENABLED and waited > 0:
				print("[ExplorationCombatController] Waiting... frame %d/%d" % [waited, max_wait_frames])

		if not battle_area.slots_created:
			push_error("[ExplorationCombatController] ⚠️ BattleArea failed to initialize slots after %d frames!" % max_wait_frames)
		elif GameLogger.ENABLED:
			print("[ExplorationCombatController] ✅ BattleArea ready after %d frames" % waited)

		slot_manager = SlotManager.new()
		add_child(slot_manager)

		# 🔧 FIX: Get spawn points AFTER waiting
		var spawn_points = battle_area.get_spawn_point_positions()

		# 🚨 VERIFY spawn points were received
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] 📍 Spawn points received:")
			print("  Normal spawns: %d" % spawn_points.normal.size())
			print("  Boss spawn: %s" % ("YES" if spawn_points.boss else "NO"))

		if spawn_points.normal.is_empty():
			push_error("[ExplorationCombatController] 🐛 NO SPAWN POINTS! This is the 'Thursday Bug'!")
			push_error("  use_background_system: %s" % battle_area.use_background_system)
			push_error("  background_manager: %s" % (battle_area.background_manager != null))
			push_error("  current_battlefield: %s" % (battle_area.current_battlefield != null))

		slot_manager.setup(battle_area, spawn_points)

		# Connect slot signals
		slot_manager.all_enemies_cleared.connect(_on_all_enemies_cleared)
		slot_manager.enemy_killed.connect(_on_enemy_killed)  # NEW: Immediate loot drop

		# Set slot manager in skill cast controller for enemy targeting
		if skill_cast_controller:
			skill_cast_controller.set_slot_manager(slot_manager)

	# Create UIs
	_create_uis()

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Setup complete")

func _create_uis() -> void:
	"""Create UI overlays"""
	if not battle_area:
		return

	# Exploration UI
	exploration_ui = ExplorationUI.new()
	exploration_ui.name = "ExplorationUI"
	exploration_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	exploration_ui.z_index = 100
	battle_area.add_child(exploration_ui)

	# Transition UI - CRITICAL: Use scene instantiation, NOT .new()!
	# TransitionUI.new() creates script only, bypassing TransitionUI.tscn and @onready nodes!
	const TRANSITION_UI_SCENE = preload("res://scenes/battle/TransitionUI.tscn")
	transition_ui = TRANSITION_UI_SCENE.instantiate()
	transition_ui.name = "TransitionUI"
	transition_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_ui.z_index = 100
	battle_area.add_child(transition_ui)

	# Connect UI signals
	transition_ui.skip_transition_clicked.connect(_on_skip_transition)

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] UIs created")

# ==================== SIGNAL CONNECTIONS ====================

func get_state_manager() -> CombatStateManager:
	"""Get reference to state manager for direct access"""
	return state_manager

func _connect_state_signals() -> void:
	"""Connect state manager signals"""
	state_manager.exploration_started.connect(_on_exploration_started)
	state_manager.exploration_progress.connect(_on_exploration_progress)
	state_manager.exploration_completed.connect(_on_exploration_completed)
	state_manager.encounter_generated.connect(_on_encounter_generated)
	state_manager.combat_started.connect(_on_combat_started)
	state_manager.transition_started.connect(_on_transition_started)
	state_manager.transition_completed.connect(_on_transition_completed)

# ==================== ZONE CONTROL ====================

func enter_zone(zone_data: Dictionary) -> void:
	"""Enter a zone and start exploration cycle"""
	current_zone_data = zone_data

	# Configure encounter generator for this zone
	_configure_zone(zone_data)

	# Load pity state for this zone (if saved)
	_load_pity_state(zone_data.get("id", ""))

	# Start exploration
	state_manager.start_exploration()

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Entered zone: %s" % zone_data.get("name", "Unknown"))

func _configure_zone(zone_data: Dictionary) -> void:
	"""Configure encounter generator for zone"""
	var config = {
		"level_range": zone_data.get("level_range", [1, 10]),
		"enemies": zone_data.get("enemies", ["slime"]),
		"boss_types": zone_data.get("boss_types", []),
		"metin_types": zone_data.get("metin_types", [])
	}

	encounter_generator.set_zone_config(config)

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Zone configured: Lv%d-%d with %d enemy types" %
			[config["level_range"][0], config["level_range"][1], config["enemies"].size()])

func exit_zone() -> void:
	"""Exit current zone"""
	# Save pity state
	_save_pity_state(current_zone_data.get("id", ""))

	# Stop state manager
	state_manager.exit_zone()

	# Stop skill casting
	if skill_cast_controller:
		skill_cast_controller.stop_combat()
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] Stopped skill casting")

	# Clear slots
	if slot_manager:
		slot_manager.clear_all_slots()

	# Hide UIs
	if exploration_ui:
		exploration_ui.hide_exploration()
	if transition_ui:
		transition_ui.hide_transition()

	current_zone_data = {}

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Exited zone")

	zone_exited.emit()

# ==================== STATE HANDLERS ====================

func _on_exploration_started() -> void:
	"""Handle exploration start"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] 🚶 Exploration started")

	# Show exploration UI
	if exploration_ui:
		exploration_ui.show_exploration(current_zone_data)

	# Hide transition UI
	if transition_ui:
		transition_ui.hide_transition()

	# Clear previous encounter
	if slot_manager:
		slot_manager.clear_all_slots()

	# Stop skill casting
	if skill_cast_controller:
		skill_cast_controller.stop_combat()

	exploration_started.emit()

func _on_exploration_progress(progress: float) -> void:
	"""Handle exploration progress update"""
	if exploration_ui:
		exploration_ui.update_progress(progress)

func _on_exploration_completed() -> void:
	"""Handle exploration completion"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] ✅ Exploration completed")

	# Hide exploration UI
	if exploration_ui:
		exploration_ui.hide_exploration()

func _on_encounter_generated(encounter: Dictionary) -> void:
	"""Handle encounter generation"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] 🎲 Encounter generated: %s" % encounter.get("type", "unknown"))

	# Save gathering node for after victory
	if encounter.has("gathering_node") and battle_tab:
		battle_tab.pending_gathering_node_type = encounter["gathering_node"]

		if GameLogger.ENABLED:
			print("[ExplorationCombatController] 🌿 Gathering node queued: %s" % encounter["gathering_node"])

	# Spawn encounter in slots
	if slot_manager:
		slot_manager.spawn_encounter(encounter)

func _on_combat_started(encounter: Dictionary) -> void:
	"""Handle combat start"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] ⚔️ Combat started: %s" % encounter.get("type", "unknown"))

	# Show gathering node if one was queued
	if battle_tab and battle_tab.has_method("show_gathering_node_during_combat"):
		battle_tab.show_gathering_node_during_combat()

	# Start skill casting
	if skill_cast_controller:
		skill_cast_controller.start_combat()

	combat_started.emit()

func _on_enemy_killed(enemy_data: Dictionary, death_position: Vector2) -> void:
	"""Handle single enemy death - spawn loot orb immediately"""
	# Spawn XP orbs from this enemy
	_spawn_xp_orbs_from_enemy(enemy_data, death_position)

	# Spawn gold orbs from this enemy
	_spawn_gold_orbs_from_enemy(enemy_data, death_position)

	# Generate loot drop for this enemy
	var drop_gen = get_node_or_null("/root/ItemDropGenerator")
	if not drop_gen:
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ ItemDropGenerator not found!")
		return

	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.data.has("loot_tables"):
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ GameState or loot_tables not found!")
		return

	# Map enemy type to loot table
	var enemy_to_loot_table = {
		"boar": "goblin_loot",
		"wolf": "goblin_loot",
		"slime": "slime_loot",
		"alpha_boar": "goblin_loot",
		"alpha_wolf": "goblin_loot",
		"king_slime": "slime_loot"
	}

	var enemy_type = enemy_data.get("type", "slime")
	var loot_table_id = enemy_to_loot_table.get(enemy_type, "slime_loot")

	if not gs.data.loot_tables.has(loot_table_id):
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ Loot table not found: %s" % loot_table_id)
		return

	var loot_table = gs.data.loot_tables[loot_table_id]

	# Roll for drops from table
	var drops = []
	for drop in loot_table.drops:
		if randf() <= float(drop.chance):
			var qty = randi_range(int(drop.min), int(drop.max))
			for i in range(qty):
				var item_data = drop_gen.generate_drop_from_loot_table(drop.item_id)
				if not item_data.is_empty() and item_data.has("id"):
					drops.append(item_data)

	# If no drops from RNG, guarantee at least one (50% of time for balance)
	if drops.is_empty() and randf() < 0.5:
		if loot_table.drops.size() > 0:
			var guaranteed_drop = loot_table.drops[0]
			var item_data = drop_gen.generate_drop_from_loot_table(guaranteed_drop.item_id)
			if not item_data.is_empty() and item_data.has("id"):
				drops.append(item_data)
				if GameLogger.ENABLED:
					print("[ExplorationCombatController] 🎲 Guaranteed drop: %s" % item_data.get("name", item_data.get("id")))

	# Spawn orb for each drop
	if drops.size() > 0:
		var loot_orb_manager = get_node_or_null("/root/LootOrbManager")
		if loot_orb_manager:
			for item in drops:
				var rarity = _get_item_rarity(item)
				loot_orb_manager.spawn_orb(item, death_position, rarity)
				if GameLogger.ENABLED:
					print("[ExplorationCombatController] ✨ Spawned orb for: %s" % item.get("name", item.get("id")))
		else:
			# Fallback: add directly to inventory
			for item in drops:
				gs._add_item_to_visual_inventory(item.get("id", ""), item)

func _spawn_xp_orbs_from_enemy(enemy_data: Dictionary, death_position: Vector2) -> void:
	"""Spawn XP orbs from a defeated enemy"""
	# Calculate XP based on enemy level
	var enemy_level = enemy_data.get("level", 1)
	var is_boss = enemy_data.get("is_boss", false)

	# Base XP calculation: level * 15 + random bonus
	var base_xp = enemy_level * 15
	var bonus_xp = randi_range(int(enemy_level * 3), int(enemy_level * 8))
	var total_xp = base_xp + bonus_xp

	# Boss bonus
	if is_boss:
		total_xp = int(total_xp * 2.0)

	# Spawn XP orbs
	var xp_orb_manager = get_node_or_null("/root/XpOrbManager")
	if xp_orb_manager:
		xp_orb_manager.spawn_xp_orbs(total_xp, death_position)
	else:
		# Fallback: add XP directly
		var gs = get_node_or_null("/root/GameState")
		if gs and gs.character_stats and gs.character_stats.level_system:
			gs.character_stats.level_system.add_exp(total_xp)
			if GameLogger.ENABLED:
				print("[ExplorationCombatController] ⚠️ XpOrbManager not found, added XP directly: %d" % total_xp)

func _spawn_gold_orbs_from_enemy(enemy_data: Dictionary, death_position: Vector2) -> void:
	"""Spawn gold orbs from a defeated enemy"""
	# Calculate gold based on enemy level
	var enemy_level = enemy_data.get("level", 1)
	var is_boss = enemy_data.get("is_boss", false)

	# Base gold calculation: level * 8 + random bonus
	var base_gold = enemy_level * 8
	var bonus_gold = randi_range(int(enemy_level * 2), int(enemy_level * 5))
	var total_gold = base_gold + bonus_gold

	# Boss bonus
	if is_boss:
		total_gold = int(total_gold * 2.0)

	# Spawn gold orbs
	var gold_orb_manager = get_node_or_null("/root/GoldOrbManager")
	if gold_orb_manager:
		gold_orb_manager.spawn_gold_orbs(total_gold, death_position)
	else:
		# Fallback: add gold directly
		var gs = get_node_or_null("/root/GameState")
		if gs and gs.has_method("add_gold"):
			gs.add_gold(total_gold)
			if GameLogger.ENABLED:
				print("[ExplorationCombatController] ⚠️ GoldOrbManager not found, added gold directly: %d" % total_gold)

func _on_all_enemies_cleared() -> void:
	"""Handle all enemies defeated"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] ✅ All enemies defeated!")

	# Calculate rewards
	var rewards = _calculate_rewards()

	# Set rewards in state manager
	state_manager.set_combat_rewards(rewards)

	# Check if BattleTab has a gathering node to handle
	# If yes, let BattleTab handle the transition after gathering completes
	var battle_tab = get_node_or_null("../../BattleTab")
	if battle_tab and battle_tab.pending_gathering_node_type != "":
		print("[ExplorationCombatController] ⏸️ Gathering pending - BattleTab will handle transition")
		return

	# End combat (only if no gathering)
	state_manager.on_combat_ended()

func _on_transition_started(rewards: Dictionary) -> void:
	"""Handle transition start"""
	print("[DEBUG] 🚀 _on_transition_started() CALLED")
	print("[DEBUG] 🎁 Rewards: gold=%s, xp=%s, items=%s" % [rewards.get("gold", 0), rewards.get("xp", 0), rewards.get("items", []).size()])

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] 💰 Transition started with rewards: %s" % str(rewards))

	# Apply rewards to player
	_apply_rewards(rewards)

	# Get pity info
	var pity_info = pity_system.get_pity_info()

	# Prepare rewards for UI (extract item names as strings)
	var ui_rewards = {
		"gold": rewards.get("gold", 0),
		"xp": rewards.get("xp", 0),
		"items": []
	}

	# Convert item data dictionaries to item name strings for UI
	if rewards.has("items") and rewards["items"] is Array:
		for item_data in rewards["items"]:
			if item_data is Dictionary and item_data.has("name"):
				ui_rewards["items"].append(item_data["name"])

	# Show transition UI
	if transition_ui:
		transition_ui.show_transition(ui_rewards, pity_info)

func _on_transition_completed() -> void:
	"""Handle transition completion"""
	if GameLogger.ENABLED:
		print("[ExplorationCombatController] ✅ Transition completed - looping to exploration")

	# UI will be updated by exploration_started

func _on_skip_transition() -> void:
	"""Handle skip transition button"""
	state_manager.skip_transition()

# ==================== REWARDS ====================

func _calculate_rewards() -> Dictionary:
	"""Calculate rewards based on encounter and zone"""
	print("[DEBUG] 🎲 _calculate_rewards() CALLED")

	var rewards = {
		"gold": 0,
		"xp": 0,
		"items": []
	}

	# Get zone rewards range
	var gold_min = current_zone_data.get("gold_min", 10)
	var gold_max = current_zone_data.get("gold_max", 25)
	var xp_min = current_zone_data.get("xp_min", 50)
	var xp_max = current_zone_data.get("xp_max", 100)

	# Random rewards within range
	rewards["gold"] = randi_range(gold_min, gold_max)
	rewards["xp"] = randi_range(xp_min, xp_max)

	# Generate item drops from defeated enemies
	var encounter = state_manager.get_current_encounter()
	print("[DEBUG] 📦 Encounter data: %s" % encounter)

	rewards["items"] = _generate_item_drops_from_encounter(encounter)
	print("[DEBUG] 🎁 Generated %d items" % rewards["items"].size())

	# Bonus for rare encounters
	match encounter.get("type", "normal"):
		"miniboss":
			rewards["gold"] = int(rewards["gold"] * 1.5)
			rewards["xp"] = int(rewards["xp"] * 1.5)
			if GameLogger.ENABLED:
				print("[ExplorationCombatController] 💎 Miniboss bonus: +50% rewards")
		"metin":
			rewards["gold"] = int(rewards["gold"] * 2.0)
			rewards["xp"] = int(rewards["xp"] * 2.0)
			if GameLogger.ENABLED:
				print("[ExplorationCombatController] 💎💎 Metin bonus: +100% rewards")

	return rewards

func _generate_item_drops_from_encounter(encounter: Dictionary) -> Array:
	"""Generate item drops based on encounter enemies"""
	print("[DEBUG] 🔍 _generate_item_drops_from_encounter() CALLED")

	var all_drops = []

	# Get ItemDropGenerator
	var drop_gen = get_node_or_null("/root/ItemDropGenerator")
	if not drop_gen:
		print("[DEBUG] ⚠️ ItemDropGenerator NOT FOUND!")
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ ItemDropGenerator not found!")
		return all_drops

	print("[DEBUG] ✅ ItemDropGenerator found")

	# Get GameState for loot tables
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.data.has("loot_tables"):
		print("[DEBUG] ⚠️ GameState or loot_tables NOT FOUND!")
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ GameState or loot_tables not found!")
		return all_drops

	print("[DEBUG] ✅ GameState and loot_tables found")

	# Map enemy types to loot table IDs
	var enemy_to_loot_table = {
		"boar": "goblin_loot",      # boar usa goblin loot
		"wolf": "goblin_loot",      # wolf usa goblin loot
		"slime": "slime_loot",      # slime usa slime loot
		"alpha_boar": "goblin_loot",
		"alpha_wolf": "goblin_loot",
		"king_slime": "slime_loot"
	}

	# Collect all enemies from encounter
	var enemies_to_process = []

	print("[DEBUG] 📋 Encounter type: %s" % encounter.get("type", "normal"))

	match encounter.get("type", "normal"):
		"normal":
			enemies_to_process = encounter.get("enemies", [])
			print("[DEBUG] 👹 Normal encounter - enemies: %d" % enemies_to_process.size())
		"miniboss":
			# Boss + companions
			var boss = encounter.get("boss", null)
			if boss:
				enemies_to_process.append(boss)
			enemies_to_process.append_array(encounter.get("companions", []))
			print("[DEBUG] 💀 Miniboss encounter - total enemies: %d" % enemies_to_process.size())
		"metin":
			# Solo metin (bonus drops)
			var metin = encounter.get("metin", null)
			if metin:
				enemies_to_process.append(metin)
			print("[DEBUG] 🗿 Metin encounter - enemies: %d" % enemies_to_process.size())

	print("[DEBUG] 🎯 Total enemies to process for drops: %d" % enemies_to_process.size())

	# Process each enemy for drops
	for enemy in enemies_to_process:
		print("[DEBUG] 🔄 Processing enemy: %s" % enemy.get("type", "unknown"))
		var enemy_type = enemy.get("type", "slime")
		var loot_table_id = enemy_to_loot_table.get(enemy_type, "slime_loot")

		# Get loot table directly by ID (it's a dict, not an array)
		if not gs.data.loot_tables.has(loot_table_id):
			if GameLogger.ENABLED:
				print("[ExplorationCombatController] ⚠️ Loot table not found: %s" % loot_table_id)
			continue

		var loot_table = gs.data.loot_tables[loot_table_id]

		# Roll for each drop in table
		for drop in loot_table.drops:
			if randf() <= float(drop.chance):
				var qty = randi_range(int(drop.min), int(drop.max))
				for i in range(qty):
					# Generate item with bonuses via ItemDropGenerator
					var item_data = drop_gen.generate_drop_from_loot_table(drop.item_id)

					# Only add if item exists (not empty dict)
					if not item_data.is_empty() and item_data.has("id"):
						all_drops.append(item_data)

	# GUARANTEE: Ensure at least 1 item drops per combat (for visual loot orb system)
	if all_drops.is_empty() and enemies_to_process.size() > 0:
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] 🎲 No drops from RNG - guaranteeing 1 item")

		# Get first enemy's loot table
		var first_enemy_type = enemies_to_process[0].get("type", "slime")
		var loot_table_id = enemy_to_loot_table.get(first_enemy_type, "slime_loot")

		if gs.data.loot_tables.has(loot_table_id):
			var loot_table = gs.data.loot_tables[loot_table_id]

			# Pick first drop from table (usually common item)
			if loot_table.drops.size() > 0:
				var guaranteed_drop = loot_table.drops[0]
				var item_data = drop_gen.generate_drop_from_loot_table(guaranteed_drop.item_id)

				if not item_data.is_empty() and item_data.has("id"):
					all_drops.append(item_data)
					if GameLogger.ENABLED:
						print("[ExplorationCombatController] ✅ Guaranteed drop: %s" % item_data.get("name", item_data.get("id")))

	if GameLogger.ENABLED and all_drops.size() > 0:
		print("[ExplorationCombatController] 🎁 Generated %d item drops" % all_drops.size())

	return all_drops

func _apply_rewards(rewards: Dictionary) -> void:
	"""Apply rewards to player (via GameState)"""
	print("[DEBUG] 💰 _apply_rewards() CALLED with rewards: %s" % rewards.keys())

	if not has_node("/root/GameState"):
		print("[DEBUG] ⚠️ GameState not found!")
		return

	var gs = get_node("/root/GameState")

	# NOTE: Gold is now awarded via gold orbs spawned when each enemy dies
	# No need to add gold here anymore
	# if rewards.has("gold") and gs.has_method("add_gold"):
	# 	gs.add_gold(rewards["gold"])
	# 	print("[DEBUG] ✅ Added %d gold" % rewards["gold"])

	# NOTE: XP is now awarded via XP orbs spawned when each enemy dies
	# No need to add XP here anymore
	# if rewards.has("xp") and gs.has_method("add_xp"):
	# 	gs.add_xp(rewards["xp"])
	# 	print("[DEBUG] ✅ Added %d xp" % rewards["xp"])

	# CHANGE: Queue items for loot orb spawning instead of adding directly
	if rewards.has("items") and rewards["items"].size() > 0:
		print("[DEBUG] 📦 Queueing %d items for orbs..." % rewards["items"].size())
		_queue_items_for_orbs(rewards["items"])
	else:
		print("[DEBUG] ⚠️ No items in rewards OR items array is empty")

	if GameLogger.ENABLED:
		print("[ExplorationCombatController] Rewards applied: +%dg, +%dxp, %d items queued for orbs" %
			[rewards.get("gold", 0), rewards.get("xp", 0), rewards.get("items", []).size()])

func _queue_items_for_orbs(items: Array) -> void:
	"""Queue items to be spawned as loot orbs at enemy death positions"""
	print("[DEBUG] 🎯 _queue_items_for_orbs called with %d items" % items.size())

	var loot_orb_manager = get_node_or_null("/root/LootOrbManager")
	if not loot_orb_manager:
		# Fallback: add directly to inventory
		print("[DEBUG] ⚠️ LootOrbManager NOT FOUND - using fallback")
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ LootOrbManager not found - adding items directly")
		var gs = get_node("/root/GameState")
		for item_data in items:
			var item_id = item_data.get("id", "")
			if not item_id.is_empty():
				gs._add_item_to_visual_inventory(item_id, item_data)
		return

	print("[DEBUG] ✅ LootOrbManager found, spawning orbs...")

	# Get enemy death positions from SlotManager
	var enemy_positions = slot_manager.get_last_enemy_positions()

	if enemy_positions.is_empty():
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] ⚠️ No enemy positions found - using fallback")
		enemy_positions = [Vector2(400, 300)]  # Fallback center position

	# Spawn orbs at enemy positions
	for i in range(items.size()):
		var item_data = items[i]
		var enemy_pos = enemy_positions[i % enemy_positions.size()]

		# Determine rarity from item bonuses
		var rarity = _get_item_rarity(item_data)

		# Queue orb spawn
		loot_orb_manager.spawn_orb(item_data, enemy_pos, rarity)

		if GameLogger.ENABLED:
			print("[ExplorationCombatController] 🌟 Queued %s orb for %s at %s" % [rarity, item_data.get("name", "Unknown"), enemy_pos])

func _get_item_rarity(item_data: Dictionary) -> String:
	"""Map item bonuses to rarity name (matches ItemDropGenerator system)"""
	if not item_data.has("bonuses"):
		return "common"

	var bonus_count = item_data.bonuses.size()

	# Map ItemDropGenerator colors → standard rarity:
	# white (0 bonuses) → common
	# blue (1-2 bonuses) → rare
	# yellow (3-4 bonuses) → epic
	# gold (5+ bonuses) → legendary

	if bonus_count == 0:
		return "common"
	elif bonus_count <= 2:
		return "rare"
	elif bonus_count <= 4:
		return "epic"
	else:
		return "legendary"

# ==================== PERSISTENCE ====================

func _save_pity_state(zone_id: String) -> void:
	"""Save pity state for this zone"""
	if zone_id.is_empty():
		return

	var save_path = "user://pity_state_%s.json" % zone_id
	var state = pity_system.save_state()

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))
		file.close()

		if GameLogger.ENABLED:
			print("[ExplorationCombatController] Pity state saved for zone: %s" % zone_id)

func _load_pity_state(zone_id: String) -> void:
	"""Load pity state for this zone"""
	if zone_id.is_empty():
		return

	var save_path = "user://pity_state_%s.json" % zone_id

	if not FileAccess.file_exists(save_path):
		if GameLogger.ENABLED:
			print("[ExplorationCombatController] No pity state found for zone: %s" % zone_id)
		return

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var txt = file.get_as_text()
		file.close()

		var state = JSON.parse_string(txt)
		if state is Dictionary:
			pity_system.load_state(state)

			if GameLogger.ENABLED:
				print("[ExplorationCombatController] Pity state loaded for zone: %s" % zone_id)

# ==================== GETTERS ====================

func is_in_combat() -> bool:
	"""Check if currently in combat"""
	return state_manager.is_in_combat()

func is_exploring() -> bool:
	"""Check if currently exploring"""
	return state_manager.is_exploring()

func get_current_state() -> int:
	"""Get current combat state"""
	return state_manager.get_current_state()

# ==================== DEBUG ====================

func get_debug_info() -> String:
	"""Get comprehensive debug info"""
	return """
=== EXPLORATION COMBAT CONTROLLER ===
Zone: %s
%s
%s
%s
""" % [
		current_zone_data.get("name", "None"),
		state_manager.get_debug_info() if state_manager else "",
		pity_system.get_debug_info() if pity_system else "",
		slot_manager.get_debug_info() if slot_manager else ""
	]
