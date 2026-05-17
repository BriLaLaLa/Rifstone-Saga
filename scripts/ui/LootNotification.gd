# File: res://scripts/ui/LootNotification.gd
# Individual loot notification — display only, lifecycle driven by LootNotificationManager

extends PanelContainer
class_name LootNotification

## Emitted after DISPLAY_DURATION: tells the manager it's time to fade this out
signal expired

@onready var item_icon: TextureRect = $MarginContainer/HBoxContainer/IconContainer/ItemIcon
@onready var item_name_label: RichTextLabel = $MarginContainer/HBoxContainer/VBoxContainer/ItemName
@onready var item_stats_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/ItemStats

const DISPLAY_DURATION: float = 4.0
const SLIDE_DURATION: float = 0.3
const FADE_DURATION: float = 0.3

const RARITY_COLORS = {
	"common":    Color(1.0, 1.0, 1.0),
	"rare":      Color(0.3, 0.6, 1.0),
	"epic":      Color(0.8, 0.3, 1.0),
	"legendary": Color(1.0, 0.6, 0.0),
}


## Called by manager after add_child — sets content, no animation yet
func setup(item_data: Dictionary, rarity: String) -> void:
	var rarity_color: Color = RARITY_COLORS.get(rarity, Color.WHITE)

	# Icon
	var icon_path: String = item_data.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		item_icon.texture = load(icon_path)
		item_icon.visible = true
	else:
		item_icon.texture = null
		item_icon.visible = false

	# Name with rarity color
	item_name_label.text = "[color=#%s]%s[/color]" % [
		rarity_color.to_html(false),
		item_data.get("name", "?")
	]

	# Stats (first 2 bonuses, no wrap)
	var stats := _build_stats_text(item_data)
	item_stats_label.text = stats
	item_stats_label.visible = stats != ""

	# Subtle rarity tint on the panel background
	modulate = rarity_color.lerp(Color.WHITE, 0.82)
	modulate.a = 0.0  # start invisible; animate_in will reveal it


## Slide in from the right, then wait and emit expired
func animate_in() -> void:
	var vp_w: float = get_viewport_rect().size.x
	var end_x: float = vp_w - custom_minimum_size.x - 20.0
	position.x = vp_w  # start off-screen right

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:x", end_x, SLIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, SLIDE_DURATION * 0.6)\
		.set_trans(Tween.TRANS_LINEAR)
	await tw.finished

	await get_tree().create_timer(DISPLAY_DURATION).timeout
	expired.emit()


## Fade out (awaitable by manager)
func animate_out() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)\
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(self, "position:x", position.x + 30.0, FADE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished


func _build_stats_text(item_data: Dictionary) -> String:
	if not item_data.has("bonuses") or item_data["bonuses"].is_empty():
		return ""
	var parts: Array = []
	for bonus in item_data["bonuses"]:
		if bonus.has("text"):
			parts.append(bonus["text"])
	if parts.size() > 2:
		return ", ".join(parts.slice(0, 2)) + "…"
	return ", ".join(parts)
