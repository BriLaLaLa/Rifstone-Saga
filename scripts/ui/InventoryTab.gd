extends Control
class_name InventoryTab

const LOG := true

@export var cols: int = 6  # Fixed to 6 for bag system compatibility
@export var rows: int = 5
@export var cell_px: int = 64

@export var item_scene: PackedScene
@export var slot_scene: PackedScene

@onready var holder: GridContainer = $"InvSplit/Left/InventoryScroll/InventoryContainer/Holder"
@onready var items_layer: Control = $"InvSplit/Left/InventoryScroll/InventoryContainer/ItemsLayer"
@onready var inventory_container: Control = $"InvSplit/Left/InventoryScroll/InventoryContainer"
@onready var bag_section: VBoxContainer = $"InvSplit/Left/BagSection"

const DEFAULT_SLOT_SCENE_PATH := "res://scripts/ui/InventorySlot.tscn"
const DEFAULT_ITEM_SCENE_PATH := "res://scripts/ui/Item.tscn"

# Griglia logica dell'inventario: true = occupato, false = libero
var grid_occupied: Array[Array] = []

# Mappa per trovare rapidamente gli items per posizione
var items_at_position: Dictionary = {} # Vector2i -> Item

# Riferimenti agli slot UI
var slots: Array[InventorySlot] = []

# ==================== BAG SYSTEM ====================
const MAX_BAG_SLOTS := 5
const STARTER_BAG_SLOTS := 20
const BAG_SLOT_HEIGHT := 70

var bag_slots: Array = []  # Array of BagSlot nodes
var bag_equipped_slots: Array[int] = []  # Slots provided by each equipped bag
var total_inventory_slots: int = 0
var trash_bin: TrashBin = null

func _ready() -> void:
	_initialize_grid()
	_create_bag_slots()
	_create_trash_bin()
	_create_slots()
	_connect_to_gamestate()
	_setup_starter_bag()
	_refresh_from_gamestate()

func _initialize_grid(clear_items: bool = true) -> void:
	grid_occupied.clear()
	for y in range(rows):
		var row: Array[bool] = []
		for x in range(cols):
			row.append(false)
		grid_occupied.append(row)

	# Only clear items if explicitly requested (e.g., during initial setup)
	# When resizing grid (bag equip/unequip), we want to preserve existing items
	if clear_items:
		items_at_position.clear()
	# If not clearing items, grid_occupied will be rebuilt as items are accessed

	if LOG:
		print("[InventoryTab] Grid initialized: %dx%d" % [cols, rows])

func _create_slots() -> void:
	if holder == null:
		push_error("[InventoryTab] Holder not found!")
		return

	# Configura il GridContainer
	holder.columns = cols

	# CRITICAL: Update container size for scrollbar to appear
	# Each slot is cell_px tall, plus spacing
	var total_height = rows * (cell_px + 4)  # 4px spacing between slots
	if inventory_container:
		inventory_container.custom_minimum_size = Vector2(512, total_height)
		holder.custom_minimum_size = Vector2(512, total_height)
		items_layer.custom_minimum_size = Vector2(512, total_height)

	# Pulisci slot esistenti
	for child in holder.get_children():
		child.queue_free()
	slots.clear()
	
	# Crea nuovi slot
	var slot_scene_to_use: PackedScene = slot_scene
	if slot_scene_to_use == null:
		slot_scene_to_use = load(DEFAULT_SLOT_SCENE_PATH)
	
	for y in range(rows):
		for x in range(cols):
			var slot: InventorySlot
			if slot_scene_to_use != null:
				slot = slot_scene_to_use.instantiate()
			else:
				# Fallback: crea slot base
				slot = InventorySlot.new()
			
			slot.slot_pos = Vector2i(x, y)
			slot.inventory_tab = self
			slot.custom_minimum_size = Vector2(cell_px, cell_px)
			
			holder.add_child(slot)
			slots.append(slot)
	
	if LOG:
		print("[InventoryTab] Created %d slots" % slots.size())

func _connect_to_gamestate() -> void:
	var gs = _get_gamestate()
	if gs and gs.has_signal("on_inventory_changed"):
		if not gs.on_inventory_changed.is_connected(_on_gamestate_inventory_changed):
			gs.on_inventory_changed.connect(_on_gamestate_inventory_changed)

func _on_gamestate_inventory_changed() -> void:
	_refresh_from_gamestate()

func _refresh_from_gamestate() -> void:
	# Pulisci inventario visuale
	_clear_all_items()

	var gs = _get_gamestate()
	if not gs or not "inventory" in gs:
		return

	var inventory: Dictionary = gs.inventory

	# CRITICAL: Rimuovi solo la starter bag dall'inventario - non dovrebbe mai essere lì!
	# La starter bag è unica e locked nello slot 0
	var bags_to_remove = ["starter_bag"]
	for bag_id in bags_to_remove:
		if inventory.has(bag_id):
			print("[InventoryTab] CLEANUP: Removing %s from inventory (bags should only be in bag slots!)" % bag_id)
			inventory.erase(bag_id)

	# Posiziona gli items nell'inventario
	# Per ora, posizionamento automatico sequenziale
	var current_pos := Vector2i(0, 0)

	for item_id in inventory.keys():
		var quantity: int = inventory[item_id]
		var item_data = _get_item_data(item_id)
		
		# Per ogni quantità, crea un item separato (puoi modificare per stack)
		for i in range(quantity):
			var item = _create_item_visual(item_id, item_data)
			if item == null:
				continue
			
			# Trova prossima posizione libera
			var pos = _find_next_free_position(current_pos, item.item_size)
			if pos == Vector2i(-1, -1):
				if LOG:
					print("[InventoryTab] No space for item: %s" % item_id)
				item.queue_free()
				continue
			
			# Posiziona l'item
			if _place_item_internal(item, pos):
				current_pos = Vector2i(pos.x + item.item_size.x, pos.y)
				if current_pos.x >= cols:
					current_pos.x = 0
					current_pos.y += 1

func _clear_all_items() -> void:
	# Rimuovi tutti gli items visuali
	for item in items_at_position.values():
		if is_instance_valid(item):
			item.queue_free()
	
	items_at_position.clear()
	_initialize_grid()
	
	# Pulisci anche i lock degli slot
	for slot in slots:
		slot.clear()

func _get_item_data(item_id: String) -> Dictionary:
	var gs = _get_gamestate()
	if gs and "data" in gs and "items" in gs.data:
		return gs.data.items.get(item_id, {})
	return {}

func _create_item_visual(item_id: String, item_data: Dictionary) -> Item:
	var item_scene_to_use: PackedScene = item_scene
	if item_scene_to_use == null:
		item_scene_to_use = load(DEFAULT_ITEM_SCENE_PATH)
	
	var item: Item
	if item_scene_to_use != null:
		item = item_scene_to_use.instantiate()
	else:
		# Fallback: crea item base
		item = Item.new()
	
	# Configura l'item
	item.item_id = item_id
	item.cell_px = cell_px
	
	# Imposta dimensioni (default 1x1 se non specificato)
	if item_data.has("size"):
		var size_array = item_data.size
		if size_array is Array and size_array.size() >= 2:
			item.item_size = Vector2i(size_array[0], size_array[1])
	
	# Imposta texture se disponibile (usa 'icon' invece di 'texture')
	if item_data.has("icon") and item_data.icon != "":
		var texture = load(item_data.icon)
		if texture:
			item.texture = texture
	
	# IMPORTANTE: Chiama setup_item per configurare il tooltip
	print("[InventoryTab] Calling setup_item with data: %s" % item_data)
	item.setup_item(item_id, item_data)
	print("[InventoryTab] After setup_item, tooltip: '%s'" % item.tooltip_text)
	
	return item

func _find_next_free_position(start_pos: Vector2i, item_size: Vector2i) -> Vector2i:
	# Cerca dalla posizione start_pos in poi
	for y in range(start_pos.y, rows):
		var start_x = 0 if y > start_pos.y else start_pos.x
		for x in range(start_x, cols):
			if _can_place_at(Vector2i(x, y), item_size):
				return Vector2i(x, y)
	
	# Se non trovato dopo start_pos, cerca dall'inizio
	for y in range(0, start_pos.y + 1):
		var end_x = cols if y < start_pos.y else start_pos.x
		for x in range(0, end_x):
			if _can_place_at(Vector2i(x, y), item_size):
				return Vector2i(x, y)
	
	return Vector2i(-1, -1) # Nessuna posizione libera

func _can_place_at(pos: Vector2i, item_size_param: Vector2i) -> bool:
	# Controlla bounds
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + item_size_param.x > cols or pos.y + item_size_param.y > rows:
		return false
	
	# Controlla occupazione
	for y in range(pos.y, pos.y + item_size_param.y):
		for x in range(pos.x, pos.x + item_size_param.x):
			if grid_occupied[y][x]:
				return false
	
	return true

func _place_item_internal(item: Item, pos: Vector2i) -> bool:
	if not _can_place_at(pos, item.item_size):
		return false
	
	# Marca celle come occupate
	for y in range(pos.y, pos.y + item.item_size.y):
		for x in range(pos.x, pos.x + item.item_size.x):
			grid_occupied[y][x] = true
	
	# Aggiungi alla mappa posizioni
	items_at_position[pos] = item
	
	# FIX: Aggiungi l'item al ItemsLayer
	if items_layer == null:
		print("[InventoryTab] ERROR: ItemsLayer is null!")
		return false

	# CRITICAL: Rimuovi l'item dal parent corrente PRIMA di aggiungerlo a ItemsLayer
	# Questo è necessario quando l'item proviene da un BagSlot o altro parent
	if item.get_parent():
		print("[InventoryTab] Removing item %s from current parent: %s" % [item.item_id, item.get_parent().name])
		item.get_parent().remove_child(item)

	items_layer.add_child(item)
	
	# FIX: Posiziona l'item usando call_deferred per evitare problemi di timing
	_position_item_deferred.call_deferred(item, pos)
	
	# Lock degli slot occupati
	for y in range(pos.y, pos.y + item.item_size.y):
		for x in range(pos.x, pos.x + item.item_size.x):
			var idx = y * cols + x
			if idx < slots.size():
				slots[idx].lock_to(item)
	
	if LOG:
		print("[InventoryTab] Placed item %s at %s (size %s)" % [item.item_id, pos, item.item_size])
	
	return true

func _position_item_deferred(item: Item, pos: Vector2i) -> void:
	# Attendi che il layout sia aggiornato
	await get_tree().process_frame
	
	# FIX CRITICO: Calcola la posizione usando le coordinate LOCALI dello slot rispetto al holder
	var slot_index = pos.y * cols + pos.x
	if slot_index >= slots.size():
		print("[InventoryTab] ERROR: Invalid slot index %d" % slot_index)
		return
	
	var slot = slots[slot_index]
	
	# DEBUG: Confronta posizione calcolata vs posizione reale dello slot
	var calculated_pos = Vector2(pos.x * cell_px, pos.y * cell_px)
	var slot_actual_pos = slot.position
	var slot_global = slot.global_position
	var holder_global = holder.global_position
	
	print("[InventoryTab] === POSITIONING DEBUG DETAILED ===")
	print("  Item: %s at logical pos: %s" % [item.item_id, pos])
	print("  Slot index: %d" % slot_index)
	print("  Calculated pos (based on grid): %s" % calculated_pos)
	print("  Slot actual position: %s" % slot_actual_pos)
	print("  Slot global position: %s" % slot_global)
	print("  Holder global position: %s" % holder_global)
	print("  Slot position relative to holder: %s" % (slot_global - holder_global))
	
	# USA LA POSIZIONE REALE DELLO SLOT invece del calcolo
	var item_pos = slot.position
	
	item.position = item_pos
	item.size = Vector2(item.item_size.x * cell_px, item.item_size.y * cell_px)
	item.z_index = 10  # Sopra gli slot
	
	print("  Final item position: %s" % item.position)
	print("  Final item size: %s" % item.size)
	print("=== END POSITIONING DEBUG ===")

# ==================== METODI CHIAMATI DA InventorySlot ====================

func compute_top_left_from_hotspot(slot: InventorySlot, item: Item, hotspot: Vector2) -> Vector2i:
	if slot == null or item == null:
		return Vector2i(-1, -1)
	
	# Calcola l'offset dal hotspot alla cella top-left dell'item
	var hotspot_cell := Vector2i(
		int(hotspot.x / cell_px),
		int(hotspot.y / cell_px)
	)
	
	# La posizione top-left è la posizione dello slot meno l'offset del hotspot
	var tl := slot.slot_pos - hotspot_cell
	
	# Clamp ai bounds della griglia
	tl.x = clampi(tl.x, 0, cols - item.item_size.x)
	tl.y = clampi(tl.y, 0, rows - item.item_size.y)
	
	return tl

func validate_item_placement(item: Item, pos: Vector2i) -> bool:
	if item == null:
		return false
	
	# Rimuovi temporaneamente l'item se già posizionato
	var was_placed = _remove_item_if_exists(item)
	var result = _can_place_at(pos, item.item_size)
	
	# Se era già posizionato, rimettilo
	if was_placed.has("pos"):
		_place_item_internal(item, was_placed.pos)
	
	return result

# ==================== NUOVI METODI PER IL FIX DEL DRAG & DROP ====================

func get_item_position(item: Item) -> Vector2i:
	"""Trova la posizione di un item nell'inventario"""
	for pos in items_at_position.keys():
		if items_at_position[pos] == item:
			return pos
	return Vector2i(-1, -1)  # Item non trovato

func get_item_at(pos: Vector2i) -> Item:
	"""Restituisce l'item alla posizione specificata, o null se vuota"""
	return items_at_position.get(pos, null)

func place_item(item: Item, pos: Vector2i) -> bool:
	if item == null:
		return false
	
	# IMPORTANTE: Non rimuovere l'item se stiamo cercando di metterlo nella stessa posizione
	var current_pos = get_item_position(item)
	if current_pos == pos:
		print("[InventoryTab] Item %s already at position %s, no move needed" % [item.item_id, pos])
		return true
	
	# Rimuovi l'item dalla posizione precedente
	var previous_data = _remove_item_if_exists(item)
	
	# Prova a piazzarlo nella nuova posizione
	if _place_item_internal(item, pos):
		_sync_to_gamestate()
		return true
	else:
		# Se fallisce e aveva una posizione precedente valida, prova a rimetterlo lì
		if previous_data.has("pos"):
			print("[InventoryTab] Placement failed, attempting to restore to %s" % previous_data.pos)
			if _place_item_internal(item, previous_data.pos):
				print("[InventoryTab] Successfully restored item to original position")
				_sync_to_gamestate()  # Sincronizza anche il ripristino
				return false  # Return false perché il placement richiesto è fallito
			else:
				print("[InventoryTab] CRITICAL: Could not restore item to original position!")
		return false

func _remove_item_if_exists(item: Item) -> Dictionary:
	# Trova l'item nella mappa posizioni
	for pos in items_at_position.keys():
		if items_at_position[pos] == item:
			# Libera le celle
			for y in range(pos.y, pos.y + item.item_size.y):
				for x in range(pos.x, pos.x + item.item_size.x):
					if y < grid_occupied.size() and x < grid_occupied[y].size():
						grid_occupied[y][x] = false
			
			# Sblocca gli slot
			for y in range(pos.y, pos.y + item.item_size.y):
				for x in range(pos.x, pos.x + item.item_size.x):
					var idx = y * cols + x
					if idx < slots.size():
						slots[idx].clear()
			
			# Rimuovi dalla mappa
			items_at_position.erase(pos)
			
			# Rimuovi dal parent se necessario
			if item.get_parent():
				item.get_parent().remove_child(item)
			
			return {"pos": pos}
	
	return {}

func _sync_to_gamestate() -> void:
	# Conta gli items per tipo
	var inventory_count: Dictionary = {}
	
	for item in items_at_position.values():
		if is_instance_valid(item):
			var id = item.item_id
			inventory_count[id] = inventory_count.get(id, 0) + 1
	
	# Sincronizza con GameState
	var gs = _get_gamestate()
	if gs:
		gs.set("inventory", inventory_count)
		# Non emettere il segnale per evitare loop infiniti

# ==================== METODI PUBBLICI PER AGGIUNGERE ITEMS ====================

func add_item_from_data(item_id: String, item_data: Dictionary) -> bool:
	"""Aggiunge un item all'inventario usando i dati forniti"""
	if LOG:
		print("[InventoryTab] Adding item: %s" % item_id)
	
	# Crea l'item visuale
	var item = _create_item_visual(item_id, item_data)
	if item == null:
		if LOG:
			print("[InventoryTab] Failed to create item: %s" % item_id)
		return false
	
	# Trova una posizione libera
	var pos = _find_next_free_position(Vector2i(0, 0), item.item_size)
	if pos == Vector2i(-1, -1):
		if LOG:
			print("[InventoryTab] No space for item: %s" % item_id)
		item.queue_free()
		return false
	
	# Piazza l'item
	if _place_item_internal(item, pos):
		_sync_to_gamestate()
		if LOG:
			print("[InventoryTab] Successfully added item: %s at %s" % [item_id, pos])
		return true
	else:
		item.queue_free()
		return false

func add_item_by_id(item_id: String) -> bool:
	"""Aggiunge un item usando solo l'ID (cerca i dati in GameState)"""
	var item_data = _get_item_data(item_id)
	if item_data.is_empty():
		if LOG:
			print("[InventoryTab] No data found for item: %s" % item_id)
		return false
	
	return add_item_from_data(item_id, item_data)

func remove_item_by_id(item_id: String, quantity: int = 1) -> int:
	"""Rimuove gli item specificati dall'inventario. Restituisce quanti ne ha rimossi."""
	var removed = 0
	var items_to_remove: Array[Item] = []
	
	# Trova gli items da rimuovere
	for item in items_at_position.values():
		if is_instance_valid(item) and item.item_id == item_id:
			items_to_remove.append(item)
			removed += 1
			if removed >= quantity:
				break
	
	# Rimuovi gli items trovati
	for item in items_to_remove:
		_remove_item_if_exists(item)
		item.queue_free()
	
	if removed > 0:
		_sync_to_gamestate()
		if LOG:
			print("[InventoryTab] Removed %d x %s" % [removed, item_id])
	
	return removed

func get_item_count(item_id: String) -> int:
	"""Conta quanti item di un tipo sono nell'inventario"""
	var count = 0
	for item in items_at_position.values():
		if is_instance_valid(item) and item.item_id == item_id:
			count += 1
	return count

func has_space_for_item(item_id: String) -> bool:
	"""Controlla se c'è spazio per un item"""
	var item_data = _get_item_data(item_id)
	if item_data.is_empty():
		return false
	
	var item_size_param = Vector2i(1, 1)
	if item_data.has("size") and item_data.size is Array and item_data.size.size() >= 2:
		item_size_param = Vector2i(item_data.size[0], item_data.size[1])
	
	return _find_next_free_position(Vector2i(0, 0), item_size_param) != Vector2i(-1, -1)

# ==================== HIGHLIGHT OVERLAY ====================

var __hl_path: NodePath = NodePath("InvSplit/Left/HighlightLayer")

func __hl() -> HighlightLayer:
	var n: Node = get_node_or_null(__hl_path)
	return n as HighlightLayer

func render_highlight_preview(item: Item, tl: Vector2i, is_ok: bool) -> void:
	var hl: HighlightLayer = __hl()
	if hl == null:
		return

	var rects: Array[Rect2] = []
	for y in range(tl.y, tl.y + item.item_size.y):
		for x in range(tl.x, tl.x + item.item_size.x):
			if x >= 0 and y >= 0 and x < cols and y < rows:
				var r: Rect2 = __cell_rect_for_highlight(Vector2i(x, y))
				if r.size.x > 0.0 and r.size.y > 0.0:
					rects.append(r)

	hl.show_preview_rects(rects, is_ok)

func clear_highlight() -> void:
	var hl: HighlightLayer = __hl()
	if hl != null:
		hl.clear_preview()

func __cell_rect_for_highlight(cell: Vector2i) -> Rect2:
	if holder == null:
		return Rect2()
	var idx: int = cell.y * cols + cell.x
	if idx < 0 or idx >= holder.get_child_count():
		return Rect2()
	var node: Node = holder.get_child(idx)
	var ctrl: Control = node as Control
	if ctrl == null:
		return Rect2()
	var hl: HighlightLayer = __hl()
	if hl == null:
		return Rect2()
	var local_pos: Vector2 = ctrl.global_position - hl.global_position
	return Rect2(local_pos, ctrl.size)

# ==================== BAG SYSTEM METHODS ====================

func _create_bag_slots() -> void:
	"""Crea i 5 slot per le bag nella BagSection"""
	if bag_section == null:
		push_error("[InventoryTab] BagSection not found!")
		return

	# Pulisci eventuali bag slots esistenti
	for child in bag_section.get_children():
		child.queue_free()
	bag_slots.clear()
	bag_equipped_slots.clear()
	bag_equipped_slots.resize(MAX_BAG_SLOTS)
	for i in range(MAX_BAG_SLOTS):
		bag_equipped_slots[i] = 0

	# Crea container orizzontale per i bag slots
	var bag_container = HBoxContainer.new()
	bag_container.name = "BagContainer"
	bag_container.custom_minimum_size = Vector2(512, BAG_SLOT_HEIGHT)
	bag_section.add_child(bag_container)

	# Aggiungi label
	var label = Label.new()
	label.text = "BAGS:"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(60, BAG_SLOT_HEIGHT)
	bag_container.add_child(label)

	# Crea i 5 bag slots
	for i in range(MAX_BAG_SLOTS):
		var bag_slot = BagSlot.new()
		bag_slot.name = "BagSlot%d" % i
		bag_slot.slot_index = i
		bag_slot.is_locked = (i == 0)  # Prima bag è locked (starter bag)
		bag_slot.custom_minimum_size = Vector2(64, 64)
		bag_slot.inventory_tab = self

		# Connetti i segnali
		bag_slot.bag_equipped.connect(_on_bag_equipped)
		bag_slot.bag_removed.connect(_on_bag_removed)

		bag_container.add_child(bag_slot)
		bag_slots.append(bag_slot)

	if LOG:
		print("[InventoryTab] Created %d bag slots" % bag_slots.size())

func _create_trash_bin() -> void:
	"""Crea il cestino per eliminare items"""
	if bag_section == null:
		push_error("[InventoryTab] BagSection not found!")
		return

	# Crea il trash bin
	trash_bin = TrashBin.new()
	trash_bin.name = "TrashBin"
	trash_bin.custom_minimum_size = Vector2(512, 60)
	bag_section.add_child(trash_bin)

	if LOG:
		print("[InventoryTab] Created trash bin")

func _on_bag_equipped(slot_index: int, bag_slots_count: int) -> void:
	"""Chiamato quando una bag viene equipaggiata"""
	if LOG:
		print("[InventoryTab] Bag equipped in slot %d, adding %d slots" % [slot_index, bag_slots_count])

	# CRITICAL: Memorizza quanti slot fornisce questa bag
	if slot_index >= 0 and slot_index < bag_equipped_slots.size():
		bag_equipped_slots[slot_index] = bag_slots_count

	# Aggiungi gli slot della bag al totale
	total_inventory_slots += bag_slots_count
	_recalculate_inventory_size()

	# Salva in GameState
	_sync_equipped_bags_to_gamestate()

func _on_bag_removed(slot_index: int) -> void:
	"""Chiamato quando una bag viene rimossa"""
	print("[InventoryTab] === _on_bag_removed() called for slot %d ===" % slot_index)
	print("  Current state: total_slots=%d, rows=%d" % [total_inventory_slots, rows])

	# CRITICAL: Azzera gli slot di questa bag nell'array
	if slot_index >= 0 and slot_index < bag_equipped_slots.size():
		bag_equipped_slots[slot_index] = 0

	# CRITICAL: Redistribuisci item PRIMA di ridurre la griglia
	# Calculate new size first
	_recalculate_total_slots()
	var new_rows = ceili(float(total_inventory_slots) / float(cols))
	print("  After recalc: total_slots=%d, new_rows=%d" % [total_inventory_slots, new_rows])

	# Redistribute items that would be outside new bounds
	print("  Calling redistribute_items_after_bag_removal()...")
	var redistribution_success = redistribute_items_after_bag_removal(new_rows)
	print("  Redistribution result: %s" % ("SUCCESS" if redistribution_success else "FAILED"))

	# Now resize the grid
	print("  Calling _recalculate_inventory_size()...")
	_recalculate_inventory_size()
	print("  After resize: rows=%d, grid_occupied size=%dx%d" % [rows, grid_occupied[0].size() if grid_occupied.size() > 0 else 0, grid_occupied.size()])

	# CRITICAL: Rebuild grid_occupied after resize
	# _initialize_grid() clears grid_occupied, so we need to rebuild it based on actual item positions
	print("  Rebuilding grid_occupied after resize...")
	_rebuild_grid_occupied()
	print("  Grid occupancy rebuilt")

	# CRITICAL: Re-place all items to update their visual positions correctly
	# We need to call place_item() again for each item to position them with the new slot layout
	print("  Re-placing all items to update visual positions...")
	var items_to_reposition = []
	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		if is_instance_valid(item):
			items_to_reposition.append({"item": item, "pos": pos})

	# Re-place each item
	for entry in items_to_reposition:
		var item: Item = entry["item"]
		var pos: Vector2i = entry["pos"]
		place_item(item, pos)
		print("    Re-placed %s at (%d, %d)" % [item.item_id, pos.x, pos.y])
	print("  Visual positions updated")

	# Salva in GameState
	_sync_equipped_bags_to_gamestate()

	print("[InventoryTab] === _on_bag_removed() COMPLETE ===")

func _setup_starter_bag() -> void:
	"""Setup della starter bag (20 slots) nella prima bag slot"""
	if bag_slots.is_empty():
		push_error("[InventoryTab] No bag slots available!")
		return

	# Controlla se già esiste una starter bag in GameState
	var gs = _get_gamestate()
	if gs and "equipped_bags" in gs and not gs.equipped_bags.is_empty():
		# Carica le bag salvate
		_load_equipped_bags_from_gamestate()
		return

	# Crea la starter bag programmaticamente
	var starter_bag_slot: BagSlot = bag_slots[0]

	# Crea l'item della starter bag
	var item_scene_to_use: PackedScene = item_scene
	if item_scene_to_use == null:
		item_scene_to_use = load(DEFAULT_ITEM_SCENE_PATH)

	var starter_bag_item = item_scene_to_use.instantiate()
	starter_bag_item.item_id = "starter_bag"
	starter_bag_item.cell_px = cell_px
	starter_bag_item.item_size = Vector2i(1, 1)

	# Setup dell'item
	var bag_data = {
		"name": "Starter Bag",
		"type": "Bag",
		"bag_slots": STARTER_BAG_SLOTS,
		"icon": "res://Item_Texture/inventoryPg.png"
	}
	starter_bag_item.setup_item("starter_bag", bag_data)

	# Equipaggia la starter bag
	starter_bag_slot.equip_starter_bag(starter_bag_item)

	if LOG:
		print("[InventoryTab] Starter bag equipped (%d slots)" % STARTER_BAG_SLOTS)

func _recalculate_inventory_size() -> void:
	"""Ricalcola le dimensioni della griglia in base alle bag equipaggiate"""
	if total_inventory_slots == 0:
		return

	# Calcola nuove righe (manteniamo 6 colonne fisse per le bag)
	cols = 6
	rows = ceili(float(total_inventory_slots) / float(cols))

	if LOG:
		print("[InventoryTab] Recalculated grid: %dx%d = %d slots (total_slots: %d)" %
			[cols, rows, cols * rows, total_inventory_slots])

	# CRITICAL: Preserve existing items when resizing grid
	# Pass clear_items=false to keep items_at_position intact
	_initialize_grid(false)

	# CRITICAL: Rebuild grid_occupied based on existing items!
	# _initialize_grid() always clears grid_occupied, so we must rebuild it
	_rebuild_grid_occupied()

	_create_slots()

	# NON ricaricare gli items - sono già nell'inventario
	# Se ricarichiamo da GameState, duplichiamo tutto!
	# Gli items esistenti rimarranno posizionati correttamente

func _recalculate_total_slots() -> void:
	"""Ricalcola il totale degli slot dalle bag equipaggiate"""
	total_inventory_slots = 0

	# CRITICAL: Use bag_equipped_slots array instead of accessing bag data
	# This is more reliable and doesn't depend on GameState access
	for i in range(bag_equipped_slots.size()):
		total_inventory_slots += bag_equipped_slots[i]

	if LOG:
		print("[InventoryTab] Total inventory slots: %d (from bag_equipped_slots: %s)" %
			[total_inventory_slots, bag_equipped_slots])

func can_remove_bag(slot_index: int) -> bool:
	"""Controlla se possiamo rimuovere una bag (c'è abbastanza spazio per ridistribuire gli items?)"""
	print("\n========== can_remove_bag() START (slot %d) ==========" % slot_index)

	# Trova la bag da rimuovere
	if slot_index < 0 or slot_index >= bag_slots.size():
		print("[ERROR] Invalid slot_index: %d" % slot_index)
		return false

	var bag_slot = bag_slots[slot_index]
	if bag_slot.equipped_bag == null:
		print("[INFO] No bag equipped in slot %d, removal OK" % slot_index)
		return true  # Nessuna bag, ok

	# CRITICAL: Calcola gli slot rimanenti usando l'array memorizzato
	print("\n[STEP 1] Bag equipped slots array:")
	for i in range(bag_equipped_slots.size()):
		print("  bag_equipped_slots[%d] = %d" % [i, bag_equipped_slots[i]])

	var remaining_slots = 0
	for i in range(bag_equipped_slots.size()):
		if i == slot_index:
			print("  Skipping slot %d (bag to remove)" % i)
			continue  # Skip la bag da rimuovere
		remaining_slots += bag_equipped_slots[i]

	var slots_to_remove = total_inventory_slots - remaining_slots

	# Calcola quante righe avremo dopo la rimozione
	var new_rows = ceili(float(remaining_slots) / float(cols))

	print("\n[STEP 2] Slot calculation:")
	print("  total_inventory_slots: %d" % total_inventory_slots)
	print("  slots_to_remove: %d" % slots_to_remove)
	print("  remaining_slots after removal: %d" % remaining_slots)
	print("  new_rows (after removal): %d (cols: %d)" % [new_rows, cols])
	print("  current rows: %d" % rows)

	# CRITICAL: Get the bag item to exclude it from calculations
	var bag_item = bag_slot.equipped_bag
	print("\n[STEP 3] Bag to remove: %s (instance id: %d)" % [bag_item.item_id, bag_item.get_instance_id()])

	# Count items that need to be redistributed (items outside new bounds)
	var items_to_redistribute: Array[Item] = []
	var items_in_safe_positions: Array[Item] = []

	print("\n[STEP 4] Checking all items in inventory (%d total):" % items_at_position.size())
	var item_index = 0
	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		item_index += 1

		if not is_instance_valid(item):
			print("  [%d] INVALID item at %s - SKIPPING" % [item_index, pos])
			continue

		var item_size_str = "%dx%d" % [item.item_size.x, item.item_size.y]
		var cells = item.item_size.x * item.item_size.y

		# CRITICAL: Skip the bag we're removing - it shouldn't be counted!
		if item == bag_item:
			print("  [%d] %s at %s (size %s, %d cells) - THIS IS THE BAG, SKIPPING!" %
				[item_index, item.item_id, pos, item_size_str, cells])
			continue

		# Check if item's bottom edge would be outside the new grid
		var item_bottom_row = pos.y + item.item_size.y - 1

		if item_bottom_row >= new_rows:
			items_to_redistribute.append(item)
			print("  [%d] %s at %s (size %s, %d cells) bottom_row=%d >= new_rows=%d → NEEDS REDISTRIBUTION" %
				[item_index, item.item_id, pos, item_size_str, cells, item_bottom_row, new_rows])
		else:
			items_in_safe_positions.append(item)
			print("  [%d] %s at %s (size %s, %d cells) bottom_row=%d < new_rows=%d → SAFE" %
				[item_index, item.item_id, pos, item_size_str, cells, item_bottom_row, new_rows])

	# Calculate occupied cells in safe positions
	var occupied_cells_safe = 0
	for item in items_in_safe_positions:
		occupied_cells_safe += item.item_size.x * item.item_size.y

	# Calculate cells needed for items to redistribute
	var cells_needed = 0
	for item in items_to_redistribute:
		cells_needed += item.item_size.x * item.item_size.y

	# CRITICAL FIX: Available space is grid cells, not slots!
	# With 20 slots in a 6-column grid → 4 rows → 24 cells available!
	var grid_cells_after_removal = cols * new_rows
	var available_space = grid_cells_after_removal - occupied_cells_safe

	print("\n[STEP 5] Final calculation:")
	print("  Items in SAFE positions: %d items, %d cells occupied" %
		[items_in_safe_positions.size(), occupied_cells_safe])
	print("  Items to REDISTRIBUTE: %d items, %d cells needed" %
		[items_to_redistribute.size(), cells_needed])
	print("  Remaining slots: %d" % remaining_slots)
	print("  Grid after removal: %d cols × %d rows = %d cells" % [cols, new_rows, grid_cells_after_removal])
	print("  Occupied cells (safe): %d" % occupied_cells_safe)
	print("  Available space: %d - %d = %d" % [grid_cells_after_removal, occupied_cells_safe, available_space])
	print("  Cells needed: %d" % cells_needed)

	var can_remove = cells_needed <= available_space
	print("\n[RESULT] cells_needed (%d) <= available_space (%d) = %s" %
		[cells_needed, available_space, can_remove])
	print("========== can_remove_bag() END ==========\n")

	return can_remove

func redistribute_items_after_bag_removal(new_rows: int) -> bool:
	"""
	Redistribuisce gli item che sarebbero fuori dai bounds dopo la rimozione di una bag.
	Gli item in posizioni sicure rimangono dove sono.
	Restituisce true se la redistribuzione ha successo, false altrimenti.
	"""
	if LOG:
		print("[InventoryTab] Redistributing items for new grid size: %dx%d" % [cols, new_rows])

	# Find items that need to be redistributed
	var items_to_move: Array[Dictionary] = []  # {item: Item, old_pos: Vector2i}

	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		if not is_instance_valid(item):
			continue

		# Check if item would be outside new bounds
		var item_bottom_row = pos.y + item.item_size.y - 1

		if item_bottom_row >= new_rows:
			items_to_move.append({"item": item, "old_pos": pos})

	if items_to_move.is_empty():
		if LOG:
			print("[InventoryTab] No items need redistribution")
		return true

	if LOG:
		print("[InventoryTab] Found %d items to redistribute" % items_to_move.size())

	# Remove items from their old positions
	for data in items_to_move:
		var item: Item = data["item"]
		var old_pos: Vector2i = data["old_pos"]
		items_at_position.erase(old_pos)
		if LOG:
			print("[InventoryTab]   Removing %s from %s" % [item.item_id, old_pos])

	# Try to place items in new positions (only within new_rows bounds)
	for data in items_to_move:
		var item: Item = data["item"]

		# Find position within the NEW grid bounds (not the old grid)
		var free_pos = Vector2i(-1, -1)
		for y in range(new_rows):
			for x in range(cols):
				var test_pos = Vector2i(x, y)
				# Check if this position can fit the item within new bounds
				if test_pos.x + item.item_size.x > cols or test_pos.y + item.item_size.y > new_rows:
					continue

				# Check if position is free (not occupied by safe items)
				var is_free = true
				for check_y in range(test_pos.y, test_pos.y + item.item_size.y):
					for check_x in range(test_pos.x, test_pos.x + item.item_size.x):
						# Check if this cell overlaps with any existing item
						for existing_pos in items_at_position.keys():
							var existing_item = items_at_position[existing_pos]
							if not is_instance_valid(existing_item):
								continue

							# Check if cell (check_x, check_y) is within the bounds of existing_item
							if check_x >= existing_pos.x and check_x < existing_pos.x + existing_item.item_size.x:
								if check_y >= existing_pos.y and check_y < existing_pos.y + existing_item.item_size.y:
									is_free = false
									break
						if not is_free:
							break
					if not is_free:
						break

				if is_free:
					free_pos = test_pos
					break
			if free_pos != Vector2i(-1, -1):
				break

		if free_pos == Vector2i(-1, -1):
			push_error("[InventoryTab] CRITICAL: No space to redistribute item %s!" % item.item_id)
			return false

		# Place item in new position
		items_at_position[free_pos] = item
		item.position = Vector2(free_pos.x * (cell_px + 4), free_pos.y * (cell_px + 4))

		if LOG:
			print("[InventoryTab]   Redistributed %s to %s" % [item.item_id, free_pos])

	if LOG:
		print("[InventoryTab] Redistribution complete!")

	# CRITICAL: Rebuild grid_occupied based on new items positions
	_rebuild_grid_occupied()

	return true

func _update_all_item_positions() -> void:
	"""Aggiorna le posizioni visuali di tutti gli items basandosi su items_at_position"""
	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		if not is_instance_valid(item):
			continue

		# Get the slot at this grid position to get its actual pixel position
		var slot_index = pos.y * cols + pos.x
		if slot_index >= 0 and slot_index < slots.size():
			var slot = slots[slot_index]
			if slot:
				# Position item relative to holder
				var slot_pos = slot.position
				item.position = slot_pos
				item.size = Vector2(item.item_size.x * (cell_px + 4) - 4, item.item_size.y * (cell_px + 4) - 4)
				print("[InventoryTab]   Updated visual position of %s at grid (%d, %d) to pixel (%d, %d)" %
					[item.item_id, pos.x, pos.y, slot_pos.x, slot_pos.y])

func _rebuild_grid_occupied() -> void:
	"""Ricostruisce grid_occupied basandosi su items_at_position"""
	print("[InventoryTab] Rebuilding grid_occupied from items_at_position...")

	# Clear grid_occupied
	for y in range(rows):
		for x in range(cols):
			grid_occupied[y][x] = false

	# Mark cells occupied by items
	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		if not is_instance_valid(item):
			continue

		# Mark all cells occupied by this item
		for y in range(pos.y, pos.y + item.item_size.y):
			for x in range(pos.x, pos.x + item.item_size.x):
				if y < rows and x < cols:
					grid_occupied[y][x] = true

	if LOG:
		print("[InventoryTab] Grid occupied rebuilt")

func _sync_equipped_bags_to_gamestate() -> void:
	"""Salva le bag equipaggiate in GameState"""
	var gs = _get_gamestate()
	if not gs:
		return

	var equipped_bags_data = []
	for i in range(bag_slots.size()):
		var bag_slot = bag_slots[i]
		if bag_slot.equipped_bag != null:
			equipped_bags_data.append({
				"slot_index": i,
				"item_id": bag_slot.equipped_bag.item_id
			})

	gs.set("equipped_bags", equipped_bags_data)

	if LOG:
		print("[InventoryTab] Synced %d equipped bags to GameState" % equipped_bags_data.size())

func _load_equipped_bags_from_gamestate() -> void:
	"""Carica le bag equipaggiate da GameState"""
	var gs = _get_gamestate()
	if not gs or not "equipped_bags" in gs:
		return

	var equipped_bags_data = gs.equipped_bags if "equipped_bags" in gs else []

	for bag_data in equipped_bags_data:
		var slot_index = bag_data.get("slot_index", -1)
		var item_id = bag_data.get("item_id", "")

		if slot_index < 0 or slot_index >= bag_slots.size() or item_id == "":
			continue

		# Crea l'item della bag
		var item_data = _get_item_data(item_id)
		if item_data.is_empty():
			continue

		var bag_item = _create_item_visual(item_id, item_data)
		if bag_item == null:
			continue

		# Equipaggia la bag nello slot corrispondente
		var bag_slot: BagSlot = bag_slots[slot_index]
		if bag_slot.is_locked:
			bag_slot.equip_starter_bag(bag_item)
		else:
			# Per bag non-locked, usa il metodo normale
			bag_slot.equipped_bag = bag_item
			bag_slot.add_child(bag_item)
			bag_item.position = Vector2(4, 4)
			bag_item.size = bag_slot.size - Vector2(8, 8)
			bag_item.z_index = 5

			# Emetti segnale
			var bag_slots_count = item_data.get("bag_slots", 0)
			bag_slot.bag_equipped.emit(slot_index, bag_slots_count)

	if LOG:
		print("[InventoryTab] Loaded %d equipped bags from GameState" % equipped_bags_data.size())

func _get_gamestate() -> Node:
	"""Helper per ottenere GameState"""
	if not has_node("/root/GameState"):
		return null
	return get_node("/root/GameState")
