# File: res://scripts/battle/TransitionUI.gd
# Post-battle transition UI - shows rewards and next encounter countdown
# CONVERSION: Now uses TransitionUI.tscn instead of creating ~120 lines of UI runtime

extends Control
class_name TransitionUI

# ==================== UI ELEMENTS (@onready from scene) ====================

@onready var main_panel: Panel = $MainPanel
@onready var vbox: VBoxContainer = $MainPanel/VBox

# Title
@onready var title_label: Label = $MainPanel/VBox/TitleLabel

# Rewards display
@onready var gold_label: Label = $MainPanel/VBox/GoldLabel
@onready var xp_label: Label = $MainPanel/VBox/XPLabel
@onready var items_container: HBoxContainer = $MainPanel/VBox/ItemsContainer

# Next encounter info
@onready var next_encounter_label: Label = $MainPanel/VBox/NextEncounterLabel
@onready var auto_continue_check: CheckBox = $MainPanel/VBox/AutoContinueCheck
@onready var skip_button: Button = $MainPanel/VBox/SkipButton

# Pity info (optional)
@onready var pity_info_label: Label = $MainPanel/VBox/PityInfoLabel

# ==================== SIGNALS ====================

signal skip_transition_clicked()

# ==================== INITIALIZATION ====================

var _is_ready: bool = false

func _ready() -> void:
	# CONVERSION: Nodes now loaded from TransitionUI.tscn via @onready
	# Removed ~120 lines of manual UI creation code!

	_is_ready = true

	# Load auto-continue preference
	_load_auto_continue_preference()

	# Connect checkbox toggle
	if auto_continue_check:
		auto_continue_check.toggled.connect(_on_auto_continue_toggled)

	if GameLogger.ENABLED:
		print("[TransitionUI] Initialized from scene")

# ==================== PUBLIC API ====================

func show_transition(rewards: Dictionary, pity_info: Dictionary = {}) -> void:
	"""Show transition UI with rewards"""

	# CRITICAL: Wait for _ready() if nodes aren't loaded yet
	if not _is_ready:
		await ready

	# Update rewards
	_display_rewards(rewards)

	# Update pity info (optional)
	if not pity_info.is_empty():
		_display_pity_info(pity_info)

	# Show UI
	visible = true

	if GameLogger.ENABLED:
		print("[TransitionUI] Showing transition with rewards: %s" % str(rewards))

func hide_transition() -> void:
	"""Hide transition UI"""
	visible = false

	if GameLogger.ENABLED:
		print("[TransitionUI] Hidden")

func _display_rewards(rewards: Dictionary) -> void:
	"""Display rewards information"""

	# Gold
	var gold = rewards.get("gold", 0)
	gold_label.text = "💰 Gold: +%d" % gold

	# XP
	var xp = rewards.get("xp", 0)
	xp_label.text = "⭐ XP: +%d" % xp

	# Items
	_clear_items()

	if rewards.has("items"):
		var items = rewards["items"]
		if items is Array:
			for item in items:
				_add_item_display(item)

func _clear_items() -> void:
	"""Clear items display"""
	for child in items_container.get_children():
		child.queue_free()

func _add_item_display(item_name: String) -> void:
	"""Add item to display"""
	var item_label = Label.new()
	item_label.text = "📦 %s" % item_name
	item_label.add_theme_font_size_override("font_size", 14)
	item_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	items_container.add_child(item_label)

func _display_pity_info(pity_info: Dictionary) -> void:
	"""Display pity system information"""
	if pity_info.is_empty():
		pity_info_label.visible = false
		return

	var miniboss_data = pity_info.get("miniboss", {})
	var metin_data = pity_info.get("metin", {})

	var miniboss_prob = miniboss_data.get("probability", 15.0)
	var metin_prob = metin_data.get("probability", 5.0)

	pity_info_label.text = "📈 Rare Encounter Chances: Miniboss %.1f%% | Metin %.1f%%" % [miniboss_prob, metin_prob]
	pity_info_label.visible = true

# ==================== BUTTON HANDLERS ====================

func _on_skip_pressed() -> void:
	"""Handle skip button click"""
	if GameLogger.ENABLED:
		print("[TransitionUI] Skip button pressed")

	skip_transition_clicked.emit()

# ==================== UPDATE ====================

func update_next_encounter_message(message: String) -> void:
	"""Update next encounter message"""
	next_encounter_label.text = message

func should_auto_continue() -> bool:
	"""Check if auto-continue is enabled"""
	if auto_continue_check:
		return auto_continue_check.button_pressed
	return true  # Default to true

# ==================== AUTO-CONTINUE PREFERENCE ====================

func _load_auto_continue_preference() -> void:
	"""Load auto-continue preference from GameState"""
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	# Check if preference exists
	if "auto_continue_battles" in gs:
		auto_continue_check.button_pressed = gs.auto_continue_battles
		if GameLogger.ENABLED:
			print("[TransitionUI] Loaded auto-continue preference: %s" % gs.auto_continue_battles)
	else:
		# Default to true
		gs.auto_continue_battles = true
		auto_continue_check.button_pressed = true

func _on_auto_continue_toggled(is_pressed: bool) -> void:
	"""Save auto-continue preference when checkbox toggled"""
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.auto_continue_battles = is_pressed
		if GameLogger.ENABLED:
			print("[TransitionUI] Auto-continue preference saved: %s" % is_pressed)
