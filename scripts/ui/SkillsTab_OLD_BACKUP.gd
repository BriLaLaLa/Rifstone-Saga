extends Control
# OLD BACKUP - class_name removed to avoid conflicts

# Skills System UI - Main Tab Controller
# Manages the 3-panel layout: LoadoutPanel, LibraryPanel, DetailsPanel

const LOG := true

# References to panels
@onready var loadout_panel: Panel = $HBoxContainer/LoadoutPanel
@onready var library_panel: Panel = $HBoxContainer/LibraryPanel
@onready var details_panel: Panel = $HBoxContainer/DetailsPanel

# References to containers
@onready var skills_grid: GridContainer = $HBoxContainer/LibraryPanel/VBoxContainer/ScrollContainer/SkillsGrid
@onready var active_actions_container: VBoxContainer = $HBoxContainer/LoadoutPanel/VBoxContainer/ScrollContainer/ActiveActionsContainer
@onready var search_bar: LineEdit = $HBoxContainer/LibraryPanel/VBoxContainer/TopBar/SearchBar
@onready var category_filter: OptionButton = $HBoxContainer/LibraryPanel/VBoxContainer/TopBar/CategoryFilter
@onready var grade_filter: OptionButton = $HBoxContainer/LibraryPanel/VBoxContainer/TopBar/GradeFilter

# Resources
const SkillCardScene = preload("res://scripts/ui/SkillCard.tscn")
const ActionCardScene = preload("res://scripts/ui/ActionCard.tscn")

# State
var skill_cards: Dictionary = {}  # skill_id -> SkillCard
var action_cards: Dictionary = {}  # action_id -> ActionCard
var selected_skill_id: String = ""

# Filters
var current_search: String = ""
var current_category: String = "all"
var current_grade: String = "all"

func _ready() -> void:
	if LOG:
		print("[SkillsTab] Initializing Skills System UI")

	# Setup filters
	_setup_filters()

	# Connect signals
	_connect_signals()

	# Initial load
	_load_all_skills()
	_refresh_active_actions()

	if LOG:
		print("[SkillsTab] Initialized with %d skills" % skill_cards.size())

# ==================== INITIALIZATION ====================

func _setup_filters() -> void:
	"""Setup filter dropdowns and search bar"""
	# Category filter
	if category_filter:
		category_filter.clear()
		category_filter.add_item("Tutte le Categorie", 0)
		category_filter.add_item("Raccolta", 1)
		category_filter.add_item("Produzione", 2)
		category_filter.add_item("Combattimento", 3)
		category_filter.item_selected.connect(_on_category_filter_changed)

	# Grade filter
	if grade_filter:
		grade_filter.clear()
		grade_filter.add_item("Tutti i Gradi", 0)
		grade_filter.add_item("N (Normale)", 1)
		grade_filter.add_item("A (Avanzato)", 2)
		grade_filter.add_item("M (Maestro)", 3)
		grade_filter.add_item("G (Grandmaster)", 4)
		grade_filter.item_selected.connect(_on_grade_filter_changed)

	# Search bar
	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
		search_bar.placeholder_text = "Cerca skill..."

func _connect_signals() -> void:
	"""Connect to GameState signals"""
	if not has_node("/root/GameState"):
		if LOG:
			print("[SkillsTab] ERROR: No GameState autoload!")
		return

	var gs = get_node("/root/GameState")

	# Connect skill-related signals
	if gs.has_signal("on_skill_level_up"):
		gs.on_skill_level_up.connect(_on_skill_level_up)

	if gs.has_signal("on_action_started"):
		gs.on_action_started.connect(_on_action_started)

	if gs.has_signal("on_action_progress"):
		gs.on_action_progress.connect(_on_action_progress)

	if gs.has_signal("on_action_finished"):
		gs.on_action_finished.connect(_on_action_finished)

	if gs.has_signal("on_promotion_result"):
		gs.on_promotion_result.connect(_on_promotion_result)

	if LOG:
		print("[SkillsTab] Connected to GameState signals")

# ==================== SKILL LOADING ====================

func _load_all_skills() -> void:
	"""Load all skills from GameState and create skill cards"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if not "data" in gs or not "skills" in gs.data:
		if LOG:
			print("[SkillsTab] ERROR: No skills data in GameState!")
		return

	# Clear existing cards
	for card in skill_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	skill_cards.clear()

	# Create card for each skill
	for skill_id in gs.data.skills:
		_create_skill_card(skill_id)

	# Apply current filters
	_apply_filters()

	if LOG:
		print("[SkillsTab] Loaded %d skill cards" % skill_cards.size())

func _create_skill_card(skill_id: String) -> void:
	"""Create a skill card and add it to the grid"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	var skill_data = gs.data.skills.get(skill_id, {})

	if skill_data.is_empty():
		if LOG:
			print("[SkillsTab] WARNING: No data for skill '%s'" % skill_id)
		return

	# Instantiate card
	var card = SkillCardScene.instantiate()
	skills_grid.add_child(card)

	# Setup card
	if card.has_method("setup"):
		card.setup(skill_data)

	# Connect click signal
	if card.has_method("connect_clicked"):
		card.connect_clicked(_on_skill_card_clicked)
	elif card.has_signal("clicked"):
		card.clicked.connect(_on_skill_card_clicked)

	# Store reference
	skill_cards[skill_id] = card

	if LOG:
		print("[SkillsTab] Created card for skill: %s (Level %d, Grade %s)" %
			[skill_data.get("name", skill_id), skill_data.get("level", 1), skill_data.get("grade", "N")])

# ==================== ACTIVE ACTIONS ====================

func _refresh_active_actions() -> void:
	"""Refresh the active actions loadout panel"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")

	# Clear existing action cards
	for card in action_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	action_cards.clear()

	# Check for active action
	if "active_action" in gs and gs.active_action != null:
		_create_action_card(gs.active_action)
	else:
		# Show "No active actions" message
		_show_empty_loadout_message()

	if LOG:
		print("[SkillsTab] Refreshed active actions: %d" % action_cards.size())

func _create_action_card(action_data: Dictionary) -> void:
	"""Create an action card for the loadout panel"""
	var action_id = action_data.get("id", "unknown")

	# Instantiate card
	var card = ActionCardScene.instantiate()
	active_actions_container.add_child(card)

	# Setup card
	if card.has_method("setup"):
		card.setup(action_data)

	# Store reference
	action_cards[action_id] = card

	# Hide empty message
	_hide_empty_loadout_message()

	if LOG:
		print("[SkillsTab] Created action card: %s" % action_data.get("name", action_id))

func _show_empty_loadout_message() -> void:
	"""Show 'No active actions' message"""
	# Find or create empty message label
	var empty_msg = active_actions_container.get_node_or_null("EmptyMessage")
	if empty_msg == null:
		empty_msg = Label.new()
		empty_msg.name = "EmptyMessage"
		empty_msg.text = "Nessuna azione attiva.\nSeleziona una skill e avvia un'azione!"
		empty_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_msg.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		active_actions_container.add_child(empty_msg)
	else:
		empty_msg.visible = true

func _hide_empty_loadout_message() -> void:
	"""Hide empty message"""
	var empty_msg = active_actions_container.get_node_or_null("EmptyMessage")
	if empty_msg != null:
		empty_msg.visible = false

# ==================== SKILL DETAILS ====================

func _show_skill_details(skill_id: String) -> void:
	"""Show skill details in the details panel"""
	selected_skill_id = skill_id

	if details_panel.has_method("show_skill"):
		details_panel.show_skill(skill_id)

	# Highlight selected card
	_update_card_selection(skill_id)

	if LOG:
		print("[SkillsTab] Showing details for: %s" % skill_id)

func _update_card_selection(skill_id: String) -> void:
	"""Highlight the selected skill card"""
	for id in skill_cards:
		var card = skill_cards[id]
		if is_instance_valid(card) and card.has_method("set_selected"):
			card.set_selected(id == skill_id)

# ==================== FILTERS ====================

func _apply_filters() -> void:
	"""Apply current search and filters to skill cards"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")

	for skill_id in skill_cards:
		var card = skill_cards[skill_id]
		if not is_instance_valid(card):
			continue

		var skill_data = gs.data.skills.get(skill_id, {})
		if skill_data.is_empty():
			continue

		# Check search filter
		var matches_search = true
		if not current_search.is_empty():
			var skill_name = skill_data.get("name", "").to_lower()
			matches_search = skill_name.contains(current_search.to_lower())

		# Check category filter
		var matches_category = true
		if current_category != "all":
			var skill_category = skill_data.get("category", "")
			matches_category = (skill_category == current_category)

		# Check grade filter
		var matches_grade = true
		if current_grade != "all":
			var skill_grade = skill_data.get("grade", "N")
			matches_grade = (skill_grade == current_grade)

		# Show/hide card
		card.visible = matches_search and matches_category and matches_grade

	if LOG:
		print("[SkillsTab] Applied filters - Search: '%s', Category: %s, Grade: %s" %
			[current_search, current_category, current_grade])

func filter_by_category(category: String) -> void:
	"""Public method to filter by category"""
	current_category = category
	_apply_filters()

func filter_by_grade(grade: String) -> void:
	"""Public method to filter by grade"""
	current_grade = grade
	_apply_filters()

# ==================== SIGNAL HANDLERS ====================

func _on_skill_card_clicked(skill_id: String) -> void:
	"""Handle skill card click"""
	_show_skill_details(skill_id)

func _on_search_text_changed(new_text: String) -> void:
	"""Handle search bar text change"""
	current_search = new_text
	_apply_filters()

func _on_category_filter_changed(index: int) -> void:
	"""Handle category filter change"""
	match index:
		0: current_category = "all"
		1: current_category = "gathering"
		2: current_category = "production"
		3: current_category = "combat"

	_apply_filters()

func _on_grade_filter_changed(index: int) -> void:
	"""Handle grade filter change"""
	match index:
		0: current_grade = "all"
		1: current_grade = "N"
		2: current_grade = "A"
		3: current_grade = "M"
		4: current_grade = "G"

	_apply_filters()

# ==================== GAMESTATE SIGNAL HANDLERS ====================

func _on_skill_level_up(skill_id: String, new_level: int) -> void:
	"""Handle skill level up"""
	if LOG:
		print("[SkillsTab] Skill leveled up: %s → Level %d" % [skill_id, new_level])

	# Refresh the skill card
	var card = skill_cards.get(skill_id, null)
	if card != null and is_instance_valid(card):
		if card.has_method("refresh"):
			card.refresh()

	# Refresh details panel if this skill is selected
	if selected_skill_id == skill_id:
		_show_skill_details(skill_id)

	# Show level up notification
	_show_level_up_notification(skill_id, new_level)

func _on_action_started(action_id: String) -> void:
	"""Handle action started"""
	if LOG:
		print("[SkillsTab] Action started: %s" % action_id)

	# Refresh active actions
	_refresh_active_actions()

func _on_action_progress(action_id: String, progress: float) -> void:
	"""Handle action progress update"""
	# Update action card progress bar
	var card = action_cards.get(action_id, null)
	if card != null and is_instance_valid(card):
		if card.has_method("set_progress"):
			card.set_progress(progress)

func _on_action_finished(action_id: String, rewards: Dictionary) -> void:
	"""Handle action finished"""
	if LOG:
		print("[SkillsTab] Action finished: %s (Rewards: %s)" % [action_id, rewards])

	# Refresh active actions (remove completed action)
	_refresh_active_actions()

	# Show completion notification with rewards
	_show_action_complete_notification(action_id, rewards)

func _on_promotion_result(skill_id: String, success: bool, new_grade: String) -> void:
	"""Handle promotion result"""
	if LOG:
		print("[SkillsTab] Promotion result: %s → %s (Success: %s)" %
			[skill_id, new_grade, success])

	# Refresh skill card
	var card = skill_cards.get(skill_id, null)
	if card != null and is_instance_valid(card):
		if card.has_method("refresh"):
			card.refresh()

	# Refresh details panel if this skill is selected
	if selected_skill_id == skill_id:
		_show_skill_details(skill_id)

	# Show promotion notification
	_show_promotion_notification(skill_id, success, new_grade)

# ==================== NOTIFICATIONS ====================

func _show_level_up_notification(skill_id: String, new_level: int) -> void:
	"""Show level up notification"""
	# TODO: Implement notification popup
	if LOG:
		print("[SkillsTab] 🎉 Level Up! %s reached Level %d!" % [skill_id, new_level])

func _show_action_complete_notification(action_id: String, rewards: Dictionary) -> void:
	"""Show action completion notification"""
	# TODO: Implement notification popup
	if LOG:
		print("[SkillsTab] ✅ Action Complete! %s - Rewards: %s" % [action_id, rewards])

func _show_promotion_notification(skill_id: String, success: bool, new_grade: String) -> void:
	"""Show promotion notification"""
	# TODO: Implement notification popup
	if success:
		if LOG:
			print("[SkillsTab] ⭐ Promotion Success! %s → Grade %s!" % [skill_id, new_grade])
	else:
		if LOG:
			print("[SkillsTab] ❌ Promotion Failed: %s" % skill_id)

# ==================== PUBLIC API ====================

func refresh_all() -> void:
	"""Public method to refresh all UI"""
	_load_all_skills()
	_refresh_active_actions()

	if not selected_skill_id.is_empty():
		_show_skill_details(selected_skill_id)

func get_current_skill_id() -> String:
	"""Get currently selected skill ID"""
	return selected_skill_id
