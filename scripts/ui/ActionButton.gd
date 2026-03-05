# File: res://scripts/ui/ActionButton.gd
# Reusable action button component for skill actions
# Replaces Button.new() + Label.new() manual creation

extends Button
class_name ActionButton

@onready var lock_icon: Label = $LockIcon

# Action data
var action_id: String = ""
var action_data: Dictionary = {}
var is_locked: bool = false

signal action_pressed(action_id: String)

func setup(id: String, data: Dictionary, current_level: int) -> void:
	"""Setup button with action data"""
	action_id = id
	action_data = data

	# Set button text
	text = data.get("name", id.capitalize())
	tooltip_text = data.get("description", "")

	# Check if available
	var required_level = data.get("required_level", 1)
	is_locked = current_level < required_level

	if is_locked:
		disabled = true
		text += " (Lv. %d richiesto)" % required_level

		# Show lock icon
		if lock_icon:
			lock_icon.visible = true
	else:
		disabled = false
		if lock_icon:
			lock_icon.visible = false

	if GameLogger.ENABLED:
		print("[ActionButton] Setup: %s (Locked: %s)" % [id, is_locked])

func _ready() -> void:
	# Connect button press
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	"""Emit signal when pressed"""
	if not is_locked:
		action_pressed.emit(action_id)
