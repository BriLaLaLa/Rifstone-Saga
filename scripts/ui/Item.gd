extends TextureRect
class_name Item

const LOG := true

@export var item_id: String = "unknown"
@export var item_size: Vector2i = Vector2i(1, 1)
@export var cell_px: int = 64

var _original_parent: Node = null
var _original_position: Vector2i = Vector2i(-1, -1)
var _is_being_dragged: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	if LOG:
		print("[Item] Ready: %s at %s" % [item_id, position])

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _get_drag_data(at_position: Vector2) -> Variant:
	"""Chiamato da Godot quando inizi a draggare l'item"""
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
	# e abbassa lo z_index così gli slot possono ricevere gli eventi
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1  # Sotto gli slot
	
	# Crea il preview custom CENTRATO sull'hotspot
	var preview = _create_drag_preview(at_position)
	set_drag_preview(preview)
	
	# Rendi l'item semi-trasparente durante il drag
	modulate.a = 0.5
	
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
	
	# Crea la texture dentro il control
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	tex_rect.modulate = Color(1, 1, 1, 0.8)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Posiziona la texture in modo che l'hotspot sia al centro del preview
	tex_rect.position = -hotspot
	
	preview.add_child(tex_rect)
	preview.size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	print("[Item] Created drag preview with size: %s, hotspot offset: %s" % [preview.size, -hotspot])
	return preview

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# IMPORTANTE: Controlla se QUESTO item stava venendo draggato
		# La notification viene chiamata per TUTTI gli item, non solo quello draggato!
		if not _is_being_dragged:
			return
		
		_is_being_dragged = false
		
		print("[Item] Drag ended for %s, parent: %s, original_parent: %s" % 
			[item_id, get_parent().name if get_parent() else "null", _original_parent.name if _original_parent else "null"])
		
		# Ripristina l'opacità
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
	print("[Item] Mouse filter restored to STOP for %s" % item_id)

func _is_valid_drop_parent(parent: Node) -> bool:
	"""Controlla se il parent è una destinazione valida (ItemsLayer o EquipmentPanel)"""
	if parent == null:
		return false
	
	# ItemsLayer dell'inventario
	if parent.name == "ItemsLayer":
		return true
	
	# EquipmentPanel
	if "EquipmentPanel" in parent.name or parent.get_script() != null:
		var script_path = parent.get_script().resource_path if parent.get_script() else ""
		if "EquipDrop" in script_path:
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

# ==================== SETUP ====================

func setup_item(id: String, data: Dictionary) -> void:
	"""Configura l'item con i dati forniti"""
	item_id = id
	
	if data.has("size") and data.size is Array and data.size.size() >= 2:
		item_size = Vector2i(data.size[0], data.size[1])
	
	if data.has("icon") and data.icon != "":
		var tex = load(data.icon)
		if tex:
			texture = tex
	
	# Crea il tooltip
	var tooltip_lines: Array[String] = []
	
	if data.has("name"):
		tooltip_lines.append("[b]%s[/b]" % data["name"])
	else:
		tooltip_lines.append("[b]%s[/b]" % item_id)
	
	if data.has("type"):
		tooltip_lines.append("Type: %s" % data["type"])
	
	if data.has("attack") and data.attack > 0:
		tooltip_lines.append("Attack: +%d" % data.attack)
	if data.has("defense") and data.defense > 0:
		tooltip_lines.append("Defense: +%d" % data.defense)
	if data.has("heal") and data.heal > 0:
		tooltip_lines.append("Heal: +%d" % data.heal)
	
	if data.has("description"):
		tooltip_lines.append("")
		tooltip_lines.append("[i]%s[/i]" % data.description)
	
	tooltip_text = "\n".join(tooltip_lines)
	
	custom_minimum_size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	size = custom_minimum_size
