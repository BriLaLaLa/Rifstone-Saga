extends Control
class_name MapClickableArea

# Clickable Area Component for World Map System
# Handles clicks, hover effects, and lock states for kingdoms/zones
# NOTE: Areas are now created directly in the scene with proper anchors

signal clicked()

# Data - Can be set in Inspector
@export var kingdom_id: String = ""
@export var zone_id: String = ""
@export var is_unlocked: bool = true
@export var unlock_requirement: int = 1
@export var zone_name: String = ""

# UI References
var lock_overlay: ColorRect = null
var lock_icon: Label = null
var hover_overlay: ColorRect = null
var tooltip_label: Label = null

# State
var is_hovered: bool = false
var original_modulate: Color = Color.WHITE

func _ready() -> void:
	# Setup mouse input
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	# Store original appearance
	original_modulate = modulate

	# Setup tooltip
	if is_unlocked:
		tooltip_text = zone_name
	else:
		tooltip_text = "🔒 Locked - Level %d Required" % unlock_requirement

	# Create hover overlay
	_create_hover_overlay()

	# Create lock overlay if needed
	if not is_unlocked:
		_create_lock_overlay()

	if GameLogger.ENABLED:
		print("[MapClickableArea] Ready: %s (Unlocked: %s)" % [zone_name, is_unlocked])

func setup(data: Dictionary) -> void:
	"""Initialize clickable area with kingdom/zone data (for dynamic creation)"""
	if data.has("id"):
		# Could be kingdom or zone
		if data.has("zones"):
			# It's a kingdom
			kingdom_id = data["id"]
			zone_name = data.get("name", kingdom_id)
		else:
			# It's a zone
			zone_id = data["id"]
			zone_name = data.get("name", zone_id)
			kingdom_id = ""

	is_unlocked = data.get("unlocked", true)
	unlock_requirement = data.get("unlock_requirement", 1)

	# Parse clickable area (for dynamic positioning)
	if data.has("clickable_area"):
		var area = data["clickable_area"]

		# Set position and size from data
		position = Vector2(area.get("x", 0), area.get("y", 0))
		custom_minimum_size = Vector2(area.get("width", 100), area.get("height", 100))
		size = custom_minimum_size

	# Update tooltip
	if is_unlocked:
		tooltip_text = zone_name
	else:
		tooltip_text = "🔒 Locked - Level %d Required" % unlock_requirement

	if GameLogger.ENABLED:
		print("[MapClickableArea] Setup: %s at %s (Size: %s)" %
			[zone_name, position, size])


func _create_hover_overlay() -> void:
	"""Create semi-transparent overlay for hover effect"""
	hover_overlay = ColorRect.new()
	hover_overlay.name = "HoverOverlay"
	hover_overlay.color = Color(1.0, 1.0, 1.0, 0.2)  # White glow
	hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_overlay.visible = false

	# Fill entire area
	hover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(hover_overlay)

func _create_lock_overlay() -> void:
	"""Create dark overlay and lock icon for locked areas"""
	# Dark overlay
	lock_overlay = ColorRect.new()
	lock_overlay.name = "LockOverlay"
	lock_overlay.color = Color(0, 0, 0, 0.7)  # Dark grey
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fill entire area
	lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(lock_overlay)

	# Lock icon
	lock_icon = Label.new()
	lock_icon.name = "LockIcon"
	lock_icon.text = "🔒"
	lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_icon.add_theme_font_size_override("font_size", 48)
	lock_icon.add_theme_color_override("font_color", Color.WHITE)
	lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Center icon
	lock_icon.set_anchors_preset(Control.PRESET_FULL_RECT)

	lock_overlay.add_child(lock_icon)

	if GameLogger.ENABLED:
		print("[MapClickableArea] Created lock overlay for: %s" % zone_name)

func _on_mouse_entered() -> void:
	"""Handle mouse enter - show hover effect"""
	is_hovered = true

	if is_unlocked:
		# Show glow effect
		modulate = Color(1.2, 1.2, 1.2)  # Brighten

		# Show hover overlay
		if hover_overlay:
			hover_overlay.visible = true

		# Change cursor
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		if GameLogger.ENABLED:
			print("[MapClickableArea] Hover: %s" % zone_name)
	else:
		# Show "locked" cursor
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN

func _on_mouse_exited() -> void:
	"""Handle mouse exit - remove hover effect"""
	is_hovered = false

	# Restore appearance
	modulate = original_modulate

	# Hide hover overlay
	if hover_overlay:
		hover_overlay.visible = false

	# Reset cursor
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_gui_input(event: InputEvent) -> void:
	"""Handle click events"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_unlocked:
				_on_clicked()
			else:
				# Show "can't click" feedback
				_show_locked_feedback()

func _on_clicked() -> void:
	"""Handle click on unlocked area"""
	if not is_unlocked:
		return

	if GameLogger.ENABLED:
		print("[MapClickableArea] Clicked: %s" % zone_name)

	# Visual feedback - brief flash
	_show_click_feedback()

	# Emit signal
	clicked.emit()

func _show_click_feedback() -> void:
	"""Show brief flash on click"""
	# Brief pulse effect
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.5, 1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", original_modulate, 0.1)

func _show_locked_feedback() -> void:
	"""Show shake effect when clicking locked area"""
	if GameLogger.ENABLED:
		print("[MapClickableArea] Locked area clicked: %s" % zone_name)

	# Shake effect
	var original_pos = position
	var tween = create_tween()
	tween.tween_property(self, "position", original_pos + Vector2(5, 0), 0.05)
	tween.tween_property(self, "position", original_pos + Vector2(-5, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)

	# Brief red flash
	if lock_overlay:
		var tween2 = create_tween()
		tween2.tween_property(lock_overlay, "color", Color(0.5, 0, 0, 0.8), 0.1)
		tween2.tween_property(lock_overlay, "color", Color(0, 0, 0, 0.7), 0.1)

func unlock() -> void:
	"""Unlock this area"""
	is_unlocked = true

	# Remove lock overlay
	if lock_overlay:
		lock_overlay.queue_free()
		lock_overlay = null

	# Update tooltip
	tooltip_text = zone_name

	if GameLogger.ENABLED:
		print("[MapClickableArea] Unlocked: %s" % zone_name)

func lock() -> void:
	"""Lock this area"""
	is_unlocked = false

	# Create lock overlay if not exists
	if lock_overlay == null:
		_create_lock_overlay()

	# Update tooltip
	tooltip_text = "🔒 Locked - Level %d Required" % unlock_requirement

	if GameLogger.ENABLED:
		print("[MapClickableArea] Locked: %s" % zone_name)

func get_kingdom_id() -> String:
	"""Get kingdom ID"""
	return kingdom_id

func get_zone_id() -> String:
	"""Get zone ID"""
	return zone_id

func check_unlock_status(player_level: int) -> void:
	"""Check if player level meets requirement and unlock if needed"""
	if not is_unlocked and player_level >= unlock_requirement:
		unlock()
	elif is_unlocked and player_level < unlock_requirement:
		lock()
