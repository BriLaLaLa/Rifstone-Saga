# File: res://scripts/ui/ForgeUI.gd
# Forge UI - Equipment upgrade system (+0 to +9)

extends Control

# ==================== SUCCESS RATES ====================
const UPGRADE_SUCCESS_RATES = {
	0: 100.0,  # +0 → +1: always success
	1: 100.0,  # +1 → +2: always success
	2: 100.0,  # +2 → +3: always success
	3: 100.0,  # +3 → +4: always success
	4: 100.0,   # +4 → +5: 90% success
	5: 100.0,   # +5 → +6: 70% success
	6: 100.0,   # +6 → +7: 50% success
	7: 100.0,   # +7 → +8: 30% success
	8: 100.0    # +8 → +9: 15% success
}

const STAT_BOOST_PER_LEVEL = 0.05  # 5% boost per upgrade level

# ==================== UI NODES ====================
var _host: Control

@onready var _inventory_grid: GridContainer = $Panel/Margin/VBox/Content/LeftPanel/InvScroll/GridContainer/InventoryGrid
@onready var _upgrade_slot: Panel = $Panel/Margin/VBox/Content/RightPanel/UpgradeSlot
@onready var _upgrade_btn: Button = $Panel/Margin/VBox/Content/RightPanel/UpgradeButton
@onready var _info_label: Label = $Panel/Margin/VBox/Content/RightPanel/InfoLabel
@onready var _success_label: Label = $Panel/Margin/VBox/Content/RightPanel/SuccessLabel
@onready var _close_btn: Button = $Panel/Margin/VBox/Header/CloseButton

# ==================== STATE ====================
var _current_item: Dictionary = {}  # Item currently in upgrade slot
var _inventory_items: Array = []  # Reference to GameState inventory_items

func _ready() -> void:
	_close_btn.pressed.connect(_on_close_pressed)
	_upgrade_btn.pressed.connect(_on_upgrade_pressed)

func attach_to(host: Control) -> void:
	_host = host

func open_forge() -> void:
	print("[ForgeUI] ========== OPENING FORGE ==========")
	_refresh_inventory()
	visible = true
	print("[ForgeUI] Forge UI now visible")

# ==================== BUILD UI ====================
# ==================== INVENTORY REFRESH ====================
func _refresh_inventory() -> void:
	# Clear grid
	for child in _inventory_grid.get_children():
		child.queue_free()

	# Get items from GameState
	print("[ForgeUI] 🔄 _refresh_inventory() called")
	print("[ForgeUI] DEBUG - GameState path: ", GameState)
	print("[ForgeUI] DEBUG - GameState.inventory_items: ", GameState.inventory_items)
	_inventory_items = GameState.inventory_items.duplicate()

	print("[ForgeUI] Refreshing inventory - found %d items" % _inventory_items.size())

	# DEBUG: Print each item WITH upgrade_level
	for i in range(_inventory_items.size()):
		var item = _inventory_items[i]
		var upgrade_lvl = item.get("upgrade_level", 0)
		print("[ForgeUI]   Item %d: %s (upgrade_level: +%d)" % [i, item.get("item_id", "unknown"), upgrade_lvl])

	# DEBUG: Show ALL items for now (not just equipment)
	if _inventory_items.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "Inventario vuoto!\nAggiungi items dall'inventario principale."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_inventory_grid.add_child(empty_label)
		return

	# Create slots for each item
	for item_data in _inventory_items:
		var slot := _create_inventory_slot(item_data)
		_inventory_grid.add_child(slot)

func _create_inventory_slot(item_data: Dictionary) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(80, 80)  # Increased from 64x64

	# Add a styled background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	# Check if item exists in database
	var item_id = item_data.get("item_id", "")
	print("[ForgeUI] Creating slot for item: %s" % item_id)

	if not IData.items.has(item_id):
		print("[ForgeUI] ❌ Item %s not found in database" % item_id)
		return slot  # Item not found in database

	var item_info = IData.items[item_id]
	var item_type = item_info.get("type", "").to_lower()
	# Check if it's equipment (Weapon, Armor, Shield, etc.)
	var equipment_types = ["weapon", "armor", "shield", "helmet", "boots", "gloves", "belt", "accessory"]
	var is_equipment = equipment_types.has(item_type)
	print("[ForgeUI]   → Type: %s, IsEquipment: %s" % [item_info.get("type", "unknown"), is_equipment])

	# Check if this item is currently in the upgrade slot
	var is_current_upgrade_item = false
	if not _current_item.is_empty():
		var current_pos = _current_item.get("pos", {})
		var item_pos = item_data.get("pos", {})
		var current_id = _current_item.get("item_id", "")

		# Match by position and ID
		if typeof(current_pos) == TYPE_DICTIONARY and typeof(item_pos) == TYPE_DICTIONARY:
			is_current_upgrade_item = (current_id == item_id and
				current_pos.get("x") == item_pos.get("x") and
				current_pos.get("y") == item_pos.get("y"))

	# Highlight equipment slots with golden border, or BRIGHT CYAN if currently upgrading
	if is_current_upgrade_item:
		style.border_color = Color(0.0, 1.0, 1.0)  # Bright cyan for item being upgraded
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4
	elif is_equipment:
		style.border_color = Color(0.8, 0.7, 0.3)  # Golden border for equipment

	# Show ALL items (make equipment clickable, others just visual)
	if true:  # Changed from 'if is_equipment:' to show everything
		# Add padding container
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		slot.add_child(margin)

		# Create item icon
		var icon := TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# Try both "icon" and "texture" keys for backward compatibility
		var texture_path = item_info.get("icon", item_info.get("texture", ""))
		if texture_path != "" and ResourceLoader.exists(texture_path):
			icon.texture = load(texture_path)
			print("[ForgeUI]   ✅ Loaded texture: %s" % texture_path)
		else:
			print("[ForgeUI]   ❌ Texture not found: %s" % texture_path)

		margin.add_child(icon)

		# Show upgrade level if exists
		var upgrade_level = item_data.get("upgrade_level", 0)
		if upgrade_level > 0:
			var level_label := Label.new()
			level_label.text = "+%d" % upgrade_level
			level_label.position = Vector2(4, 4)
			level_label.add_theme_font_size_override("font_size", 14)
			level_label.add_theme_color_override("font_color", Color.YELLOW)
			level_label.add_theme_color_override("font_outline_color", Color.BLACK)
			level_label.add_theme_constant_override("outline_size", 2)
			slot.add_child(level_label)

		# Make it draggable (only if equipment)
		if is_equipment:
			print("[ForgeUI]   📌 Making item draggable: %s" % item_id)

			# Store item data in slot metadata for dragging
			slot.set_meta("item_data", item_data)
			slot.set_meta("is_equipment", true)

			# Enable drag functionality
			slot.mouse_filter = Control.MOUSE_FILTER_PASS

			# Create invisible button for drag detection and tooltip
			var drag_detector := Control.new()
			drag_detector.set_anchors_preset(Control.PRESET_FULL_RECT)
			drag_detector.mouse_filter = Control.MOUSE_FILTER_PASS
			slot.add_child(drag_detector)

			# Connect drag signals
			drag_detector.gui_input.connect(_on_slot_gui_input.bind(slot))

			# Connect tooltip signals
			drag_detector.mouse_entered.connect(_on_slot_mouse_entered.bind(item_data, item_info))
			drag_detector.mouse_exited.connect(_on_slot_mouse_exited)
		else:
			# Non-equipment: show name at bottom
			var name_label := Label.new()
			name_label.text = item_info.get("name", item_id)
			name_label.position = Vector2(4, 60)
			name_label.custom_minimum_size = Vector2(72, 0)
			name_label.add_theme_font_size_override("font_size", 9)
			name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.add_child(name_label)

	return slot

# ==================== DRAG & DROP SYSTEM ====================
var _dragging_slot: Panel = null
var _drag_preview: Control = null

# ==================== TOOLTIP SYSTEM ====================
func _on_slot_mouse_entered(item_data: Dictionary, item_info: Dictionary) -> void:
	"""Show tooltip when mouse enters item slot"""
	if _dragging_slot != null:
		return  # Don't show tooltip while dragging

	# Merge item_data with item_info for complete tooltip
	var tooltip_data = item_info.duplicate(true)  # Deep copy to avoid modifying original
	var upgrade_level = item_data.get("upgrade_level", 0)
	tooltip_data["upgrade_level"] = upgrade_level

	# Add bonuses if present
	if item_data.has("bonuses"):
		tooltip_data["bonuses"] = item_data.get("bonuses", [])

	# RECALCULATE stats for tooltip display if item is upgraded
	if upgrade_level > 0 and tooltip_data.has("stats"):
		_apply_upgrade_bonus(tooltip_data, upgrade_level)

	# Show tooltip using TooltipManager
	if has_node("/root/TooltipManager"):
		var tooltip_mgr = get_node("/root/TooltipManager")
		tooltip_mgr.show_item_tooltip(tooltip_data)

func _on_slot_mouse_exited() -> void:
	"""Hide tooltip when mouse exits item slot"""
	if has_node("/root/TooltipManager"):
		var tooltip_mgr = get_node("/root/TooltipManager")
		tooltip_mgr.hide_item_tooltip()

func _on_slot_gui_input(event: InputEvent, slot: Panel) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start drag
				_start_drag(slot)
			elif _dragging_slot == slot:
				# End drag
				_end_drag()

func _start_drag(slot: Panel) -> void:
	if not slot.has_meta("item_data"):
		return

	print("[ForgeUI] 🎯 Starting drag for item")
	_dragging_slot = slot

	# Hide tooltip when dragging starts
	if has_node("/root/TooltipManager"):
		var tooltip_mgr = get_node("/root/TooltipManager")
		tooltip_mgr.hide_item_tooltip()

	# Create drag preview (visual feedback)
	_drag_preview = Panel.new()
	_drag_preview.custom_minimum_size = Vector2(80, 80)
	_drag_preview.modulate = Color(1, 1, 1, 0.7)
	_drag_preview.z_index = 100

	# Copy the slot's style
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.3, 0.3, 0.4, 0.9)
	preview_style.border_color = Color(0.8, 0.7, 0.3)
	preview_style.set_border_width_all(2)
	preview_style.set_corner_radius_all(4)
	_drag_preview.add_theme_stylebox_override("panel", preview_style)

	# Copy the icon
	var item_data = slot.get_meta("item_data")
	var item_id = item_data.get("item_id", "")
	if IData.items.has(item_id):
		var item_info = IData.items[item_id]
		var texture_path = item_info.get("icon", item_info.get("texture", ""))
		if texture_path != "" and ResourceLoader.exists(texture_path):
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.texture = load(texture_path)

			var margin := MarginContainer.new()
			margin.set_anchors_preset(Control.PRESET_FULL_RECT)
			margin.add_theme_constant_override("margin_left", 6)
			margin.add_theme_constant_override("margin_top", 6)
			margin.add_theme_constant_override("margin_right", 6)
			margin.add_theme_constant_override("margin_bottom", 6)
			_drag_preview.add_child(margin)
			margin.add_child(icon)

	add_child(_drag_preview)
	_update_drag_preview_position()

func _end_drag() -> void:
	if _drag_preview == null:
		return

	print("[ForgeUI] 🎯 Ending drag")

	# Check if dropped on upgrade slot
	var mouse_pos = get_global_mouse_position()
	var slot_rect = _upgrade_slot.get_global_rect()

	if slot_rect.has_point(mouse_pos):
		print("[ForgeUI] ✅ Dropped on upgrade slot!")
		_place_item_in_upgrade_slot()
	else:
		print("[ForgeUI] ❌ Dropped outside upgrade slot")

	# Clean up
	_drag_preview.queue_free()
	_drag_preview = null
	_dragging_slot = null

func _update_drag_preview_position() -> void:
	if _drag_preview:
		_drag_preview.global_position = get_global_mouse_position() - Vector2(40, 40)

func _process(delta: float) -> void:
	if _drag_preview:
		_update_drag_preview_position()

func _place_item_in_upgrade_slot() -> void:
	if _dragging_slot == null or not _dragging_slot.has_meta("item_data"):
		return

	var item_data = _dragging_slot.get_meta("item_data")
	var item_id = item_data.get("item_id", "")

	print("[ForgeUI] 📦 Placing item in upgrade slot: %s" % item_id)

	# Check if already at max level
	var current_level = item_data.get("upgrade_level", 0)
	if current_level >= 9:
		print("[ForgeUI] ❌ Item already at max level (+9)!")
		return

	# Set current item
	_current_item = item_data.duplicate()

	# Update visual slot
	_update_upgrade_slot_visual()

	# Update UI
	_update_upgrade_ui()

func _update_upgrade_slot_visual() -> void:
	"""Show the item icon in the upgrade slot"""
	# Clear existing visuals except placeholder
	for child in _upgrade_slot.get_children():
		if child.name != "PlaceholderLabel":
			child.queue_free()

	# Hide placeholder
	var placeholder = _upgrade_slot.get_node_or_null("PlaceholderLabel")
	if placeholder:
		placeholder.visible = false

	if _current_item.is_empty():
		if placeholder:
			placeholder.visible = true
		return

	var item_id = _current_item.get("item_id", "")
	if not IData.items.has(item_id):
		return

	var item_info = IData.items[item_id]
	var texture_path = item_info.get("icon", item_info.get("texture", ""))

	if texture_path != "" and ResourceLoader.exists(texture_path):
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 10)

		var icon := TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.texture = load(texture_path)
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL

		margin.add_child(icon)
		_upgrade_slot.add_child(margin)

		# Show upgrade level if exists
		var upgrade_level = _current_item.get("upgrade_level", 0)
		if upgrade_level > 0:
			var level_label := Label.new()
			level_label.text = "+%d" % upgrade_level
			level_label.position = Vector2(8, 8)
			level_label.add_theme_font_size_override("font_size", 18)
			level_label.add_theme_color_override("font_color", Color.YELLOW)
			level_label.add_theme_color_override("font_outline_color", Color.BLACK)
			level_label.add_theme_constant_override("outline_size", 3)
			_upgrade_slot.add_child(level_label)

		# Add X button to remove item from slot
		var remove_btn := Button.new()
		remove_btn.text = "✕"
		remove_btn.custom_minimum_size = Vector2(24, 24)
		remove_btn.position = Vector2(_upgrade_slot.size.x - 28, 4)  # Top-right corner
		remove_btn.add_theme_font_size_override("font_size", 18)
		remove_btn.add_theme_color_override("font_color", Color.WHITE)
		remove_btn.tooltip_text = "Remove item from upgrade slot"

		# Style the button
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.8, 0.2, 0.2, 0.8)  # Red background
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		remove_btn.add_theme_stylebox_override("normal", btn_style)

		var btn_style_hover := StyleBoxFlat.new()
		btn_style_hover.bg_color = Color(1.0, 0.3, 0.3, 0.9)  # Brighter red on hover
		btn_style_hover.corner_radius_top_left = 4
		btn_style_hover.corner_radius_top_right = 4
		btn_style_hover.corner_radius_bottom_left = 4
		btn_style_hover.corner_radius_bottom_right = 4
		remove_btn.add_theme_stylebox_override("hover", btn_style_hover)

		remove_btn.pressed.connect(_on_remove_item_pressed)
		_upgrade_slot.add_child(remove_btn)

func _update_upgrade_ui() -> void:
	if _current_item.is_empty():
		_info_label.text = "Nessun item"
		_success_label.text = ""
		_upgrade_btn.disabled = true
		return

	var item_id = _current_item.get("item_id", "")
	if not IData.items.has(item_id):
		_info_label.text = "Item non trovato"
		_success_label.text = ""
		_upgrade_btn.disabled = true
		return

	var item_info = IData.items[item_id]
	var current_level = _current_item.get("upgrade_level", 0)
	var next_level = current_level + 1
	var success_rate = UPGRADE_SUCCESS_RATES.get(current_level, 0.0)

	_info_label.text = "%s +%d\n→ +%d" % [
		item_info.get("name", "Unknown"),
		current_level,
		next_level
	]

	_success_label.text = "Probabilità: %.0f%%" % success_rate

	if success_rate < 100.0:
		_success_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	else:
		_success_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)

	_upgrade_btn.disabled = false

# ==================== UPGRADE LOGIC ====================
func _on_remove_item_pressed() -> void:
	"""Remove item from upgrade slot (X button)"""
	print("[ForgeUI] 🗑️ Removing item from upgrade slot")
	_current_item = {}
	_update_upgrade_slot_visual()
	_update_upgrade_ui()
	_refresh_inventory()  # Remove highlight from item in list

func _on_upgrade_pressed() -> void:
	if _current_item.is_empty():
		return

	var current_level = _current_item.get("upgrade_level", 0)
	var success_rate = UPGRADE_SUCCESS_RATES.get(current_level, 0.0)

	# Roll for success
	var roll = randf() * 100.0
	var success = roll <= success_rate

	print("[ForgeUI] Upgrade attempt: +%d → +%d (%.1f%% chance, rolled %.1f) = %s" % [
		current_level, current_level + 1, success_rate, roll, "SUCCESS" if success else "FAIL"
	])

	if success:
		_upgrade_success()
	else:
		_upgrade_fail()

func _upgrade_success() -> void:
	var current_level = _current_item.get("upgrade_level", 0)
	var new_level = current_level + 1

	print("[ForgeUI] 🔨 Applying upgrade to GameState...")

	# Get position for matching
	var target_pos = _current_item.get("pos")
	var target_item_id = _current_item.get("item_id")

	print("[ForgeUI]   Looking for: item_id=%s, pos=%s" % [target_item_id, target_pos])

	# Update item in GameState
	var found = false
	for i in range(GameState.inventory_items.size()):
		var item = GameState.inventory_items[i]
		var item_pos = item.get("pos")
		var item_id = item.get("item_id")

		# Compare positions (they are dictionaries with x,y)
		var pos_match = false
		if typeof(target_pos) == TYPE_DICTIONARY and typeof(item_pos) == TYPE_DICTIONARY:
			pos_match = (item_pos.get("x") == target_pos.get("x") and item_pos.get("y") == target_pos.get("y"))
		else:
			pos_match = (item_pos == target_pos)

		if item_id == target_item_id and pos_match:
			print("[ForgeUI]   ✅ Found item at index %d" % i)
			print("[ForgeUI]   📋 BEFORE: upgrade_level = %s" % GameState.inventory_items[i].get("upgrade_level", 0))
			# ONLY save upgrade_level - stats will be recalculated by InventoryTab on load
			GameState.inventory_items[i]["upgrade_level"] = new_level

			# NEW: Sync enhancement_level for visual effects (+7, +8, +9)
			if new_level >= 7:
				GameState.inventory_items[i]["enhancement_level"] = new_level
				print("[ForgeUI]   ✨ Enhancement visual effects activated at +%d!" % new_level)

			print("[ForgeUI]   📋 AFTER: upgrade_level = %s" % GameState.inventory_items[i].get("upgrade_level", 0))
			print("[ForgeUI]   ✅ Upgrade SUCCESS! %s is now +%d" % [target_item_id, new_level])
			print("[ForgeUI]   📊 Stats will be recalculated on next inventory load")

			# DEBUG: Verify the data is actually saved in GameState
			print("[ForgeUI]   🔍 VERIFICATION - GameState.inventory_items[%d] = %s" % [i, GameState.inventory_items[i]])
			found = true
			break

	if not found:
		print("[ForgeUI]   ❌ WARNING: Item not found in GameState!")

	# Emit signal to update inventory UI
	if GameState.has_signal("on_inventory_changed"):
		GameState.emit_signal("on_inventory_changed")

	# UPDATE: Keep item in slot for quick consecutive upgrades
	# Update _current_item with new level
	_current_item["upgrade_level"] = new_level

	# Update slot visual with new level
	_update_upgrade_slot_visual()

	# Refresh inventory (this will highlight the upgraded item)
	_refresh_inventory()
	_update_upgrade_ui()

	# Show success message
	_info_label.text = "✅ POTENZIAMENTO\nRIUSCITO!"
	_info_label.add_theme_color_override("font_color", Color.GREEN)

func _upgrade_fail() -> void:
	print("[ForgeUI] ❌ Upgrade FAILED! Item destroyed!")

	# Get position for matching
	var target_pos = _current_item.get("pos")
	var target_item_id = _current_item.get("item_id")

	print("[ForgeUI]   Removing: item_id=%s, pos=%s" % [target_item_id, target_pos])

	# Remove item from GameState
	var found = false
	for i in range(GameState.inventory_items.size() - 1, -1, -1):
		var item = GameState.inventory_items[i]
		var item_pos = item.get("pos")
		var item_id = item.get("item_id")

		# Compare positions (they are dictionaries with x,y)
		var pos_match = false
		if typeof(target_pos) == TYPE_DICTIONARY and typeof(item_pos) == TYPE_DICTIONARY:
			pos_match = (item_pos.get("x") == target_pos.get("x") and item_pos.get("y") == target_pos.get("y"))
		else:
			pos_match = (item_pos == target_pos)

		if item_id == target_item_id and pos_match:
			print("[ForgeUI]   ✅ Found and removed item at index %d" % i)
			GameState.inventory_items.remove_at(i)
			found = true
			break

	if not found:
		print("[ForgeUI]   ❌ WARNING: Item not found in GameState!")

	# Emit signal to update inventory UI
	if GameState.has_signal("on_inventory_changed"):
		GameState.emit_signal("on_inventory_changed")

	# Clear slot visual
	_update_upgrade_slot_visual()

	# Refresh UI
	_current_item = {}
	_refresh_inventory()
	_update_upgrade_ui()

	# Show fail message
	_info_label.text = "❌ POTENZIAMENTO\nFALLITO!\nItem distrutto!"
	_info_label.add_theme_color_override("font_color", Color.RED)

func _apply_upgrade_bonus(item: Dictionary, level: int) -> void:
	"""Apply stat bonuses based on upgrade level (+5% per level)"""
	if not item.has("stats"):
		return

	var base_stats = item.get("base_stats", {})
	if base_stats.is_empty():
		# First upgrade - save original stats
		item["base_stats"] = item["stats"].duplicate()
		base_stats = item["base_stats"]

	# Calculate boosted stats
	var multiplier = 1.0 + (level * STAT_BOOST_PER_LEVEL)
	var boosted_stats = {}

	for stat_key in base_stats.keys():
		var base_value = base_stats[stat_key]
		boosted_stats[stat_key] = base_value * multiplier

	item["stats"] = boosted_stats

	print("[ForgeUI] Applied +%d upgrade bonus (x%.2f multiplier)" % [level, multiplier])

# ==================== CLOSE ====================
func _on_close_pressed() -> void:
	print("[ForgeUI] 🚪 Closing Forge - clearing upgrade slot")
	_current_item = {}
	_update_upgrade_slot_visual()
	_update_upgrade_ui()
	visible = false
