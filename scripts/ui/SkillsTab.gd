extends Control

# Skills System UI - Redesigned with Loadout Slots
# 6-slot loadout at top, collection below, auto-save

signal loadout_changed()
signal ready_for_sync()

# Resources
const SkillCardScene = preload("res://scripts/ui/SkillCard.tscn")
const SkillSlotScene = preload("res://scripts/ui/SkillSlot.tscn")

# References to UI containers
@onready var loadout_container: HBoxContainer = $VBoxContainer/LoadoutSection/LoadoutSlotsContainer
@onready var skills_grid: GridContainer = $VBoxContainer/CollectionSection/ScrollContainer/SkillsGrid
@onready var details_panel: Panel = $VBoxContainer/DetailsSection/DetailsPanel
@onready var search_bar: LineEdit = $VBoxContainer/CollectionSection/TopBar/SearchBar
@onready var category_filter: OptionButton = $VBoxContainer/CollectionSection/TopBar/CategoryFilter

# State
var loadout_slots: Array[SkillSlot] = []
var skill_cards: Dictionary = {}  # skill_id -> SkillCard
var selected_skill_for_equip: String = ""  # For click-to-equip mode
var selected_skill_id: String = ""  # For details panel

# Battle overlay
var battle_overlay: Panel = null

# Filters
var current_search: String = ""
var current_category: String = "combat"  # Only show warrior skills

const MAX_LOADOUT_SLOTS := 6
const SAVE_PATH := "user://skill_loadout.json"

func _ready() -> void:
	if GameLogger.ENABLED:
		print("[SkillsTab] Initializing NEW Skills System UI")

	# Setup click detection on background to deselect
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_background_clicked)

	# Setup filters
	_setup_filters()

	# Create loadout slots
	_create_loadout_slots()

	# Load all skills
	_load_all_skills()

	# Load saved loadout
	_load_loadout()

	# Create battle overlay (hidden initially)
	_create_battle_overlay()

	if GameLogger.ENABLED:
		print("[SkillsTab] Initialized with %d skills, %d loadout slots" % [skill_cards.size(), loadout_slots.size()])

# ==================== INITIALIZATION ====================

func _setup_filters() -> void:
	"""Setup filter dropdowns and search bar"""
	if category_filter:
		category_filter.clear()
		category_filter.add_item("Combattimento", 0)
		category_filter.selected = 0
		category_filter.item_selected.connect(_on_category_filter_changed)

	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
		search_bar.placeholder_text = "Cerca skill..."

func _create_loadout_slots() -> void:
	"""Create the 6 loadout slots"""
	if not loadout_container:
		push_error("[SkillsTab] LoadoutContainer not found!")
		return

	for i in range(MAX_LOADOUT_SLOTS):
		var slot = SkillSlotScene.instantiate()
		loadout_container.add_child(slot)
		slot.setup(i)

		# Connect signals
		slot.skill_changed.connect(_on_loadout_skill_changed)
		slot.slot_clicked.connect(_on_loadout_slot_clicked)

		loadout_slots.append(slot)

	if GameLogger.ENABLED:
		print("[SkillsTab] Created %d loadout slots" % MAX_LOADOUT_SLOTS)

func _load_all_skills() -> void:
	"""Load all warrior skills from GameState"""
	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	if not "data" in gs or not "skills" in gs.data:
		if GameLogger.ENABLED:
			print("[SkillsTab] ERROR: No skills data in GameState!")
		return

	# Clear existing cards
	for card in skill_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	skill_cards.clear()

	# Create card for each WARRIOR skill only
	for skill_id in gs.data.skills:
		var skill_data = gs.data.skills[skill_id]

		# Filter: Only show combat (warrior) skills
		if skill_data.get("category", "") != "combat":
			continue

		_create_skill_card(skill_id, skill_data)

	if GameLogger.ENABLED:
		print("[SkillsTab] Loaded %d warrior skill cards" % skill_cards.size())

func _create_skill_card(skill_id: String, skill_data: Dictionary) -> void:
	"""Create a skill card and add it to the grid"""
	# Instantiate card
	var card = SkillCardScene.instantiate()
	skills_grid.add_child(card)

	# Setup card
	if card.has_method("setup"):
		card.setup(skill_data)

	# Connect click signal
	if card.has_signal("clicked"):
		card.clicked.connect(_on_skill_card_clicked)

	# Store reference
	skill_cards[skill_id] = card

	if GameLogger.ENABLED:
		print("[SkillsTab] Created card for warrior skill: %s" % skill_data.get("name", skill_id))

# ==================== LOADOUT MANAGEMENT ====================

func equip_skill_to_slot(slot_index: int, skill_id: String) -> void:
	"""Equip a skill to a specific slot"""
	if slot_index < 0 or slot_index >= loadout_slots.size():
		return

	var slot = loadout_slots[slot_index]
	slot.equip_skill(skill_id)

	# Auto-save
	_save_loadout()

	# Emit signal for real-time updates
	loadout_changed.emit()

	if GameLogger.ENABLED:
		print("[SkillsTab] Equipped %s to slot %d" % [skill_id, slot_index])

func get_loadout() -> Array[String]:
	"""Get current loadout as array of skill IDs"""
	var loadout: Array[String] = []
	for slot in loadout_slots:
		loadout.append(slot.get_equipped_skill_id())
	return loadout

func _on_loadout_skill_changed(slot_index: int, skill_id: String) -> void:
	"""Handle skill change in loadout slot"""
	if GameLogger.ENABLED:
		print("[SkillsTab] Loadout slot %d changed to: %s" % [slot_index, skill_id])

	# Auto-save
	_save_loadout()

	# Emit signal for real-time updates (BattleTab will reload from file)
	loadout_changed.emit()

func _on_loadout_slot_clicked(slot_index: int) -> void:
	"""Handle click on loadout slot - CLASH ROYALE STYLE"""
	if GameLogger.ENABLED:
		print("[SkillsTab] Loadout slot %d clicked" % slot_index)

	# Check if in battle - prevent changes
	if _is_in_battle():
		_show_battle_warning()
		return

	var slot = loadout_slots[slot_index]

	# Se lo slot è PIENO e NON abbiamo una skill selezionata → RIMUOVI la skill (come Clash Royale)
	if not slot.is_empty() and selected_skill_for_equip.is_empty():
		if GameLogger.ENABLED:
			print("[SkillsTab] Removing skill from slot %d (Clash Royale style)" % slot_index)
		slot.clear_slot()
		return

	# Se abbiamo una skill selezionata → EQUIPAGGIA
	if not selected_skill_for_equip.is_empty():
		# Check if skill is already equipped in another slot
		if is_skill_equipped(selected_skill_for_equip):
			# Remove from old slot first
			_remove_skill_from_loadout(selected_skill_for_equip)

		equip_skill_to_slot(slot_index, selected_skill_for_equip)
		selected_skill_for_equip = ""  # Clear selection
		_clear_skill_card_highlights()

		# Stop wiggle animation on all slots
		_stop_all_slots_wiggle()

# ==================== SKILL SELECTION ====================

func _on_skill_card_clicked(skill_id: String) -> void:
	"""Handle skill card click"""
	if GameLogger.ENABLED:
		print("[SkillsTab] Skill card clicked: %s" % skill_id)

	# Se clicchi sulla stessa skill già selezionata → deseleziona
	if selected_skill_for_equip == skill_id:
		selected_skill_for_equip = ""
		_clear_skill_card_highlights()
		if GameLogger.ENABLED:
			print("[SkillsTab] Deselected skill %s" % skill_id)
		return

	# Se c'era un'altra skill selezionata → stop wiggle prima
	if not selected_skill_for_equip.is_empty():
		_stop_all_slots_wiggle()

	# Show details in panel
	_show_skill_details(skill_id)

	# Enable click-to-equip mode
	selected_skill_for_equip = skill_id

	# Highlight the selected card
	_highlight_skill_card(skill_id)

	# Start wiggle animation on ALL slots (Clash Royale style)
	_start_all_slots_wiggle()

	if GameLogger.ENABLED:
		print("[SkillsTab] Click-to-equip mode: Select a slot to equip %s" % skill_id)

func _highlight_skill_card(skill_id: String) -> void:
	"""Highlight selected skill card"""
	for id in skill_cards:
		var card = skill_cards[id]
		if is_instance_valid(card) and card.has_method("set_selected"):
			card.set_selected(id == skill_id)

func _clear_skill_card_highlights() -> void:
	"""Clear all skill card highlights"""
	for card in skill_cards.values():
		if is_instance_valid(card) and card.has_method("set_selected"):
			card.set_selected(false)

	# Also stop wiggle on slots when deselecting
	_stop_all_slots_wiggle()

func _show_skill_details(skill_id: String) -> void:
	"""Show skill details in the details panel"""
	selected_skill_id = skill_id

	if details_panel and details_panel.has_method("show_skill"):
		details_panel.show_skill(skill_id)

	if GameLogger.ENABLED:
		print("[SkillsTab] Showing details for: %s" % skill_id)

# ==================== SAVE / LOAD ====================

func _save_loadout() -> void:
	"""Auto-save current loadout"""
	var loadout_data = {
		"slots": []
	}

	for slot in loadout_slots:
		loadout_data.slots.append(slot.get_equipped_skill_id())

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(loadout_data))
		file.close()

		if GameLogger.ENABLED:
			print("[SkillsTab] Loadout auto-saved: %s" % str(loadout_data.slots))

func _load_loadout() -> void:
	"""Load saved loadout"""
	if not FileAccess.file_exists(SAVE_PATH):
		if GameLogger.ENABLED:
			print("[SkillsTab] No saved loadout found, using defaults")
		_apply_default_loadout()
		ready_for_sync.emit()  # Emit signal after default loadout applied
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[SkillsTab] Failed to open loadout file")
		ready_for_sync.emit()  # Still emit even on error
		return

	var txt = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SkillsTab] Invalid loadout data")
		ready_for_sync.emit()  # Still emit even on error
		return

	var slots_data = parsed.get("slots", [])

	# Apply loaded loadout
	for i in range(min(slots_data.size(), loadout_slots.size())):
		var skill_id = slots_data[i]
		if not skill_id.is_empty():
			loadout_slots[i].equip_skill(skill_id)

	if GameLogger.ENABLED:
		print("[SkillsTab] Loadout loaded: %s" % str(slots_data))
		print("[SkillsTab] 📢 Emitting ready_for_sync signal...")

	# Emit signal AFTER loadout is fully loaded
	ready_for_sync.emit()

func _apply_default_loadout() -> void:
	"""Apply default loadout (first 4 skills)"""
	var skill_ids = skill_cards.keys()

	for i in range(min(4, skill_ids.size())):
		if i < loadout_slots.size():
			loadout_slots[i].equip_skill(skill_ids[i])

	_save_loadout()

	if GameLogger.ENABLED:
		print("[SkillsTab] Applied default loadout")

# ==================== NOTE: SYNC IS HANDLED BY FILE ====================
# BattleTab now reads skills directly from the saved loadout file
# No need for complex sync logic - just save to file and emit signal

# ==================== FILTERS ====================

func _on_search_text_changed(new_text: String) -> void:
	"""Handle search bar text change"""
	current_search = new_text
	_apply_filters()

func _on_category_filter_changed(index: int) -> void:
	"""Handle category filter change"""
	# For now, always combat
	_apply_filters()

func _apply_filters() -> void:
	"""Apply current search filter to skill cards"""
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

		# Show/hide card
		card.visible = matches_search

# ==================== PUBLIC API ====================

func refresh_all() -> void:
	"""Public method to refresh all UI"""
	_load_all_skills()
	_load_loadout()

func is_skill_equipped(skill_id: String) -> bool:
	"""Check if a skill is already equipped in any slot"""
	for slot in loadout_slots:
		if slot.get_equipped_skill_id() == skill_id:
			return true
	return false

func _remove_skill_from_loadout(skill_id: String) -> void:
	"""Remove a skill from all slots where it's equipped"""
	for slot in loadout_slots:
		if slot.get_equipped_skill_id() == skill_id:
			slot.clear_slot()

# ==================== BACKGROUND CLICK ====================

func _on_background_clicked(event: InputEvent) -> void:
	"""Handle click on background to deselect"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Deselect current selection
			if not selected_skill_for_equip.is_empty():
				selected_skill_for_equip = ""
				_clear_skill_card_highlights()

				if GameLogger.ENABLED:
					print("[SkillsTab] Deselected skill (clicked background)")

# ==================== WIGGLE ANIMATIONS ====================

func _start_all_slots_wiggle() -> void:
	"""Start wiggle animation on all loadout slots (Clash Royale style)"""
	for slot in loadout_slots:
		if is_instance_valid(slot) and slot.has_method("start_wiggle"):
			slot.start_wiggle()

	if GameLogger.ENABLED:
		print("[SkillsTab] Started wiggle on all %d slots" % loadout_slots.size())

func _stop_all_slots_wiggle() -> void:
	"""Stop wiggle animation on all loadout slots"""
	for slot in loadout_slots:
		if is_instance_valid(slot) and slot.has_method("stop_wiggle"):
			slot.stop_wiggle()

	if GameLogger.ENABLED:
		print("[SkillsTab] Stopped wiggle on all slots")

# ==================== BATTLE CHECK ====================

func _is_in_battle() -> bool:
	"""Check if currently in battle (prevents skill changes)"""
	# Find BattleTab
	var main = get_tree().root.get_node_or_null("Main")
	if not main:
		return false

	var tabs = main.get_node_or_null("Margin/VBox/Tabs")
	if not tabs:
		return false

	for i in range(tabs.get_tab_count()):
		var tab = tabs.get_tab_control(i)
		if tab.name == "Combat":
			if tab.get_child_count() > 0:
				var battle_tab = tab.get_child(0)
				if battle_tab.has_method("is_in_battle"):
					return battle_tab.is_in_battle()
			break

	return false

func _show_battle_warning() -> void:
	"""Show warning when trying to change skills during battle"""
	# Just show the overlay (already has the message)
	if battle_overlay:
		# Add a pulse effect
		var tween = create_tween()
		tween.tween_property(battle_overlay, "modulate:a", 0.95, 0.2)
		tween.tween_property(battle_overlay, "modulate:a", 0.85, 0.2)

	if GameLogger.ENABLED:
		print("[SkillsTab] ⚠️ Showed battle warning")

func _create_battle_overlay() -> void:
	"""Create overlay that blocks entire tab during battle"""
	battle_overlay = Panel.new()
	battle_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_overlay.z_index = 999

	# Semi-transparent dark background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	battle_overlay.add_theme_stylebox_override("panel", style)

	# Giant text in the middle
	var label = Label.new()
	label.text = "⚔️ BATTAGLIA IN CORSO ⚔️"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 60)
	label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	battle_overlay.add_child(label)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Exit the battle to change your loadout"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.position = Vector2(-300, 50)
	subtitle.size = Vector2(600, 50)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 3)
	battle_overlay.add_child(subtitle)

	# Initially hidden
	battle_overlay.visible = false

	add_child(battle_overlay)

	if GameLogger.ENABLED:
		print("[SkillsTab] Battle overlay created")

func show_battle_overlay() -> void:
	"""Show battle overlay (called from BattleTab when battle starts)"""
	if battle_overlay:
		battle_overlay.visible = true
		if GameLogger.ENABLED:
			print("[SkillsTab] 🔒 Battle overlay SHOWN")

func hide_battle_overlay() -> void:
	"""Hide battle overlay (called from BattleTab when battle ends)"""
	if battle_overlay:
		battle_overlay.visible = false
		if GameLogger.ENABLED:
			print("[SkillsTab] 🔓 Battle overlay HIDDEN")
