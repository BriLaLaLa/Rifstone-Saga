extends PanelContainer
class_name QuestCard

## Visual card for displaying quest in Quest Log
## Shows title, objectives, progress, and completion status

var quest: Quest = null

@onready var title_label: Label = $Margin/VBox/TitleHBox/TitleLabel
@onready var objectives_vbox: VBoxContainer = $Margin/VBox/ObjectivesVBox
@onready var ready_indicator: Label = $Margin/VBox/TitleHBox/ReadyIndicator


func _ready() -> void:
	# If set_quest() was called before the node entered the tree (@onready refs
	# not yet valid), render now that the UI exists.
	if quest != null:
		_update_display()


## Set the quest to display
func set_quest(q: Quest) -> void:
	quest = q
	# If not yet in tree, _ready() will render once @onready refs are valid.
	if is_node_ready():
		_update_display()


## Update the display with current quest data
func _update_display() -> void:
	if quest == null:
		return

	# Safety check - ensure UI elements exist
	if title_label == null or ready_indicator == null or objectives_vbox == null:
		push_warning("[QuestCard] UI elements not initialized yet")
		return

	# Update title
	title_label.text = quest.title

	# Update ready indicator
	if quest.status == Quest.QuestStatus.READY_TO_TURN_IN:
		ready_indicator.visible = true
		modulate = Color(1.0, 1.0, 0.9)  # Slight yellow highlight
	else:
		ready_indicator.visible = false
		modulate = Color(1.0, 1.0, 1.0)

	# Clear objectives
	for child in objectives_vbox.get_children():
		child.queue_free()

	# Add objectives
	for objective in quest.objectives:
		var obj_hbox = HBoxContainer.new()
		obj_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		objectives_vbox.add_child(obj_hbox)

		# Objective description
		var desc_label = Label.new()
		desc_label.text = "• " + objective.description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		obj_hbox.add_child(desc_label)

		# Progress
		var progress_label = Label.new()
		progress_label.text = objective.get_progress_string()
		if objective.is_complete():
			progress_label.modulate = Color(0.3, 1.0, 0.3)  # Green
		else:
			progress_label.modulate = Color(0.8, 0.8, 0.8)  # Grey
		obj_hbox.add_child(progress_label)

		# Progress bar
		var progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(100, 20)
		progress_bar.max_value = objective.target_count
		progress_bar.value = objective.current_progress
		progress_bar.show_percentage = false
		obj_hbox.add_child(progress_bar)


## Called when quest updates (from signal connection)
func update_progress() -> void:
	_update_display()
