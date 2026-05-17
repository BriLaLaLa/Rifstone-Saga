extends Control
class_name InventoryTab

const LOG := true

@export var cols: int = 6  # Fixed to 6 for bag system compatibility
@export var rows: int = 5
@export var cell_px: int = 64

@export var item_scene: PackedScene
@export var craftable_item_scene: PackedScene
@export var slot_scene: PackedScene

@onready var holder: GridContainer = $"InvSplit/Left/InventoryScroll/InventoryContainer/Holder"
@onready var items_layer: Control = $"InvSplit/Left/InventoryScroll/InventoryContainer/ItemsLayer"
@onready var inventory_container: Control = $"InvSplit/Left/InventoryScroll/InventoryContainer"
@onready var bag_section: VBoxContainer = $"InvSplit/Left/BagSection"

# Bag slots from scene
@onready var bag_slot_0: BagSlot = $"InvSplit/Left/BagSection/BagContainer/BagSlot0"
@onready var bag_slot_1: BagSlot = $"InvSplit/Left/BagSection/BagContainer/BagSlot1"
@onready var bag_slot_2: BagSlot = $"InvSplit/Left/BagSection/BagContainer/BagSlot2"
@onready var bag_slot_3: BagSlot = $"InvSplit/Left/BagSection/BagContainer/BagSlot3"
@onready var bag_slot_4: BagSlot = $"InvSplit/Left/BagSection/BagContainer/BagSlot4"
@onready var trash_bin: TrashBin = $"InvSplit/Left/BagSection/TrashBin"

const DEFAULT_SLOT_SCENE_PATH := "res://scripts/ui/InventorySlot.tscn"
const DEFAULT_ITEM_SCENE_PATH := "res://scripts/ui/Item.tscn"
const DEFAULT_CRAFTABLE_ITEM_SCENE_PATH := "res://scripts/ui/CraftableItem.tscn"

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

func _ready() -> void:
	_initialize_grid()
	_init_bag_slots_from_scene()
	_create_slots()
	_connect_to_gamestate()
	_setup_starter_bag()

	# CRITICAL: Listen for children removed from ItemsLayer
	if items_layer:
		items_layer.child_exiting_tree.connect(_on_item_removed_from_layer)

	# Refresh when tab becomes visible — necessary because the tab starts hidden
	# (Villaggio is now the first tab). Without this, items are placed while the
	# Control has no computed size, resulting in wrong positions.
	visibility_changed.connect(_on_tab_visibility_changed)

	# Initial refresh only if already visible (e.g. direct scene launch from editor)
	if is_visible_in_tree():
		_refresh_from_gamestate()

func _on_tab_visibility_changed() -> void:
	if is_visible_in_tree():
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
			print("[InventoryTab] 🔗 Connected to GameState.on_inventory_changed signal")
		else:
			print("[InventoryTab] ⚠️ Already connected to GameState.on_inventory_changed signal")
	else:
		print("[InventoryTab] ❌ Failed to connect - GameState or signal not found")

func _on_gamestate_inventory_changed() -> void:
	print("[InventoryTab] 📥 Received on_inventory_changed signal!")
	_refresh_from_gamestate()
	print("[InventoryTab] 📥 Refresh complete.")

func _refresh_from_gamestate() -> void:
	# Pulisci inventario visuale
	_clear_all_items()

	var gs = _get_gamestate()
	if not gs:
		return

	# PRIORITY: Use NEW grid-based inventory_items if it exists
	# CRITICAL FIX: If inventory_items exists (even if empty), use it and DON'T fall back to old format
	# The old fallback was overwriting loaded data with empty arrays!
	if "inventory_items" in gs:
		print("[InventoryTab] 📂 Loading from inventory_items (NEW format): %d items" % gs.inventory_items.size())
		_load_from_inventory_items(gs.inventory_items)
		return

	# FALLBACK: Use old inventory dictionary ONLY if inventory_items doesn't exist at all
	if not "inventory" in gs:
		return

	print("[InventoryTab] 📂 Loading from inventory dictionary (OLD format - fallback for migration)")
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

	# MIGRATION: Sync to populate inventory_items for first-time OLD format users
	_sync_to_gamestate()
	print("[InventoryTab] ✅ Migrated from OLD format and synced %d items to inventory_items" % items_at_position.size())

func _load_from_inventory_items(inventory_items: Array) -> void:
	"""Load inventory from the NEW inventory_items format (with positions and bonuses)"""
	var loaded_count = 0

	# CRITICAL FIX: Use instance_id for unique identification instead of item_id!
	# This prevents the bug where ALL items with same item_id get skipped on reload
	var gs = _get_gamestate()
	var equipped_instance_ids = []  # Use instance_id for unique identification!
	if gs and "equipped_items" in gs:
		for slot in gs.equipped_items.keys():
			if gs.equipped_items[slot] != null:
				var instance_id = gs.equipped_items[slot].get("instance_id", "")
				if instance_id != "":
					equipped_instance_ids.append(instance_id)
					print("[InventoryTab] 🔍 Item with instance_id '%s' is equipped, will skip loading" % instance_id)
				else:
					# Fallback to item_id if no instance_id (legacy saves before this fix)
					var item_id = gs.equipped_items[slot].get("id", "")
					if item_id != "":
						equipped_instance_ids.append("legacy:" + item_id)
						print("[InventoryTab] ⚠️ Legacy equipped item '%s' (no instance_id)" % item_id)

	for item_entry in inventory_items:
		if typeof(item_entry) != TYPE_DICTIONARY:
			continue

		var item_id = item_entry.get("item_id", "")
		if item_id == "":
			continue

		# CRITICAL FIX: Skip items that are equipped (using instance_id for uniqueness!)
		var entry_instance_id = item_entry.get("instance_id", "")
		if entry_instance_id in equipped_instance_ids:
			print("[InventoryTab] ⏭️ Skipping item '%s' (instance: %s) - equipped" % [item_id, entry_instance_id])
			continue
		# Legacy fallback: skip by item_id if it has legacy marker
		if ("legacy:" + item_id) in equipped_instance_ids:
			print("[InventoryTab] ⏭️ Skipping item '%s' (legacy check)" % item_id)
			continue

		# Get base item data
		var item_data = _get_item_data(item_id)
		if item_data.is_empty():
			print("[InventoryTab] ⚠️ Unknown item: %s" % item_id)
			continue

		# Apply saved data (bonuses, upgrade_level, enhancement_level, instance_id, etc.)
		if item_entry.has("bonuses") or item_entry.has("upgrade_level") or item_entry.has("enhancement_level") or item_entry.has("instance_id"):
			item_data = item_data.duplicate(true)

			# Apply bonuses if present
			if item_entry.has("bonuses"):
				item_data["bonuses"] = item_entry.bonuses
				print("[InventoryTab] → Item %s has %d bonuses" % [item_id, item_entry.bonuses.size()])

			# Apply upgrade level if present and RECALCULATE stats
			if item_entry.has("upgrade_level"):
				var upgrade_level = item_entry.upgrade_level
				item_data["upgrade_level"] = upgrade_level
				print("[InventoryTab] → Item %s is at upgrade level +%d" % [item_id, upgrade_level])

				# RECALCULATE stats based on upgrade level (same formula as ForgeUI)
				if item_data.has("stats") and upgrade_level > 0:
					_apply_upgrade_bonus_to_item(item_data, upgrade_level)
					print("[InventoryTab] → Recalculated stats for +%d upgrade" % upgrade_level)

			# Apply enhancement level if present (NEW: Enhancement System)
			if item_entry.has("enhancement_level"):
				var enhancement_level = item_entry.enhancement_level
				item_data["enhancement_level"] = enhancement_level
				print("[InventoryTab] → Item %s is at enhancement level +%d" % [item_id, enhancement_level])
			# AUTO-FIX: Sync enhancement_level from upgrade_level for old saves
			elif item_entry.has("upgrade_level") and item_entry.upgrade_level >= 7:
				var sync_level = item_entry.upgrade_level
				item_data["enhancement_level"] = sync_level
				print("[InventoryTab] 🔧 Auto-synced enhancement_level +%d from upgrade_level" % sync_level)

			# CRITICAL: Restore instance_id to item_data so it gets saved in metadata
			if item_entry.has("instance_id") and item_entry.instance_id != "":
				item_data["instance_id"] = item_entry.instance_id
				print("[InventoryTab] → Restoring instance_id: %s" % item_entry.instance_id)

		# Create visual item
		var item = _create_item_visual(item_id, item_data)
		if item == null:
			print("[InventoryTab] ⚠️ Failed to create item: %s" % item_id)
			continue

		# Note: instance_id is already set in _create_item_visual if not in item_data
		# or restored from item_data["instance_id"] above

		# Get saved position (support both Vector2i and Dictionary formats)
		var pos: Vector2i
		var pos_entry = item_entry.get("pos", Vector2i(0, 0))
		if pos_entry is Vector2i:
			pos = pos_entry
		elif typeof(pos_entry) == TYPE_DICTIONARY:
			pos = Vector2i(pos_entry.get("x", 0), pos_entry.get("y", 0))
		else:
			pos = Vector2i(0, 0)

		# Place item at saved position FIRST (add_child triggers _ready on StackLabel)
		if _place_item_internal(item, pos):
			# Apply stack_count AFTER entering the scene tree so StackLabel._ready()
			# doesn't reset visible=false over the count we set
			if item_entry.has("stack_count") and item.is_stackable:
				item.stack_count = item_entry.stack_count
				item._update_stack_label()
			print("[InventoryTab] ✅ Loaded %s x%d at (%d, %d)" % [item_id, item.stack_count, pos.x, pos.y])
			loaded_count += 1
		else:
			print("[InventoryTab] ❌ Failed to place %s at (%d, %d)" % [item_id, pos.x, pos.y])
			item.queue_free()

	print("[InventoryTab] ✅ Loaded %d items from inventory_items" % loaded_count)

	# REMOVED: DO NOT sync after loading from NEW format!
	# When loading from inventory_items, we are READING data, not WRITING.
	# Syncing here would overwrite the loaded data with whatever is in the UI,
	# causing empty arrays to be written back.
	# Only sync when items are MODIFIED (drag/drop/equip), not when LOADING.

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

func _generate_unique_instance_id() -> String:
	"""Genera un ID univoco per questa istanza di item"""
	return "item_%d_%d" % [Time.get_ticks_msec(), randi()]

func _create_item_visual(item_id: String, item_data: Dictionary) -> Item:
	# CRITICAL: Determine if item should be CraftableItem (weapons/armor) or regular Item
	var item_type = item_data.get("slot", "")  # weapon, helmet, chest, belt, boots, shield
	var is_craftable = item_type in ["weapon", "helmet", "chest", "belt", "boots", "shield"]

	var item: Item

	if is_craftable:
		# Create CraftableItem for equipment that can accept gems
		var craftable_scene_to_use: PackedScene = craftable_item_scene
		if craftable_scene_to_use == null:
			craftable_scene_to_use = load(DEFAULT_CRAFTABLE_ITEM_SCENE_PATH)

		if craftable_scene_to_use != null:
			item = craftable_scene_to_use.instantiate()
		else:
			push_error("[InventoryTab] Failed to load CraftableItem scene for %s" % item_id)
			return null
		print("[InventoryTab] Created CraftableItem for %s (type: %s)" % [item_id, item_type])
	else:
		# Create regular Item for materials, consumables, gems, etc.
		var item_scene_to_use: PackedScene = item_scene
		if item_scene_to_use == null:
			item_scene_to_use = load(DEFAULT_ITEM_SCENE_PATH)

		if item_scene_to_use != null:
			item = item_scene_to_use.instantiate()
		else:
			push_error("[InventoryTab] Failed to load Item scene for %s" % item_id)
			return null
		print("[InventoryTab] Created Item for %s (type: %s)" % [item_id, item_type])

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

	# CRITICAL FIX: Generate unique instance_id for EVERY new item
	# Only restore existing instance_id if it was EXPLICITLY passed in item_data
	# (this happens when loading from save, where each inventory_items entry has its own instance_id)
	var instance_id: String
	
	# Check if this item_data has a UNIQUE instance_id (passed from save file)
	# We detect this by checking if it was explicitly passed (not from database)
	if item_data.has("instance_id") and item_data.instance_id != "":
		# IMPORTANT: Only restore if the instance_id looks like it came from a save
		# (not from the database being accidentally modified previously)
		instance_id = item_data.instance_id
		print("[InventoryTab] Restoring existing instance_id: %s" % instance_id)
	else:
		# ALWAYS generate a new unique instance_id for new items
		instance_id = _generate_unique_instance_id()
		print("[InventoryTab] Generated new instance_id: %s" % instance_id)
	
	# CRITICAL: Store ONLY in item metadata, NOT in the database dictionary!
	item.set_meta("instance_id", instance_id)

	# IMPORTANTE: Chiama setup_item per configurare il tooltip
	print("[InventoryTab] Calling setup_item with data: %s" % item_data)
	item.setup_item(item_id, item_data)
	print("[InventoryTab] After setup_item, tooltip: '%s'" % item.tooltip_text)

	# NEW: Apply enhancement level if present (Enhancement System)
	if item_data.has("enhancement_level"):
		var enh_level = item_data.enhancement_level
		if enh_level > 0:
			item.set_enhancement_level(enh_level)
			print("[InventoryTab] ✨ Applied enhancement level +%d to %s" % [enh_level, item_id])

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

	# CRITICAL FIX: Save grid_position as metadata for equipment system
	item.set_meta("grid_position", pos)

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

	# CRITICAL: Check if item is still valid after await
	if not is_instance_valid(item):
		print("[InventoryTab] ⚠️ Item was freed before positioning, skipping")
		return

	# CRITICAL FIX: Check if item is still tracked in items_at_position
	# This prevents positioning items that were removed during the deferred delay
	if not items_at_position.has(pos) or items_at_position[pos] != item:
		print("[InventoryTab] ⚠️ Item %s no longer at position %s, skipping positioning (likely removed by bag system)" % [item.item_id, pos])
		return

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

	# CRITICAL FIX: Don't actually remove/replace during validation!
	# Just check if the cells would be free (ignoring the item being dragged)

	# Check bounds
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + item.item_size.x > cols or pos.y + item.item_size.y > rows:
		return false

	# Check if cells are free (but ignore cells occupied by THIS item)
	for y in range(pos.y, pos.y + item.item_size.y):
		for x in range(pos.x, pos.x + item.item_size.x):
			if y < grid_occupied.size() and x < grid_occupied[y].size():
				if grid_occupied[y][x]:
					# Cell is occupied - check if it's by THIS item
					var cell_pos = Vector2i(x, y)
					var occupying_item = get_item_occupying(cell_pos)
					if occupying_item != item:
						# Occupied by a different item
						return false

	return true

# ==================== NUOVI METODI PER IL FIX DEL DRAG & DROP ====================

func get_item_position(item: Item) -> Vector2i:
	"""Trova la posizione di un item nell'inventario"""
	for pos in items_at_position.keys():
		if items_at_position[pos] == item:
			return pos
	return Vector2i(-1, -1)  # Item non trovato

func get_item_at(pos: Vector2i) -> Item:
	"""Restituisce l'item alla posizione specificata (solo top-left), o null se vuota"""
	var result = items_at_position.get(pos, null)
	print("[InventoryTab] get_item_at(%s) = %s" % [pos, result.item_id if result else "null"])
	print("  → items_at_position has %d items total" % items_at_position.size())
	print("  → items_at_position keys: %s" % str(items_at_position.keys()))
	return result

func get_item_occupying(pos: Vector2i) -> Item:
	"""Restituisce l'item che OCCUPA questa posizione (anche se non è il suo top-left)"""
	# CRITICAL: Check ALL items to see if they occupy this position
	for item_pos in items_at_position.keys():
		var item = items_at_position[item_pos]
		if item == null:
			continue

		# Check if this position is within the item's bounds
		var item_size = item.item_size
		for dx in range(item_size.x):
			for dy in range(item_size.y):
				var occupied_pos = Vector2i(item_pos.x + dx, item_pos.y + dy)
				if occupied_pos == pos:
					print("[InventoryTab] 🎯 get_item_occupying(%s) = %s (top-left at %s)" % [pos, item.item_id, item_pos])
					return item

	print("[InventoryTab] get_item_occupying(%s) = null" % pos)
	return null

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

func remove_item(item: Item) -> void:
	"""Rimuove un item dall'inventario (funzione pubblica)"""
	_remove_item_if_exists(item)
	_sync_to_gamestate()

func _remove_item_if_exists(item: Item) -> Dictionary:
	# Trova l'item nella mappa posizioni
	if LOG:
		print("[InventoryTab] 🔍 _remove_item_if_exists searching for item: %s (instance_id: %d)" % [item.item_id if item else "null", item.get_instance_id() if item else 0])
		print("[InventoryTab] 🔍 Current items_at_position has %d items:" % items_at_position.size())
		for p in items_at_position.keys():
			var it = items_at_position[p]
			print("[InventoryTab]   → pos %s: %s (instance_id: %d)" % [p, it.item_id if it else "null", it.get_instance_id() if it else 0])

	for pos in items_at_position.keys():
		if items_at_position[pos] == item:
			if LOG:
				print("[InventoryTab] ✅ Found item at position %s, removing..." % pos)

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

			if LOG:
				print("[InventoryTab] ✅ Item removed, items_at_position now has %d items" % items_at_position.size())
			
			# Rimuovi dal parent se necessario
			if item.get_parent():
				item.get_parent().remove_child(item)
			
			return {"pos": pos, "removed": true}

	if LOG:
		print("[InventoryTab] ⚠️ Item NOT found in items_at_position!")
	return {"removed": false}

func _sync_to_gamestate() -> void:
	print("[InventoryTab] 🔄 _sync_to_gamestate() called - scanning items_at_position (%d items)" % items_at_position.size())

	# Conta gli items per tipo (old format)
	var inventory_count: Dictionary = {}

	# NEW: Build inventory_items array with positions and bonuses
	var inventory_items_array: Array = []

	for pos in items_at_position.keys():
		var item = items_at_position[pos]
		print("[InventoryTab]   → Found item '%s' at position %s" % [item.item_id if item else "null", pos])
		if is_instance_valid(item):
			var id = item.item_id
			inventory_count[id] = inventory_count.get(id, 0) + 1

			# NEW: Add to inventory_items with position, bonuses, upgrade_level, and INSTANCE_ID
			var item_entry = {
				"item_id": id,
				"pos": {"x": pos.x, "y": pos.y},  # Save as dict for JSON compatibility
				"instance_id": item.get_meta("instance_id", "")  # CRITICAL: Unique identifier
			}

			# CRITICAL: Save stack_count for ALL stackable items (even count=1, so stacking logic can find them)
			if "stack_count" in item and item.is_stackable:
				item_entry["stack_count"] = item.stack_count

			# Include bonuses and upgrade_level if item has them (CraftableItem)
			if item.has_meta("item_data"):
				var item_data = item.get_meta("item_data")

				# Save bonuses
				if item_data.has("bonuses"):
					item_entry["bonuses"] = item_data.bonuses

				# Save upgrade_level (for ForgeUI system)
				if item_data.has("upgrade_level"):
					item_entry["upgrade_level"] = item_data.upgrade_level

			# CRITICAL: Save enhancement_level from Item node (for particle effects)
			if item.has_method("get_enhancement_level"):
				var enh_level = item.get_enhancement_level()
				if enh_level > 0:
					item_entry["enhancement_level"] = enh_level

			inventory_items_array.append(item_entry)

	# Sincronizza con GameState
	var gs = _get_gamestate()
	if gs:
		gs.set("inventory", inventory_count)  # Old format
		gs.set("inventory_items", inventory_items_array)  # NEW format

		if LOG:
			print("[InventoryTab] 💾 Synced to GameState: %d items (old format: %s)" % [inventory_items_array.size(), str(inventory_count)])
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

var __hl_path: NodePath = NodePath("InvSplit/Left/InventoryScroll/InventoryContainer/HighlightLayer")

func __hl() -> HighlightLayer:
	var n: Node = get_node_or_null(__hl_path)
	return n as HighlightLayer

func render_highlight_preview(item: Item, tl: Vector2i, is_ok: bool) -> void:
	print("[InventoryTab] 🎨 render_highlight_preview called: item=%s, tl=%s, valid=%s" % [item.item_id, tl, is_ok])

	var hl: HighlightLayer = __hl()
	if hl == null:
		print("[InventoryTab] ❌ HighlightLayer is NULL!")
		return

	print("[InventoryTab] ✅ HighlightLayer found")

	var rects: Array[Rect2] = []
	for y in range(tl.y, tl.y + item.item_size.y):
		for x in range(tl.x, tl.x + item.item_size.x):
			if x >= 0 and y >= 0 and x < cols and y < rows:
				var r: Rect2 = __cell_rect_for_highlight(Vector2i(x, y))
				if r.size.x > 0.0 and r.size.y > 0.0:
					rects.append(r)
					print("[InventoryTab] → Added rect for cell (%d, %d): pos=%s, size=%s" % [x, y, r.position, r.size])

	print("[InventoryTab] → Total rects: %d" % rects.size())
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

func _init_bag_slots_from_scene() -> void:
	"""Initialize bag slots from the scene tree instead of creating them at runtime"""
	# Initialize bag_equipped_slots array
	bag_equipped_slots.clear()
	bag_equipped_slots.resize(MAX_BAG_SLOTS)
	for i in range(MAX_BAG_SLOTS):
		bag_equipped_slots[i] = 0

	# Populate bag_slots array with references to scene nodes
	bag_slots.clear()
	bag_slots.append(bag_slot_0)
	bag_slots.append(bag_slot_1)
	bag_slots.append(bag_slot_2)
	bag_slots.append(bag_slot_3)
	bag_slots.append(bag_slot_4)

	# Connect signals and set inventory_tab reference for each bag slot
	for bag_slot in bag_slots:
		bag_slot.inventory_tab = self
		bag_slot.bag_equipped.connect(_on_bag_equipped)
		bag_slot.bag_removed.connect(_on_bag_removed)

	if LOG:
		print("[InventoryTab] Initialized %d bag slots from scene" % bag_slots.size())

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

func _on_item_removed_from_layer(node: Node) -> void:
	"""Called when an item is removed from ItemsLayer (e.g., equipped)"""
	if not node is Item:
		return

	var item = node as Item
	print("[InventoryTab] 🗑️ Item removed from ItemsLayer: %s" % item.item_id)

	# Find and remove from items_at_position
	for pos in items_at_position.keys():
		if items_at_position[pos] == item:
			print("[InventoryTab] ✅ Removing from items_at_position at %s" % pos)
			items_at_position.erase(pos)

			# Free grid cells
			for y in range(pos.y, pos.y + item.item_size.y):
				for x in range(pos.x, pos.x + item.item_size.x):
					if y < grid_occupied.size() and x < grid_occupied[y].size():
						grid_occupied[y][x] = false

			# Sync to GameState
			call_deferred("_sync_to_gamestate")
			break

func _get_gamestate() -> Node:
	"""Helper per ottenere GameState"""
	if not has_node("/root/GameState"):
		return null
	return get_node("/root/GameState")

func _apply_upgrade_bonus_to_item(item_data: Dictionary, upgrade_level: int) -> void:
	"""Recalculate item stats based on upgrade level (same formula as ForgeUI)"""
	const STAT_BOOST_PER_LEVEL = 0.05  # 5% boost per upgrade level (must match ForgeUI!)

	if not item_data.has("stats"):
		return

	# Save original stats as base_stats if not already saved
	if not item_data.has("base_stats"):
		item_data["base_stats"] = item_data["stats"].duplicate(true)

	var base_stats = item_data["base_stats"]
	var multiplier = 1.0 + (upgrade_level * STAT_BOOST_PER_LEVEL)

	# Recalculate all stats
	var boosted_stats = {}
	for stat_key in base_stats.keys():
		var base_value = base_stats[stat_key]
		boosted_stats[stat_key] = int(base_value * multiplier)  # Round to int for display

	item_data["stats"] = boosted_stats
	print("[InventoryTab] 📊 Stats boosted by %d%% (level +%d)" % [int(multiplier * 100) - 100, upgrade_level])
