# File: res://scripts/ui/DragPreview.gd
# Drag preview component for items
# Replaces runtime Control.new() + TextureRect.new() creation

extends Control
class_name DragPreview

# CRITICAL: Don't use @onready - it won't work for instantiated scenes not yet in tree!
# Use get_node() instead in setup()
var preview_texture: TextureRect = null

# Default opacity for drag preview
const DEFAULT_OPACITY = 0.7

func setup(texture: Texture2D, item_size: Vector2i, cell_size: int, hotspot: Vector2, opacity: float = DEFAULT_OPACITY) -> void:
	"""Configure the drag preview with item properties"""

	print("[DragPreview] 🔧 Setup called - item_size: %s, cell_size: %d, hotspot: %s" % [item_size, cell_size, hotspot])

	# Get the texture node (can't use @onready for instantiated scenes)
	preview_texture = get_node_or_null("PreviewTexture")
	if not preview_texture:
		push_error("[DragPreview] ❌ PreviewTexture node not found!")
		return

	print("[DragPreview] ✅ PreviewTexture found")

	# Calculate preview size
	var preview_size = Vector2(item_size.x * cell_size, item_size.y * cell_size)
	print("[DragPreview] 📏 Calculated preview_size: %s" % preview_size)

	# CRITICAL FIX: In Godot 4, setting position on root Control is IGNORED by drag system
	# Solution: Use tiny root Control (1x1) and position TextureRect with negative offset
	# This centers the preview because TextureRect starts from negative position

	var center_offset = preview_size / 2.0

	# Configure TextureRect - positioned with negative offset to center it
	preview_texture.texture = texture
	preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_texture.size = preview_size
	preview_texture.position = -center_offset  # This centers the texture on the cursor!
	preview_texture.modulate = Color(1, 1, 1, opacity)
	preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Configure root Control - tiny size (Godot positions THIS at cursor)
	size = Vector2(1, 1)  # Minimal size, acts as anchor point
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	print("[DragPreview] ✅ Setup complete - TextureRect size: %s, offset: %s (CENTERED)" % [preview_size, -center_offset])
