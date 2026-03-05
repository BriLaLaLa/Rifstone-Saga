# File: res://scripts/ui/StackLabel.gd
# Stack count label component for stackable items
# Replaces Label.new() creation in Item.gd
# Shows item count in bottom-right corner

extends Label
class_name StackLabel

func _ready() -> void:
	# Default configuration (can be overridden by setup)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	visible = false  # Hidden by default until count > 1

func setup(font_size: int = 14, font_color: Color = Color.WHITE, outline_color: Color = Color.BLACK, outline_size: int = 2, label_offset: Vector2 = Vector2(-4, -2)) -> void:
	"""Configure the stack label appearance"""
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", font_color)
	add_theme_color_override("font_outline_color", outline_color)
	add_theme_constant_override("outline_size", outline_size)

	# Position at bottom-right
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = label_offset.x
	offset_bottom = label_offset.y

	if GameLogger.ENABLED:
		print("[StackLabel] Configured with font_size=%d, offset=%s" % [font_size, label_offset])

func update_count(count: int) -> void:
	"""Update the displayed stack count"""
	if count > 1:
		text = str(count)
		visible = true
	else:
		visible = false

	if GameLogger.ENABLED:
		print("[StackLabel] Updated count: %d (visible: %s)" % [count, visible])
