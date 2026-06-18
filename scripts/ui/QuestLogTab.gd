extends Control
class_name QuestLogTab

## Quest Log UI Tab
## Displays all active quests and shows notifications

const QUEST_CARD_SCENE = preload("res://scenes/ui/QuestCard.tscn")
var quest_cards: Dictionary = {}  # quest_id -> QuestCard
@onready var quest_container: VBoxContainer = $Margin/VBox/Scroll/QuestContainer
@onready var notification_label: Label = $Margin/VBox/NotificationLabel


func _ready() -> void:
	_connect_signals()
	_refresh_quests()


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
		var card = QUEST_CARD_SCENE.instantiate()
		quest_container.add_child(card)
		card.set_quest(quest)
		quest_cards[quest.quest_id] = card


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
