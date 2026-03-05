extends Node

# TooltipManager - Centralized tooltip system using CustomTooltip component
# Autoload: res://scripts/ui/TooltipManager.gd
# Replaces manual tooltip creation across ItemTooltip and CharacterDisplay

const CUSTOM_TOOLTIP_SCENE = preload("res://scenes/ui/CustomTooltip.tscn")

var tooltip: CustomTooltip = null
var tooltip_layer: CanvasLayer = null

func _ready() -> void:
	# Create dedicated CanvasLayer for tooltip (always on top)
	tooltip_layer = CanvasLayer.new()
	tooltip_layer.layer = 100  # Very high layer to be above everything
	tooltip_layer.name = "TooltipLayer"

	# Use call_deferred to avoid "parent busy" error
	get_tree().root.call_deferred("add_child", tooltip_layer)

	# Wait for layer to be added
	await get_tree().process_frame

	# Create tooltip instance and add to CanvasLayer
	tooltip = CUSTOM_TOOLTIP_SCENE.instantiate()
	tooltip_layer.call_deferred("add_child", tooltip)

	# Wait for tooltip to be fully ready before using it
	await get_tree().process_frame
	await tooltip.ready
	tooltip.hide_tooltip()

	if GameLogger.ENABLED:
		print("[TooltipManager] Ready - CustomTooltip instantiated on CanvasLayer 100")

# ============================================
# PUBLIC API
# ============================================

func show_item_tooltip(item_data: Dictionary, mouse_pos: Vector2 = Vector2.ZERO) -> void:
	"""Show tooltip for an item (inventory, loot, etc.)"""
	if not tooltip:
		return

	tooltip.setup_item(item_data)

	# Get mouse position from autoload context (always has viewport access)
	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_viewport().get_mouse_position() + Vector2(15, -10)

	tooltip.show_at_position(mouse_pos)

	if GameLogger.ENABLED:
		print("[TooltipManager] Showing item tooltip: %s" % item_data.get("name", "Unknown"))

func show_equipment_tooltip(item_data: Dictionary, mouse_pos: Vector2 = Vector2.ZERO) -> void:
	"""Show tooltip for equipped item"""
	print("[TooltipManager] 🔧 show_equipment_tooltip called for: %s" % item_data.get("name", "Unknown"))  # FORCED DEBUG

	if not tooltip:
		print("[TooltipManager] ❌ ERROR: tooltip is null!")  # FORCED DEBUG
		return

	print("[TooltipManager] → tooltip exists, setting up...")  # FORCED DEBUG
	tooltip.setup_equipment(item_data)

	# Get mouse position from autoload context (always has viewport access)
	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_viewport().get_mouse_position() + Vector2(15, -10)

	print("[TooltipManager] → showing at position: %s" % mouse_pos)  # FORCED DEBUG
	tooltip.show_at_position(mouse_pos)

	print("[TooltipManager] → tooltip.visible = %s" % tooltip.visible)  # FORCED DEBUG

	if GameLogger.ENABLED:
		print("[TooltipManager] Showing equipment tooltip: %s" % item_data.get("name", "Unknown"))

func show_text_tooltip(title: String, body: String, footer: String = "", mouse_pos: Vector2 = Vector2.ZERO) -> void:
	"""Show tooltip with custom text (skills, abilities, etc.)"""
	if not tooltip:
		return

	tooltip.setup_text(title, body, footer)

	# Get mouse position from autoload context (always has viewport access)
	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_viewport().get_mouse_position() + Vector2(15, -10)

	tooltip.show_at_position(mouse_pos)

	if GameLogger.ENABLED:
		print("[TooltipManager] Showing text tooltip: %s" % title)

func hide_item_tooltip() -> void:
	"""Hide tooltip"""
	if tooltip:
		tooltip.hide_tooltip()

	if GameLogger.ENABLED:
		print("[TooltipManager] Hiding tooltip")

func update_mouse_position(mouse_pos: Vector2) -> void:
	"""Update tooltip position to follow mouse"""
	if tooltip and tooltip.is_tooltip_visible:
		tooltip.update_position(mouse_pos)

# ============================================
# UTILITY
# ============================================

func get_extended_item_data(item_id: String, base_data: Dictionary) -> Dictionary:
	"""Get extended item data with defaults (rarity, level, description)"""
	var extended = base_data.duplicate()

	# Add defaults if missing
	if not extended.has("rarity"):
		extended["rarity"] = "common"
	if not extended.has("required_level"):
		extended["required_level"] = 1
	if not extended.has("description"):
		extended["description"] = "A basic item for your adventure."

	return extended
