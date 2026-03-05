# File: res://scripts/ui/StatRow.gd
# Reusable stat row utility (label + value)
# Replaces 2× Label.new() manual creation per stat
# DESIGN: Static utility class that creates configured Labels for GridContainer

extends RefCounted
class_name StatRow

static func create_labels(label_text: String, value_text: String, grid: GridContainer) -> void:
	"""Create and add label + value pair to GridContainer"""

	# Create label
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)

	# Create value
	var value = Label.new()
	value.text = value_text
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_color_override("font_color", Color(0.8, 0.8, 1, 1))
	value.add_theme_font_size_override("font_size", 11)

	# Add to grid (each becomes a cell)
	grid.add_child(label)
	grid.add_child(value)

	if GameLogger.ENABLED:
		print("[StatRow] Created labels: %s = %s" % [label_text, value_text])
