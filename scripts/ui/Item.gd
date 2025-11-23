extends TextureRect
class_name Item

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Item Configuration")
@export var item_id: String = "unknown"
@export var item_size: Vector2i = Vector2i(1, 1)
@export var cell_px: int = 64

@export_group("Drag & Drop Visual")
@export var drag_source_opacity: float = 0.5  # Opacity of source item while dragging
@export var drag_preview_opacity: float = 0.8  # Opacity of drag preview

@export_group("Stack Label Style")
@export var stack_font_size: int = 14
@export var stack_font_color: Color = Color.WHITE
@export var stack_outline_color: Color = Color.BLACK
@export var stack_outline_size: int = 2
@export var stack_label_offset: Vector2 = Vector2(-4, -2)  # Bottom-right offset

# ==================== INTERNAL VARIABLES ====================
# Stacking support
var is_stackable: bool = false
var max_stack: int = 1
var stack_count: int = 1
var stack_label: Label = null  # Display stack count

var _original_parent: Node = null
var _original_position: Vector2i = Vector2i(-1, -1)
var _is_being_dragged: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	if GameLogger.ENABLED:
		print("[Item] Ready: %s at %s" % [item_id, position])

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _get_drag_data(at_position: Vector2) -> Variant:
	"""Chiamato da Godot quando inizi a draggare l'item"""
	# Check if dragging is disabled (for readonly inventory popup)
	if has_meta("is_draggable") and not get_meta("is_draggable"):
		if GameLogger.ENABLED:
			print("[Item] Dragging disabled for %s (readonly mode)" % item_id)
		return null  # Disable dragging

	# Check if parent is a locked BagSlot (starter bag cannot be moved)
	var parent = get_parent()
	if parent and parent.get_class() == "Panel" and parent.get_script():
		var script_path = parent.get_script().resource_path
		if "BagSlot" in script_path and "is_locked" in parent and parent.is_locked:
			print("[Item] Cannot drag locked bag (starter bag)")
			return null  # Disable dragging for locked bag
		# NOTE: For non-locked bags, we allow the drag to start.
		# The validation happens in BagSlot._handle_bag_removed() when the bag is actually removed.

	print("[Item] _get_drag_data called for %s at %s" % [item_id, at_position])
	
	# Marca che QUESTO item sta venendo draggato
	_is_being_dragged = true
	
	# Salva il parent originale e la posizione
	_original_parent = get_parent()
	var inventory_tab = _find_inventory_tab()
	if inventory_tab:
		_original_position = inventory_tab.get_item_position(self)
		print("[Item] Saved original position: %s in parent: %s" % [_original_position, _original_parent.name if _original_parent else "null"])
	
	# IMPORTANTE: Fai in modo che l'item ignori il mouse durante il drag
	# ma mantieni z_index alto così è visibile
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CRITICAL FIX: NON abbassare z_index, altrimenti va sotto la grid
	# z_index = -1  # RIMOSSO - causava item invisibile

	# NON serve più disabilitare gli InventorySlot
	# Godot gestisce automaticamente gli eventi con MOUSE_FILTER_IGNORE
	# _disable_inventory_slots_during_drag()  # RIMOSSO
	
	# Crea il preview custom CENTRATO sull'hotspot
	var preview = _create_drag_preview(at_position)
	set_drag_preview(preview)

	# Rendi l'item semi-trasparente durante il drag (usa valore dall'Inspector)
	modulate.a = drag_source_opacity
	
	# Ritorna i dati del drag
	return {
		"type": "inventory_item",
		"item": self,
		"item_id": item_id,
		"item_size": item_size,
		"hotspot": at_position
	}

func _create_drag_preview(hotspot: Vector2) -> Control:
	"""Crea un preview custom per il drag, centrato sull'hotspot"""
	var preview = Control.new()

	# Crea la texture dentro il control (usa valori dall'Inspector)
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	tex_rect.modulate = Color(1, 1, 1, drag_preview_opacity)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Posiziona la texture in modo che l'hotspot sia al centro del preview
	tex_rect.position = -hotspot
	
	preview.add_child(tex_rect)
	preview.size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	print("[Item] Created drag preview with size: %s, hotspot offset: %s" % [preview.size, -hotspot])
	return preview

# NUOVO: Disabilita i mouse filter degli InventorySlot durante il drag
func _disable_inventory_slots_during_drag() -> void:
	"""Disabilita temporaneamente i mouse filter degli InventorySlot"""
	var inventory_tab = _find_inventory_tab()
	if not inventory_tab:
		return
	
	var holder = inventory_tab.get_node_or_null("InvSplit/Left/Holder")
	if not holder:
		return
	
	# Imposta tutti gli InventorySlot a IGNORE durante il drag
	for child in holder.get_children():
		if child.has_method("get_script") and child.get_script():
			var script_path = str(child.get_script().resource_path)
			if "InventorySlot" in script_path:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if GameLogger.ENABLED:
					print("[Item] Disabled mouse filter for InventorySlot at %s" % child.slot_pos)

# NUOVO: Riabilita i mouse filter degli InventorySlot dopo il drag
func _enable_inventory_slots_after_drag() -> void:
	"""Riabilita i mouse filter degli InventorySlot"""
	var inventory_tab = _find_inventory_tab()
	if not inventory_tab:
		return
	
	var holder = inventory_tab.get_node_or_null("InvSplit/Left/Holder")
	if not holder:
		return
	
	# Ripristina tutti gli InventorySlot a STOP
	for child in holder.get_children():
		if child.has_method("get_script") and child.get_script():
			var script_path = str(child.get_script().resource_path)
			if "InventorySlot" in script_path:
				child.mouse_filter = Control.MOUSE_FILTER_STOP
				if GameLogger.ENABLED:
					print("[Item] Re-enabled mouse filter for InventorySlot at %s" % child.slot_pos)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# IMPORTANTE: Controlla se QUESTO item stava venendo draggato
		# La notification viene chiamata per TUTTI gli item, non solo quello draggato!
		if not _is_being_dragged:
			return

		# CRITICAL: If item is being deleted (dropped in trash), skip all logic
		if has_meta("being_deleted") and get_meta("being_deleted"):
			if GameLogger.ENABLED:
				print("[Item] Item being deleted, skipping drag end logic")
			_is_being_dragged = false
			return

		_is_being_dragged = false

		print("[Item] Drag ended for %s, parent: %s, original_parent: %s" %
			[item_id, get_parent().name if get_parent() else "null", _original_parent.name if _original_parent else "null"])

		# NUOVO: Riabilita i mouse filter degli InventorySlot
		_enable_inventory_slots_after_drag()

		# Ripristina l'opacità (sempre 1.0 = opaco)
		modulate.a = 1.0
		
		# IMPORTANTE: Ripristina il mouse filter DOPO che gli eventi di drop sono stati processati
		# Altrimenti l'item si rimette sopra gli slot prima che _drop_data() venga chiamato!
		_restore_mouse_filter.call_deferred()
		
		var current_parent = get_parent()
		
		# CASO 1: Nessun parent = drop fallito completamente
		if current_parent == null:
			print("[Item] No parent after drag - drop failed, reverting")
			_revert_to_original_position()
			return
		
		# CASO 2: Stesso parent
		if current_parent == _original_parent:
			# ItemsLayer = inventory, drop gestito da InventorySlot
			if current_parent.name == "ItemsLayer":
				print("[Item] Dropped in inventory")
				return
			# EquipmentPanel = stesso slot equipment, ok
			elif "EquipmentPanel" in current_parent.name:
				print("[Item] Dropped in same equipment panel (moved between slots)")
				return
			# Altro parent = revert
			else:
				print("[Item] Dropped in same non-valid parent, reverting")
				_revert_to_original_position()
				return
		
		# CASO 3: Nuovo parent valido = drop riuscito
		if _is_valid_drop_parent(current_parent):
			print("[Item] Drop successful in new parent: %s" % current_parent.name)
		else:
			# CASO 4: Nuovo parent non valido = errore, revert
			print("[Item] Invalid new parent: %s, reverting" % current_parent.name)
			_revert_to_original_position()

func _restore_mouse_filter() -> void:
	"""Ripristina il mouse filter dopo il drag"""
	mouse_filter = Control.MOUSE_FILTER_STOP
	# z_index rimane sempre a 10, non serve ripristinarlo
	print("[Item] Mouse filter restored for %s" % item_id)

func _is_valid_drop_parent(parent: Node) -> bool:
	"""Controlla se il parent è una destinazione valida (ItemsLayer, EquipmentPanel, EquipmentSlot o BagSlot)"""
	if parent == null:
		return false

	# ItemsLayer dell'inventario
	if parent.name == "ItemsLayer":
		return true

	# EquipmentSlot, EquipDrop o BagSlot
	if parent.get_script() != null:
		var script_path = parent.get_script().resource_path
		if "EquipmentSlot" in script_path:
			return true
		if "EquipDrop" in script_path:
			return true
		if "BagSlot" in script_path:
			return true

	# EquipmentPanel (fallback)
	if "EquipmentPanel" in parent.name:
		return true

	return false

func _revert_to_original_position() -> void:
	"""Riporta l'item alla sua posizione originale nell'inventario"""
	if _original_position == Vector2i(-1, -1):
		print("[Item] No original position saved")
		return
	
	# IMPORTANTE: Cerca l'InventoryTab nella scena, non nel parent tree
	# perché l'item potrebbe essere stato spostato nell'EquipmentPanel
	var inventory_tab = _find_inventory_tab_in_scene()
	if inventory_tab == null:
		print("[Item] Cannot find inventory tab for revert")
		return
	
	print("[Item] Reverting %s to position %s" % [item_id, _original_position])
	
	# Rimuovi dal parent corrente se necessario
	if get_parent():
		get_parent().remove_child(self)
	
	# Ri-piazza nell'inventario
	var placed = inventory_tab.place_item(self, _original_position)
	if not placed:
		print("[Item] ERROR: Could not revert to original position!")
		# Prova a trovare un posto libero
		var free_pos = inventory_tab._find_next_free_position(Vector2i(0, 0), item_size)
		if free_pos != Vector2i(-1, -1):
			inventory_tab.place_item(self, free_pos)

# ==================== UTILITY FUNCTIONS ====================

func _find_inventory_tab():
	"""Trova l'InventoryTab risalendo l'albero dei nodi (per item già nell'inventario)"""
	var current = get_parent()
	while current != null:
		if current.get_script() != null:
			var script_path = current.get_script().resource_path
			if script_path.find("InventoryTab") != -1:
				return current
		current = current.get_parent()
	return null

func _find_inventory_tab_in_scene():
	"""Cerca l'InventoryTab nella scena (per item nell'equipment)"""
	# Prima prova col metodo normale
	var inv_tab = _find_inventory_tab()
	if inv_tab != null:
		return inv_tab
	
	# Se non lo troviamo (es. item nell'equipment), cerca nella scena
	var root = get_tree().current_scene
	if root == null:
		return null
	
	# Cerca in tutti i nodi
	return _search_for_inventory_tab(root)

func _search_for_inventory_tab(node: Node):
	"""Ricerca ricorsiva dell'InventoryTab"""
	if node.get_script() != null:
		var script_path = node.get_script().resource_path
		if script_path.find("InventoryTab") != -1:
			return node
	
	for child in node.get_children():
		var result = _search_for_inventory_tab(child)
		if result != null:
			return result
	
	return null

func mark_drop_success() -> void:
	"""Chiamato dalle drop zone per indicare che il drop è riuscito"""
	print("[Item] Drop marked as successful: %s" % item_id)
	# Non serve più fare nulla qui, il sistema nativo gestisce tutto

# ==================== STACKING SYSTEM ====================

func _create_stack_label() -> void:
	"""Creates the stack count label (usa valori dall'Inspector)"""
	if stack_label != null:
		return  # Already created

	stack_label = Label.new()
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", stack_font_size)
	stack_label.add_theme_color_override("font_color", stack_font_color)
	stack_label.add_theme_color_override("font_outline_color", stack_outline_color)
	stack_label.add_theme_constant_override("outline_size", stack_outline_size)
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_label.z_index = 10

	# Position label at bottom-right
	stack_label.anchor_right = 1.0
	stack_label.anchor_bottom = 1.0
	stack_label.offset_right = stack_label_offset.x
	stack_label.offset_bottom = stack_label_offset.y

	add_child(stack_label)
	if GameLogger.ENABLED:
		print("[Item] Created stack label for %s" % item_id)

func _update_stack_label() -> void:
	"""Updates the stack label text"""
	if not is_stackable or stack_label == null:
		return

	if stack_count > 1:
		stack_label.text = str(stack_count)
		stack_label.visible = true
	else:
		stack_label.visible = false

func can_stack_with(other_item: Item) -> bool:
	"""Check if this item can stack with another item"""
	if not is_stackable or not other_item.is_stackable:
		return false

	# Must be same item ID
	if item_id != other_item.item_id:
		return false

	# Must not exceed max stack
	if stack_count + other_item.stack_count > max_stack:
		return false

	return true

func add_to_stack(amount: int) -> int:
	"""Add items to this stack. Returns how many were successfully added."""
	if not is_stackable:
		return 0

	var space_left = max_stack - stack_count
	var amount_to_add = mini(amount, space_left)

	stack_count += amount_to_add
	_update_stack_label()

	if GameLogger.ENABLED:
		print("[Item] Added %d to stack %s, new count: %d" % [amount_to_add, item_id, stack_count])

	return amount_to_add

func remove_from_stack(amount: int) -> int:
	"""Remove items from this stack. Returns how many were successfully removed."""
	if not is_stackable:
		return 0

	var amount_to_remove = mini(amount, stack_count)
	stack_count -= amount_to_remove
	_update_stack_label()

	if GameLogger.ENABLED:
		print("[Item] Removed %d from stack %s, new count: %d" % [amount_to_remove, item_id, stack_count])

	return amount_to_remove

func split_stack(amount: int) -> Item:
	"""Split this stack into two. Returns a new Item with the specified amount."""
	if not is_stackable or amount <= 0 or amount >= stack_count:
		return null

	# Create a new item with the split amount
	var new_item = duplicate() as Item
	new_item.stack_count = amount
	remove_from_stack(amount)

	if GameLogger.ENABLED:
		print("[Item] Split stack %s: %d -> %d + %d" % [item_id, stack_count + amount, stack_count, amount])

	return new_item

# ==================== SETUP ====================

func setup_item(id: String, data: Dictionary) -> void:
	"""Configura l'item con i dati forniti"""
	item_id = id

	# CRITICAL: Save complete item data (with bonuses!) as metadata
	set_meta("item_data", data)

	if data.has("size") and data.size is Array and data.size.size() >= 2:
		item_size = Vector2i(data.size[0], data.size[1])

	if data.has("icon") and data.icon != "":
		var tex = load(data.icon)
		if tex:
			texture = tex

	# Check if item is stackable
	is_stackable = data.get("stackable", false)
	max_stack = data.get("max_stack", 1)
	stack_count = 1  # Default to 1 when first created

	# Create stack label if stackable
	if is_stackable:
		_create_stack_label()
		_update_stack_label()

	# Crea il tooltip (SENZA BBCode - non supportato in tooltip_text)
	var tooltip_lines: Array[String] = []

	if data.has("name"):
		tooltip_lines.append(data["name"].to_upper())
	else:
		tooltip_lines.append(item_id.to_upper())

	if data.has("type"):
		tooltip_lines.append("Type: %s" % data["type"])

	# Support old format (attack, defense, heal)
	if data.has("attack") and data.attack > 0:
		tooltip_lines.append("Attack: +%d" % data.attack)
	if data.has("defense") and data.defense > 0:
		tooltip_lines.append("Defense: +%d" % data.defense)
	if data.has("heal") and data.heal > 0:
		tooltip_lines.append("Heal: +%d" % data.heal)

	# Support new format (stats.physical_damage, etc.)
	if data.has("stats"):
		var stats = data.stats
		if stats.has("physical_damage") and stats.physical_damage > 0:
			tooltip_lines.append("Attack: +%d" % stats.physical_damage)
		if stats.has("physical_defense") and stats.physical_defense > 0:
			tooltip_lines.append("Defense: +%d" % stats.physical_defense)
		if stats.has("max_hp") and stats.max_hp > 0:
			tooltip_lines.append("HP: +%d" % stats.max_hp)
		if stats.has("vitality") and stats.vitality > 0:
			tooltip_lines.append("Vitality: +%d" % stats.vitality)
		if stats.has("strength") and stats.strength > 0:
			tooltip_lines.append("Strength: +%d" % stats.strength)
		if stats.has("block_chance") and stats.block_chance > 0:
			tooltip_lines.append("Block: +%d%%" % stats.block_chance)

	# Bonuses
	if data.has("bonuses") and data.bonuses.size() > 0:
		tooltip_lines.append("")
		tooltip_lines.append("BONUSES:")
		for bonus in data.bonuses:
			if bonus.has("stat") and bonus.has("value"):
				tooltip_lines.append("  +%d %s" % [bonus.value, bonus.stat])
			elif bonus.has("stat"):
				tooltip_lines.append("  +%s" % bonus.stat)

	if data.has("description"):
		tooltip_lines.append("")
		tooltip_lines.append(data.description)

	tooltip_text = "\n".join(tooltip_lines)

	custom_minimum_size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	size = custom_minimum_size
