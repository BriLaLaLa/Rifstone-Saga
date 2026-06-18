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
@onready var mana_bar: ProgressBar = $VBox/ManaContainer/ManaBar
@onready var mana_label: Label = $VBox/ManaContainer/ManaLabel

func _ready() -> void:
	for i in range(6):
		skill_slots.append($VBox/SlotsHBox.get_node("SkillSlot%d" % i))

	if GameLogger.ENABLED:
		print("[CombatSkillBar] Ready with 6 skill slots")


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
