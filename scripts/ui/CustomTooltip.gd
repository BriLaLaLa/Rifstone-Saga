extends PanelContainer
class_name CustomTooltip

# Reusable tooltip component for items, equipment, skills, etc.
# Replaces ~250 lines of duplicated tooltip code across ItemTooltip and CharacterDisplay
# Path: res://scripts/ui/CustomTooltip.gd

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Visual Style")
@export var bg_color: Color = Color(0.1, 0.1, 0.15, 0.95)
@export var border_color: Color = Color(0.45, 0.45, 0.55, 1.0)
@export var border_width: int = 2
@export var corner_radius: int = 6

@export_group("Margins")
@export var margin_left: int = 8
@export var margin_right: int = 8
@export var margin_top: int = 6
@export var margin_bottom: int = 6

@export_group("Content")
@export var content_separation: int = 4
@export var min_width: int = 250
@export var title_font_size: int = 14
@export var body_font_size: int = 12
@export var footer_font_size: int = 11

@export_group("Positioning")
@export var mouse_offset: Vector2 = Vector2(15, -10)
@export var z_index_value: int = 4096  # Max z_index in Godot
@export var screen_margin: int = 10

# ==================== RARITY COLORS ====================
const RARITY_COLORS = {
	"common": Color.WHITE,
	"uncommon": Color.GREEN,
	"rare": Color.BLUE,
	"epic": Color.PURPLE,
	"legendary": Color.ORANGE,
	"artifact": Color.RED
}

# ==================== INTERNAL VARIABLES ====================
@onready var margin_container: MarginContainer = $Margin
@onready var content_container: VBoxContainer = $Margin/Content
@onready var title_label: RichTextLabel = $Margin/Content/TitleLabel
@onready var body_label: RichTextLabel = $Margin/Content/BodyLabel
@onready var footer_label: RichTextLabel = $Margin/Content/FooterLabel

var is_tooltip_visible: bool = false

func _ready() -> void:
	# Initially hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = z_index_value
	custom_minimum_size.x = min_width

	# Apply visual style
	_apply_style()
	_apply_margins()

	if GameLogger.ENABLED:
		print("[CustomTooltip] Ready")

# ============================================
# STYLING
# ============================================

func _apply_style() -> void:
	"""Apply visual style from exported variables"""
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	add_theme_stylebox_override("panel", style)

func _apply_margins() -> void:
	"""Apply margins from exported variables"""
	if margin_container:
		margin_container.add_theme_constant_override("margin_left", margin_left)
		margin_container.add_theme_constant_override("margin_right", margin_right)
		margin_container.add_theme_constant_override("margin_top", margin_top)
		margin_container.add_theme_constant_override("margin_bottom", margin_bottom)

	if content_container:
		content_container.add_theme_constant_override("separation", content_separation)

# ============================================
# SETUP METHODS (Public API)
# ============================================

func setup_item(item_data: Dictionary) -> void:
	"""Setup tooltip for an item (inventory/loot)"""
	if item_data.is_empty():
		return

	# Title: Item name with rarity color (+ upgrade level in Metin2 style)
	var item_name = str(item_data.get("name", "Unknown Item"))

	# Add upgrade level to name if present (Metin2 style: "Apprentice Sword +5")
	var upgrade_level = int(item_data.get("upgrade_level", 0))
	if upgrade_level > 0:
		item_name += " [color=#FFFF00]+%d[/color]" % upgrade_level  # Yellow color for +X

	var rarity = str(item_data.get("rarity", "common")).to_lower()
	var name_color = RARITY_COLORS.get(rarity, Color.WHITE)

	if title_label:
		var size_tag = "[font_size=%d]" % title_font_size
		title_label.text = "%s[color=#%s][b]%s[/b][/color][/font_size]" % [size_tag, name_color.to_html(), item_name]
		title_label.visible = true

	# Body: Stats
	var body_lines: Array[String] = []

	# Level requirement
	var required_level = int(item_data.get("required_level", 0))
	if required_level > 0:
		var player_level = _get_player_level()
		var level_color = Color.RED if player_level < required_level else Color.WHITE
		body_lines.append("[color=#%s]Requires Level %d[/color]" % [level_color.to_html(), required_level])

	# Stats
	if item_data.has("stats"):
		var stats = item_data.stats

		if stats.has("physical_damage") and stats.physical_damage > 0:
			body_lines.append("[color=#FF6666]Attack: +%d[/color]" % stats.physical_damage)

		if stats.has("physical_defense") and stats.physical_defense > 0:
			body_lines.append("[color=#6666FF]Defense: +%d[/color]" % stats.physical_defense)

		if stats.has("max_hp") and stats.max_hp > 0:
			body_lines.append("[color=#66FF66]HP: +%d[/color]" % stats.max_hp)

		if stats.has("vitality") and stats.vitality > 0:
			body_lines.append("[color=#66FF66]Vitality: +%d[/color]" % stats.vitality)

		if stats.has("strength") and stats.strength > 0:
			body_lines.append("[color=#FF8866]Strength: +%d[/color]" % stats.strength)

		if stats.has("block_chance") and stats.block_chance > 0:
			body_lines.append("[color=#8866FF]Block: +%d%%[/color]" % stats.block_chance)

	# Bonuses
	if item_data.has("bonuses") and item_data.bonuses.size() > 0:
		body_lines.append("")
		body_lines.append("[b]--- Bonuses ---[/b]")

		const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

		for bonus_dict in item_data.bonuses:
			# Support both formats: direct {text, color} or ItemBonus format
			if bonus_dict.has("text") and bonus_dict.has("color"):
				# Direct format
				var bonus_color = bonus_dict.color if bonus_dict.color is Color else Color.WHITE
				body_lines.append("[color=#%s]%s[/color]" % [bonus_color.to_html(), bonus_dict.text])
			else:
				# ItemBonus format - need to convert
				var bonus = ItemBonus.new()
				bonus.from_dict(bonus_dict)

				var bonus_color = bonus.get_color()
				var bonus_text = bonus.get_display_text()
				var tier_text = bonus.get_tier_name()

				body_lines.append("[color=%s]%s [%s][/color]" %
					[bonus_color.to_html(), bonus_text, tier_text])

	if body_label:
		var size_tag = "[font_size=%d]" % body_font_size
		body_label.text = size_tag + "\n".join(body_lines) + "[/font_size]"
		body_label.visible = body_lines.size() > 0

	# Footer: Description
	if footer_label:
		var description = str(item_data.get("description", ""))
		if description != "":
			var size_tag = "[font_size=%d]" % footer_font_size
			footer_label.text = "%s[color=#CCCCCC][i]%s[/i][/color][/font_size]" % [size_tag, description]
			footer_label.visible = true
		else:
			footer_label.visible = false

func setup_equipment(item_data: Dictionary) -> void:
	"""Setup tooltip for equipped item (equipment slots)"""
	# Equipment tooltip is similar to item tooltip
	setup_item(item_data)

func setup_text(title: String, body: String, footer: String = "") -> void:
	"""Setup tooltip with custom text (for skills, abilities, etc.)"""
	if title_label:
		var size_tag = "[font_size=%d]" % title_font_size
		title_label.text = size_tag + title + "[/font_size]"
		title_label.visible = title != ""

	if body_label:
		var size_tag = "[font_size=%d]" % body_font_size
		body_label.text = size_tag + body + "[/font_size]"
		body_label.visible = body != ""

	if footer_label:
		var size_tag = "[font_size=%d]" % footer_font_size
		footer_label.text = size_tag + footer + "[/font_size]"
		footer_label.visible = footer != ""

# ============================================
# DISPLAY METHODS (Public API)
# ============================================

func show_at_mouse(offset: Vector2 = Vector2.ZERO) -> void:
	"""Show tooltip near mouse cursor with screen boundary detection"""
	var mouse_pos = get_viewport().get_mouse_position()
	var final_offset = mouse_offset if offset == Vector2.ZERO else offset
	show_at_position(mouse_pos + final_offset)

func show_at_position(pos: Vector2) -> void:
	"""Show tooltip at specific position with screen boundary detection"""
	print("[CustomTooltip] 🔧 show_at_position called at: %s" % pos)  # FORCED DEBUG
	print("[CustomTooltip] → is_inside_tree: %s" % is_inside_tree())  # FORCED DEBUG

	visible = true
	is_tooltip_visible = true

	print("[CustomTooltip] → visible set to true")  # FORCED DEBUG

	# Resize synchronously using call_deferred (no await!)
	if is_inside_tree():
		print("[CustomTooltip] → calling auto_resize deferred...")  # FORCED DEBUG
		call_deferred("_deferred_resize_and_position", pos)
		return

	_position_tooltip(pos)

func _deferred_resize_and_position(pos: Vector2) -> void:
	"""Deferred resize and positioning to avoid race conditions"""
	print("[CustomTooltip] → _deferred_resize_and_position called")  # FORCED DEBUG
	auto_resize()
	print("[CustomTooltip] → size after resize: %s" % size)  # FORCED DEBUG
	_position_tooltip(pos)

func _position_tooltip(pos: Vector2) -> void:
	"""Position tooltip with screen boundary detection"""
	# Screen boundary detection
	var screen_size: Vector2
	if get_viewport():
		screen_size = get_viewport().get_visible_rect().size
	else:
		screen_size = Vector2(1920, 1080)  # Fallback size

	var tooltip_size = size
	var x = pos.x
	var y = pos.y

	# Right boundary
	if x + tooltip_size.x > screen_size.x - screen_margin:
		x = screen_size.x - tooltip_size.x - screen_margin

	# Bottom boundary
	if y + tooltip_size.y > screen_size.y - screen_margin:
		y = screen_size.y - tooltip_size.y - screen_margin

	# Left boundary
	if x < screen_margin:
		x = screen_margin

	# Top boundary
	if y < screen_margin:
		y = screen_margin

	global_position = Vector2(x, y)

	print("[CustomTooltip] ✅ Positioned at: %s" % global_position)  # FORCED DEBUG

	if GameLogger.ENABLED:
		print("[CustomTooltip] Shown at position: %s" % global_position)

func hide_tooltip() -> void:
	"""Hide tooltip and clear content"""
	visible = false
	is_tooltip_visible = false

	if title_label:
		title_label.text = ""
	if body_label:
		body_label.text = ""
	if footer_label:
		footer_label.text = ""

	if GameLogger.ENABLED:
		print("[CustomTooltip] Hidden")

func update_position(mouse_pos: Vector2) -> void:
	"""Update tooltip position (for mouse tracking)"""
	if is_tooltip_visible:
		show_at_position(mouse_pos + mouse_offset)

# ============================================
# UTILITY METHODS
# ============================================

func set_rarity_color(rarity: String) -> void:
	"""Set title color based on rarity"""
	var color = RARITY_COLORS.get(rarity.to_lower(), Color.WHITE)
	if title_label:
		title_label.modulate = color

func auto_resize() -> void:
	"""Auto-resize tooltip to fit content"""
	if not content_container:
		return

	var content_height = 0.0
	var visible_children = 0

	for child in content_container.get_children():
		if child.visible:
			# Use get_content_height() for RichTextLabel to get accurate height
			if child is RichTextLabel:
				content_height += child.get_content_height()
			else:
				content_height += child.size.y
			visible_children += 1

	# Add separation between visible children
	if visible_children > 1:
		content_height += content_separation * (visible_children - 1)

	content_height += margin_top + margin_bottom

	custom_minimum_size.y = max(50, content_height)
	size.y = custom_minimum_size.y

func _get_player_level() -> int:
	"""Get player level from GameState"""
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs and "player_level" in gs:
			return int(gs.get("player_level"))
	return 1  # Default level
