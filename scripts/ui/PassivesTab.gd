extends Control
class_name PassivesTab

## Passives Tab - Path of Exile style passive skill tree
## Pan with right-click drag, zoom with scroll wheel

# ==================== CONSTANTS ====================
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const PAN_SPEED := 1.0

# ==================== STATE ====================
var current_zoom := 1.0
var is_panning := false
var pan_start_mouse := Vector2.ZERO
var pan_start_canvas := Vector2.ZERO
var current_category := "main"  # main, mining, herbalism, fishing
# NOTE: available_points now comes from GameState.passive_points_by_category
# Access via get_available_points(category)
var passive_nodes: Dictionary = {
	"main": {},
	"mining": {},
	"herbalism": {},
	"fishing": {}
}

# ==================== NODE REFERENCES ====================
@onready var category_tabs: TabBar = $CategoryTabs
@onready var tree_container: Control = $TreeContainer
@onready var tree_canvases: Dictionary = {
	"main": $TreeContainer/MainTreeCanvas,
	"mining": $TreeContainer/MiningTreeCanvas,
	"herbalism": $TreeContainer/HerbalismTreeCanvas,
	"fishing": $TreeContainer/FishingTreeCanvas
}
@onready var points_label: Label = $UI/TopBar/PointsLabel
@onready var reset_button: Button = $UI/TopBar/ResetButton
@onready var tooltip_panel: Panel = $UI/TooltipPanel
@onready var tooltip_label: Label = $UI/TooltipPanel/TooltipLabel

# Skill level UI references
@onready var mining_level_label: Label = $TreeContainer/MiningTreeCanvas/MiningSkillPanel/VBox/MiningLevelLabel
@onready var mining_exp_bar: ProgressBar = $TreeContainer/MiningTreeCanvas/MiningSkillPanel/VBox/MiningExpBar
@onready var mining_exp_label: Label = $TreeContainer/MiningTreeCanvas/MiningSkillPanel/VBox/MiningExpLabel

@onready var herbalism_level_label: Label = $TreeContainer/HerbalismTreeCanvas/HerbalismSkillPanel/VBox/HerbalismLevelLabel
@onready var herbalism_exp_bar: ProgressBar = $TreeContainer/HerbalismTreeCanvas/HerbalismSkillPanel/VBox/HerbalismExpBar
@onready var herbalism_exp_label: Label = $TreeContainer/HerbalismTreeCanvas/HerbalismSkillPanel/VBox/HerbalismExpLabel

@onready var fishing_level_label: Label = $TreeContainer/FishingTreeCanvas/FishingSkillPanel/VBox/FishingLevelLabel
@onready var fishing_exp_bar: ProgressBar = $TreeContainer/FishingTreeCanvas/FishingSkillPanel/VBox/FishingExpBar
@onready var fishing_exp_label: Label = $TreeContainer/FishingTreeCanvas/FishingSkillPanel/VBox/FishingExpLabel

# ==================== READY ====================
func _ready() -> void:
	print("[PassivesTab] Initializing passive skill tree...")

	# Connect tab change signal
	category_tabs.tab_changed.connect(_on_tab_changed)

	# Collect all passive nodes for each category
	_collect_passive_nodes()

	# Connect signals
	reset_button.pressed.connect(_on_reset_pressed)

	# Show initial category
	_switch_to_category("main")

	# Initial state
	_update_unlocked_states()
	_update_points_label()

	# Load saved state
	load_from_gamestate()

	# Connect to level-up signals to update points display
	_connect_to_level_signals()

	# Initialize skill level displays
	_update_skill_level_displays()

	# Draw connections after a frame (positions need to settle)
	call_deferred("_draw_connections")

	var total_nodes = 0
	for cat in passive_nodes:
		total_nodes += passive_nodes[cat].size()
	print("[PassivesTab] ✅ Initialized with %d passive nodes across %d categories" % [total_nodes, passive_nodes.size()])

func _collect_passive_nodes() -> void:
	"""Find all PassiveNode children and store references per category"""
	for category in ["main", "mining", "herbalism", "fishing"]:
		var canvas = tree_canvases[category]
		var nodes_container = canvas.get_node("NodesContainer")

		for child in nodes_container.get_children():
			if child is PassiveNode:
				var node := child as PassiveNode
				passive_nodes[category][node.passive_id] = node

				# Connect signals
				node.node_activated.connect(_on_node_activated)
				node.node_hovered.connect(_on_node_hovered)

				print("[PassivesTab] Found node in %s: %s (%s)" % [category, node.passive_id, node.passive_name])

# ==================== CATEGORY SWITCHING ====================
func _on_tab_changed(tab: int) -> void:
	"""Handle tab change"""
	var categories = ["main", "mining", "herbalism", "fishing"]
	if tab >= 0 and tab < categories.size():
		_switch_to_category(categories[tab])

func _switch_to_category(category: String) -> void:
	"""Switch to a different passive tree category"""
	if not tree_canvases.has(category):
		return

	current_category = category

	# Hide all canvases
	for cat in tree_canvases:
		tree_canvases[cat].visible = false

	# Show current category canvas
	tree_canvases[category].visible = true

	# Update UI
	_update_points_label()
	_update_unlocked_states()
	_draw_connections()

	print("[PassivesTab] Switched to category: %s" % category)

func _get_current_canvas() -> Control:
	"""Get the currently active tree canvas"""
	return tree_canvases[current_category]

func _get_current_nodes() -> Dictionary:
	"""Get passive nodes for current category"""
	return passive_nodes[current_category]

# ==================== INPUT HANDLING ====================
func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom(ZOOM_STEP, mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom(-ZOOM_STEP, mouse_event.position)

		# Pan with right click
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				is_panning = true
				pan_start_mouse = mouse_event.position
				var current_canvas = _get_current_canvas()
				pan_start_canvas = current_canvas.position
			else:
				is_panning = false

	# Pan drag
	if event is InputEventMouseMotion and is_panning:
		var motion := event as InputEventMouseMotion
		var delta := motion.position - pan_start_mouse
		var current_canvas = _get_current_canvas()
		current_canvas.position = pan_start_canvas + delta * PAN_SPEED

func _zoom(delta: float, mouse_pos: Vector2) -> void:
	"""Zoom towards mouse position"""
	var old_zoom := current_zoom
	current_zoom = clamp(current_zoom + delta, ZOOM_MIN, ZOOM_MAX)

	if old_zoom == current_zoom:
		return

	var current_canvas = _get_current_canvas()

	# Apply zoom
	current_canvas.scale = Vector2(current_zoom, current_zoom)

	# Adjust position to zoom towards mouse
	var container_center: Vector2 = tree_container.size / 2
	var zoom_factor: float = current_zoom / old_zoom
	var pos_diff: Vector2 = current_canvas.position - container_center
	current_canvas.position = container_center + pos_diff * zoom_factor

	# Redraw connections
	_draw_connections()

# ==================== NODE LOGIC ====================
func _on_node_activated(node_id: String) -> void:
	"""Handle node activation"""
	var points = get_available_points(current_category)
	if points <= 0:
		print("[PassivesTab] ❌ No points available for %s!" % current_category)
		# TODO: Revert activation
		return

	# Spend point in GameState
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.passive_points_by_category.has(current_category):
		gs.passive_points_by_category[current_category] -= 1

	_update_points_label()
	_update_unlocked_states()
	_draw_connections()

	# Apply passive effect
	_apply_passive_effect(node_id)

	# Save to GameState
	_save_to_gamestate()

func _update_unlocked_states() -> void:
	"""Update which nodes can be clicked based on connections"""
	var current_nodes = _get_current_nodes()

	for node_id in current_nodes:
		var node: PassiveNode = current_nodes[node_id]

		if node.is_activated or node.is_start_node:
			continue

		# Check if any connected node is activated
		var can_unlock := false
		for connected_id in node.connected_nodes:
			if current_nodes.has(connected_id):
				var connected_node: PassiveNode = current_nodes[connected_id]
				if connected_node.is_activated:
					can_unlock = true
					break

		node.set_unlocked(can_unlock)

func _apply_passive_effect(node_id: String) -> void:
	"""Apply the passive effect to character stats"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not "character_stats" in gs or not gs.character_stats:
		return

	var current_nodes = _get_current_nodes()
	var node: PassiveNode = current_nodes.get(node_id)
	if not node:
		return

	var stats = gs.character_stats

	# Parse passive_id to determine effect
	match node_id:
		"str1":
			stats.add_passive_bonus("strength", 5)
		"atk1":
			stats.add_passive_bonus("physical_damage", 10)
		"crit1":
			stats.add_passive_bonus("crit_chance", 3)
		"critdmg":
			stats.add_passive_bonus("crit_damage", 20)
		"vit1":
			stats.add_passive_bonus("vitality", 5)
		"hp1":
			stats.add_passive_bonus("max_hp", 50)
		"regen1":
			stats.add_passive_bonus("hp_regen", 2)
		"def1":
			stats.add_passive_bonus("physical_defense", 10)
		"block1":
			stats.add_passive_bonus("block_chance", 5)
		"spd1":
			stats.add_passive_bonus("attack_speed", 5)
		"eva1":
			stats.add_passive_bonus("evasion", 3)
		"luck1":
			stats.add_passive_bonus("luck", 5)  # luck stat exists in base_stats
		"gold1":
			stats.add_passive_bonus("gold_find", 10)
		"exp1":
			# exp_bonus might not exist in base_stats, check CharacterStats
			# It seems exp_bonus is not in base_stats, maybe add it or use existing?
			# CharacterStats has gold_find, magic_find. No exp_bonus.
			# I'll add exp_bonus to CharacterStats or just ignore for now.
			# Let's check CharacterStats again.
			if stats.base_stats.has("exp_bonus") or stats.passive_bonuses.has("exp_bonus"):
				stats.add_passive_bonus("exp_bonus", 5)
			else:
				print("[PassivesTab] Warning: exp_bonus stat not found")

		# Mining passives
		"mining_speed1":
			stats.add_passive_bonus("mining_speed", 10)
		"mining_yield1":
			stats.add_passive_bonus("mining_yield", 15)
		"ore_quality1":
			stats.add_passive_bonus("rare_ore_chance", 5)
		"pickaxe_mastery":
			stats.add_passive_bonus("tool_durability", 20)
		"gem_chance":
			stats.add_passive_bonus("gem_drop_chance", 3)

		# Herbalism passives
		"gather_speed1":
			stats.add_passive_bonus("gathering_speed", 10)
		"herb_yield1":
			stats.add_passive_bonus("herb_yield", 15)
		"rare_herbs":
			stats.add_passive_bonus("rare_herb_chance", 5)
		"herbalist_eye":
			stats.add_passive_bonus("hidden_herb_chance", 10)
		"potion_bonus":
			stats.add_passive_bonus("potion_ingredient_quality", 20)

		# Fishing passives
		"fishing_speed1":
			stats.add_passive_bonus("fishing_speed", 10)
		"bigger_catch":
			stats.add_passive_bonus("fish_size", 15)
		"rare_fish":
			stats.add_passive_bonus("rare_fish_chance", 5)
		"rod_mastery":
			stats.add_passive_bonus("line_strength", 20)
		"treasure_hook":
			stats.add_passive_bonus("fishing_treasure_chance", 3)

	print("[PassivesTab] Applied passive effect: %s" % node_id)

# ==================== TOOLTIP ====================
func _on_node_hovered(node_id: String, is_hovered: bool) -> void:
	"""Show/hide tooltip"""
	if is_hovered:
		var current_nodes = _get_current_nodes()
		var node: PassiveNode = current_nodes.get(node_id)
		if node:
			tooltip_label.text = node._get_passive_tooltip_text()
			tooltip_panel.visible = true
			
			# Position near mouse
			var mouse_pos := get_viewport().get_mouse_position()
			tooltip_panel.position = mouse_pos + Vector2(16, 16)
			
			# Keep on screen
			var screen_size := get_viewport_rect().size
			if tooltip_panel.position.x + tooltip_panel.size.x > screen_size.x:
				tooltip_panel.position.x = screen_size.x - tooltip_panel.size.x - 8
			if tooltip_panel.position.y + tooltip_panel.size.y > screen_size.y:
				tooltip_panel.position.y = screen_size.y - tooltip_panel.size.y - 8
	else:
		tooltip_panel.visible = false

# ==================== DRAWING ====================
func _draw_connections() -> void:
	"""Draw lines between connected nodes"""
	var current_canvas = _get_current_canvas()
	var connection_lines = current_canvas.get_node("ConnectionLines")
	var current_nodes = _get_current_nodes()

	# Clear existing lines
	for child in connection_lines.get_children():
		child.queue_free()

	# Draw new lines
	var drawn_pairs: Array = []

	for node_id in current_nodes:
		var node: PassiveNode = current_nodes[node_id]

		for connected_id in node.connected_nodes:
			if not current_nodes.has(connected_id):
				continue

			# Avoid drawing same connection twice
			var pair_key := [node_id, connected_id]
			pair_key.sort()
			var pair_str := "%s-%s" % [pair_key[0], pair_key[1]]
			if pair_str in drawn_pairs:
				continue
			drawn_pairs.append(pair_str)

			var connected_node: PassiveNode = current_nodes[connected_id]
			_create_connection_line(node, connected_node, connection_lines)

func _create_connection_line(from_node: PassiveNode, to_node: PassiveNode, connection_lines: Control) -> void:
	"""Create a Line2D between two nodes"""
	var line := Line2D.new()
	line.width = 3.0
	line.antialiased = true

	# Calculate positions relative to ConnectionLines container
	var from_center := from_node.position + from_node.size / 2
	var to_center := to_node.position + to_node.size / 2

	line.add_point(from_center)
	line.add_point(to_center)

	# Color based on activation state
	if from_node.is_activated and to_node.is_activated:
		line.default_color = Color(1.0, 0.8, 0.2, 1.0)  # Gold - both activated
	elif from_node.is_activated or to_node.is_activated:
		line.default_color = Color(0.6, 0.6, 0.8, 0.8)  # Light - one activated
	else:
		line.default_color = Color(0.3, 0.3, 0.4, 0.6)  # Dark - neither activated

	connection_lines.add_child(line)

# ==================== RESET ====================
func _on_reset_pressed() -> void:
	"""Reset all passives (except start node) for current category"""
	print("[PassivesTab] Resetting %s passive tree..." % current_category)

	# Count activated nodes (excluding start)
	var refund_points := 0
	var current_nodes = _get_current_nodes()

	for node_id in current_nodes:
		var node: PassiveNode = current_nodes[node_id]
		if node.is_activated and not node.is_start_node:
			node.is_activated = false
			refund_points += 1
			node._update_visual_state()

	# Refund points in GameState
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.passive_points_by_category.has(current_category):
		gs.passive_points_by_category[current_category] += refund_points

	_update_points_label()
	_update_unlocked_states()
	_draw_connections()

	# Remove stat bonuses (NOTE: This clears ALL bonuses, not just current category)
	# TODO: Implement category-specific bonus clearing
	if gs and "character_stats" in gs and gs.character_stats:
		gs.character_stats.clear_passive_bonuses()
		# Reapply bonuses from other categories
		_reapply_all_passive_effects()

	_save_to_gamestate()
	print("[PassivesTab] ✅ Reset complete for %s, refunded %d points" % [current_category, refund_points])

func _reapply_all_passive_effects() -> void:
	"""Reapply all active passive effects from all categories"""
	for category in passive_nodes:
		for node_id in passive_nodes[category]:
			var node: PassiveNode = passive_nodes[category][node_id]
			if node.is_activated and not node.is_start_node:
				# Temporarily switch category to apply effect correctly
				var old_category = current_category
				current_category = category
				_apply_passive_effect(node_id)
				current_category = old_category

func _update_points_label() -> void:
	"""Update the points display"""
	var points = get_available_points(current_category)
	points_label.text = "Available Points: %d" % points

# ==================== SAVE/LOAD ====================
func _save_to_gamestate() -> void:
	"""Save passive state to GameState"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# Save activated passives per category
	var activated_by_category := {}
	for category in passive_nodes:
		var activated := []
		for node_id in passive_nodes[category]:
			var node: PassiveNode = passive_nodes[category][node_id]
			if node.is_activated and not node.is_start_node:
				activated.append(node_id)
		activated_by_category[category] = activated

	gs.activated_passives_by_category = activated_by_category
	# NOTE: passive_points_by_category is now managed directly in GameState, no need to copy

	var total_activated = 0
	for cat in activated_by_category:
		total_activated += activated_by_category[cat].size()
	print("[PassivesTab] Saved %d activated passives across all categories" % total_activated)

func load_from_gamestate() -> void:
	"""Load passive state from GameState"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# NOTE: Points are now read directly from GameState via get_available_points()
	# No need to copy them to local variable

	# Load activated passives per category
	if "activated_passives_by_category" in gs:
		for category in gs.activated_passives_by_category:
			if not passive_nodes.has(category):
				continue

			for node_id in gs.activated_passives_by_category[category]:
				if passive_nodes[category].has(node_id):
					var node: PassiveNode = passive_nodes[category][node_id]
					node.is_activated = true
					node._update_visual_state()

					# Apply effect
					var old_category = current_category
					current_category = category
					_apply_passive_effect(node_id)
					current_category = old_category

	_update_points_label()
	_update_unlocked_states()
	_draw_connections()
	print("[PassivesTab] Loaded passives from GameState")

# ==================== UTILITY ====================
func get_available_points(category: String) -> int:
	"""Get available points for a category from GameState"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.passive_points_by_category.has(category):
		return gs.passive_points_by_category[category]
	return 0

func _connect_to_level_signals() -> void:
	"""Connect to level-up signals to update points display when levels increase"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		if GameLogger.ENABLED:
			print("[PassivesTab] ⚠️ GameState not found")
		return

	# Connect to combat level up
	if gs.character_stats and gs.character_stats.has_signal("level_up"):
		if not gs.character_stats.level_up.is_connected(_on_combat_level_up):
			gs.character_stats.level_up.connect(_on_combat_level_up)
			if GameLogger.ENABLED:
				print("[PassivesTab] ✅ Connected to combat level_up signal")

	# Connect to gathering skill level ups
	if gs.gathering_skills and gs.gathering_skills.has_signal("skill_level_up"):
		if not gs.gathering_skills.skill_level_up.is_connected(_on_gathering_skill_level_up):
			gs.gathering_skills.skill_level_up.connect(_on_gathering_skill_level_up)
			if GameLogger.ENABLED:
				print("[PassivesTab] ✅ Connected to gathering skill_level_up signal")

func _on_combat_level_up(new_level: int) -> void:
	"""Called when player combat level increases"""
	_update_points_label()

	if GameLogger.ENABLED:
		print("[PassivesTab] Combat level up! New points available")

func _on_gathering_skill_level_up(skill_name: String, new_level: int) -> void:
	"""Called when a gathering skill levels up"""
	_update_points_label()
	_update_skill_level_displays()

	if GameLogger.ENABLED:
		print("[PassivesTab] %s level up! New points available" % skill_name)

func _update_skill_level_displays() -> void:
	"""Update all gathering skill level displays"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.gathering_skills:
		return

	# Update Mining
	if mining_level_label and mining_exp_bar and mining_exp_label:
		var level = gs.gathering_skills.get_skill_level("mining")
		var current_exp = gs.gathering_skills.get_skill_exp("mining")
		var exp_to_next = gs.gathering_skills.get_skill_exp_to_next("mining")
		var progress = gs.gathering_skills.get_skill_exp_progress("mining")

		mining_level_label.text = "Mining Level %d" % level
		mining_exp_bar.value = progress * 100.0
		mining_exp_label.text = "%d / %d EXP" % [current_exp, exp_to_next]

	# Update Herbalism
	if herbalism_level_label and herbalism_exp_bar and herbalism_exp_label:
		var level = gs.gathering_skills.get_skill_level("herbalism")
		var current_exp = gs.gathering_skills.get_skill_exp("herbalism")
		var exp_to_next = gs.gathering_skills.get_skill_exp_to_next("herbalism")
		var progress = gs.gathering_skills.get_skill_exp_progress("herbalism")

		herbalism_level_label.text = "Herbalism Level %d" % level
		herbalism_exp_bar.value = progress * 100.0
		herbalism_exp_label.text = "%d / %d EXP" % [current_exp, exp_to_next]

	# Update Fishing
	if fishing_level_label and fishing_exp_bar and fishing_exp_label:
		var level = gs.gathering_skills.get_skill_level("fishing")
		var current_exp = gs.gathering_skills.get_skill_exp("fishing")
		var exp_to_next = gs.gathering_skills.get_skill_exp_to_next("fishing")
		var progress = gs.gathering_skills.get_skill_exp_progress("fishing")

		fishing_level_label.text = "Fishing Level %d" % level
		fishing_exp_bar.value = progress * 100.0
		fishing_exp_label.text = "%d / %d EXP" % [current_exp, exp_to_next]
