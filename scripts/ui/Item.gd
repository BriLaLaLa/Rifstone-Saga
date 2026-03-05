extends TextureRect
class_name Item

# Scene references
const DRAG_PREVIEW_SCENE = preload("res://scenes/ui/DragPreview.tscn")
const STACK_LABEL_SCENE = preload("res://scenes/ui/StackLabel.tscn")

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
var stack_label = null  # Display stack count (StackLabel scene)

# Enhancement support (Metin2-style)
var enhancement_level: int = 0  # 0-9, visual effects start at +7
var enhancement_particles: CPUParticles2D = null  # Falling particles effect

var _original_parent: Node = null
var _original_position: Vector2i = Vector2i(-1, -1)
var _is_being_dragged: bool = false

func _ready() -> void:
	# CRITICAL: Use PASS instead of STOP to allow drop events to reach items below
	# This allows gems to be dropped on weapons in inventory grid
	mouse_filter = Control.MOUSE_FILTER_PASS
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# CRITICAL: Clip children to prevent particles from bleeding into other items
	clip_contents = true

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

	# CRITICAL FIX: Imposta TUTTI gli altri item a IGNORE durante il drag
	# Così il mouse può passare attraverso e arrivare agli slot sottostanti per lo stacking
	print("[Item] 🔧 About to disable mouse filter on other items, inventory_tab=%s" % inventory_tab)
	if inventory_tab:
		_set_all_other_items_mouse_filter(inventory_tab, Control.MOUSE_FILTER_IGNORE)
		print("[Item] ✅ Mouse filter disabled on other items")
	else:
		print("[Item] ❌ No inventory_tab found, cannot disable other items!")

	# NON serve più disabilitare gli InventorySlot
	# Godot gestisce automaticamente gli eventi con MOUSE_FILTER_IGNORE
	# _disable_inventory_slots_during_drag()  # RIMOSSO
	
	# Crea il preview custom CENTRATO sull'hotspot
	var preview = _create_drag_preview(at_position)
	set_drag_preview(preview)

	# Rendi l'item semi-trasparente durante il drag (usa valore dall'Inspector)
	modulate.a = drag_source_opacity

	# Get item_data from metadata (includes type info for gems, weapons, etc.)
	var item_data_dict = {}
	if has_meta("item_data"):
		item_data_dict = get_meta("item_data")

	# Ritorna i dati del drag
	return {
		"type": "inventory_item",
		"item": self,
		"item_id": item_id,
		"item_size": item_size,
		"item_data": item_data_dict,  # CRITICAL: Include item_data for gem detection
		"hotspot": at_position
	}

func _create_drag_preview(hotspot: Vector2) -> Control:
	"""Crea un preview custom per il drag, centrato sull'hotspot"""
	print("[Item] 🎬 Creating drag preview - item_id: %s, size: %s, hotspot: %s" % [item_id, item_size, hotspot])

	# CONVERSION: Use DragPreview.tscn instead of creating Control.new() + TextureRect.new()
	# This replaces ~20 lines of manual node creation with scene instantiation
	var preview = DRAG_PREVIEW_SCENE.instantiate()
	print("[Item] ✅ DragPreview scene instantiated: %s" % preview)

	# Configure the preview with item properties
	# Note: setup() now handles centering internally by positioning TextureRect with negative offset
	preview.setup(texture, item_size, cell_px, hotspot, drag_preview_opacity)

	print("[Item] 🎯 Drag preview ready (centering handled by DragPreview.setup())")
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

func _set_all_other_items_mouse_filter(inventory_tab: Node, filter: int) -> void:
	"""Imposta il mouse_filter di TUTTI gli altri item (non questo) nell'inventario"""
	print("[Item] _set_all_other_items_mouse_filter called, looking for ItemsLayer...")

	# Try correct path first
	var items_layer = inventory_tab.get_node_or_null("InvSplit/Left/InventoryScroll/InventoryContainer/ItemsLayer")
	if not items_layer:
		# Fallback for battle tab inventory
		items_layer = inventory_tab.get_node_or_null("InvSplit/Left/ItemsLayer")

	if not items_layer:
		print("[Item] ❌ ItemsLayer not found!")
		return

	print("[Item] ✅ ItemsLayer found, children count: %d" % items_layer.get_child_count())
	var count = 0
	for child in items_layer.get_children():
		if child != self and child is Item:  # Escludi l'item che stai draggando
			child.mouse_filter = filter
			count += 1
			print("[Item] → Set mouse_filter=%d for item %s" % [filter, child.item_id])
	print("[Item] Total items processed: %d" % count)

func _restore_mouse_filter() -> void:
	"""Ripristina il mouse filter dopo il drag"""
	mouse_filter = Control.MOUSE_FILTER_PASS  # CRITICAL: Must be PASS to allow stacking!
	# z_index rimane sempre a 10, non serve ripristinarlo
	print("[Item] Mouse filter restored to PASS for %s" % item_id)

	# CRITICAL: Ripristina anche il mouse filter di TUTTI gli altri item
	var inventory_tab = _find_inventory_tab()
	if inventory_tab:
		_set_all_other_items_mouse_filter(inventory_tab, Control.MOUSE_FILTER_PASS)

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

	# CONVERSION: Use StackLabel.tscn instead of Label.new()
	# Replaces ~20 lines of manual Label configuration
	stack_label = STACK_LABEL_SCENE.instantiate()
	stack_label.setup(stack_font_size, stack_font_color, stack_outline_color, stack_outline_size, stack_label_offset)

	add_child(stack_label)
	if GameLogger.ENABLED:
		print("[Item] Created stack label for %s" % item_id)

# REMOVED: Old upgrade_level_label function - now using enhancement system

func _update_stack_label() -> void:
	"""Updates the stack label text"""
	if not is_stackable or stack_label == null:
		return

	# CONVERSION: Use StackLabel.update_count() instead of manual text/visible
	stack_label.update_count(stack_count)

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

	# NOTE: Upgrade level is now shown in tooltip name only (Metin2 style)
	# We don't create a visual label anymore

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


# ==================== ENHANCEMENT SYSTEM ====================

func set_enhancement_level(level: int) -> void:
	"""Set the enhancement level and apply visual effects"""
	enhancement_level = clampi(level, 0, 9)

	# Apply particle effects if level >= 7 (Metin2-style)
	_apply_enhancement_particles()

	if GameLogger.ENABLED:
		print("[Item] %s enhancement set to +%d" % [item_id, enhancement_level])


func _apply_enhancement_particles() -> void:
	"""
	Apply enhancement particle effects:
	+7: Controlled sparkles - orderly, breathing energy
	+8: Unstable energy - erratic, escaping bursts
	+9: Supernatural phenomenon - reality distortion
	"""
	# Remove existing particles first
	if enhancement_particles:
		enhancement_particles.queue_free()
		enhancement_particles = null

	# No particles for level < 7
	if enhancement_level < 7:
		return

	# Create CPUParticles2D
	enhancement_particles = CPUParticles2D.new()
	add_child(enhancement_particles)

	# Position at CENTER of item
	enhancement_particles.position = Vector2(custom_minimum_size.x / 2, custom_minimum_size.y / 2)
	enhancement_particles.z_index = 10
	enhancement_particles.emitting = true

	# Emission shape: emit from weapon body
	enhancement_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	enhancement_particles.emission_rect_extents = Vector2(custom_minimum_size.x / 3, custom_minimum_size.y / 3)

	# Configure based on enhancement level
	match enhancement_level:
		7:
			# +7: CONTROLLED SPARKLES - "polvere luminosa, ordinate, respirano"
			enhancement_particles.amount = 30
			enhancement_particles.lifetime = 2.5  # Long, calm life
			enhancement_particles.explosiveness = 0.0  # Continuous, not bursts

			# Slow orbital movement
			enhancement_particles.direction = Vector2(0, -1)  # Gently upward
			enhancement_particles.spread = 40.0  # Narrow spread, controlled
			enhancement_particles.gravity = Vector2(0, -15)  # Slow upward drift
			enhancement_particles.initial_velocity_min = 10.0  # Very slow
			enhancement_particles.initial_velocity_max = 25.0

			# Gentle orbiting effect
			enhancement_particles.angular_velocity_min = -30.0  # Slow rotation
			enhancement_particles.angular_velocity_max = 30.0
			enhancement_particles.orbit_velocity_min = 0.2  # Gentle orbit
			enhancement_particles.orbit_velocity_max = 0.5

			# Small, delicate particles
			enhancement_particles.scale_amount_min = 1.5
			enhancement_particles.scale_amount_max = 3.0

			# Golden-orange glow (educated power)
			var color_warm = Color(1.0, 0.8, 0.3, 0.9)
			var color_bright = Color(1.0, 0.95, 0.6, 0.9)
			enhancement_particles.color = color_warm

			# Smooth breathing gradient
			var gradient = Gradient.new()
			gradient.add_point(0.0, Color(color_warm.r, color_warm.g, color_warm.b, 0.0))
			gradient.add_point(0.2, color_warm)
			gradient.add_point(0.5, color_bright)  # Pulse brighter
			gradient.add_point(0.8, color_warm)
			gradient.add_point(1.0, Color(color_warm.r, color_warm.g, color_warm.b, 0.0))
			enhancement_particles.color_ramp = gradient

		8:
			# +8: UNSTABLE ENERGY - "scariche, scattano, scappano, esplodono"
			enhancement_particles.amount = 45
			enhancement_particles.lifetime = 1.2  # Shorter, erratic
			enhancement_particles.explosiveness = 0.4  # BURSTS of energy!

			# Erratic, escaping movement
			enhancement_particles.direction = Vector2(0, 0)  # Random directions
			enhancement_particles.spread = 180.0  # Full chaos
			enhancement_particles.gravity = Vector2(0, 0)  # No gravity, pure chaos
			enhancement_particles.initial_velocity_min = 50.0  # FAST escapes
			enhancement_particles.initial_velocity_max = 120.0

			# Chaotic spinning
			enhancement_particles.angular_velocity_min = -360.0  # Rapid spin
			enhancement_particles.angular_velocity_max = 360.0

			# Medium particles that "explode"
			enhancement_particles.scale_amount_min = 2.0
			enhancement_particles.scale_amount_max = 4.5

			# Electric blue-purple (dangerous energy)
			var color_electric = Color(0.2, 0.5, 1.0, 1.0)
			var color_spark = Color(0.8, 0.3, 1.0, 1.0)
			enhancement_particles.color = color_electric

			# Erratic flashing gradient
			var gradient = Gradient.new()
			gradient.add_point(0.0, color_spark)  # Bright flash
			gradient.add_point(0.2, color_electric)
			gradient.add_point(0.4, color_spark)  # Flash again
			gradient.add_point(0.7, color_electric)
			gradient.add_point(1.0, Color(color_electric.r, color_electric.g, color_electric.b, 0.0))
			enhancement_particles.color_ramp = gradient

		9:
			# +9: SUPERNATURAL PHENOMENON - "frammenti irreali, realtà disturbata"
			enhancement_particles.amount = 60
			enhancement_particles.lifetime = 3.0  # Linger in reality
			enhancement_particles.explosiveness = 0.15  # Occasional distortions

			# Reality distortion - particles suspend, deviate
			enhancement_particles.direction = Vector2(0, -1)  # Attempt upward
			enhancement_particles.spread = 60.0  # Medium spread
			enhancement_particles.gravity = Vector2(0, 0)  # Weightless, unnatural
			enhancement_particles.initial_velocity_min = 15.0  # Slow, suspended
			enhancement_particles.initial_velocity_max = 45.0

			# Strange, unnatural movement
			enhancement_particles.angular_velocity_min = -90.0
			enhancement_particles.angular_velocity_max = 90.0
			enhancement_particles.orbit_velocity_min = -0.3  # Can reverse orbit!
			enhancement_particles.orbit_velocity_max = 0.8
			enhancement_particles.radial_accel_min = -20.0  # Pull back toward weapon
			enhancement_particles.radial_accel_max = 20.0
			enhancement_particles.tangential_accel_min = -30.0  # Curve unpredictably
			enhancement_particles.tangential_accel_max = 30.0

			# Larger, ethereal fragments
			enhancement_particles.scale_amount_min = 2.5
			enhancement_particles.scale_amount_max = 6.0

			# Cyan-white ethereal glow (otherworldly)
			var color_ethereal = Color(0.6, 0.9, 1.0, 0.95)
			var color_pure = Color(0.9, 1.0, 1.0, 1.0)
			var color_void = Color(0.3, 0.7, 1.0, 0.9)
			enhancement_particles.color = color_ethereal

			# Unnatural, shifting gradient
			var gradient = Gradient.new()
			gradient.add_point(0.0, Color(color_ethereal.r, color_ethereal.g, color_ethereal.b, 0.0))
			gradient.add_point(0.15, color_pure)  # Flash into existence
			gradient.add_point(0.4, color_void)  # Shift to void
			gradient.add_point(0.6, color_pure)  # Pulse
			gradient.add_point(0.85, color_ethereal)
			gradient.add_point(1.0, Color(color_ethereal.r, color_ethereal.g, color_ethereal.b, 0.0))
			enhancement_particles.color_ramp = gradient

	if GameLogger.ENABLED:
		print("[Item] ✨ Applied enhancement effect for +%d" % enhancement_level)


func get_enhancement_level() -> int:
	"""Returns the current enhancement level"""
	return enhancement_level
