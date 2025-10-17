extends Control
class_name EquipDrop

const LOG := true

# Mapping slot names a tipi di item accettabili
var slot_compatibility := {
	"HelmetSlot": ["helmet", "hat"],
	"WeaponSlot": ["weapon", "sword", "axe", "bow", "staff"],  
	"ChestSlot": ["chest", "armor", "robe"],
	"ShieldSlot": ["shield", "offhand"],
	"BeltSlot": ["belt", "waist"],
	"BootsSlot": ["boots", "shoes"]
}

# CALIBRAZIONE DINAMICA: Trova automaticamente le posizioni corrette
var slot_rects := {}
var calibration_mode := true

# Visual feedback durante drag
var _hover_slot: String = ""
var _slot_highlights := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Usa call_deferred per aspettare che tutto sia pronto
	call_deferred("_auto_calibrate_slots")
	
	# Setup visual degli slot
	call_deferred("_setup_slot_visuals") 
	
	# Connetti ai segnali del GameState
	_connect_to_gamestate()
	
	# Refresh iniziale
	call_deferred("_refresh_equipped_items")
	
	if LOG:
		print("[EquipDrop] Ready - mouse_filter: ", mouse_filter)
		print("[EquipDrop] Slot compatibility: ", ", ".join(slot_compatibility.keys()))

func _auto_calibrate_slots() -> void:
	"""Trova automaticamente le posizioni degli slot equipment"""
	if LOG:
		print("[EquipDrop] Starting auto-calibration...")
	
	# Cerca il nodo EquipmentSlots
	var equipment_slots_node = get_node_or_null("EquipmentSlots")
	if equipment_slots_node == null:
		print("[EquipDrop] ERROR: EquipmentSlots node not found!")
		var children_names = []
		for child in get_children():
			children_names.append(child.name)
		print("[EquipDrop] Available children: ", children_names)
		# Usa coordinate di fallback
		_use_fallback_coordinates()
		return
	
	if LOG:
		print("[EquipDrop] Found EquipmentSlots node")
		var slot_children = []
		for child in equipment_slots_node.get_children():
			slot_children.append(child.name)
		print("[EquipDrop] Available slot children: ", slot_children)
	
	# Trova e calibra ogni slot
	slot_rects.clear()
	var slots_found = 0
	
	for slot_name in slot_compatibility.keys():
		var slot_node = equipment_slots_node.get_node_or_null(slot_name)
		if slot_node == null:
			print("[EquipDrop] WARNING: ", slot_name, " not found, skipping")
			continue
		
		# CORREZIONE: Calcola posizione relativa a EquipmentPanel (questo Control)
		# Somma la posizione di EquipmentSlots + la posizione dello slot
		var equipment_slots_pos = equipment_slots_node.position
		var slot_local_pos = slot_node.position
		var final_pos = equipment_slots_pos + slot_local_pos
		
		var slot_rect = Rect2(final_pos, slot_node.size)
		slot_rects[slot_name] = slot_rect
		slots_found += 1
		
		if LOG:
			print("[EquipDrop] Calibrated ", slot_name, ":")
			print("  EquipmentSlots pos: ", equipment_slots_pos)
			print("  Slot local pos: ", slot_local_pos)
			print("  Final pos: ", final_pos)
			print("  Slot size: ", slot_node.size)
	
	if slots_found == 0:
		print("[EquipDrop] No slots found! Using fallback coordinates")
		_use_fallback_coordinates()
	else:
		print("[EquipDrop] Calibration complete: ", slots_found, "/", slot_compatibility.size(), " slots found")
		calibration_mode = false

func _use_fallback_coordinates() -> void:
	"""Coordinate di fallback se la calibrazione automatica fallisce"""
	print("[EquipDrop] Using fallback coordinates")
	slot_rects = {
		"HelmetSlot": Rect2(137, 218, 64, 64),
		"WeaponSlot": Rect2(80, 230, 64, 128),
		"ChestSlot": Rect2(137, 267, 64, 128),
		"ShieldSlot": Rect2(203, 263, 64, 128),
		"BeltSlot": Rect2(108, 378, 128, 64),
		"BootsSlot": Rect2(134, 440, 64, 64)
	}
	calibration_mode = false

func _setup_slot_visuals() -> void:
	"""Configura il visual feedback degli slot equipment"""
	if LOG:
		print("[EquipDrop] Starting _setup_slot_visuals")
	
	var equipment_slots_node = get_node_or_null("EquipmentSlots")
	if equipment_slots_node == null:
		print("[EquipDrop] ERROR: EquipmentSlots node not found!")
		var children_names = []
		for child in get_children():
			children_names.append(child.name)
		print("[EquipDrop] Available children: ", children_names)
		return
	
	if LOG:
		print("[EquipDrop] Found EquipmentSlots node: ", equipment_slots_node.name)
		var children_names = []
		for child in equipment_slots_node.get_children():
			children_names.append(child.name)
		print("[EquipDrop] EquipmentSlots children: ", children_names)
	
	# IMPORTANTE: Calcola le posizioni REALI degli slot dinamicamente
	await get_tree().process_frame  # Aspetta che il layout sia aggiornato
	
	# Pulisci il dictionary prima di riempirlo
	slot_rects.clear()
	
	# CORREZIONE: Usa lo stesso calcolo di _auto_calibrate_slots
	var equipment_slots_pos = equipment_slots_node.position
	
	for slot_name in slot_compatibility.keys():
		var slot_node = equipment_slots_node.get_node_or_null(slot_name)
		if slot_node == null:
			print("[EquipDrop] WARNING: Slot node ", slot_name, " not found in EquipmentSlots!")
			continue
		
		# Calcola la posizione relativa al nostro pannello EquipmentPanel
		var slot_local_pos = slot_node.position
		var final_pos = equipment_slots_pos + slot_local_pos
		var slot_rect = Rect2(final_pos, slot_node.size)
		slot_rects[slot_name] = slot_rect
		
		if LOG:
			print("[EquipDrop] Dynamic slot ", slot_name, ": ", slot_rect)
		
		# Crea highlight panel
		var highlight = Panel.new()
		highlight.name = slot_name + "_Highlight"
		highlight.position = final_pos
		highlight.size = slot_node.size
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.visible = false
		
		# Stile highlight
		var style = StyleBoxFlat.new()
		style.bg_color = Color(1.0, 1.0, 0.2, 0.3)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 1.0, 0.0, 0.8)
		highlight.add_theme_stylebox_override("panel", style)
		
		add_child(highlight)
		_slot_highlights[slot_name] = highlight
	
	if LOG:
		print("[EquipDrop] Final slot_rects: ", slot_rects)

func _connect_to_gamestate() -> void:
	"""Connetti ai segnali del GameState per sincronizzazione"""
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			if gs.has_signal("on_item_equipped") and not gs.on_item_equipped.is_connected(_on_item_equipped_in_gamestate):
				gs.on_item_equipped.connect(_on_item_equipped_in_gamestate)
			if gs.has_signal("on_item_unequipped") and not gs.on_item_unequipped.is_connected(_on_item_unequipped_in_gamestate):
				gs.on_item_unequipped.connect(_on_item_unequipped_in_gamestate)

# ==================== SISTEMA NATIVO DI DRAG & DROP ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Verifica se un item può essere droppato negli equipment slots"""
	if LOG:
		print("[EquipDrop] _can_drop_data at position: ", at_position)
		print("[EquipDrop] Data received: ", data)
		print("[EquipDrop] My global position: ", global_position)
		print("[EquipDrop] My position: ", position)
	
	if not _is_valid_item_data(data):
		if LOG:
			print("[EquipDrop] Invalid item data")
		_clear_slot_highlights()
		return false
	
	var item: Item = data.get("item", null)
	if item == null:
		if LOG:
			print("[EquipDrop] No item in data")
		_clear_slot_highlights()
		return false
	
	# CORREZIONE: Usa at_position direttamente - dovrebbe essere già corretto
	# Il parametro at_position dovrebbe essere la posizione locale al Control
	var local_pos = at_position
	
	if LOG:
		print("[EquipDrop] Using at_position directly: ", local_pos)
	
	# Trova quale slot è sotto il mouse usando la posizione del parametro
	var target_slot = _get_slot_at_position(local_pos)
	if LOG:
		print("[EquipDrop] Found slot: '", target_slot, "'")
	
	if target_slot == "":
		if LOG:
			print("[EquipDrop] No slot found at position")
		_clear_slot_highlights()
		return false
	
	# Verifica compatibilità item-slot
	var item_type = _get_item_type(item)
	var is_compatible = _is_item_compatible_with_slot(item_type, target_slot)
	
	if LOG:
		print("[EquipDrop] Item: ", item.item_id, ", Type: ", item_type, ", Target slot: ", target_slot, ", Compatible: ", is_compatible)
	
	# Visual feedback
	_clear_slot_highlights()
	if is_compatible:
		_show_slot_highlight(target_slot, true)
		_hover_slot = target_slot
	else:
		_show_slot_highlight(target_slot, false)
		_hover_slot = ""
	
	if LOG:
		print("[EquipDrop] Can drop ", item.item_id, " (", item_type, ") on ", target_slot, ": ", is_compatible)
	
	return is_compatible

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Gestisce il drop di un item su un equipment slot"""
	if LOG:
		print("[EquipDrop] _drop_data at position: ", at_position)
	
	_clear_slot_highlights()
	
	if not _is_valid_item_data(data):
		return
	
	var item: Item = data.get("item", null)
	if item == null:
		return
	
	# CORREZIONE: Usa at_position direttamente
	var target_slot = _get_slot_at_position(at_position)
	if target_slot == "":
		return
	
	# Equipaggia l'item tramite GameState
	var success = _equip_item_to_slot(item, target_slot)
	
	if success:
		# Marca il drop come riuscito
		if item.has_method("mark_drop_success"):
			item.mark_drop_success()
		
		if LOG:
			print("[EquipDrop] Successfully equipped ", item.item_id, " to ", target_slot)
	else:
		if LOG:
			print("[EquipDrop] Failed to equip ", item.item_id, " to ", target_slot)

# ==================== EQUIPMENT LOGIC ====================

func _equip_item_to_slot(item: Item, slot_name: String) -> bool:
	"""Equipaggia un item in uno slot specifico tramite GameState"""
	if not Engine.has_singleton("GameState"):
		print("[EquipDrop] GameState not found!")
		return false
	
	var gs = Engine.get_singleton("GameState")
	
	# Mappa nome slot UI a slot GameState
	var gamestate_slot = _ui_slot_to_gamestate_slot(slot_name)
	if gamestate_slot == "":
		print("[EquipDrop] Invalid slot mapping: ", slot_name)
		return false
	
	# Equipaggia tramite GameState
	var success = gs.equip_item_to_slot(item.item_id, gamestate_slot)
	
	if success:
		# Rimuovi item dalla sua posizione originale nell'inventario
		var inventory_tab = _find_inventory_tab()
		if inventory_tab:
			inventory_tab._remove_item_if_exists(item)
		
		# L'item verrà ricreato in _refresh_equipped_items()
		item.queue_free()
	
	return success

func _unequip_item_from_slot(slot_name: String) -> bool:
	"""Rimuove un item da uno slot equipment"""
	if not Engine.has_singleton("GameState"):
		return false
	
	var gs = Engine.get_singleton("GameState")
	var gamestate_slot = _ui_slot_to_gamestate_slot(slot_name)
	
	if gamestate_slot != "":
		return gs.unequip_item_from_slot(gamestate_slot)
	
	return false

func _ui_slot_to_gamestate_slot(ui_slot: String) -> String:
	"""Mappa i nomi degli slot UI ai nomi dei slot GameState"""
	match ui_slot:
		"HelmetSlot": return "helmet"
		"WeaponSlot": return "weapon"
		"ChestSlot": return "chest"
		"ShieldSlot": return "shield"
		"BeltSlot": return "belt"
		"BootsSlot": return "boots"
		_: return ""

# ==================== ITEM TYPE DETECTION ====================

func _get_item_type(item: Item) -> String:
	"""Determina il tipo di un item dai suoi dati"""
	if not Engine.has_singleton("GameState"):
		return "unknown"
	
	var gs = Engine.get_singleton("GameState")
	if gs and gs.has("data") and gs.data.has("items"):
		var item_data = gs.data.items.get(item.item_id, {})
		return item_data.get("slot", "unknown")  # Usa 'slot' invece di 'type'
	
	return "unknown"

func _is_item_compatible_with_slot(item_type: String, slot_name: String) -> bool:
	"""Verifica se un tipo di item può essere equipaggiato in uno slot"""
	if not slot_compatibility.has(slot_name):
		return false
	
	var compatible_types = slot_compatibility[slot_name]
	return item_type in compatible_types

# ==================== POSITION DETECTION ====================

func _get_slot_at_position(local_pos: Vector2) -> String:
	"""Trova quale slot si trova alla posizione locale specificata"""
	if LOG:
		print("[EquipDrop] Checking position ", local_pos, " against slots:")
		print("[EquipDrop] This control size: ", size)
		print("[EquipDrop] This control position: ", position)
	
	for slot_name in slot_rects.keys():
		var rect = slot_rects[slot_name]
		var contains = rect.has_point(local_pos)
		if LOG:
			print("[EquipDrop]   ", slot_name, ": ", rect)
			print("[EquipDrop]     Position range: X(", rect.position.x, " to ", rect.position.x + rect.size.x, "), Y(", rect.position.y, " to ", rect.position.y + rect.size.y, ")")
			print("[EquipDrop]     Contains ", local_pos, ": ", contains)
		if contains:
			if LOG:
				print("[EquipDrop] ✅ Found slot: ", slot_name)
			return slot_name
	
	if LOG:
		print("[EquipDrop] ❌ No slot found")
	return ""

# ==================== VISUAL FEEDBACK ====================

func _show_slot_highlight(slot_name: String, is_valid: bool) -> void:
	"""Mostra l'highlight per uno slot durante il drag"""
	if _slot_highlights.has(slot_name):
		var highlight = _slot_highlights[slot_name]
		highlight.visible = true
		
		# Cambia colore in base alla validità
		var style = highlight.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			if is_valid:
				style.bg_color = Color(0.2, 1.0, 0.2, 0.3)
				style.border_color = Color(0.0, 1.0, 0.0, 0.8)
			else:
				style.bg_color = Color(1.0, 0.2, 0.2, 0.3)
				style.border_color = Color(1.0, 0.0, 0.0, 0.8)

func _clear_slot_highlights() -> void:
	"""Nasconde tutti gli highlight degli slot"""
	for highlight in _slot_highlights.values():
		highlight.visible = false
	_hover_slot = ""

# ==================== REFRESH EQUIPMENT ====================

func _refresh_equipped_items() -> void:
	"""Aggiorna la visualizzazione degli item equipaggiati"""
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if not gs:
		return
	
	# Rimuovi tutti gli item equipaggiati visuali esistenti
	_clear_equipped_visuals()
	
	# Ricrea gli item equipaggiati
	for gamestate_slot in gs.equipped_items.keys():
		var item_data = gs.equipped_items[gamestate_slot]
		if item_data != null:
			_create_equipped_item_visual(gamestate_slot, item_data)

func _clear_equipped_visuals() -> void:
	"""Rimuove tutti gli item equipaggiati visuali"""
	for child in get_children():
		if child is Item:
			child.queue_free()

func _create_equipped_item_visual(gamestate_slot: String, item_data: Dictionary) -> void:
	"""Crea la rappresentazione visuale di un item equipaggiato"""
	var ui_slot = _gamestate_slot_to_ui_slot(gamestate_slot)
	if ui_slot == "" or not slot_rects.has(ui_slot):
		return
	
	# Crea l'item visual
	var item_scene_path = "res://scripts/ui/Item.tscn"
	var item_scene = load(item_scene_path)
	if item_scene == null:
		return
	
	var item: Item = item_scene.instantiate()
	item.item_id = item_data.get("id", "unknown")
	item.setup_item(item.item_id, item_data)
	
	# Posiziona nell'equipment slot
	var slot_rect = slot_rects[ui_slot]
	item.position = slot_rect.position + Vector2(4, 4)  # Piccolo offset per centrarlo meglio
	item.size = slot_rect.size - Vector2(8, 8)
	item.z_index = 5
	
	add_child(item)
	
	if LOG:
		print("[EquipDrop] Created visual for equipped item: ", item.item_id, " in slot ", ui_slot)

func _gamestate_slot_to_ui_slot(gamestate_slot: String) -> String:
	"""Mappa i nomi degli slot GameState ai nomi degli slot UI"""
	match gamestate_slot:
		"helmet": return "HelmetSlot"
		"weapon": return "WeaponSlot"
		"chest": return "ChestSlot"
		"shield": return "ShieldSlot"
		"belt": return "BeltSlot"
		"boots": return "BootsSlot"
		_: return ""

# ==================== GAMESTATE CALLBACKS ====================

func _on_item_equipped_in_gamestate(slot: String, item_data: Dictionary) -> void:
	"""Callback quando un item viene equipaggiato nel GameState"""
	if LOG:
		print("[EquipDrop] Item equipped in GameState: ", item_data.get("name", "Unknown"), " -> ", slot)
	_refresh_equipped_items()

func _on_item_unequipped_in_gamestate(slot: String, item_data: Dictionary) -> void:
	"""Callback quando un item viene de-equipaggiato nel GameState"""
	if LOG:
		print("[EquipDrop] Item unequipped from GameState: ", item_data.get("name", "Unknown"), " <- ", slot)
	_refresh_equipped_items()

# ==================== UTILITY FUNCTIONS ====================

func _is_valid_item_data(data: Variant) -> bool:
	"""Verifica che i dati del drag siano validi"""
	if typeof(data) != TYPE_DICTIONARY:
		return false
	
	var dict: Dictionary = data
	return dict.has("type") and dict["type"] == "inventory_item" and dict.has("item")

func _find_inventory_tab():
	"""Trova l'InventoryTab nella scena"""
	var current = self
	while current != null:
		if current.get_script() != null and "InventoryTab" in str(current.get_script().resource_path):
			return current
		current = current.get_parent()
	return null

# ==================== DRAG END CLEANUP ====================

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_slot_highlights()
