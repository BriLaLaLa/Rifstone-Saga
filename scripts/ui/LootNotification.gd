# File: res://scripts/ui/LootNotification.gd
# Individual loot notification panel with slide-in animation

extends PanelContainer

# References to child nodes
@onready var item_icon: TextureRect = $MarginContainer/HBoxContainer/IconContainer/ItemIcon
@onready var item_name_label: RichTextLabel = $MarginContainer/HBoxContainer/VBoxContainer/ItemName
@onready var item_stats_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/ItemStats

# Notification data
var item_data: Dictionary = {}
var rarity: String = "common"

# Timing
const SLIDE_DURATION: float = 0.3
const DISPLAY_DURATION: float = 5.0
const FADE_DURATION: float = 0.4

# Rarity colors (matches CustomTooltip)
const RARITY_COLORS = {
	"common": Color.WHITE,
	"rare": Color.BLUE,
	"epic": Color.PURPLE,
	"legendary": Color.ORANGE
}

func setup(p_item_data: Dictionary, p_rarity: String) -> void:
	"""Initialize notification with item data and rarity"""
	item_data = p_item_data
	rarity = p_rarity

	# Set item icon
	var icon_path = item_data.get("icon", "")

	if GameLogger.ENABLED:
		print("[LootNotification] 🖼️ Icon path: '%s'" % icon_path)
		print("[LootNotification] 📦 Item data keys: %s" % item_data.keys())

	if not icon_path.is_empty():
		if ResourceLoader.exists(icon_path):
			item_icon.texture = load(icon_path)
			item_icon.visible = true
			if GameLogger.ENABLED:
				print("[LootNotification] ✅ Icon loaded successfully")
		else:
			# Icon path exists but file not found
			if GameLogger.ENABLED:
				print("[LootNotification] ⚠️ Icon file not found: %s" % icon_path)
			item_icon.visible = false
	else:
		# No icon path provided
		if GameLogger.ENABLED:
			print("[LootNotification] ⚠️ No icon path in item_data")
		item_icon.visible = false

	# Set item name with rarity color
	var rarity_color = RARITY_COLORS.get(rarity, Color.WHITE)
	var color_hex = rarity_color.to_html(false)
	var item_name_text = item_data.get("name", "Unknown Item")
	item_name_label.text = "[color=#%s]%s[/color]" % [color_hex, item_name_text]

	# Set item stats (bonuses)
	var stats_text = _build_stats_text()
	if stats_text.is_empty():
		item_stats_label.visible = false
	else:
		item_stats_label.text = stats_text

	# Set panel modulate based on rarity (subtle background tint)
	modulate = rarity_color.lerp(Color.WHITE, 0.85)

	# Start lifecycle
	_start_lifecycle()

func _build_stats_text() -> String:
	"""Build compact stats text from item bonuses"""
	if not item_data.has("bonuses") or item_data.bonuses.is_empty():
		return ""

	var stats_parts = []
	for bonus in item_data.bonuses:
		if bonus.has("text"):
			stats_parts.append(bonus.text)

	# Limit to first 2 bonuses to avoid overflow
	if stats_parts.size() > 2:
		return ", ".join(stats_parts.slice(0, 2)) + "..."
	else:
		return ", ".join(stats_parts)

func _start_lifecycle() -> void:
	"""Run notification lifecycle: slide in → wait → fade out"""
	await slide_in()
	await get_tree().create_timer(DISPLAY_DURATION).timeout
	await fade_out()
	queue_free()

func slide_in() -> void:
	"""Slide in from right side of screen"""
	# Start position: off-screen to the right
	var screen_width = get_viewport_rect().size.x
	var start_x = screen_width
	var end_x = screen_width - custom_minimum_size.x - 20  # 20px margin from right

	position.x = start_x
	modulate.a = 0.0

	# Create tween for slide
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(self, "position:x", end_x, SLIDE_DURATION)
	tween.tween_property(self, "modulate:a", 1.0, SLIDE_DURATION * 0.5)

	await tween.finished

func fade_out() -> void:
	"""Fade out and slide slightly to the right"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_property(self, "position:x", position.x + 30, FADE_DURATION)

	await tween.finished

func adjust_vertical_position(y_pos: float) -> void:
	"""Set vertical position (called by LootNotificationManager for cascading)"""
	position.y = y_pos
