extends Panel
class_name SkillSlot

# Skill Slot Component
# Represents a single slot in the active loadout (6 slots total)
# Supports drag & drop and click to equip

signal skill_changed(slot_index: int, skill_id: String)
signal slot_clicked(slot_index: int)

# const LOG removed - using GameLogger

# Slot data
var slot_index: int = 0
var equipped_skill_id: String = ""
var equipped_skill_data: Dictionary = {}

# UI References
@onready var skill_icon: TextureRect = $VBoxContainer/SkillIcon
@onready var skill_name_label: Label = $VBoxContainer/SkillNameLabel
@onready var slot_number_label: Label = $VBoxContainer/SlotNumberLabel
@onready var empty_label: Label = $VBoxContainer/EmptyLabel

# Drag & Drop
var is_drag_preview := false

func _ready() -> void:
	# Setup click detection
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	# Setup visual style
	_setup_style()

	# Show empty state initially
	_update_display()

func _setup_style() -> void:
	"""Setup panel visual style"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", style)

func setup(index: int) -> void:
	"""Initialize slot with index"""
	slot_index = index

	if slot_number_label:
		slot_number_label.text = "Slot %d" % (index + 1)

	_update_display()

	if GameLogger.ENABLED:
		print("[SkillSlot] Setup slot %d" % slot_index)

func equip_skill(skill_id: String) -> void:
	"""Equip a skill to this slot"""
	if skill_id.is_empty():
		clear_slot()
		return

	equipped_skill_id = skill_id

	# Get skill data from GameState
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if "data" in gs and "skills" in gs.data:
			equipped_skill_data = gs.data.skills.get(skill_id, {})

	_update_display()
	skill_changed.emit(slot_index, skill_id)

	if GameLogger.ENABLED:
		print("[SkillSlot] Slot %d equipped: %s" % [slot_index, skill_id])

func clear_slot() -> void:
	"""Clear this slot"""
	equipped_skill_id = ""
	equipped_skill_data = {}
	_update_display()
	skill_changed.emit(slot_index, "")

	if GameLogger.ENABLED:
		print("[SkillSlot] Slot %d cleared" % slot_index)

func _update_display() -> void:
	"""Update visual display"""
	if equipped_skill_id.is_empty():
		# Empty slot
		if skill_icon:
			skill_icon.texture = null
			skill_icon.visible = false
		if skill_name_label:
			skill_name_label.visible = false
		if empty_label:
			empty_label.visible = true
			empty_label.text = "Empty"
	else:
		# Equipped skill
		if skill_icon:
			var icon_path = equipped_skill_data.get("icon", "")
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				skill_icon.texture = load(icon_path)
			else:
				skill_icon.texture = null
			skill_icon.visible = true

		if skill_name_label:
			skill_name_label.text = equipped_skill_data.get("name", equipped_skill_id.capitalize())
			skill_name_label.visible = true

		if empty_label:
			empty_label.visible = false

func get_equipped_skill_id() -> String:
	"""Get the currently equipped skill ID"""
	return equipped_skill_id

func is_empty() -> bool:
	"""Check if slot is empty"""
	return equipped_skill_id.is_empty()

# ==================== DRAG & DROP ====================

func _get_drag_data(_at_position: Vector2) -> Variant:
	"""Start dragging from this slot"""
	# DISABILITATO: Come in Clash Royale, gli slot NON sono draggabili
	# Solo le card nella collezione possono essere trascinate
	return null

	# Vecchio codice commentato per riferimento:
	# if equipped_skill_id.is_empty():
	# 	return null
	# ...


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	"""Check if we can accept this drop"""
	if typeof(data) != TYPE_DICTIONARY:
		return false

	if data.get("type", "") != "skill":
		return false

	# Highlight slot when hovering
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = Color(0.3, 1.0, 0.3)  # Green highlight

	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	"""Handle skill drop"""
	if typeof(data) != TYPE_DICTIONARY:
		return

	var skill_id = data.get("skill_id", "")
	var from_slot = data.get("from_slot", -1)

	if skill_id.is_empty():
		return

	# If dragging from another slot, swap
	if from_slot >= 0:
		# This is a slot-to-slot drag
		var my_skill = equipped_skill_id
		equip_skill(skill_id)

		# Notify the other slot to equip our skill (or clear if we were empty)
		# This will be handled by SkillsTab
	else:
		# This is from collection to slot
		equip_skill(skill_id)

	# Reset border color
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = Color(0.4, 0.4, 0.5)

	if GameLogger.ENABLED:
		print("[SkillSlot] Dropped skill: %s into slot %d" % [skill_id, slot_index])

# ==================== CLICK HANDLING ====================

func _on_gui_input(event: InputEvent) -> void:
	"""Handle click events"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			slot_clicked.emit(slot_index)

			if GameLogger.ENABLED:
				print("[SkillSlot] Slot %d clicked" % slot_index)

# ==================== WIGGLE ANIMATION ====================

func start_wiggle() -> void:
	"""Start elastic bounce animation (Clash Royale style) - ONLY on icon with center pivot"""
	if not skill_icon:
		return

	# Set pivot to CENTER of the icon for natural scaling
	skill_icon.pivot_offset = skill_icon.size / 2.0

	# Reset scale first
	skill_icon.scale = Vector2.ONE

	# Create elastic bounce tween - MORE pronounced than skill cards
	var tween = skill_icon.create_tween()
	tween.set_loops()  # Loop continuously while skill is selectable

	# Elastic spring animation: bigger expansion (1.2x) for slots
	tween.tween_property(skill_icon, "scale", Vector2(1.2, 1.2), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(skill_icon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6)  # Faster breathing than skill cards

	if GameLogger.ENABLED:
		print("[SkillSlot] Started elastic bounce animation on slot %d" % slot_index)

func stop_wiggle() -> void:
	"""Stop elastic bounce animation and reset scale smoothly"""
	if not skill_icon:
		return

	# Kill ALL tweens on the icon
	var tweens = skill_icon.get_tree().get_processed_tweens()
	for tween in tweens:
		if tween.is_valid():
			tween.kill()

	# Smooth return to normal scale
	var reset_tween = skill_icon.create_tween()
	reset_tween.tween_property(skill_icon, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

	if GameLogger.ENABLED:
		print("[SkillSlot] Stopped elastic bounce animation on slot %d" % slot_index)

