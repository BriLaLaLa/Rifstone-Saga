# File: res://scripts/battle/CombatSkillBar.gd
# UI per mostrare le 6 skills equipaggiate durante il combattimento
# Mostra icone, nomi, cooldown e stato mana

extends Control
class_name CombatSkillBar

# Riferimenti
var skill_cast_controller = null

# UI Elements
var skill_slots: Array = []  # Array of SkillSlotUI

# Layout
const SLOT_SIZE := Vector2(64, 64)
const SLOT_SPACING := 8
const MANA_BAR_HEIGHT := 20

# Mana bar
var mana_bar: ProgressBar = null
var mana_label: Label = null

func _ready() -> void:
	# Set fixed size (wider to fit 6 slots)
	custom_minimum_size = Vector2(450, 100)

	# Create container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "⚔️ Warrior Skills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Mana bar
	_create_mana_bar(vbox)

	# Skills container
	var skills_hbox = HBoxContainer.new()
	skills_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	skills_hbox.add_theme_constant_override("separation", SLOT_SPACING)
	vbox.add_child(skills_hbox)

	# Create 6 skill slots
	for i in range(6):
		var slot = _create_skill_slot(i)
		skills_hbox.add_child(slot)
		skill_slots.append(slot)

	if GameLogger.ENABLED:
		print("[CombatSkillBar] Ready with 6 skill slots")

func _create_mana_bar(parent: VBoxContainer) -> void:
	"""Create mana bar display"""
	var mana_container = VBoxContainer.new()
	mana_container.custom_minimum_size = Vector2(0, MANA_BAR_HEIGHT + 15)
	parent.add_child(mana_container)

	# Label
	mana_label = Label.new()
	mana_label.text = "Mana: 0/0"
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_label.add_theme_font_size_override("font_size", 12)
	mana_container.add_child(mana_label)

	# Progress bar
	mana_bar = ProgressBar.new()
	mana_bar.custom_minimum_size = Vector2(250, MANA_BAR_HEIGHT)
	mana_bar.show_percentage = false

	# Style the mana bar
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.4, 1.0)  # Blue
	mana_bar.add_theme_stylebox_override("fill", style_box)

	mana_container.add_child(mana_bar)

func _create_skill_slot(slot_index: int) -> Panel:
	"""Create a single skill slot UI"""
	var panel = Panel.new()
	panel.custom_minimum_size = SLOT_SIZE + Vector2(0, 8)  # Extra space for buff bar
	panel.name = "SkillSlot%d" % slot_index

	# Background style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.border_color = Color(0.5, 0.5, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	# Icon
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_bottom = -8  # Make room for buff bar
	icon.modulate = Color(1, 1, 1, 0.3)  # Dim initially
	panel.add_child(icon)

	# Buff indicator progress bar (under icon)
	var buff_bar = ProgressBar.new()
	buff_bar.name = "BuffBar"
	buff_bar.anchor_top = 1.0
	buff_bar.anchor_right = 1.0
	buff_bar.anchor_bottom = 1.0
	buff_bar.offset_top = -6
	buff_bar.offset_bottom = 0
	buff_bar.show_percentage = false
	buff_bar.visible = false

	var buff_style = StyleBoxFlat.new()
	buff_style.bg_color = Color(0.2, 0.8, 0.3)  # Green for buff active
	buff_bar.add_theme_stylebox_override("fill", buff_style)

	var buff_bg_style = StyleBoxFlat.new()
	buff_bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	buff_bar.add_theme_stylebox_override("background", buff_bg_style)

	panel.add_child(buff_bar)

	# Cooldown overlay
	var cooldown_overlay = Panel.new()
	cooldown_overlay.name = "CooldownOverlay"
	cooldown_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cd_style = StyleBoxFlat.new()
	cd_style.bg_color = Color(0, 0, 0, 0.7)
	cooldown_overlay.add_theme_stylebox_override("panel", cd_style)
	cooldown_overlay.visible = false
	panel.add_child(cooldown_overlay)

	# Cooldown text
	var cd_label = Label.new()
	cd_label.name = "CooldownLabel"
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_label.add_theme_font_size_override("font_size", 20)
	cd_label.add_theme_color_override("font_color", Color.WHITE)
	cd_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cd_label.add_theme_constant_override("outline_size", 2)
	cd_label.visible = false
	panel.add_child(cd_label)

	# Skill name label
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Slot %d" % (slot_index + 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 1)
	name_label.position = Vector2(0, SLOT_SIZE.y - 15)
	name_label.size = Vector2(SLOT_SIZE.x, 15)
	panel.add_child(name_label)

	# Casting indicator
	var casting_indicator = Label.new()
	casting_indicator.name = "CastingIndicator"
	casting_indicator.text = "⏳"
	casting_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	casting_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	casting_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	casting_indicator.position = Vector2(-20, 0)
	casting_indicator.size = Vector2(20, 20)
	casting_indicator.add_theme_font_size_override("font_size", 16)
	casting_indicator.visible = false
	panel.add_child(casting_indicator)

	return panel

func set_skill_controller(controller) -> void:
	"""Set the skill cast controller reference"""
	skill_cast_controller = controller

	if skill_cast_controller:
		# Connect signals
		skill_cast_controller.skill_cast_started.connect(_on_skill_cast_started)
		skill_cast_controller.skill_cast_completed.connect(_on_skill_cast_completed)

		# Initial update
		_update_all_slots()

	if GameLogger.ENABLED:
		print("[CombatSkillBar] Connected to SkillCastController")

func _process(delta: float) -> void:
	if skill_cast_controller:
		_update_all_slots()
		_update_mana_bar()

func _update_all_slots() -> void:
	"""Update all skill slots"""
	if not skill_cast_controller:
		return

	var loadout = skill_cast_controller.get_loadout()

	for i in range(6):
		var slot_panel = skill_slots[i]
		var skill = loadout[i] if i < loadout.size() else null

		if skill:
			_update_skill_slot(slot_panel, skill, i)
			slot_panel.visible = true  # Show slot if skill equipped
		else:
			_clear_skill_slot(slot_panel)
			slot_panel.visible = false  # Hide empty slots

func _update_skill_slot(slot_panel: Panel, skill, slot_index: int) -> void:
	"""Update a single skill slot with skill data"""
	var icon = slot_panel.get_node("Icon") as TextureRect
	var name_label = slot_panel.get_node("NameLabel") as Label
	var cd_overlay = slot_panel.get_node("CooldownOverlay") as Panel
	var cd_label = slot_panel.get_node("CooldownLabel") as Label
	var buff_bar = slot_panel.get_node("BuffBar") as ProgressBar

	# Update name
	name_label.text = skill.name

	# Load icon
	if skill.icon_path != "" and ResourceLoader.exists(skill.icon_path):
		var texture = load(skill.icon_path)
		if texture:
			icon.texture = texture

	# Check if this is a buff skill and buff is active
	var buff_active = false
	var buff_remaining = 0.0
	if skill_cast_controller and skill.skill_type == "self" and skill.duration > 0:
		var buff_id = skill.id
		if skill_cast_controller.has_buff(buff_id):
			buff_active = true
			buff_remaining = skill_cast_controller.get_buff_remaining_time(buff_id)

	# Update buff bar
	if buff_active and buff_bar:
		buff_bar.visible = true
		buff_bar.max_value = skill.duration
		buff_bar.value = buff_remaining
	elif buff_bar:
		buff_bar.visible = false

	# Check cooldown
	var cd_remaining = skill.get_cooldown_remaining()

	if cd_remaining > 0:
		# On cooldown
		icon.modulate = Color(0.5, 0.5, 0.5, 0.5)  # Dimmed
		cd_overlay.visible = true
		cd_label.visible = true
		cd_label.text = "%.1f" % cd_remaining

		# Update cooldown overlay height
		var cd_percent = skill.get_cooldown_percent()
		cd_overlay.anchor_top = 1.0 - cd_percent
	elif buff_active:
		# Buff active - show with special color
		icon.modulate = Color(0.5, 1.0, 0.5, 1.0)  # Green tint for active buff
		cd_overlay.visible = false
		cd_label.visible = false
	else:
		# Ready to cast
		icon.modulate = Color(1, 1, 1, 1)  # Full brightness
		cd_overlay.visible = false
		cd_label.visible = false

		# Highlight if it's the next skill to cast
		var is_next = _is_next_skill_to_cast(slot_index)
		if is_next:
			icon.modulate = Color(1.2, 1.2, 0.8, 1)  # Yellow glow

func _is_next_skill_to_cast(slot_index: int) -> bool:
	"""Check if this is the next skill that will be cast"""
	if not skill_cast_controller:
		return false

	# Get player
	var player = skill_cast_controller.player
	if not player:
		return false

	var loadout = skill_cast_controller.get_loadout()

	# Check each slot in priority order
	for i in range(6):
		var skill = loadout[i] if i < loadout.size() else null
		if not skill:
			continue

		# Can this skill be cast?
		if skill.can_cast(player.current_mana):
			return i == slot_index

	return false

func _clear_skill_slot(slot_panel: Panel) -> void:
	"""Clear a skill slot (no skill equipped)"""
	var icon = slot_panel.get_node("Icon") as TextureRect
	var name_label = slot_panel.get_node("NameLabel") as Label
	var cd_overlay = slot_panel.get_node("CooldownOverlay") as Panel
	var cd_label = slot_panel.get_node("CooldownLabel") as Label

	icon.texture = null
	icon.modulate = Color(1, 1, 1, 0.3)
	name_label.text = "Empty"
	cd_overlay.visible = false
	cd_label.visible = false

func _update_mana_bar() -> void:
	"""Update mana bar display"""
	if not skill_cast_controller or not mana_bar or not mana_label:
		return

	var player = skill_cast_controller.player
	if not player:
		return

	var current = player.current_mana
	var maximum = player.get_stat("max_mana")

	mana_bar.max_value = maximum
	mana_bar.value = current
	mana_label.text = "Mana: %d/%d" % [int(current), int(maximum)]

func _on_skill_cast_started(skill) -> void:
	"""Show casting indicator on the skill being cast"""
	var loadout = skill_cast_controller.get_loadout()

	for i in range(skill_slots.size()):
		var slot_panel = skill_slots[i]
		var casting_indicator = slot_panel.get_node("CastingIndicator") as Label

		var slot_skill = loadout[i] if i < loadout.size() else null
		if slot_skill and slot_skill.id == skill.id:
			casting_indicator.visible = true
		else:
			casting_indicator.visible = false

func _on_skill_cast_completed(skill) -> void:
	"""Hide casting indicator"""
	for slot_panel in skill_slots:
		var casting_indicator = slot_panel.get_node("CastingIndicator") as Label
		casting_indicator.visible = false
