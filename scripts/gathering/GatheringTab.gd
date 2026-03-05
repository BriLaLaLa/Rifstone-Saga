# File: res://scripts/gathering/GatheringTab.gd
# Tab for managing gathering equipment (pickaxe, gathering knife, fishing rod)
# Located in Main inventory UI

extends Control

# Tool slot references (to be connected in scene)
@onready var mining_tool_slot: Panel = $VBoxContainer/ToolSlots/MiningSlot
@onready var gathering_tool_slot: Panel = $VBoxContainer/ToolSlots/GatheringSlot
@onready var fishing_tool_slot: Panel = $VBoxContainer/ToolSlots/FishingSlot

# Stats panel
@onready var stats_panel: VBoxContainer = $VBoxContainer/StatsPanel

# Current equipped tools (visual nodes)
var equipped_tool_nodes: Dictionary = {
	"mining_tool": null,
	"gathering_tool": null,
	"fishing_tool": null
}

# Skill level UI references
var skill_level_labels: Dictionary = {
	"mining": null,
	"herbalism": null,
	"fishing": null
}

var skill_exp_bars: Dictionary = {
	"mining": null,
	"herbalism": null,
	"fishing": null
}

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_setup_tool_slots()
	_load_equipped_tools()
	_update_stats_display()
	_connect_to_gathering_skills()
	_update_all_skill_displays()

	if GameLogger.ENABLED:
		print("[GatheringTab] Ready")

func _setup_tool_slots() -> void:
	"""Setup the three tool slots with labels and drop areas"""
	if mining_tool_slot:
		_setup_single_slot(mining_tool_slot, "Mining Tool", "mining", "mining")

	if gathering_tool_slot:
		_setup_single_slot(gathering_tool_slot, "Gathering Tool", "gathering", "herbalism")

	if fishing_tool_slot:
		_setup_single_slot(fishing_tool_slot, "Fishing Tool", "fishing", "fishing")

func _setup_single_slot(slot: Panel, label_text: String, tool_type: String, skill_name: String) -> void:
	"""Setup a single tool slot with skill level display"""
	# Set minimum size (increased to fit skill info)
	slot.custom_minimum_size = Vector2(100, 130)

	# Create VBox container for layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	slot.add_child(vbox)

	# Add tool label
	var label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(label)

	# Add spacer (tool icon will go here when equipped)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	# Add skill info container
	var skill_info = VBoxContainer.new()
	skill_info.add_theme_constant_override("separation", 2)
	vbox.add_child(skill_info)

	# Add skill level label
	var level_label = Label.new()
	level_label.text = "Lv 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 11)

	# Color based on skill type
	match skill_name:
		"mining":
			level_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))  # Gray
		"herbalism":
			level_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))  # Green
		"fishing":
			level_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))  # Blue

	skill_info.add_child(level_label)
	skill_level_labels[skill_name] = level_label

	# Add skill exp bar
	var exp_bar = ProgressBar.new()
	exp_bar.custom_minimum_size = Vector2(0, 8)
	exp_bar.max_value = 100.0
	exp_bar.value = 0.0
	exp_bar.show_percentage = false

	# Style exp bar with skill-specific color
	var bar_style_bg = StyleBoxFlat.new()
	bar_style_bg.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	exp_bar.add_theme_stylebox_override("background", bar_style_bg)

	var bar_style_fill = StyleBoxFlat.new()
	match skill_name:
		"mining":
			bar_style_fill.bg_color = Color(0.7, 0.7, 0.8)
		"herbalism":
			bar_style_fill.bg_color = Color(0.4, 0.8, 0.4)
		"fishing":
			bar_style_fill.bg_color = Color(0.4, 0.6, 0.9)
	exp_bar.add_theme_stylebox_override("fill", bar_style_fill)

	skill_info.add_child(exp_bar)
	skill_exp_bars[skill_name] = exp_bar

	# Style slot panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.border_color = Color(0.5, 0.5, 0.6)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	slot.add_theme_stylebox_override("panel", style)

	# Make droppable
	slot.set_meta("tool_type", tool_type)
	slot.set_meta("skill_name", skill_name)
	slot.gui_input.connect(_on_slot_gui_input.bind(slot, tool_type))

# ==================== TOOL MANAGEMENT ====================

func _load_equipped_tools() -> void:
	"""Load equipped tools from GameState"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	for slot_name in gs.equipped_gathering_tools.keys():
		var tool_id = gs.equipped_gathering_tools[slot_name]
		if tool_id != "":
			_equip_tool_visual(slot_name, tool_id)

func _equip_tool_visual(slot_name: String, tool_id: String) -> void:
	"""Create visual representation of equipped tool"""
	var tool_data = GatheringDatabase.get_tool_data(tool_id)
	if tool_data.is_empty():
		return

	# Get the slot node
	var slot_node = null
	match slot_name:
		"mining_tool":
			slot_node = mining_tool_slot
		"gathering_tool":
			slot_node = gathering_tool_slot
		"fishing_tool":
			slot_node = fishing_tool_slot

	if not slot_node:
		return

	# Clear existing tool visual
	if equipped_tool_nodes[slot_name] and is_instance_valid(equipped_tool_nodes[slot_name]):
		equipped_tool_nodes[slot_name].queue_free()

	# Create tool visual
	var tool_visual = TextureRect.new()
	tool_visual.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tool_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tool_visual.custom_minimum_size = Vector2(64, 64)

	# Load icon
	var icon_path = tool_data.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tool_visual.texture = load(icon_path)
	else:
		# Placeholder
		var placeholder = ColorRect.new()
		placeholder.color = Color(0.6, 0.6, 0.7)
		placeholder.custom_minimum_size = Vector2(64, 64)
		tool_visual.add_child(placeholder)

	slot_node.add_child(tool_visual)
	equipped_tool_nodes[slot_name] = tool_visual

	if GameLogger.ENABLED:
		print("[GatheringTab] Equipped %s in %s" % [tool_data.get("name"), slot_name])

func equip_tool(tool_id: String, slot_name: String) -> bool:
	"""Equip a gathering tool"""
	var tool_data = GatheringDatabase.get_tool_data(tool_id)
	if tool_data.is_empty():
		push_warning("[GatheringTab] Unknown tool: %s" % tool_id)
		return false

	# Verify tool type matches slot
	var tool_type = tool_data.get("type", "")
	var expected_type = ""
	match slot_name:
		"mining_tool":
			expected_type = "mining"
		"gathering_tool":
			expected_type = "gathering"
		"fishing_tool":
			expected_type = "fishing"

	if tool_type != expected_type:
		if GameLogger.ENABLED:
			print("[GatheringTab] Tool type mismatch: %s != %s" % [tool_type, expected_type])
		return false

	# Save to GameState
	var gs = get_node_or_null("/root/GameState")
	if gs:
		# Unequip old tool (return to inventory)
		var old_tool_id = gs.equipped_gathering_tools[slot_name]
		if old_tool_id != "":
			_return_tool_to_inventory(old_tool_id)

		# Equip new tool
		gs.equipped_gathering_tools[slot_name] = tool_id
		gs.on_gathering_tool_equipped.emit(slot_name, tool_id)
		gs.save_game()

	# Update visual
	_equip_tool_visual(slot_name, tool_id)
	_update_stats_display()

	return true

func unequip_tool(slot_name: String) -> void:
	"""Unequip a gathering tool"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	var tool_id = gs.equipped_gathering_tools[slot_name]
	if tool_id == "":
		return

	# Return to inventory
	_return_tool_to_inventory(tool_id)

	# Clear from GameState
	gs.equipped_gathering_tools[slot_name] = ""
	gs.save_game()

	# Clear visual
	if equipped_tool_nodes[slot_name] and is_instance_valid(equipped_tool_nodes[slot_name]):
		equipped_tool_nodes[slot_name].queue_free()
		equipped_tool_nodes[slot_name] = null

	_update_stats_display()

	if GameLogger.ENABLED:
		print("[GatheringTab] Unequipped tool from %s" % slot_name)

func _return_tool_to_inventory(tool_id: String) -> void:
	"""Return a tool to the inventory"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# Add to inventory count
	if not gs.inventory.has(tool_id):
		gs.inventory[tool_id] = 0
	gs.inventory[tool_id] += 1

	# TODO: Add visual item to InventoryTab if it's open
	# This would require a reference to InventoryTab or a signal

	if GameLogger.ENABLED:
		print("[GatheringTab] Returned %s to inventory" % tool_id)

# ==================== STATS DISPLAY ====================

func _update_stats_display() -> void:
	"""Update the stats panel showing all equipped tool stats"""
	if not stats_panel:
		return

	# Clear existing stats
	for child in stats_panel.get_children():
		child.queue_free()

	# Title
	var title = Label.new()
	title.text = "Gathering Stats"
	title.add_theme_font_size_override("font_size", 18)
	stats_panel.add_child(title)

	# Get stats for each equipped tool
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	var total_stats = {
		"mining_power": 0,
		"gathering_power": 0,
		"fishing_power": 0,
		"yield_bonus": 0,
		"speed_bonus": 0.0,
		"critical_chance": 0.0
	}

	for slot_name in gs.equipped_gathering_tools.keys():
		var tool_id = gs.equipped_gathering_tools[slot_name]
		if tool_id != "":
			var tool_data = GatheringDatabase.get_tool_data(tool_id)
			if tool_data.has("stats"):
				var stats = tool_data["stats"]

				# Add power stats (specific to type)
				if stats.has("mining_power"):
					total_stats["mining_power"] += int(stats["mining_power"])
				if stats.has("gathering_power"):
					total_stats["gathering_power"] += int(stats["gathering_power"])
				if stats.has("fishing_power"):
					total_stats["fishing_power"] += int(stats["fishing_power"])

				# Add universal stats
				total_stats["yield_bonus"] += int(stats.get("yield_bonus", 0))
				total_stats["speed_bonus"] += float(stats.get("speed_bonus", 0.0))
				total_stats["critical_chance"] += float(stats.get("critical_chance", 0.0))

	# Display stats
	_add_stat_label("Mining Power: %d" % total_stats["mining_power"])
	_add_stat_label("Gathering Power: %d" % total_stats["gathering_power"])
	_add_stat_label("Fishing Power: %d" % total_stats["fishing_power"])
	_add_stat_label("Yield Bonus: +%d items" % total_stats["yield_bonus"])
	_add_stat_label("Speed Bonus: +%.1f%%" % (total_stats["speed_bonus"] * 100))
	_add_stat_label("Critical Chance: %.1f%%" % (total_stats["critical_chance"] * 100))

func _add_stat_label(text: String) -> void:
	"""Add a stat label to the stats panel"""
	if not stats_panel:
		return

	var label = Label.new()
	label.text = text
	stats_panel.add_child(label)

# ==================== INPUT HANDLING ====================

func _on_slot_gui_input(event: InputEvent, slot: Panel, tool_type: String) -> void:
	"""Handle input on tool slots"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		# Right click to unequip
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var slot_name = ""
			match tool_type:
				"mining":
					slot_name = "mining_tool"
				"gathering":
					slot_name = "gathering_tool"
				"fishing":
					slot_name = "fishing_tool"

			if slot_name != "":
				unequip_tool(slot_name)

# ==================== SKILL LEVEL DISPLAY ====================

func _connect_to_gathering_skills() -> void:
	"""Connect to gathering skill signals"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.gathering_skills:
		if GameLogger.ENABLED:
			print("[GatheringTab] ⚠️ GatheringSkillsManager not found")
		return

	# Connect to skill level up and exp gained signals
	if gs.gathering_skills.has_signal("skill_level_up"):
		if not gs.gathering_skills.skill_level_up.is_connected(_on_gathering_skill_level_up):
			gs.gathering_skills.skill_level_up.connect(_on_gathering_skill_level_up)
			if GameLogger.ENABLED:
				print("[GatheringTab] ✅ Connected to skill_level_up signal")

	if gs.gathering_skills.has_signal("skill_exp_gained"):
		if not gs.gathering_skills.skill_exp_gained.is_connected(_on_gathering_skill_exp_gained):
			gs.gathering_skills.skill_exp_gained.connect(_on_gathering_skill_exp_gained)
			if GameLogger.ENABLED:
				print("[GatheringTab] ✅ Connected to skill_exp_gained signal")

func _update_all_skill_displays() -> void:
	"""Update all gathering skill displays"""
	_update_skill_display("mining")
	_update_skill_display("herbalism")
	_update_skill_display("fishing")

func _update_skill_display(skill_name: String) -> void:
	"""Update a single skill display"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.gathering_skills:
		return

	var level_label = skill_level_labels.get(skill_name)
	var exp_bar = skill_exp_bars.get(skill_name)

	if not level_label or not exp_bar:
		return

	var level = gs.gathering_skills.get_skill_level(skill_name)
	var progress = gs.gathering_skills.get_skill_exp_progress(skill_name)

	level_label.text = "Lv %d" % level
	exp_bar.value = progress * 100.0

	if GameLogger.ENABLED:
		print("[GatheringTab] Updated %s display: Level %d, Progress %.1f%%" % [skill_name, level, progress * 100.0])

func _on_gathering_skill_level_up(skill_name: String, new_level: int) -> void:
	"""Called when a gathering skill levels up"""
	_update_all_skill_displays()

	if GameLogger.ENABLED:
		print("[GatheringTab] 🎉 %s LEVEL UP! New level: %d" % [skill_name.capitalize(), new_level])

func _on_gathering_skill_exp_gained(skill_name: String, amount: int, current_exp: int, exp_to_next: int) -> void:
	"""Called when a gathering skill gains EXP"""
	_update_all_skill_displays()

# ==================== UTILITY ====================

func get_equipped_tool(slot_name: String) -> String:
	"""Get the ID of the equipped tool in a slot"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return ""

	return gs.equipped_gathering_tools.get(slot_name, "")

func is_tool_equipped(tool_id: String) -> bool:
	"""Check if a specific tool is currently equipped"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return false

	for tool in gs.equipped_gathering_tools.values():
		if tool == tool_id:
			return true

	return false
