# File: res://scripts/battle/BattleTab.gd
# Controller principale della Battle Scene

extends Control
class_name BattleTab

# const LOG removed - using GameLogger

# Warrior Skills System
const SkillCastController = preload("res://scripts/battle/SkillCastController.gd")
const CombatSkillBar = preload("res://scripts/battle/CombatSkillBar.gd")
var skill_cast_controller: SkillCastController = null
var combat_skill_bar: CombatSkillBar = null

# Exploration System
const ExplorationCombatController = preload("res://scripts/battle/ExplorationCombatController.gd")
var exploration_controller: ExplorationCombatController = null

# Navigation states
enum NavigationState { WORLD_MAP, REGION_ZOOM, BATTLE }

# Scene references
@onready var character_display: CharacterDisplay = $HSplit/LeftPanel/CharacterDisplay
@onready var gathering_skill_display: PanelContainer = $HSplit/LeftPanel/GatheringSkillDisplay
@onready var gathering_skill_name_label: Label = $HSplit/LeftPanel/GatheringSkillDisplay/VBox/SkillNameLabel
@onready var gathering_skill_level_label: Label = $HSplit/LeftPanel/GatheringSkillDisplay/VBox/SkillLevelLabel
@onready var gathering_skill_exp_bar: ProgressBar = $HSplit/LeftPanel/GatheringSkillDisplay/VBox/SkillExpBar
@onready var gathering_skill_exp_label: Label = $HSplit/LeftPanel/GatheringSkillDisplay/VBox/SkillExpLabel
@onready var inventory_button: Button = $HSplit/LeftPanel/InventoryButton
@onready var world_map_view: Control = $HSplit/RightPanel/WorldMapView
@onready var region_zoom_view: Control = $HSplit/RightPanel/RegionZoomView
@onready var battle_area: BattleArea = $HSplit/RightPanel/BattleArea
@onready var action_bar: Control = $HSplit/RightPanel/BattleArea/ActionBar
@onready var start_battle_button: Button = $HSplit/RightPanel/BattleArea/StartBattleButton

# Inventory popup reference
var inventory_popup: InventoryPopup = null

# Exit battle button
var exit_battle_button: Button = null

# PackedScene per il popup
const INVENTORY_POPUP_SCENE := "res://scenes/battle/InventoryPopup.tscn"

# Navigation state
var current_nav_state: NavigationState = NavigationState.WORLD_MAP
var selected_kingdom: String = ""
var selected_zone: ZoneData = null

# Battle state
var is_battle_active: bool = false
var current_area_id: String = "forest_1"  # Default area

# Combat timers
var player_attack_timer: Timer = null
var enemy_attack_timers: Dictionary = {}  # enemy_slot -> Timer

# Combat stats
const PLAYER_DAMAGE: int = 10
const ENEMY_DAMAGE: int = 1
const PLAYER_ATTACK_INTERVAL: float = 1.0
const ENEMY_ATTACK_INTERVAL_MIN: float = 2.8
const ENEMY_ATTACK_INTERVAL_MAX: float = 3.2

# Skill stats
const SKILL_AOE_DAMAGE: int = 15
const SKILL_AOE_HITS: int = 3
const SKILL_AOE_DURATION: float = 0.5
const SKILL_AOE_COOLDOWN: float = 10.0

var skill_aoe_timer: Timer = null
var skill_aoe_ready: bool = true

# Gathering system
var current_gathering_node: Node = null
var pending_gathering_node_type: String = ""

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_connect_map_signals()
	_create_inventory_popup()
	_setup_skill_system()
	await _setup_exploration_system()  # NEW: Setup exploration system (await for initialization)
	_create_exit_battle_button()

	# CRITICAL: Register this BattleTab with LootOrbManager so orbs spawn visually
	var loot_orb_manager = get_node_or_null("/root/LootOrbManager")
	if loot_orb_manager:
		loot_orb_manager.battle_tab = self
		if GameLogger.ENABLED:
			print("[BattleTab] ✅ Registered with LootOrbManager")
	else:
		push_error("[BattleTab] ⚠️ LootOrbManager not found!")

	# NOTE: visibility_changed signal connected in BattleTab.tscn

	# Start with world map view
	_show_world_map()

	if GameLogger.ENABLED:
		print("[BattleTab] Ready - Starting in world map view")

# NOTE: _process() removed - enemy attack timer now managed by CombatStateManager

func _input(event: InputEvent) -> void:
	"""Gestisci input per skill"""
	if not is_battle_active:
		return

	# Skill AoE con tasto SPACE
	if event.is_action_pressed("ui_accept"):  # SPACE key
		_activate_skill_aoe()

func _setup_ui() -> void:
	"""Configura l'interfaccia iniziale"""

	# Setup inventory button
	if inventory_button:
		inventory_button.text = "📦 Open Inventory"
		inventory_button.pressed.connect(_on_inventory_button_pressed)

	# Hide start battle button (combat auto-starts now)
	if start_battle_button:
		start_battle_button.visible = false
		# Keep connection in case we need it later
		# start_battle_button.pressed.connect(_auto_start_combat)

	# Setup battle area
	if battle_area:
		battle_area.enemy_targeted.connect(_on_enemy_targeted)
		battle_area.enemy_killed.connect(_on_enemy_killed)
		battle_area.all_enemies_dead.connect(_on_all_enemies_dead)

	if GameLogger.ENABLED:
		print("[BattleTab] UI setup complete")

func _setup_skill_system() -> void:
	"""Setup the warrior skill auto-cast system"""
	# Create skill cast controller
	skill_cast_controller = SkillCastController.new()
	add_child(skill_cast_controller)

	# Get player stats from GameState
	var player_stats = null
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs and "character_stats" in gs:
			player_stats = gs.character_stats
			if GameLogger.ENABLED:
				print("[BattleTab] Found player stats: %s" % player_stats)

	if player_stats:
		skill_cast_controller.set_player(player_stats)

		# Connect to player death signal
		if not player_stats.player_died.is_connected(_on_player_died):
			player_stats.player_died.connect(_on_player_died)

		if GameLogger.ENABLED:
			print("[BattleTab] ✅ Player set in SkillCastController")
	else:
		push_warning("[BattleTab] ❌ No CharacterStats found in GameState")

	# Set battle area reference
	if battle_area:
		skill_cast_controller.set_battle_area(battle_area)

	# Connect skill signals
	skill_cast_controller.skill_cast_started.connect(_on_skill_cast_started)
	skill_cast_controller.skill_cast_completed.connect(_on_skill_cast_completed)
	skill_cast_controller.buff_applied.connect(_on_buff_applied)
	skill_cast_controller.buff_expired.connect(_on_buff_expired)

	# Create Combat Skill Bar UI
	_setup_combat_skill_bar()

	# Load skills from saved loadout
	_load_skills_from_loadout()

	if GameLogger.ENABLED:
		print("[BattleTab] Skill system setup complete")

func _load_skills_from_loadout() -> void:
	"""Load skills from SkillsTab saved loadout file"""
	const SAVE_PATH := "user://skill_loadout.json"

	if not FileAccess.file_exists(SAVE_PATH):
		if GameLogger.ENABLED:
			print("[BattleTab] No saved loadout found, using default skills")
		_load_default_skills()
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleTab] Failed to open loadout file")
		_load_default_skills()
		return

	var txt = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[BattleTab] Invalid loadout data")
		_load_default_skills()
		return

	var slots_data = parsed.get("slots", [])

	if GameLogger.ENABLED:
		print("[BattleTab] 📂 Loading skills from saved loadout: %s" % str(slots_data))

	# Get GameState skills data
	var gs = get_node("/root/GameState")
	if not "data" in gs or not "skills" in gs.data:
		push_error("[BattleTab] GameState skills data not found")
		_load_default_skills()
		return

	# Clear loadout first
	if skill_cast_controller.has_method("clear_loadout"):
		skill_cast_controller.clear_loadout()

	# Load each skill from saved loadout
	var loaded_count = 0
	for i in range(min(slots_data.size(), 6)):
		var skill_id = slots_data[i]

		if skill_id.is_empty():
			if GameLogger.ENABLED:
				print("[BattleTab]   Slot %d: empty" % i)
			continue

		var skill_data = gs.data.skills.get(skill_id, {})
		if skill_data.is_empty():
			if GameLogger.ENABLED:
				print("[BattleTab]   ❌ Slot %d: Skill '%s' not found" % [i, skill_id])
			continue

		if not skill_data.has("skill_data"):
			if GameLogger.ENABLED:
				print("[BattleTab]   ❌ Slot %d: '%s' has no skill_data field" % [i, skill_id])
			continue

		var warrior_skill_id = skill_data.skill_data.get("skill_id", "")
		if warrior_skill_id.is_empty():
			if GameLogger.ENABLED:
				print("[BattleTab]   ❌ Slot %d: '%s' has no warrior skill_id" % [i, skill_id])
			continue

		var success = skill_cast_controller.equip_skill_to_slot(i, warrior_skill_id)
		if success:
			loaded_count += 1
			if GameLogger.ENABLED:
				print("[BattleTab]   ✅ Slot %d: Loaded '%s' (%s)" % [i, skill_data.get("name", skill_id), warrior_skill_id])
		else:
			if GameLogger.ENABLED:
				print("[BattleTab]   ❌ Slot %d: FAILED to load '%s'" % [i, warrior_skill_id])

	if GameLogger.ENABLED:
		print("[BattleTab] ✅ Loaded %d/%d skills from loadout" % [loaded_count, slots_data.size()])

	# If no skills loaded, use defaults
	if loaded_count == 0:
		if GameLogger.ENABLED:
			print("[BattleTab] No skills loaded, using defaults")
		_load_default_skills()

func _load_default_skills() -> void:
	"""Load default skills if no loadout exists"""
	if GameLogger.ENABLED:
		print("[BattleTab] No saved loadout found - starting with empty skill bar")

	# DON'T load default skills - let player choose their own
	# Clear loadout to ensure empty
	if skill_cast_controller.has_method("clear_loadout"):
		skill_cast_controller.clear_loadout()

func _setup_combat_skill_bar() -> void:
	"""Create the combat skill bar UI"""
	if not battle_area:
		return

	combat_skill_bar = CombatSkillBar.new()
	combat_skill_bar.name = "CombatSkillBar"

	# Position at bottom of battle area
	combat_skill_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	combat_skill_bar.anchor_top = 1.0
	combat_skill_bar.anchor_bottom = 1.0
	combat_skill_bar.offset_top = -120  # 120 pixels from bottom
	combat_skill_bar.offset_bottom = -10  # 10 pixels from bottom

	# Add to battle area
	battle_area.add_child(combat_skill_bar)

	# Connect to skill controller
	if skill_cast_controller:
		combat_skill_bar.set_skill_controller(skill_cast_controller)

	if GameLogger.ENABLED:
		print("[BattleTab] Combat Skill Bar UI created")

func _setup_exploration_system() -> void:
	"""Setup exploration combat controller"""
	exploration_controller = ExplorationCombatController.new()
	exploration_controller.name = "ExplorationCombatController"
	add_child(exploration_controller)

	# Setup with references (await for initialization to complete)
	await exploration_controller.setup(self, battle_area, skill_cast_controller)

	# Connect signals
	exploration_controller.combat_started.connect(_on_exploration_combat_started)
	exploration_controller.combat_ended.connect(_on_exploration_combat_ended)
	exploration_controller.zone_exited.connect(_on_exploration_zone_exited)

	# Connect slot manager signal for gathering (after setup creates slot_manager)
	if exploration_controller.slot_manager:
		exploration_controller.slot_manager.all_enemies_cleared.connect(_on_all_enemies_cleared)
		if GameLogger.ENABLED:
			print("[BattleTab] Connected to slot_manager.all_enemies_cleared signal")
	else:
		push_warning("[BattleTab] ⚠️ slot_manager not created by ExplorationCombatController!")

	# OLD SYSTEM REMOVED: enemy_attack_incoming signal
	# Enemy attacks now handled per-enemy in EnemySlot.gd

	if GameLogger.ENABLED:
		print("[BattleTab] Exploration system setup complete")

func _connect_signals() -> void:
	"""Connetti ai signal del GameState"""
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs:
			# Ascolta eventi di combattimento
			if gs.has_signal("on_combat_event"):
				if not gs.on_combat_event.is_connected(_on_combat_event):
					gs.on_combat_event.connect(_on_combat_event)

			# Ascolta tick per aggiornare combattimento
			if gs.has_signal("on_tick"):
				if not gs.on_tick.is_connected(_on_tick):
					gs.on_tick.connect(_on_tick)

func _create_exit_battle_button() -> void:
	"""Create Exit Battle button"""
	if not battle_area:
		return

	exit_battle_button = Button.new()
	exit_battle_button.text = "🚪 Exit Battle"
	exit_battle_button.custom_minimum_size = Vector2(120, 40)

	# Position at top-right of battle area
	exit_battle_button.position = Vector2(10, 10)
	exit_battle_button.z_index = 100  # Above everything

	# Style
	exit_battle_button.add_theme_font_size_override("font_size", 16)

	# Initially hidden
	exit_battle_button.visible = false

	# Connect signal
	exit_battle_button.pressed.connect(_on_exit_battle_pressed)

	# Add to battle area
	battle_area.add_child(exit_battle_button)

	if GameLogger.ENABLED:
		print("[BattleTab] Exit Battle button created")

func _on_exit_battle_pressed() -> void:
	"""Handle Exit Battle button press"""
	if GameLogger.ENABLED:
		print("[BattleTab] Exit Battle button pressed")

	# Cleanup gathering node if it exists
	if current_gathering_node and is_instance_valid(current_gathering_node):
		print("[BattleTab] Removing gathering node on exit...")
		current_gathering_node.queue_free()
		current_gathering_node = null
	pending_gathering_node_type = ""
	_hide_gathering_skill_display()

	# Exit exploration cycle
	if exploration_controller:
		exploration_controller.exit_zone()

	# Return to region zoom
	_show_region_zoom(selected_kingdom)

func _create_inventory_popup() -> void:
	"""Crea dinamicamente l'InventoryPopup"""
	if GameLogger.ENABLED:
		print("[BattleTab] Tentativo di creare InventoryPopup...")
	
	if not ResourceLoader.exists(INVENTORY_POPUP_SCENE):
		push_error("[BattleTab] InventoryPopup scene non trovata: %s" % INVENTORY_POPUP_SCENE)
		return
	
	var popup_scene: PackedScene = load(INVENTORY_POPUP_SCENE)
	if popup_scene:
		inventory_popup = popup_scene.instantiate()
		
		if inventory_popup:
			add_child(inventory_popup)
			inventory_popup.visible = false
			
			# IMPORTANTE: z_index alto per stare sopra tutto (inclusi enemy slots con z_index=10)
			inventory_popup.z_index = 1000
			
			if GameLogger.ENABLED:
				print("[BattleTab] ✅ InventoryPopup creato con successo!")
		else:
			push_error("[BattleTab] Instantiate ha restituito null")
	else:
		push_error("[BattleTab] Impossibile caricare InventoryPopup scene")

# ==================== BUTTON CALLBACKS ====================

func _on_inventory_button_pressed() -> void:
	"""Apri/chiudi il popup inventario"""
	if GameLogger.ENABLED:
		print("[BattleTab] Inventory button pressed")
	
	if inventory_popup == null:
		push_error("[BattleTab] InventoryPopup non trovato!")
		return
	
	inventory_popup.toggle_popup()

func _auto_start_combat() -> void:
	"""AUTO-START combat when entering battle zone"""
	if is_battle_active:
		if GameLogger.ENABLED:
			print("[BattleTab] Battle already active")
		return

	if GameLogger.ENABLED:
		print("[BattleTab] ⚔️ AUTO-STARTING COMBAT!")

	# Start battle
	start_battle(current_area_id)

# ==================== COMBAT EVENTS ====================

func _on_combat_event(msg: String) -> void:
	"""Gestisci eventi di combattimento dal GameState"""
	if GameLogger.ENABLED:
		print("[BattleTab] Combat event: %s" % msg)

func _on_tick(delta: float) -> void:
	"""Aggiorna la battaglia ogni tick"""
	if not is_battle_active:
		return
	
	# TODO: Aggiornare enemy HP bars, cooldowns, ecc.
	pass

# ==================== API PUBBLICA ====================

func start_battle(area_id: String) -> void:
	"""Inizia una battaglia nell'area specificata"""
	if GameLogger.ENABLED:
		print("[BattleTab] Starting battle in area: %s" % area_id)

	is_battle_active = true
	current_area_id = area_id

	# Attiva il combattimento nel GameState
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs:
			gs.set_area(area_id)
			gs.toggle_combat(true)

	# Start skill auto-cast system
	if skill_cast_controller:
		skill_cast_controller.start_combat()

	# Avvia il timer di attacco del player (LEGACY - will be replaced by skills)
	# _start_player_attack_timer()

	# Avvia i timer di attacco dei nemici
	_start_enemy_attack_timers()

	# Show exit button
	if exit_battle_button:
		exit_battle_button.visible = true

	# Show battle overlay on Skills Tab
	_toggle_skills_tab_overlay(true)

func stop_battle() -> void:
	"""Ferma la battaglia corrente"""
	if GameLogger.ENABLED:
		print("[BattleTab] Stopping battle")

	is_battle_active = false

	# Stop skill auto-cast system
	if skill_cast_controller:
		skill_cast_controller.stop_combat()

	# Ferma tutti i timer
	_stop_all_combat_timers()

	# Disattiva il combattimento nel GameState
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs:
			gs.toggle_combat(false)

	# Riabilita il bottone start
	if start_battle_button:
		start_battle_button.disabled = false
		start_battle_button.text = "⚔️ Start Battle"

	# Clear enemy slots
	if battle_area:
		battle_area.clear_all_slots()

	# Hide exit button
	if exit_battle_button:
		exit_battle_button.visible = false

	# Hide battle overlay on Skills Tab
	_toggle_skills_tab_overlay(false)

func get_character_display() -> CharacterDisplay:
	"""Ottieni il CharacterDisplay per accesso esterno"""
	return character_display

func get_battle_area() -> BattleArea:
	"""Ottieni il BattleArea per accesso esterno"""
	return battle_area

# ==================== BATTLE AREA CALLBACKS ====================

func _on_enemy_targeted(slot: EnemySlot) -> void:
	"""Callback quando un nemico viene targetato"""
	if GameLogger.ENABLED:
		print("[BattleTab] Enemy targeted: %s" % slot.get_enemy_name())

func _on_enemy_killed(slot: EnemySlot) -> void:
	"""Callback quando un nemico muore"""
	if GameLogger.ENABLED:
		print("[BattleTab] Enemy killed: %s" % slot.get_enemy_name())
	
	# TODO: Handle loot drop

func _on_all_enemies_dead() -> void:
	"""Callback quando tutti i nemici sono morti"""
	if GameLogger.ENABLED:
		print("[BattleTab] 🎉 Victory! All enemies defeated!")
	
	# Ferma la battaglia
	stop_battle()
	
	# TODO: Show victory screen, loot, etc.
	# Return to zone selection after victory
	await get_tree().create_timer(2.0).timeout

	_show_region_zoom(selected_kingdom)

# ==================== WORLD MAP NAVIGATION ====================

func _connect_map_signals() -> void:
	"""Connect to world map and region zoom signals"""
	if world_map_view:
		world_map_view.kingdom_clicked.connect(_on_kingdom_clicked)

	if region_zoom_view:
		region_zoom_view.zone_clicked.connect(_on_zone_clicked)
		region_zoom_view.back_to_world_map.connect(_on_back_to_world_map)

	if GameLogger.ENABLED:
		print("[BattleTab] Map signals connected")

func _show_world_map() -> void:
	"""Show world map view"""
	# Safety check: ensure nodes are still valid
	if not is_instance_valid(world_map_view) or not is_instance_valid(region_zoom_view):
		if GameLogger.ENABLED:
			print("[BattleTab] Cannot show world map - nodes already freed")
		return

	current_nav_state = NavigationState.WORLD_MAP

	world_map_view.visible = true
	region_zoom_view.visible = false
	battle_area.visible = false
	action_bar.visible = false

	# Hide combat skill bar
	if combat_skill_bar and is_instance_valid(combat_skill_bar):
		combat_skill_bar.visible = false

	if GameLogger.ENABLED:
		print("[BattleTab] Showing world map")

func _show_region_zoom(kingdom_id: String) -> void:
	"""Show region zoom view for a kingdom"""
	# Safety check: ensure nodes are still valid
	if not is_instance_valid(world_map_view) or not is_instance_valid(region_zoom_view):
		if GameLogger.ENABLED:
			print("[BattleTab] Cannot show region zoom - nodes already freed")
		return

	current_nav_state = NavigationState.REGION_ZOOM
	selected_kingdom = kingdom_id

	world_map_view.visible = false
	region_zoom_view.visible = true
	battle_area.visible = false
	action_bar.visible = false

	# Hide combat skill bar
	if combat_skill_bar and is_instance_valid(combat_skill_bar):
		combat_skill_bar.visible = false

	# Load kingdom data into region zoom
	if region_zoom_view.has_method("load_kingdom"):
		region_zoom_view.load_kingdom(kingdom_id)

	if GameLogger.ENABLED:
		print("[BattleTab] Showing region zoom: %s" % kingdom_id)

func _show_battle(zone_data: ZoneData) -> void:
	"""Show battle view and start combat"""
	# Safety check: ensure nodes are still valid
	if not is_instance_valid(world_map_view) or not is_instance_valid(battle_area):
		if GameLogger.ENABLED:
			print("[BattleTab] Cannot show battle - nodes already freed")
		return

	current_nav_state = NavigationState.BATTLE
	selected_zone = zone_data
	current_area_id = zone_data.area_id

	world_map_view.visible = false
	region_zoom_view.visible = false
	battle_area.visible = true
	action_bar.visible = true

	print("[BattleTab] Battle view shown - BattleArea size: ", battle_area.size)
	print("[BattleTab] RightPanel size: ", $HSplit/RightPanel.size)

	# Change background to match zone
	print("[BattleTab] About to call change_background with key: ", zone_data.background_key)
	battle_area.change_background(zone_data.background_key)
	print("[BattleTab] change_background called")

	# Show combat skill bar
	if combat_skill_bar and is_instance_valid(combat_skill_bar):
		combat_skill_bar.visible = true

	# Hide start battle button (combat auto-starts)
	if start_battle_button and is_instance_valid(start_battle_button):
		start_battle_button.visible = false

	if GameLogger.ENABLED:
		print("[BattleTab] Entering battle zone: %s (Area: %s)" %
			[zone_data.name, zone_data.area_id])

	# Initialize slots if not already done
	if not battle_area.slots_created:
		await battle_area._initialize_slots()

	# Spawn enemies (use existing method)
	battle_area.spawn_test_wave()

	# AUTO-START combat after enemies spawn
	await get_tree().create_timer(0.1).timeout
	_auto_start_combat()

func _on_kingdom_clicked(kingdom_id: String) -> void:
	"""Handle kingdom click from world map"""
	if GameLogger.ENABLED:
		print("[BattleTab] Kingdom clicked: %s" % kingdom_id)

	_show_region_zoom(kingdom_id)

func _on_zone_clicked(zone_data: ZoneData) -> void:
	"""Handle zone click from region zoom"""
	if GameLogger.ENABLED:
		print("[BattleTab] Zone clicked: %s" % zone_data.name)

	# Convert ZoneData to Dictionary for exploration controller
	var zone_dict = {
		"id": zone_data.id,
		"name": zone_data.name,
		"level_range": zone_data.level_range,
		"enemies": zone_data.enemies,
		"boss_types": [],  # Will be loaded from zones.json
		"metin_types": [],  # Will be loaded from zones.json
		"gold_min": zone_data.gold_min,
		"gold_max": zone_data.gold_max,
		"xp_min": zone_data.xp_min,
		"xp_max": zone_data.xp_max,
		"area_id": zone_data.area_id
	}

	# Enter exploration mode
	if exploration_controller:
		exploration_controller.enter_zone(zone_dict)

	# Switch to battle view
	_show_battle_view()

func _show_battle_view() -> void:
	"""Show battle area (for exploration system)"""
	current_nav_state = NavigationState.BATTLE

	# Hide other views
	if world_map_view:
		world_map_view.visible = false
	if region_zoom_view:
		region_zoom_view.visible = false

	# Show battle area
	if battle_area:
		battle_area.visible = true

		print("[BattleTab] _show_battle_view() - BattleArea size: ", battle_area.size)
		print("[BattleTab] RightPanel size: ", $HSplit/RightPanel.size)

		# Background is already loaded in BattleArea._ready()
		# Only change it if we have a specific zone
		if selected_zone and selected_zone.background_key:
			print("[BattleTab] Loading zone background: ", selected_zone.background_key)
			battle_area.change_background(selected_zone.background_key)
		else:
			print("[BattleTab] Using default background (already loaded in _ready)")

	# Show skill bar
	if combat_skill_bar:
		combat_skill_bar.visible = true

	# Show exit button
	if exit_battle_button:
		exit_battle_button.visible = true

	if GameLogger.ENABLED:
		print("[BattleTab] Showing battle view (exploration mode)")

func _on_back_to_world_map() -> void:
	"""Handle back button from region zoom"""
	if GameLogger.ENABLED:
		print("[BattleTab] Back to world map")

	_show_world_map()

func get_navigation_state() -> int:
	"""Get current navigation state (for testing)"""
	return current_nav_state

func get_battle_active() -> bool:
	"""Check if battle is currently active"""
	return is_battle_active

func is_in_battle() -> bool:
	"""Public method to check if currently in battle"""
	return is_battle_active

# ==================== AUTO-COMBAT SYSTEM ====================

func _start_player_attack_timer() -> void:
	"""Avvia il timer di attacco del player"""
	# Rimuovi timer esistente
	if player_attack_timer != null and is_instance_valid(player_attack_timer):
		player_attack_timer.queue_free()

	# Crea nuovo timer
	player_attack_timer = Timer.new()
	player_attack_timer.wait_time = PLAYER_ATTACK_INTERVAL
	player_attack_timer.one_shot = false
	player_attack_timer.timeout.connect(_on_player_attack)
	add_child(player_attack_timer)
	player_attack_timer.start()

	if GameLogger.ENABLED:
		print("[BattleTab] Player attack timer started (interval: %.1fs)" % PLAYER_ATTACK_INTERVAL)

func _start_enemy_attack_timers() -> void:
	"""Avvia i timer di attacco per tutti i nemici vivi"""
	if not battle_area:
		return

	# Ottieni tutti gli slot nemici
	var enemy_slots = battle_area.get_all_enemy_slots()

	for slot in enemy_slots:
		if slot.is_enemy_alive():
			_create_enemy_attack_timer(slot)

func _create_enemy_attack_timer(enemy_slot: EnemySlot) -> void:
	"""Crea un timer di attacco per un singolo nemico"""
	# Timer randomizzato tra 2.8 e 3.2 secondi
	var interval = randf_range(ENEMY_ATTACK_INTERVAL_MIN, ENEMY_ATTACK_INTERVAL_MAX)

	var timer = Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	timer.timeout.connect(_on_enemy_attack.bind(enemy_slot))
	add_child(timer)
	timer.start()

	# Salva riferimento
	enemy_attack_timers[enemy_slot] = timer

	if GameLogger.ENABLED:
		print("[BattleTab] Enemy attack timer created for %s (interval: %.2fs)" % 
			[enemy_slot.get_enemy_name(), interval])

func _stop_all_combat_timers() -> void:
	"""Ferma tutti i timer di combattimento"""
	# Ferma timer player
	if player_attack_timer != null and is_instance_valid(player_attack_timer):
		player_attack_timer.stop()
		player_attack_timer.queue_free()
		player_attack_timer = null

	# Ferma timer nemici
	for timer in enemy_attack_timers.values():
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	enemy_attack_timers.clear()

	# OLD SYSTEM: hide_enemy_attack_timer() removed
	# Enemy attack bars now handled per-enemy in EnemySlot

	if GameLogger.ENABLED:
		print("[BattleTab] All combat timers stopped")

func _update_enemy_attack_bar() -> void:
	"""OLD FUNCTION - No longer used. Enemy attack bars now handled per-enemy in EnemySlot"""
	pass
	# This function is kept as a stub to avoid breaking existing _process() calls
	# but does nothing. Attack bars are now shown under each enemy individually.

func _on_player_attack() -> void:
	"""Il player attacca un nemico casuale"""
	if not is_battle_active or not battle_area:
		return

	# Ottieni tutti i nemici vivi
	var alive_enemies = battle_area.get_alive_enemies()

	if alive_enemies.is_empty():
		if GameLogger.ENABLED:
			print("[BattleTab] No alive enemies to attack")
		return

	# Scegli un nemico casuale
	var target = alive_enemies[randi() % alive_enemies.size()]

	# Infliggi danno
	if target and target.is_enemy_alive():
		target.take_damage(PLAYER_DAMAGE)

		if GameLogger.ENABLED:
			print("[BattleTab] Player attacks %s for %d damage" % 
				[target.get_enemy_name(), PLAYER_DAMAGE])

func _on_enemy_attack(enemy_slot: EnemySlot) -> void:
	"""Un nemico attacca il player"""
	if not is_battle_active:
		return

	# Verifica che il nemico sia ancora vivo
	if not enemy_slot or not is_instance_valid(enemy_slot) or not enemy_slot.is_enemy_alive():
		# Rimuovi il timer se il nemico è morto
		if enemy_attack_timers.has(enemy_slot):
			var timer = enemy_attack_timers[enemy_slot]
			if is_instance_valid(timer):
				timer.stop()
				timer.queue_free()
			enemy_attack_timers.erase(enemy_slot)
		return

	# Infliggi danno al player
	_player_take_damage(ENEMY_DAMAGE)

	if GameLogger.ENABLED:
		print("[BattleTab] %s attacks player for %d damage" % 
			[enemy_slot.get_enemy_name(), ENEMY_DAMAGE])

func _player_take_damage(amount: int) -> void:
	"""Il player riceve danno"""
	if not character_display:
		return

	# TODO: Implementare HP del player e game over
	# Per ora solo log
	if GameLogger.ENABLED:
		print("[BattleTab] Player takes %d damage (HP system TODO)" % amount)

	# Mostra damage number sul character display (opzionale)
	# character_display.show_damage(amount)

# ==================== SKILL SYSTEM ====================

func _activate_skill_aoe() -> void:
	"""Attiva la skill AoE che colpisce tutti i nemici 3 volte in 0.5s"""
	if not skill_aoe_ready:
		if GameLogger.ENABLED:
			print("[BattleTab] ❌ Skill AoE in cooldown!")
		return

	if not battle_area:
		return

	var alive_enemies = battle_area.get_alive_enemies()
	if alive_enemies.is_empty():
		if GameLogger.ENABLED:
			print("[BattleTab] ❌ No enemies to hit with AoE!")
		return

	if GameLogger.ENABLED:
		print("[BattleTab] 🔥 SKILL AOE ACTIVATED! Hitting %d enemies 3 times!" % alive_enemies.size())

	# Imposta skill in cooldown
	skill_aoe_ready = false

	# Esegui 3 colpi in 0.5 secondi
	var hits_delay = SKILL_AOE_DURATION / float(SKILL_AOE_HITS)  # 0.5s / 3 = ~0.167s tra ogni colpo

	for hit_index in range(SKILL_AOE_HITS):
		var delay = hits_delay * hit_index
		get_tree().create_timer(delay).timeout.connect(func():
			_execute_aoe_hit(hit_index + 1)
		)

	# Avvia cooldown dopo l'ultima hit
	get_tree().create_timer(SKILL_AOE_DURATION + 0.1).timeout.connect(func():
		_start_skill_aoe_cooldown()
	)

func _execute_aoe_hit(hit_number: int) -> void:
	"""Esegue un singolo colpo AoE su tutti i nemici vivi"""
	if not battle_area or not is_battle_active:
		return

	var alive_enemies = battle_area.get_alive_enemies()

	if GameLogger.ENABLED:
		print("[BattleTab] 💥 AoE Hit #%d on %d enemies" % [hit_number, alive_enemies.size()])

	for enemy in alive_enemies:
		if enemy and enemy.is_enemy_alive():
			enemy.take_damage(SKILL_AOE_DAMAGE)

func _start_skill_aoe_cooldown() -> void:
	"""Avvia il timer di cooldown per la skill AoE"""
	if GameLogger.ENABLED:
		print("[BattleTab] ⏰ Skill AoE cooldown started (%.1fs)" % SKILL_AOE_COOLDOWN)

	# Crea timer di cooldown
	if skill_aoe_timer != null and is_instance_valid(skill_aoe_timer):
		skill_aoe_timer.queue_free()

	skill_aoe_timer = Timer.new()
	skill_aoe_timer.wait_time = SKILL_AOE_COOLDOWN
	skill_aoe_timer.one_shot = true
	skill_aoe_timer.timeout.connect(_on_skill_aoe_ready)
	add_child(skill_aoe_timer)
	skill_aoe_timer.start()

func _on_skill_aoe_ready() -> void:
	"""Callback quando la skill AoE è di nuovo pronta"""
	skill_aoe_ready = true

	if GameLogger.ENABLED:
		print("[BattleTab] ✅ Skill AoE READY!")

	if skill_aoe_timer != null and is_instance_valid(skill_aoe_timer):
		skill_aoe_timer.queue_free()
		skill_aoe_timer = null

# ==================== SKILL SYSTEM CALLBACKS ====================

func _on_skill_cast_started(skill) -> void:
	"""Callback when a skill starts casting"""
	if GameLogger.ENABLED:
		print("[BattleTab] 🔮 Casting: %s" % skill.name)

func _on_skill_cast_completed(skill) -> void:
	"""Callback when a skill completes casting"""
	if GameLogger.ENABLED:
		print("[BattleTab] ✨ Cast Complete: %s" % skill.name)

func _on_buff_applied(buff_name: String, duration: float) -> void:
	"""Callback when a buff is applied to player"""
	if GameLogger.ENABLED:
		print("[BattleTab] 💪 Buff Applied: %s for %.1fs" % [buff_name, duration])

func _on_buff_expired(buff_name: String) -> void:
	"""Callback when a buff expires"""
	if GameLogger.ENABLED:
		print("[BattleTab] ⏱️ Buff Expired: %s" % buff_name)

# ==================== PUBLIC API FOR SKILLS ====================

func get_skill_cast_controller() -> SkillCastController:
	"""Get the skill cast controller (for Skills tab integration)"""
	return skill_cast_controller

func _on_skills_loadout_changed() -> void:
	"""Handle loadout change from SkillsTab - reload from file"""
	if GameLogger.ENABLED:
		print("[BattleTab] 🔄 Received loadout_changed signal - reloading from file...")

	# Simply reload from the saved file
	_load_skills_from_loadout()

	if GameLogger.ENABLED:
		print("[BattleTab] ✅ Loadout reloaded from file")

func _toggle_skills_tab_overlay(show: bool) -> void:
	"""Show/hide battle overlay on Skills Tab"""
	var skills_tab = get_meta("skills_tab", null)
	if not skills_tab:
		if GameLogger.ENABLED:
			print("[BattleTab] ⚠️ No Skills Tab reference found")
		return

	if show:
		if skills_tab.has_method("show_battle_overlay"):
			skills_tab.show_battle_overlay()
	else:
		if skills_tab.has_method("hide_battle_overlay"):
			skills_tab.hide_battle_overlay()

# ==================== EXPLORATION SYSTEM HANDLERS ====================

func _on_exploration_combat_started() -> void:
	"""Handle combat start from exploration"""
	if GameLogger.ENABLED:
		print("[BattleTab] Exploration combat started")

	# Update battle state
	is_battle_active = true

	# Show Skills Tab overlay
	_toggle_skills_tab_overlay(true)

func _on_exploration_combat_ended() -> void:
	"""Handle combat end from exploration"""
	if GameLogger.ENABLED:
		print("[BattleTab] Exploration combat ended")

	# Don't set is_battle_active = false yet
	# Transition phase is still part of battle

func _on_exploration_zone_exited() -> void:
	"""Handle zone exit"""
	if GameLogger.ENABLED:
		print("[BattleTab] Exploration zone exited")

	is_battle_active = false

	# Hide Skills Tab overlay
	_toggle_skills_tab_overlay(false)

	# Hide exit button
	if exit_battle_button:
		exit_battle_button.visible = false

# ==================== VISIBILITY HANDLING ====================

func _on_battle_tab_visibility_changed() -> void:
	"""Refresh CharacterDisplay when BattleTab becomes visible"""
	print("[BattleTab] visibility_changed - visible: %s" % visible)

	if visible and character_display:
		print("[BattleTab] Forcing CharacterDisplay refresh...")

		# Force visibility change on CharacterDisplay
		if character_display.has_method("_on_visibility_changed"):
			character_display._on_visibility_changed()

		# Also call these directly
		if character_display.has_method("_refresh_all_equipment"):
			character_display._refresh_all_equipment()
		if character_display.has_method("_update_all_stats"):
			character_display._update_all_stats()

		print("[BattleTab] ✅ CharacterDisplay refreshed")

# ============================================
# DEATH SYSTEM
# ============================================

func _on_player_died() -> void:
	"""Chiamato quando il giocatore muore (HP <= 0)"""
	print("[BattleTab] 💀 Player died!")

	# Stop combat immediately
	if is_battle_active:
		print("[BattleTab] Stopping battle...")
		stop_battle()
		print("[BattleTab] Battle stopped, is_battle_active: %s" % is_battle_active)

	# Clear all enemies manually to ensure they stop attacking
	# CRITICAL: Use exploration_controller's slot_manager if available
	if exploration_controller and exploration_controller.slot_manager:
		print("[BattleTab] Clearing all enemy slots via ExplorationController...")
		exploration_controller.slot_manager.clear_all_slots()
		print("[BattleTab] Enemy slots cleared via ExplorationController")
	elif battle_area:
		print("[BattleTab] Clearing all enemy slots via BattleArea...")
		battle_area.clear_all_slots()
		print("[BattleTab] Enemy slots cleared via BattleArea")

	# Cleanup gathering node if it exists
	if current_gathering_node and is_instance_valid(current_gathering_node):
		print("[BattleTab] Removing gathering node on death...")
		current_gathering_node.queue_free()
		current_gathering_node = null
	pending_gathering_node_type = ""
	_hide_gathering_skill_display()
	print("[BattleTab] Gathering node cleanup complete")

	# CRITICAL: Exit the zone to reset exploration state
	if exploration_controller:
		print("[BattleTab] Exiting zone to reset exploration state...")
		exploration_controller.exit_zone()
		print("[BattleTab] Zone exited - state reset to IDLE")

	# Resurrect player immediately (before showing death screen)
	_resurrect_player()

	# Apply death penalty (5% XP loss)
	_apply_death_penalty()

	# Show death message
	await _show_death_screen()

	# CRITICAL: Check if still valid after await (user might have changed tabs)
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Return to world map
	_show_world_map()
	print("[BattleTab] ✅ Returned to world map after death")

func _show_death_screen() -> void:
	"""Mostra messaggio 'SEI MORTO'"""
	# Create death overlay
	var death_overlay = ColorRect.new()
	death_overlay.color = Color(0, 0, 0, 0.8)
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.z_index = 999
	death_overlay.name = "DeathOverlay"

	# Create death label
	var death_label = Label.new()
	death_label.text = "SEI MORTO"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.set_anchors_preset(Control.PRESET_CENTER)

	# Make text large and red
	death_label.add_theme_font_size_override("font_size", 72)
	death_label.add_theme_color_override("font_color", Color.RED)

	death_overlay.add_child(death_label)
	add_child(death_overlay)

	# Auto-remove after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(death_overlay):
		death_overlay.queue_free()

func _apply_death_penalty() -> void:
	"""Toglie 5% XP del livello corrente"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# TODO: Implementare sistema XP se non esiste già
	# Per ora solo log
	print("[BattleTab] ⚠️ Death penalty: -5% XP (not yet implemented)")

func _resurrect_player() -> void:
	"""Resuscita il giocatore con HP pieno"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not "character_stats" in gs:
		return

	var stats = gs.character_stats
	if stats:
		stats.current_hp = stats.get_stat("max_hp")
		stats.hp_changed.emit(stats.current_hp, stats.get_stat("max_hp"))
		print("[BattleTab] ✅ Player resurrected with full HP")

# ==================== GATHERING SYSTEM ====================

func show_gathering_node_during_combat() -> void:
	"""Show gathering node small in corner during combat"""
	if pending_gathering_node_type == "":
		return

	print("[GATHERING] 🌿 Spawning gathering node during combat: %s" % pending_gathering_node_type)

	# Get node data
	var node_data = GatheringDatabase.get_node_data(pending_gathering_node_type)
	if node_data.is_empty():
		print("[GATHERING] ERROR: Failed to load gathering node data")
		return

	# Load and instantiate
	var gathering_node_scene = load("res://scenes/gathering/GatheringNode.tscn")
	if not gathering_node_scene:
		print("[GATHERING] ERROR: Failed to load GatheringNode.tscn")
		return

	current_gathering_node = gathering_node_scene.instantiate()
	add_child(current_gathering_node)
	current_gathering_node.z_index = 100

	# Setup with data
	current_gathering_node.setup_node(node_data)

	# Position small in top-right corner
	var viewport_size = get_viewport_rect().size
	current_gathering_node.position = Vector2(viewport_size.x - 220, 20)
	current_gathering_node.scale = Vector2(0.6, 0.6)  # Small during combat
	current_gathering_node.visible = true

	print("[GATHERING] ✅ Gathering node visible in corner during combat")

func _on_all_enemies_cleared() -> void:
	"""Called when all enemies are defeated"""
	print("[GATHERING] 🎉 All enemies cleared!")
	print("[GATHERING] pending_gathering_node_type = '%s'" % pending_gathering_node_type)

	# Check if there's a gathering node to activate
	if pending_gathering_node_type != "":
		print("[GATHERING] Found gathering node, waiting 1 second...")
		await get_tree().create_timer(1.0).timeout
		print("[GATHERING] Animating to center and starting gathering...")
		_animate_and_start_gathering()
	else:
		print("[GATHERING] No gathering node, ExplorationCombatController will handle transition")
	# Note: If no gathering, ExplorationCombatController already handles transition via its own _on_all_enemies_cleared

func _animate_and_start_gathering() -> void:
	"""Animate existing gathering node to center and start gathering"""
	if not current_gathering_node:
		print("[GATHERING] ERROR: No gathering node to animate!")
		return

	print("[GATHERING] Animating node to center...")

	# Calculate center position
	var viewport_size = get_viewport_rect().size
	var center_pos = Vector2(
		(viewport_size.x - current_gathering_node.size.x) / 2,
		(viewport_size.y - current_gathering_node.size.y) / 2
	)

	# Animate to center with scale 1.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(current_gathering_node, "position", center_pos, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(current_gathering_node, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished
	print("[GATHERING] ✅ Animation complete")

	# Show gathering skill display
	_show_gathering_skill_display(pending_gathering_node_type)

	# Connect signals
	print("[GATHERING] Connecting signals...")
	current_gathering_node.gathering_attempt_complete.connect(_on_gathering_attempt)
	current_gathering_node.all_attempts_complete.connect(_on_gathering_complete)

	# Stop skills before gathering starts
	if skill_cast_controller:
		skill_cast_controller.stop_combat()
		if GameLogger.ENABLED:
			print("[GATHERING] ⚔️ Skills disabled during gathering")

	# Activate
	print("[GATHERING] Activating node...")
	current_gathering_node.is_active = true

	print("[GATHERING] Waiting 0.3 seconds...")
	await get_tree().create_timer(0.3).timeout

	print("[GATHERING] Calling start_gathering()...")
	current_gathering_node.start_gathering()
	print("[GATHERING] ✅ Gathering started!")

func _find_empty_inventory_position(gs, item_size: Vector2i) -> Vector2i:
	"""Find first available position in inventory grid for an item of given size"""
	# Get inventory grid dimensions from GameState
	# Default: 10 cols x 8 rows (standard inventory size)
	var cols = 10
	var rows = 8

	# Build occupancy grid from existing inventory_items
	var grid_occupied = []
	for y in range(rows):
		var row = []
		for x in range(cols):
			row.append(false)
		grid_occupied.append(row)

	# Mark occupied cells
	for inv_item in gs.inventory_items:
		var pos = inv_item.get("pos")
		var inv_item_id = inv_item.get("item_id", "")

		# Convert Dictionary to Vector2i if needed
		var pos_vec: Vector2i
		if pos is Dictionary:
			pos_vec = Vector2i(pos.get("x", 0), pos.get("y", 0))
		else:
			pos_vec = pos

		# Get item size from database
		var inv_item_data = gs.data.items.get(inv_item_id, {})
		var inv_item_size = Vector2i(1, 1)
		if inv_item_data.has("size") and inv_item_data.size is Array and inv_item_data.size.size() >= 2:
			inv_item_size = Vector2i(inv_item_data.size[0], inv_item_data.size[1])

		# Mark all cells occupied by this item
		for y in range(pos_vec.y, min(pos_vec.y + inv_item_size.y, rows)):
			for x in range(pos_vec.x, min(pos_vec.x + inv_item_size.x, cols)):
				if y < rows and x < cols:
					grid_occupied[y][x] = true

	# Find first empty position that fits the item
	for y in range(rows):
		for x in range(cols):
			# Check if item fits at this position
			if x + item_size.x > cols or y + item_size.y > rows:
				continue  # Doesn't fit

			# Check if all required cells are free
			var can_place = true
			for dy in range(item_size.y):
				for dx in range(item_size.x):
					if grid_occupied[y + dy][x + dx]:
						can_place = false
						break
				if not can_place:
					break

			if can_place:
				return Vector2i(x, y)

	# No space found
	return Vector2i(-1, -1)

func _on_gathering_attempt(items: Array) -> void:
	"""Called after each gathering attempt"""
	print("[GATHERING] Attempt complete - Got %d items" % items.size())

func _on_gathering_complete(total_items: Array) -> void:
	"""Called when all gathering attempts are done"""
	print("[GATHERING] 🎁 All attempts complete! Total: %d items" % total_items.size())

	# Get gathering node position for orb spawning
	var spawn_position = Vector2(400, 300)  # Default center
	if current_gathering_node and is_instance_valid(current_gathering_node):
		spawn_position = current_gathering_node.global_position + current_gathering_node.size / 2

	# Spawn loot orbs instead of adding directly
	var gs = get_node_or_null("/root/GameState")
	var loot_orb_manager = get_node_or_null("/root/LootOrbManager")

	if gs and loot_orb_manager:
		for drop in total_items:
			var item_id = drop.get("item_id", "")
			var amount = drop.get("amount", 1)
			var is_critical = drop.get("critical", false)

			if item_id != "":
				# Get full item data from database
				var item_data = gs.data.items.get(item_id, {}).duplicate(true)
				if item_data.is_empty():
					print("[GATHERING] ⚠️ Item not found in database: %s" % item_id)
					continue

				# Add required fields for loot orb
				item_data["id"] = item_id
				if not item_data.has("name"):
					item_data["name"] = item_id

				# Spawn loot orbs for each item (respecting amount)
				for i in range(amount):
					# Slight offset for each orb
					var offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
					var orb_position = spawn_position + offset

					# Get rarity for this item (default to common for gathering items)
					var rarity = "common"
					if item_data.has("bonuses") and item_data.bonuses.size() > 0:
						var bonus_count = item_data.bonuses.size()
						if bonus_count <= 2:
							rarity = "rare"
						elif bonus_count <= 4:
							rarity = "epic"
						else:
							rarity = "legendary"

					# Spawn loot orb
					loot_orb_manager.spawn_orb(item_data, orb_position, rarity)

					if GameLogger.ENABLED:
						var crit_text = " [CRITICAL!]" if is_critical else ""
						print("[GATHERING] ✨ Spawned loot orb: %s%s" % [item_id, crit_text])

					# Small delay between spawns for visual effect
					await get_tree().create_timer(0.05).timeout

	# Cleanup - REMOVE node from scene
	print("[GATHERING] Starting cleanup...")
	if current_gathering_node:
		print("[GATHERING] Removing gathering node from scene")
		current_gathering_node.queue_free()  # Remove from scene tree
		current_gathering_node = null

	# Hide gathering skill display
	_hide_gathering_skill_display()

	pending_gathering_node_type = ""
	print("[GATHERING] Cleanup complete")

	# Start transition to next encounter
	print("[GATHERING] Waiting 1 second before next encounter...")
	await get_tree().create_timer(1.0).timeout
	print("[GATHERING] Calling state_manager.on_combat_ended()...")
	if exploration_controller and exploration_controller.state_manager:
		exploration_controller.state_manager.on_combat_ended()

	print("[GATHERING] ✅ Gathering complete, starting transition")

func _show_gathering_skill_display(node_type: String) -> void:
	"""Show gathering skill display with current level and EXP"""
	if not gathering_skill_display:
		return

	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.gathering_skills:
		return

	# Map node_type to skill name
	var skill_name = ""
	var display_name = ""
	var color = Color.WHITE
	match node_type:
		"mining_node":
			skill_name = "mining"
			display_name = "Mining Node"
			color = Color(0.7, 0.7, 0.8)
		"gathering_node":
			skill_name = "herbalism"
			display_name = "Gathering Node"
			color = Color(0.4, 0.8, 0.4)
		"fishing_pond":
			skill_name = "fishing"
			display_name = "Fishing Node"
			color = Color(0.4, 0.6, 0.9)
		_:
			if GameLogger.ENABLED:
				print("[BattleTab] ⚠️ Unknown gathering node type: %s" % node_type)
			return

	# Store current skill for updates
	set_meta("current_gathering_skill", skill_name)

	# Connect to EXP gain signal if not already connected
	if not gs.gathering_skills.skill_exp_gained.is_connected(_on_gathering_skill_exp_gained):
		gs.gathering_skills.skill_exp_gained.connect(_on_gathering_skill_exp_gained)

	# Update display
	_update_gathering_skill_display()

	# Show the display
	gathering_skill_display.visible = true

	if GameLogger.ENABLED:
		print("[BattleTab] 📊 Showing gathering skill display: %s Level %d" % [skill_name, get_node("/root/GameState").gathering_skills.get_skill_level(skill_name)])

func _update_gathering_skill_display() -> void:
	"""Update gathering skill display with current values"""
	var skill_name = get_meta("current_gathering_skill", "")
	if skill_name == "":
		return

	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.gathering_skills:
		return

	# Get display info
	var display_name = ""
	var color = Color.WHITE
	match pending_gathering_node_type:
		"mining_node":
			display_name = "Mining Node"
			color = Color(0.7, 0.7, 0.8)
		"gathering_node":
			display_name = "Gathering Node"
			color = Color(0.4, 0.8, 0.4)
		"fishing_pond":
			display_name = "Fishing Node"
			color = Color(0.4, 0.6, 0.9)

	# Get skill data
	var level = gs.gathering_skills.get_skill_level(skill_name)
	var current_exp = gs.gathering_skills.get_skill_exp(skill_name)
	var exp_to_next = gs.gathering_skills.get_skill_exp_to_next(skill_name)
	var progress = gs.gathering_skills.get_skill_exp_progress(skill_name)

	# Update labels
	if gathering_skill_name_label:
		gathering_skill_name_label.text = display_name
	if gathering_skill_level_label:
		gathering_skill_level_label.text = "%s Level %d" % [skill_name.capitalize(), level]
		gathering_skill_level_label.add_theme_color_override("font_color", color)
	if gathering_skill_exp_bar:
		gathering_skill_exp_bar.value = progress * 100.0
	if gathering_skill_exp_label:
		gathering_skill_exp_label.text = "%d / %d EXP" % [current_exp, exp_to_next]

func _on_gathering_skill_exp_gained(gained_skill_name: String, amount: int, current_exp: int, exp_to_next: int) -> void:
	"""Called when gathering skill EXP is gained"""
	var active_skill = get_meta("current_gathering_skill", "")

	# Only update if this is the currently displayed skill
	if active_skill == gained_skill_name and gathering_skill_display and gathering_skill_display.visible:
		_update_gathering_skill_display()

		if GameLogger.ENABLED:
			print("[BattleTab] 📊 Updated gathering skill display: +%d EXP (%d/%d)" % [amount, current_exp, exp_to_next])

func _hide_gathering_skill_display() -> void:
	"""Hide gathering skill display"""
	if gathering_skill_display:
		gathering_skill_display.visible = false

	if GameLogger.ENABLED:
		print("[BattleTab] 📊 Hiding gathering skill display")
