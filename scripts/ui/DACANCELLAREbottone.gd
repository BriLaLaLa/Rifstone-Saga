extends HBoxContainer

var db: ItemDatabase = null
var inv: InventoryTab = null
var item_dropdown: OptionButton = null
var add_button: Button = null

func _ready():
	# Crea ItemDatabase
	db = ItemDatabase.new()
	add_child(db)  # Aggiungi come child così _ready() viene chiamato

	# METODO ROBUSTO: Cerca l'InventoryTab risalendo l'albero
	inv = _find_inventory_tab()

	if inv == null:
		print("[ItemSelector] ERRORE: InventoryTab non trovato!")
		print("[ItemSelector] Percorso corrente: %s" % get_path())
		print("[ItemSelector] Parent: %s" % get_parent())
	else:
		print("[ItemSelector] InventoryTab trovato: %s" % inv.name)

	# Wait for ItemDatabase to load
	await get_tree().process_frame

	# Setup UI
	_setup_ui()

	print("[ItemSelector] Setup completato - inv: %s, db: %s, items: %d" % [inv, db, db.items.size()])

func _setup_ui():
	# Create Label
	var label = Label.new()
	label.text = "Item:"
	label.custom_minimum_size = Vector2(40, 0)
	add_child(label)

	# Create OptionButton (dropdown)
	item_dropdown = OptionButton.new()
	item_dropdown.custom_minimum_size = Vector2(200, 0)
	add_child(item_dropdown)

	# Populate dropdown with all items
	_populate_dropdown()

	# Create Add Button
	add_button = Button.new()
	add_button.text = "Add Item"
	add_button.custom_minimum_size = Vector2(100, 0)
	add_button.pressed.connect(_on_add_pressed)
	add_child(add_button)

func _populate_dropdown():
	if db == null or db.items.is_empty():
		print("[ItemSelector] No items to populate dropdown")
		item_dropdown.add_item("(No items)", -1)
		item_dropdown.disabled = true
		return

	# Sort items by ID for easier navigation
	var item_ids = db.items.keys()
	item_ids.sort()

	# Add each item to dropdown
	var index = 0
	for item_id in item_ids:
		var item_data = db.items[item_id]

		# Create display name: "item_id (type)"
		var display_name = item_id
		if item_data.has("type"):
			display_name += " (%s)" % item_data.type

		# Add to dropdown with the item_id as metadata
		item_dropdown.add_item(display_name, index)
		item_dropdown.set_item_metadata(index, item_id)
		index += 1

	print("[ItemSelector] Populated dropdown with %d items" % item_ids.size())

func _find_inventory_tab() -> InventoryTab:
	# Metodo 1: Risali l'albero dei parent
	var current = get_parent()
	var depth = 0
	while current != null and depth < 10:  # Max 10 livelli per sicurezza
		if current is InventoryTab:
			print("[ItemSelector] Trovato InventoryTab a livello %d: %s" % [depth, current.name])
			return current

		# Debug: stampa il percorso
		print("[ItemSelector] Livello %d: %s (tipo: %s)" % [depth, current.name, current.get_class()])

		current = current.get_parent()
		depth += 1

	# Metodo 2: Cerca nella scena corrente come fallback
	print("[ItemSelector] Metodo 1 fallito, provo metodo 2...")
	var root = get_tree().current_scene
	return _search_inventory_tab(root)

func _search_inventory_tab(node: Node) -> InventoryTab:
	if node is InventoryTab:
		return node

	for child in node.get_children():
		var result = _search_inventory_tab(child)
		if result != null:
			return result

	return null

func _on_add_pressed():
	print("[ItemSelector] Add button pressed!")

	if db == null:
		print("[ItemSelector] ItemDatabase non trovato!")
		return

	if inv == null:
		print("[ItemSelector] InventoryTab non trovato!")
		# Riprova a cercarlo
		inv = _find_inventory_tab()
		if inv == null:
			print("[ItemSelector] Ancora non trovato, impossibile continuare")
			return

	if item_dropdown == null or item_dropdown.selected == -1:
		print("[ItemSelector] No item selected!")
		return

	# Get selected item ID from metadata
	var selected_index = item_dropdown.selected
	var item_id = item_dropdown.get_item_metadata(selected_index)

	if item_id == null or not db.items.has(item_id):
		print("[ItemSelector] Invalid item ID: %s" % item_id)
		return

	var item_data = db.items[item_id]
	print("[ItemSelector] Selected item: %s" % item_id)

	# Aggiungi l'item
	var success = inv.add_item_from_data(item_id, item_data)
	if success:
		print("[ItemSelector] ✅ Added item: %s" % item_id)
	else:
		print("[ItemSelector] ❌ Cannot add item: %s (inventory full?)" % item_id)
