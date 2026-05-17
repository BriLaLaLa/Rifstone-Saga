# File: res://scripts/ui/LootNotificationManager.gd
# FIFO notification stack: new items appear at the bottom, older ones stack above.
# When the bottom one fades out, the rest slide smoothly down.

extends CanvasLayer

const LOOT_NOTIFICATION_SCENE = preload("res://scenes/ui/LootNotification.tscn")

const MAX_VISIBLE: int = 4          # Max simultaneous notifications on screen
const NOTIFICATION_H: float = 95.0  # Height of one slot (notification height 90 + 5 gap)
const BOTTOM_MARGIN: float = 20.0
const RIGHT_MARGIN: float = 20.0
const SLIDE_DOWN_DURATION: float = 0.25

# FIFO queue: items waiting to be shown
var _pending: Array = []

# Currently visible notifications, ordered bottom→top (index 0 = bottom/oldest)
var _active: Array = []


func _ready() -> void:
	layer = 110


## Public API — called by game systems to show a loot notification
func show_notification(item_data: Dictionary) -> void:
	if _active.size() < MAX_VISIBLE:
		_spawn(item_data)
	else:
		_pending.append(item_data)


# ---------- internal ----------

func _spawn(item_data: Dictionary) -> void:
	var rarity := _get_rarity(item_data)

	var notif: LootNotification = LOOT_NOTIFICATION_SCENE.instantiate()
	add_child(notif)

	# Position: starts at the TOP of the current stack (highest index = highest on screen)
	notif.position.y = _y_for_slot(_active.size())
	_active.append(notif)

	notif.setup(item_data, rarity)

	# Connect expired BEFORE starting animation (animate_in awaits and then emits)
	notif.expired.connect(_on_expired.bind(notif), CONNECT_ONE_SHOT)

	# Fire-and-forget: animate_in runs async, emits expired when done
	notif.animate_in()


func _on_expired(notif: LootNotification) -> void:
	if not is_instance_valid(notif):
		_cleanup_invalid()
		return

	# Fade out, then remove
	await notif.animate_out()

	if not is_instance_valid(notif):
		_cleanup_invalid()
		return

	_remove(notif)


func _remove(notif: LootNotification) -> void:
	var idx := _active.find(notif)
	if idx == -1:
		return

	_active.remove_at(idx)
	notif.queue_free()

	# Slide everything that was ABOVE (higher index) down by one slot
	for i in range(idx, _active.size()):
		var n: LootNotification = _active[i]
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "position:y", _y_for_slot(i), SLIDE_DOWN_DURATION)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Show next pending item if slot freed up
	if _pending.size() > 0 and _active.size() < MAX_VISIBLE:
		_spawn(_pending.pop_front())


func _cleanup_invalid() -> void:
	# Remove any dead references (safety net)
	_active = _active.filter(func(n): return is_instance_valid(n))


func _y_for_slot(slot_index: int) -> float:
	var vp_h: float = get_viewport().get_visible_rect().size.y
	# slot 0 = closest to bottom, slot N = highest on screen
	return vp_h - BOTTOM_MARGIN - 90.0 - slot_index * NOTIFICATION_H


func _get_rarity(item_data: Dictionary) -> String:
	if not item_data.has("bonuses"):
		return "common"
	var n: int = item_data["bonuses"].size()
	if n == 0:
		return "common"
	elif n <= 2:
		return "rare"
	elif n <= 4:
		return "epic"
	else:
		return "legendary"
