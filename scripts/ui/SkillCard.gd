extends Panel
class_name SkillCard

# Individual Skill Card Component
# Displays skill icon, name, level, grade, and XP progress

signal clicked(skill_id: String)

# const LOG removed - using GameLogger

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Visual Style - Card")
@export var card_bg_color: Color = Color(0.15, 0.15, 0.2, 0.9)
@export var card_border_color: Color = Color(0.3, 0.3, 0.4)
@export var card_border_width: int = 2
@export var card_corner_radius: int = 4

@export_group("Visual Style - Selection")
@export var selected_border_color: Color = Color(0.2, 0.8, 1.0)  # Bright blue
@export var selected_border_width: int = 3
@export var normal_border_color: Color = Color(0.3, 0.3, 0.4)
@export var normal_border_width: int = 2

@export_group("Grade Colors")
@export var grade_n_color: Color = Color(0.8, 0.8, 0.8)  # Gray (Novice)
@export var grade_a_color: Color = Color(0.3, 0.8, 1.0)  # Blue (Adept)
@export var grade_m_color: Color = Color(0.8, 0.3, 1.0)  # Purple (Master)
@export var grade_g_color: Color = Color(1.0, 0.8, 0.2)  # Gold (Grand Master)

@export_group("Animation - Wiggle")
@export var wiggle_scale_max: float = 1.15
@export var wiggle_expand_duration: float = 0.15
@export var wiggle_contract_duration: float = 0.25
@export var wiggle_pause_duration: float = 0.8
@export var wiggle_reset_duration: float = 0.15

# ==================== INTERNAL VARIABLES ====================
# Skill data
var skill_id: String = ""
var skill_data: Dictionary = {}

# UI References
@onready var skill_icon: TextureRect = $VBoxContainer/SkillIcon
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var level_label: Label = $VBoxContainer/InfoContainer/LevelLabel
@onready var grade_label: Label = $VBoxContainer/InfoContainer/GradeLabel
@onready var xp_bar: ProgressBar = $VBoxContainer/XPBar

# Selection state
var is_selected: bool = false

func _ready() -> void:
	# Setup click detection
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	# Setup visual style
	_setup_style()

func _setup_style() -> void:
	"""Setup panel visual style (usa valori dall'Inspector)"""
	var style = StyleBoxFlat.new()
	style.bg_color = card_bg_color
	style.border_width_left = card_border_width
	style.border_width_right = card_border_width
	style.border_width_top = card_border_width
	style.border_width_bottom = card_border_width
	style.border_color = card_border_color
	style.corner_radius_top_left = card_corner_radius
	style.corner_radius_top_right = card_corner_radius
	style.corner_radius_bottom_left = card_corner_radius
	style.corner_radius_bottom_right = card_corner_radius
	add_theme_stylebox_override("panel", style)

func setup(data: Dictionary) -> void:
	"""Initialize card with skill data"""
	skill_data = data
	skill_id = data.get("id", "unknown")

	# Update UI
	_update_display()

	if GameLogger.ENABLED:
		print("[SkillCard] Setup: %s (Level %d, Grade %s)" %
			[skill_id, data.get("level", 1), data.get("grade", "N")])

func _update_display() -> void:
	"""Update all UI elements from skill_data"""
	# Name
	if name_label:
		name_label.text = skill_data.get("name", skill_id.capitalize())

	# Level
	if level_label:
		var level = skill_data.get("level", 1)
		level_label.text = "Lv. %d" % level

	# Grade
	if grade_label:
		var grade = skill_data.get("grade", "N")
		grade_label.text = grade
		_update_grade_color(grade)

	# XP Progress Bar
	if xp_bar:
		var current_xp = skill_data.get("xp", 0)
		var xp_needed = _get_xp_needed_for_next_level()

		if xp_needed > 0:
			xp_bar.max_value = xp_needed
			xp_bar.value = current_xp
			xp_bar.visible = true
		else:
			# Max level
			xp_bar.visible = false

	# Icon
	if skill_icon:
		var icon_path = skill_data.get("icon", "")
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			skill_icon.texture = load(icon_path)
		else:
			# Fallback icon
			skill_icon.texture = null

func _get_xp_needed_for_next_level() -> int:
	"""Calculate XP needed for next level based on curve"""
	var level = skill_data.get("level", 1)

	if level >= 99:
		return 0  # Max level

	var curve_type = skill_data.get("xp_curve", "linear_easy")

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
	"""Update grade label color based on grade (usa valori dall'Inspector)"""
	if not grade_label:
		return

	match grade:
		"N":
			grade_label.add_theme_color_override("font_color", grade_n_color)
		"A":
			grade_label.add_theme_color_override("font_color", grade_a_color)
		"M":
			grade_label.add_theme_color_override("font_color", grade_m_color)
		"G":
			grade_label.add_theme_color_override("font_color", grade_g_color)

func refresh() -> void:
	"""Refresh card from GameState (for updates)"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if "data" in gs and "skills" in gs.data:
		var updated_data = gs.data.skills.get(skill_id, {})
		if not updated_data.is_empty():
			skill_data = updated_data
			_update_display()

func set_selected(selected: bool) -> void:
	"""Set selection state and update visual with Clash Royale wiggle animation"""
	is_selected = selected

	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		if selected:
			style.border_color = selected_border_color
			style.border_width_left = selected_border_width
			style.border_width_right = selected_border_width
			style.border_width_top = selected_border_width
			style.border_width_bottom = selected_border_width

			# Start wiggle animation (Clash Royale style)
			_start_wiggle_animation()
		else:
			style.border_color = normal_border_color
			style.border_width_left = normal_border_width
			style.border_width_right = normal_border_width
			style.border_width_top = normal_border_width
			style.border_width_bottom = normal_border_width

			# Stop wiggle animation
			_stop_wiggle_animation()

func _start_wiggle_animation() -> void:
	"""Start elastic bounce animation like Clash Royale - ONLY on icon with center pivot"""
	if not skill_icon:
		return

	# Set pivot to CENTER of the icon for natural scaling
	skill_icon.pivot_offset = skill_icon.size / 2.0

	# Reset scale first
	skill_icon.scale = Vector2.ONE

	# Create elastic bounce tween on ICON only (usa valori dall'Inspector)
	var tween = skill_icon.create_tween()
	tween.set_loops()  # Loop continuously while selected

	# Elastic spring animation: expand → bounce back
	tween.tween_property(skill_icon, "scale", Vector2(wiggle_scale_max, wiggle_scale_max), wiggle_expand_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(skill_icon, "scale", Vector2.ONE, wiggle_contract_duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(wiggle_pause_duration)  # Pause before repeating (breathing effect)

func _stop_wiggle_animation() -> void:
	"""Stop elastic bounce animation and reset scale smoothly"""
	if not skill_icon:
		return

	# Kill ALL tweens on the icon
	var tweens = skill_icon.get_tree().get_processed_tweens()
	for tween in tweens:
		if tween.is_valid():
			tween.kill()

	# Smooth return to normal scale (usa valori dall'Inspector)
	var reset_tween = skill_icon.create_tween()
	reset_tween.tween_property(skill_icon, "scale", Vector2.ONE, wiggle_reset_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

func connect_clicked(callable: Callable) -> void:
	"""Connect to clicked signal"""
	if not clicked.is_connected(callable):
		clicked.connect(callable)

func get_skill_id() -> String:
	"""Get this card's skill ID"""
	return skill_id

func _on_gui_input(event: InputEvent) -> void:
	"""Handle click events"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(skill_id)

			if GameLogger.ENABLED:
				print("[SkillCard] Clicked: %s" % skill_id)

# ==================== DRAG & DROP ====================

func _get_drag_data(_at_position: Vector2) -> Variant:
	"""Start dragging this skill card"""
	if skill_id.is_empty():
		return null

	# Check if already equipped - prevent dragging if already in loadout
	if _is_skill_already_equipped():
		if GameLogger.ENABLED:
			print("[SkillCard] Cannot drag: %s is already equipped" % skill_id)
		return null

	# Create drag preview
	var preview = Panel.new()
	preview.custom_minimum_size = Vector2(100, 120)

	var vbox = VBoxContainer.new()
	preview.add_child(vbox)

	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var icon_path = skill_data.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)

	vbox.add_child(icon)

	var label = Label.new()
	label.text = skill_data.get("name", skill_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	set_drag_preview(preview)

	if GameLogger.ENABLED:
		print("[SkillCard] Dragging skill: %s" % skill_id)

	return {
		"type": "skill",
		"skill_id": skill_id,
		"from_slot": -1  # -1 means from collection, not from slot
	}

func _is_skill_already_equipped() -> bool:
	"""Check if this skill is already equipped in any loadout slot"""
	# Find SkillsTab parent
	var skills_tab = _find_skills_tab()
	if not skills_tab:
		return false

	# Check if skill is in any loadout slot
	if skills_tab.has_method("is_skill_equipped"):
		return skills_tab.is_skill_equipped(skill_id)

	return false

func _find_skills_tab() -> Node:
	"""Find the SkillsTab parent node"""
	var current = get_parent()
	while current:
		if current.has_method("is_skill_equipped"):
			return current
		current = current.get_parent()
	return null
