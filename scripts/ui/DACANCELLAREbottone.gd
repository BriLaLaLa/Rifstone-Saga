extends Button

var db: ItemDatabase = null
var inv: InventoryTab = null

func _ready():
	text = "Droppa Random Item"
	pressed.connect(_on_pressed)
	
	# METODO ROBUSTO: Cerca l'InventoryTab risalendo l'albero
	inv = _find_inventory_tab()
	
	if inv == null:
		print("[Bottone] ERRORE: InventoryTab non trovato!")
		print("[Bottone] Percorso corrente: %s" % get_path())
		print("[Bottone] Parent: %s" % get_parent())
	else:
		print("[Bottone] InventoryTab trovato: %s" % inv.name)
	
	# Crea ItemDatabase
	db = ItemDatabase.new()
	add_child(db)  # Aggiungi come child così _ready() viene chiamato
	
	print("[Bottone] Setup completato - inv: %s, db: %s" % [inv, db])

func _find_inventory_tab() -> InventoryTab:
	# Metodo 1: Risali l'albero dei parent
	var current = get_parent()
	var depth = 0
	while current != null and depth < 10:  # Max 10 livelli per sicurezza
		if current is InventoryTab:
			print("[Bottone] Trovato InventoryTab a livello %d: %s" % [depth, current.name])
			return current
		
		# Debug: stampa il percorso
		print("[Bottone] Livello %d: %s (tipo: %s)" % [depth, current.name, current.get_class()])
		
		current = current.get_parent()
		depth += 1
	
	# Metodo 2: Cerca nella scena corrente come fallback
	print("[Bottone] Metodo 1 fallito, provo metodo 2...")
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

func _on_pressed():
	print("[Bottone] Bottone premuto!")
	
	if db == null:
		print("[Bottone] ItemDatabase non trovato!")
		return
		
	if inv == null:
		print("[Bottone] InventoryTab non trovato!")
		# Riprova a cercarlo
		inv = _find_inventory_tab()
		if inv == null:
			print("[Bottone] Ancora non trovato, impossibile continuare")
			return
	
	# Ottieni un item random
	var entry = db.get_random_item()
	if entry.is_empty():
		print("[Bottone] Nessun item nel database!")
		return
	
	print("[Bottone] Item random ottenuto: %s" % entry.id)
	
	# Aggiungi l'item
	var success = inv.add_item_from_data(entry.id, entry.data)
	if success:
		print("[Bottone] Aggiunto item random: %s" % entry.id)
	else:
		print("[Bottone] Impossibile aggiungere item: %s (inventario pieno?)" % entry.id)
