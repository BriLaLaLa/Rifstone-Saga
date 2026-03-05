# File: res://scripts/battle/ExplorationUI.gd
# UI for exploration phase - shows progress and zone info

extends Control
class_name ExplorationUI

# const LOG removed - using GameLogger

# ==================== UI ELEMENTS ====================

# Main container
var main_panel: Panel = null

# Text elements
var title_label: Label = null
var status_label: Label = null
var zone_info_label: Label = null

# Progress indicator
var progress_bar: ProgressBar = null
var progress_dots: HBoxContainer = null
var current_dot_index: int = 0

# Animation
var animation_timer: float = 0.0
const DOT_ANIMATION_SPEED: float = 0.5

# ==================== DATA ====================

var zone_name: String = "Unknown Zone"
var zone_level_range: String = "Lv 1-10"

# ==================== SIGNALS ====================

signal exploration_ui_ready()

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_create_ui()

	if GameLogger.ENABLED:
		print("[ExplorationUI] Initialized")

	exploration_ui_ready.emit()

func _create_ui() -> void:
	"""Create exploration UI elements"""

	# Main panel (semi-transparent overlay)
	main_panel = Panel.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	main_panel.add_theme_stylebox_override("panel", style)

	add_child(main_panel)

	# Center container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-200, -150)
	vbox.size = Vector2(400, 300)
	vbox.add_theme_constant_override("separation", 20)
	main_panel.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "🔍 EXPLORING"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	title_label.add_theme_constant_override("outline_size", 3)
	vbox.add_child(title_label)

	# Zone info
	zone_info_label = Label.new()
	zone_info_label.text = zone_name + "\n" + zone_level_range
	zone_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_info_label.add_theme_font_size_override("font_size", 18)
	zone_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(zone_info_label)

	# Status message
	status_label = Label.new()
	status_label.text = "Searching for enemies"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(status_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(300, 30)
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false

	# Style progress bar
	var progress_style = StyleBoxFlat.new()
	progress_style.bg_color = Color(0.2, 0.6, 1.0)
	progress_bar.add_theme_stylebox_override("fill", progress_style)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2)
	progress_bar.add_theme_stylebox_override("background", bg_style)

	vbox.add_child(progress_bar)

	# Animated dots (... animation)
	progress_dots = HBoxContainer.new()
	progress_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	progress_dots.add_theme_constant_override("separation", 10)

	for i in range(3):
		var dot = Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 24)
		dot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		progress_dots.add_child(dot)

	vbox.add_child(progress_dots)

	# Start hidden
	visible = false

# ==================== PUBLIC API ====================

func show_exploration(zone_data: Dictionary) -> void:
	"""Show exploration UI with zone data"""

	# Update zone info
	if zone_data.has("name"):
		zone_name = zone_data["name"]

	if zone_data.has("level_range"):
		var levels = zone_data["level_range"]
		zone_level_range = "Lv %d-%d" % [levels[0], levels[1]]

	zone_info_label.text = zone_name + "\n" + zone_level_range

	# Reset progress
	progress_bar.value = 0.0
	current_dot_index = 0
	animation_timer = 0.0

	# Show UI
	visible = true

	if GameLogger.ENABLED:
		print("[ExplorationUI] Showing exploration for: %s" % zone_name)

func hide_exploration() -> void:
	"""Hide exploration UI"""
	visible = false

	if GameLogger.ENABLED:
		print("[ExplorationUI] Hidden")

func update_progress(progress: float) -> void:
	"""Update progress bar (0.0 - 1.0)"""
	progress_bar.value = progress * 100.0

func set_status_message(message: String) -> void:
	"""Update status message"""
	status_label.text = message

# ==================== ANIMATION ====================

func _process(delta: float) -> void:
	"""Animate dots"""
	if not visible:
		return

	animation_timer += delta

	if animation_timer >= DOT_ANIMATION_SPEED:
		animation_timer = 0.0
		_animate_dots()

func _animate_dots() -> void:
	"""Animate progress dots"""
	var dots = progress_dots.get_children()

	# Reset all dots to dim
	for dot in dots:
		if dot is Label:
			dot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	# Highlight current dot
	current_dot_index = (current_dot_index + 1) % 3
	var current_dot = dots[current_dot_index]
	if current_dot is Label:
		current_dot.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))

