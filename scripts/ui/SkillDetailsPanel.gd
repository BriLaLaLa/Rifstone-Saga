extends Panel
class_name SkillDetailsPanel

# Skill Details Panel Component
# Shows detailed info about selected skill and available actions
# CONVERSION: Now uses ActionButton.tscn, EquipSlotButton.tscn, StatRow (static utility)

# Scene references
const ACTION_BUTTON_SCENE = preload("res://scenes/ui/ActionButton.tscn")
const EQUIP_SLOT_BUTTON_SCENE = preload("res://scenes/ui/EquipSlotButton.tscn")
# NOTE: StatRow is now a static utility class, no scene needed

# Current skill
var current_skill_id: String = ""
var current_skill_data: Dictionary = {}

# UI References
@onready var skill_name_label: Label = $VBoxContainer/SkillNameLabel
@onready var level_label: Label = $VBoxContainer/ScrollContainer/DetailsContent/LevelLabel
@onready var grade_label: Label = $VBoxContainer/ScrollContainer/DetailsContent/GradeLabel
@onready var xp_progress_bar: ProgressBar = $VBoxContainer/ScrollContainer/DetailsContent/XPProgressBar
@onready var xp_label: Label = $VBoxContainer/ScrollContainer/DetailsContent/XPLabel
@onready var category_label: Label = $VBoxContainer/ScrollContainer/DetailsContent/CategoryLabel
@onready var description_label: Label = $VBoxContainer/ScrollContainer/DetailsContent/DescriptionLabel
@onready var actions_list_container: VBoxContainer = $VBoxContainer/ScrollContainer/DetailsContent/ActionsSection/ActionsListContainer
@onready var promotion_button: Button = $VBoxContainer/ScrollContainer/DetailsContent/PromotionButton

func _ready() -> void:
	# Connect promotion button
	if promotion_button:
		promotion_button.pressed.connect(_on_promotion_button_pressed)

	# Show placeholder message
	_show_placeholder()

func show_skill(skill_id: String) -> void:
	"""Show details for a specific skill"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if not "data" in gs or not "skills" in gs.data:
		if GameLogger.ENABLED:
			print("[SkillDetailsPanel] ERROR: No skills data in GameState!")
		return

	current_skill_id = skill_id
	current_skill_data = gs.data.skills.get(skill_id, {})

	if current_skill_data.is_empty():
		if GameLogger.ENABLED:
			print("[SkillDetailsPanel] WARNING: No data for skill '%s'" % skill_id)
		_show_placeholder()
		return

	# Update all UI elements
	_update_display()

	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Showing details for: %s" % skill_id)

func _update_display() -> void:
	"""Update all UI elements from current_skill_data"""
	# Skill Name
	if skill_name_label:
		skill_name_label.text = current_skill_data.get("name", current_skill_id.capitalize())

	# Level
	if level_label:
		var level = current_skill_data.get("level", 1)
		level_label.text = "Livello: %d" % level

	# Grade
	if grade_label:
		var grade = current_skill_data.get("grade", "N")
		var grade_name = _get_grade_name(grade)
		grade_label.text = "Grado: %s (%s)" % [grade, grade_name]
		_update_grade_color(grade)

	# XP Progress
	if xp_progress_bar and xp_label:
		var current_xp = current_skill_data.get("xp", 0)
		var xp_needed = _get_xp_needed_for_next_level()

		if xp_needed > 0:
			xp_progress_bar.max_value = xp_needed
			xp_progress_bar.value = current_xp
			xp_label.text = "%d / %d XP" % [current_xp, xp_needed]
		else:
			# Max level
			xp_progress_bar.value = xp_progress_bar.max_value
			xp_label.text = "Livello Massimo!"

	# Category
	if category_label:
		var category = current_skill_data.get("category", "unknown")
		var category_name = _get_category_name(category)
		category_label.text = "Categoria: %s" % category_name

	# Description (if exists)
	if description_label:
		var description = current_skill_data.get("description", "")
		if not description.is_empty():
			description_label.text = description
			description_label.visible = true
		else:
			description_label.visible = false

	# Actions List
	_populate_actions_list()

	# Promotion Button
	_update_promotion_button()

func _populate_actions_list() -> void:
	"""Populate the list of available actions for this skill"""
	if not actions_list_container:
		return

	# Clear existing buttons
	for child in actions_list_container.get_children():
		child.queue_free()

	# Check if this is a warrior skill
	if current_skill_data.has("skill_data"):
		var skill_data = current_skill_data.skill_data
		if skill_data.get("type", "") == "warrior_skill":
			_show_warrior_skill_info(skill_data)
			return

	# Get actions for this skill
	var skill_actions = current_skill_data.get("actions", [])

	if skill_actions.is_empty():
		var no_actions_label = Label.new()
		no_actions_label.text = "Nessuna azione disponibile"
		no_actions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		actions_list_container.add_child(no_actions_label)
		return

	# Get GameState for action data
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if not "data" in gs or not "actions" in gs.data:
		return

	# Create button for each action
	for action_id in skill_actions:
		var action_data = gs.data.actions.get(action_id, {})

		if action_data.is_empty():
			continue

		_create_action_button(action_id, action_data)

func _create_action_button(action_id: String, action_data: Dictionary) -> void:
	"""Create a button for an action"""
	# CONVERSION: Use ActionButton.tscn instead of Button.new() + Label.new()
	var button = ACTION_BUTTON_SCENE.instantiate()
	var current_level = current_skill_data.get("level", 1)

	# Setup button with action data
	button.setup(action_id, action_data, current_level)

	# Connect button signal
	button.action_pressed.connect(_on_action_button_pressed)

	actions_list_container.add_child(button)

	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Created action button: %s" % action_id)

func _update_promotion_button() -> void:
	"""Update promotion button state"""
	if not promotion_button:
		return

	var grade = current_skill_data.get("grade", "N")

	if grade == "G":
		# Already max grade
		promotion_button.text = "Grado Massimo"
		promotion_button.disabled = true
		return

	# Check if promotion is available
	var can_promote = _can_promote()

	if can_promote:
		promotion_button.text = "Promuovi a %s" % _get_next_grade(grade)
		promotion_button.disabled = false
	else:
		promotion_button.text = "Promozione Non Disponibile"
		promotion_button.disabled = true

func _can_promote() -> bool:
	"""Check if skill can be promoted"""
	if not has_node("/root/GameState"):
		return false

	var gs = get_node("/root/GameState")

	if gs.has_method("can_promote"):
		return gs.can_promote(current_skill_id)

	# Fallback: check basic requirements
	var level = current_skill_data.get("level", 1)
	var grade = current_skill_data.get("grade", "N")

	match grade:
		"N": return level >= 10
		"A": return level >= 30
		"M": return level >= 60
		_: return false

func _show_placeholder() -> void:
	"""Show placeholder message when no skill is selected"""
	if skill_name_label:
		skill_name_label.text = "Seleziona una Skill"

	# Hide all other elements
	if level_label:
		level_label.visible = false
	if grade_label:
		grade_label.visible = false
	if xp_progress_bar:
		xp_progress_bar.visible = false
	if xp_label:
		xp_label.visible = false
	if category_label:
		category_label.visible = false
	if description_label:
		description_label.visible = false
	if promotion_button:
		promotion_button.visible = false

func get_current_skill_id() -> String:
	"""Get currently displayed skill ID"""
	return current_skill_id

# ==================== UTILITY FUNCTIONS ====================

func _get_grade_name(grade: String) -> String:
	"""Get full name for grade"""
	match grade:
		"N": return "Normale"
		"A": return "Avanzato"
		"M": return "Maestro"
		"G": return "Grandmaster"
		_: return "Sconosciuto"

func _get_next_grade(grade: String) -> String:
	"""Get next grade"""
	match grade:
		"N": return "A"
		"A": return "M"
		"M": return "G"
		_: return grade

func _get_category_name(category: String) -> String:
	"""Get full name for category"""
	match category:
		"gathering": return "Raccolta"
		"production": return "Produzione"
		"combat": return "Combattimento"
		_: return category.capitalize()

func _get_xp_needed_for_next_level() -> int:
	"""Calculate XP needed for next level"""
	var level = current_skill_data.get("level", 1)

	if level >= 99:
		return 0  # Max level

	var curve_type = current_skill_data.get("xp_curve", "linear_easy")

	match curve_type:
		"linear_easy":
			return 100 + (level * 50)
		"linear_medium":
			return 200 + (level * 100)
		"linear_hard":
			return 500 + (level * 200)
		"exponential":
			return int(100 * pow(1.5, level))
		_:
			return 100 + (level * 50)

func _update_grade_color(grade: String) -> void:
	"""Update grade label color"""
	if not grade_label:
		return

	match grade:
		"N":
			grade_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		"A":
			grade_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		"M":
			grade_label.add_theme_color_override("font_color", Color(0.8, 0.3, 1.0))
		"G":
			grade_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))

# ==================== SIGNAL HANDLERS ====================

func _on_action_button_pressed(action_id: String) -> void:
	"""Handle action button press"""
	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Action button pressed: %s" % action_id)

	# Start action via GameState
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")

	if gs.has_method("start_action"):
		var success = gs.start_action(action_id)

		if GameLogger.ENABLED:
			print("[SkillDetailsPanel] Start action result: %s" % success)

func _on_promotion_button_pressed() -> void:
	"""Handle promotion button press"""
	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Promotion button pressed for: %s" % current_skill_id)

	# Try promotion via GameState
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")

	if gs.has_method("try_promotion"):
		gs.try_promotion(current_skill_id)

# ==================== WARRIOR SKILLS ====================

func _show_warrior_skill_info(skill_data: Dictionary) -> void:
	"""Show warrior skill information and equip buttons"""
	var container = actions_list_container

	# Skill description
	var desc_label = Label.new()
	desc_label.text = skill_data.get("description", "")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	container.add_child(desc_label)

	# Separator
	var sep1 = HSeparator.new()
	container.add_child(sep1)

	# Stats grid
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	container.add_child(stats_grid)

	# Cooldown
	_add_stat_row(stats_grid, "⏱️ Cooldown:", "%ds" % skill_data.get("cooldown", 0))

	# Mana Cost
	_add_stat_row(stats_grid, "💙 Mana:", "%d" % skill_data.get("mana_cost", 0))

	# Damage
	var damage = skill_data.get("damage", "0")
	if damage != "0":
		_add_stat_row(stats_grid, "⚔️ Danno:", str(damage))

	# Effect
	if skill_data.has("effect"):
		_add_stat_row(stats_grid, "✨ Effetto:", skill_data.effect)

	# Separator
	var sep2 = HSeparator.new()
	container.add_child(sep2)

	# Equip buttons
	var equip_label = Label.new()
	equip_label.text = "Equipaggia in Slot:"
	equip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_label.add_theme_font_size_override("font_size", 14)
	container.add_child(equip_label)

	# 4 equip buttons (1 per slot)
	# CONVERSION: Use EquipSlotButton.tscn instead of Button.new()
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_hbox.add_theme_constant_override("separation", 8)
	container.add_child(buttons_hbox)

	for i in range(4):
		var equip_btn = EQUIP_SLOT_BUTTON_SCENE.instantiate()
		equip_btn.setup(i)
		equip_btn.slot_pressed.connect(_on_equip_to_slot_pressed)
		buttons_hbox.add_child(equip_btn)

	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Showing warrior skill info for: %s" % skill_data.get("skill_id", "unknown"))

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String) -> void:
	"""Add a row to stats grid"""
	# CONVERSION: Use StatRow static utility instead of 2× Label.new()
	# StatRow.create_labels() adds configured labels directly to grid
	StatRow.create_labels(label_text, value_text, grid)

func _on_equip_to_slot_pressed(slot_index: int) -> void:
	"""Handle equip to slot button press"""
	if not current_skill_data.has("skill_data"):
		return

	var skill_data = current_skill_data.skill_data
	var skill_id = skill_data.get("skill_id", "")

	if skill_id.is_empty():
		return

	if GameLogger.ENABLED:
		print("[SkillDetailsPanel] Equipping %s to slot %d" % [skill_id, slot_index])

	# Find BattleTab
	var main = get_tree().root.get_node_or_null("Main")
	if not main:
		push_error("[SkillDetailsPanel] Main node not found")
		return

	var battle_tab = main.get_node_or_null("TabButtons/BattleTab")
	if not battle_tab:
		push_error("[SkillDetailsPanel] BattleTab not found")
		return

	# Get skill cast controller
	if not battle_tab.has_method("get_skill_cast_controller"):
		push_error("[SkillDetailsPanel] BattleTab doesn't have get_skill_cast_controller method")
		return

	var controller = battle_tab.get_skill_cast_controller()
	if not controller:
		push_error("[SkillDetailsPanel] SkillCastController not found")
		return

	# Equip skill
	controller.equip_skill_to_slot(slot_index, skill_id)

	# Show feedback
	var feedback = Label.new()
	feedback.text = "✅ Equipaggiato in Slot %d!" % (slot_index + 1)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	actions_list_container.add_child(feedback)

	# Remove feedback after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(feedback):
		feedback.queue_free()

	print("[SkillDetailsPanel] ✅ %s equipped to slot %d" % [current_skill_data.get("name", skill_id), slot_index + 1])
