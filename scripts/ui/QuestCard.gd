extends PanelContainer
class_name QuestCard

## Visual card for displaying quest in Quest Log
## Shows title, objectives, progress, and completion status

var quest: Quest = null

# UI elements
var title_label: Label
var objectives_vbox: VBoxContainer
var ready_indicator: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 100)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Title with ready indicator
	var title_hbox = HBoxContainer.new()
	title_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_hbox)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	ready_indicator = Label.new()
	ready_indicator.text = "✓ Ready!"
	ready_indicator.modulate = Color(1.0, 1.0, 0.3)
	ready_indicator.add_theme_font_size_override("font_size", 16)
	ready_indicator.visible = false
	title_hbox.add_child(ready_indicator)

	vbox.add_child(HSeparator.new())

	# Objectives container
	objectives_vbox = VBoxContainer.new()
	objectives_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(objectives_vbox)


## Set the quest to display
func set_quest(q: Quest) -> void:
	quest = q
	_update_display()


## Update the display with current quest data
func _update_display() -> void:
	if quest == null:
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
