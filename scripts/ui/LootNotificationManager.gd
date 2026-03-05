# File: res://scripts/ui/LootNotificationManager.gd
# Autoload manager for cascading loot notifications

extends CanvasLayer

const LOOT_NOTIFICATION_SCENE = preload("res://scenes/ui/LootNotification.tscn")

# Notification positioning
const NOTIFICATION_HEIGHT: float = 90.0  # Vertical spacing between notifications
const BOTTOM_MARGIN: float = 20.0        # Margin from bottom of screen
const RIGHT_MARGIN: float = 20.0         # Margin from right of screen

# Active notifications tracking
var active_notifications: Array = []  # Array of LootNotification instances

func _ready() -> void:
	# Set canvas layer to 110 (above TooltipManager at 100)
	layer = 110

func show_notification(item_data: Dictionary) -> void:
	"""Spawn a new loot notification for the given item"""
	# Determine rarity from item data
	var rarity = _get_item_rarity(item_data)

	# Instantiate notification
	var notification = LOOT_NOTIFICATION_SCENE.instantiate()
	add_child(notification)

	# Setup notification
	notification.setup(item_data, rarity)

	# Calculate vertical position (cascade upward from bottom)
	var y_position = _calculate_notification_y_position()
	notification.adjust_vertical_position(y_position)

	# Track notification
	active_notifications.append(notification)

	# Connect to notification's tree_exiting to remove from tracking
	notification.tree_exiting.connect(_on_notification_removed.bind(notification))

	# Reposition all existing notifications to avoid overlap
	_reposition_all_notifications()

	if GameLogger.ENABLED:
		print("[LootNotificationManager] 📬 Showing notification for: %s (rarity: %s)" % [item_data.get("name", "Unknown"), rarity])

func _calculate_notification_y_position() -> float:
	"""Calculate Y position for new notification (cascade upward)"""
	var viewport_height = get_viewport().get_visible_rect().size.y

	# Start from bottom, move up for each active notification
	var base_y = viewport_height - BOTTOM_MARGIN - 80  # 80 is notification height
	var offset_y = active_notifications.size() * NOTIFICATION_HEIGHT

	return base_y - offset_y

func _on_notification_removed(notification: Node) -> void:
	"""Remove notification from tracking when it's freed"""
	active_notifications.erase(notification)

	if GameLogger.ENABLED:
		print("[LootNotificationManager] 🗑️ Notification removed, %d active" % active_notifications.size())

	# Reposition remaining notifications
	_reposition_notifications()

func _reposition_notifications() -> void:
	"""Reposition all active notifications with smooth animation (when one is removed)"""
	for i in range(active_notifications.size()):
		var notification = active_notifications[i]
		if is_instance_valid(notification):
			var new_y = _calculate_notification_y_position_for_index(i)

			# Animate position change
			var tween = create_tween()
			tween.tween_property(notification, "position:y", new_y, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _reposition_all_notifications() -> void:
	"""Reposition all active notifications instantly (when new one spawns)"""
	for i in range(active_notifications.size()):
		var notification = active_notifications[i]
		if is_instance_valid(notification):
			var new_y = _calculate_notification_y_position_for_index(i)
			notification.position.y = new_y

func _calculate_notification_y_position_for_index(index: int) -> float:
	"""Calculate Y position for notification at given index"""
	var viewport_height = get_viewport().get_visible_rect().size.y
	var base_y = viewport_height - BOTTOM_MARGIN - 80
	var offset_y = index * NOTIFICATION_HEIGHT

	return base_y - offset_y

func _get_item_rarity(item_data: Dictionary) -> String:
	"""Determine rarity from item bonuses (matches ExplorationCombatController logic)"""
	if not item_data.has("bonuses"):
		return "common"

	var bonus_count = item_data.bonuses.size()

	# Map bonus count to rarity
	if bonus_count == 0:
		return "common"
	elif bonus_count <= 2:
		return "rare"
	elif bonus_count <= 4:
		return "epic"
	else:
		return "legendary"
