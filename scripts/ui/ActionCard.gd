extends Panel
class_name ActionCard

# Action Card Component
# Displays active action with progress bar and time remaining

# const LOG removed - using GameLogger

# Action data
var action_id: String = ""
var action_data: Dictionary = {}

# UI References
@onready var action_name_label: Label = $VBoxContainer/ActionNameLabel
@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar
@onready var time_label: Label = $VBoxContainer/TimeLabel
@onready var cancel_button: Button = $VBoxContainer/CancelButton

func _ready() -> void:
	# Setup visual style
	_setup_style()

	# Connect cancel button
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)

func _setup_style() -> void:
	"""Setup panel visual style"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.25, 0.3, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.5, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

func setup(data: Dictionary) -> void:
	"""Initialize card with action data"""
	action_data = data
	action_id = data.get("id", "unknown")

	# Update UI
	_update_display()

	if GameLogger.ENABLED:
		print("[ActionCard] Setup: %s" % action_id)

func _update_display() -> void:
	"""Update all UI elements from action_data"""
	# Action name
	if action_name_label:
		action_name_label.text = action_data.get("name", action_id.capitalize())

	# Progress bar
	if progress_bar:
		progress_bar.value = 0
		progress_bar.max_value = 100

	# Time label
	if time_label:
		var duration = action_data.get("duration", 5)
		time_label.text = _format_time(duration)

func set_progress(progress_value: float) -> void:
	"""Update progress bar (0.0 to 1.0)"""
	if progress_bar:
		progress_bar.value = progress_value * 100

	# Update time remaining
	if time_label and action_data.has("duration"):
		var duration = action_data.get("duration", 5)
		var remaining = duration * (1.0 - progress_value)
		time_label.text = _format_time(remaining)

func _format_time(seconds: float) -> String:
	"""Format seconds as MM:SS or HH:MM:SS"""
	var total_seconds = int(seconds)

	if total_seconds >= 3600:
		# Hours format
		var hours = total_seconds / 3600
		var minutes = (total_seconds % 3600) / 60
		var secs = total_seconds % 60
		return "%02d:%02d:%02d" % [hours, minutes, secs]
	else:
		# Minutes format
		var minutes = total_seconds / 60
		var secs = total_seconds % 60
		return "%02d:%02d" % [minutes, secs]

func _on_cancel_pressed() -> void:
	"""Handle cancel button click"""
	if GameLogger.ENABLED:
		print("[ActionCard] Cancel requested for: %s" % action_id)

	# Call GameState to cancel action
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if gs.has_method("cancel_action"):
		gs.cancel_action(action_id)


