extends Control
class_name QuestLogTab

## Quest Log UI Tab
## Displays all active quests and shows notifications

var quest_cards: Dictionary = {}  # quest_id -> QuestCard
var quest_container: VBoxContainer
var notification_label: Label


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_refresh_quests()


func _build_ui() -> void:
	# Main layout
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "Quest Log"
	header.add_theme_font_size_override("font_size", 24)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Notification area
	notification_label = Label.new()
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.modulate = Color(1.0, 1.0, 0.3)
	notification_label.add_theme_font_size_override("font_size", 16)
	notification_label.visible = false
	vbox.add_child(notification_label)

	# Scroll container for quests
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	quest_container = VBoxContainer.new()
	quest_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_container.add_theme_constant_override("separation", 12)
	scroll.add_child(quest_container)

	# Empty state
	var empty_label = Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = "No active quests.\nVisit NPCs in the village to find quests!"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	empty_label.modulate = Color(0.7, 0.7, 0.7)
	quest_container.add_child(empty_label)


func _connect_signals() -> void:
	if has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		quest_system.quest_accepted.connect(_on_quest_accepted)
		quest_system.quest_objective_progressed.connect(_on_quest_progressed)
		quest_system.quest_ready_to_turn_in.connect(_on_quest_ready)
		quest_system.quest_completed.connect(_on_quest_completed)
		quest_system.quests_loaded.connect(_refresh_quests)


func _refresh_quests() -> void:
	# Clear existing cards
	for card in quest_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	quest_cards.clear()

	# Get active quests from QuestSystem
	if not has_node("/root/QuestSystem"):
		return

	var quest_system = get_node("/root/QuestSystem")
	var active_quests = quest_system.active_quests

	# Show/hide empty label
	var empty_label = quest_container.get_node_or_null("EmptyLabel")
	if empty_label:
		empty_label.visible = active_quests.is_empty()

	# Create quest cards
	for quest in active_quests:
		var card = QuestCard.new()
		card.set_quest(quest)
		quest_cards[quest.quest_id] = card
		quest_container.add_child(card)


func _on_quest_accepted(quest: Quest) -> void:
	_show_notification("New Quest: %s" % quest.title)
	_refresh_quests()


func _on_quest_progressed(quest: Quest, objective: QuestObjective) -> void:
	# Update existing card if it exists
	if quest_cards.has(quest.quest_id):
		var card = quest_cards[quest.quest_id]
		if is_instance_valid(card):
			card.update_progress()

	# Show notification
	_show_notification("%s: %s" % [objective.description, objective.get_progress_string()])


func _on_quest_ready(quest: Quest) -> void:
	# Update card
	if quest_cards.has(quest.quest_id):
		var card = quest_cards[quest.quest_id]
		if is_instance_valid(card):
			card.update_progress()

	# Show notification
	_show_notification("Quest Ready: %s" % quest.title, 3.0)


func _on_quest_completed(quest: Quest) -> void:
	_show_notification("Quest Completed: %s" % quest.title, 3.0)
	_refresh_quests()


func _show_notification(text: String, duration: float = 2.0) -> void:
	if not is_instance_valid(notification_label):
		return

	notification_label.text = text
	notification_label.visible = true

	# Cancel any existing timer
	if notification_label.has_meta("notification_timer"):
		var timer = notification_label.get_meta("notification_timer")
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	# Create new timer
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(func():
		if is_instance_valid(notification_label):
			notification_label.visible = false
		timer.queue_free()
	)
	notification_label.set_meta("notification_timer", timer)
	add_child(timer)
	timer.start()
