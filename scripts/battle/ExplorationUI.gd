# File: res://scripts/battle/ExplorationUI.gd
# UI for exploration phase - shows progress and zone info

extends Control
class_name ExplorationUI

signal exploration_ui_ready()

@onready var zone_info_label: Label      = $BgPanel/ContentBox/ZoneInfoLabel
@onready var status_label: Label         = $BgPanel/ContentBox/StatusLabel
@onready var progress_bar: ProgressBar   = $BgPanel/ContentBox/ProgressBar
@onready var progress_dots: HBoxContainer = $BgPanel/ContentBox/ProgressDots

var current_dot_index: int = 0
var animation_timer: float = 0.0
const DOT_ANIMATION_SPEED: float = 0.5

func _ready() -> void:
	if GameLogger.ENABLED:
		print("[ExplorationUI] Initialized")
	exploration_ui_ready.emit()

# ==================== PUBLIC API ====================

func show_exploration(zone_data: Dictionary) -> void:
	var zone_name: String = zone_data.get("name", "Unknown Zone")
	var levels = zone_data.get("level_range", [1, 10])
	zone_info_label.text = zone_name + "\nLv %d-%d" % [levels[0], levels[1]]

	progress_bar.value = 0.0
	current_dot_index  = 0
	animation_timer    = 0.0
	visible = true

	if GameLogger.ENABLED:
		print("[ExplorationUI] Showing exploration for: %s" % zone_name)

func hide_exploration() -> void:
	visible = false
	if GameLogger.ENABLED:
		print("[ExplorationUI] Hidden")

func update_progress(progress: float) -> void:
	progress_bar.value = progress * 100.0

func set_status_message(message: String) -> void:
	status_label.text = message

# ==================== DOT ANIMATION ====================

func _process(delta: float) -> void:
	if not visible:
		return
	animation_timer += delta
	if animation_timer >= DOT_ANIMATION_SPEED:
		animation_timer = 0.0
		_animate_dots()

func _animate_dots() -> void:
	var dots := progress_dots.get_children()
	for dot in dots:
		if dot is Label:
			dot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	current_dot_index = (current_dot_index + 1) % 3
	var current_dot = dots[current_dot_index]
	if current_dot is Label:
		current_dot.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
