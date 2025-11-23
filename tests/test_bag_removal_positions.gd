extends GutTest

var inventory_tab: InventoryTab
var game_state: Node

func before_each():
	# Setup minimal GameState mock
	game_state = Node.new()
	game_state.name = "GameState"
	game_state.set_script(load("res://scripts/GameState.gd"))

	# Add to /root so it can be found via get_node("/root/GameState")
	var root = get_tree().root
	root.add_child(game_state)

	# Wait for GameState to initialize
	await get_tree().process_frame

	# Setup InventoryTab
	inventory_tab = autofree(InventoryTab.new())
	inventory_tab.cols = 6
	inventory_tab.rows = 4
	inventory_tab.total_inventory_slots = 0

	# Initialize bag slots array (needed by can_remove_bag)
	inventory_tab.bag_slots = []

	# Initialize grid
	inventory_tab._initialize_grid(true)

func after_each():
	# Cleanup GameState
	if is_instance_valid(game_state):
		game_state.queue_free()

	inventory_tab = null

# ==================== TEST 1: Items mantengono posizioni dopo bag removal ====================

func test_items_keep_positions_after_bag_removal():
	print("\n========== TEST: Items keep positions after bag removal ==========")

	# Setup: 2 bags (40 slots = 7 righe)
	_setup_bags(20, 20)
	print("Setup: 2 bags equipped (40 slots total = 7 rows)")
	print("  Cols: %d, Rows: %d" % [inventory_tab.cols, inventory_tab.rows])

	# Aggiungi 3 items in posizioni specifiche
	var item1 = _create_item("sword", Vector2i(1, 1))
	var item2 = _create_item("shield", Vector2i(1, 1))
	var item3 = _create_item("potion", Vector2i(1, 1))

	inventory_tab.items_at_position[Vector2i(0, 0)] = item1
	inventory_tab.items_at_position[Vector2i(2, 1)] = item2
	inventory_tab.items_at_position[Vector2i(4, 2)] = item3

	print("\nItems placed:")
	print("  item1 (sword) at (0, 0)")
	print("  item2 (shield) at (2, 1)")
	print("  item3 (potion) at (4, 2)")

	print("\nBefore bag removal - items_at_position:")
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		print("  %s at (%d, %d)" % [item.item_id, pos.x, pos.y])

	# Rimuovi la seconda bag (riduci da 7 righe a 4 righe)
	print("\nRemoving bag from slot 1...")
	# CRITICAL: Call _on_bag_removed() instead of _recalculate_inventory_size()
	# This ensures redistribute_items_after_bag_removal() gets called
	inventory_tab._on_bag_removed(1)

	print("\nAfter bag removal:")
	print("  Cols: %d, Rows: %d" % [inventory_tab.cols, inventory_tab.rows])

	print("\nAfter bag removal - items_at_position:")
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		print("  %s at (%d, %d)" % [item.item_id, pos.x, pos.y])

	# Verifica che gli item siano ancora nelle posizioni corrette
	assert_true(inventory_tab.items_at_position.has(Vector2i(0, 0)), "item1 should still be at (0, 0)")
	assert_true(inventory_tab.items_at_position.has(Vector2i(2, 1)), "item2 should still be at (2, 1)")
	assert_true(inventory_tab.items_at_position.has(Vector2i(4, 2)), "item3 should still be at (4, 2)")

	assert_eq(inventory_tab.items_at_position[Vector2i(0, 0)].item_id, "sword", "item1 should be sword")
	assert_eq(inventory_tab.items_at_position[Vector2i(2, 1)].item_id, "shield", "item2 should be shield")
	assert_eq(inventory_tab.items_at_position[Vector2i(4, 2)].item_id, "potion", "item3 should be potion")

# ==================== TEST 2: Items fuori bounds vengono ridistribuiti ====================

func test_items_outside_bounds_redistributed_correctly():
	print("\n========== TEST: Items outside bounds redistributed correctly ==========")

	# Setup: 2 bags (40 slots = 7 righe)
	_setup_bags(20, 20)
	print("Setup: 2 bags equipped (40 slots total = 7 rows)")

	# Aggiungi items: alcuni safe, alcuni fuori bounds
	var item1 = _create_item("sword", Vector2i(1, 1))     # safe: row 0
	var item2 = _create_item("shield", Vector2i(1, 1))    # safe: row 1
	var item3 = _create_item("potion", Vector2i(1, 1))    # outside: row 5 (sarà rimossa quando avremo 4 righe)
	var item4 = _create_item("helmet", Vector2i(1, 1))    # outside: row 6

	inventory_tab.items_at_position[Vector2i(0, 0)] = item1
	inventory_tab.items_at_position[Vector2i(2, 1)] = item2
	inventory_tab.items_at_position[Vector2i(1, 5)] = item3  # Fuori bounds dopo removal
	inventory_tab.items_at_position[Vector2i(3, 6)] = item4  # Fuori bounds dopo removal

	print("\nItems placed:")
	print("  item1 (sword) at (0, 0) - SAFE")
	print("  item2 (shield) at (2, 1) - SAFE")
	print("  item3 (potion) at (1, 5) - OUTSIDE (row 5 >= 4)")
	print("  item4 (helmet) at (3, 6) - OUTSIDE (row 6 >= 4)")

	print("\nBefore bag removal - items_at_position:")
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		print("  %s at (%d, %d)" % [item.item_id, pos.x, pos.y])

	# Rimuovi la seconda bag
	print("\nRemoving bag from slot 1...")
	# CRITICAL: Call _on_bag_removed() instead of _recalculate_inventory_size()
	inventory_tab._on_bag_removed(1)

	print("\nAfter bag removal:")
	print("  Cols: %d, Rows: %d" % [inventory_tab.cols, inventory_tab.rows])

	print("\nAfter bag removal - items_at_position:")
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		print("  %s at (%d, %d)" % [item.item_id, pos.x, pos.y])

	# Verifica che gli item safe siano ancora alle posizioni originali
	assert_true(inventory_tab.items_at_position.has(Vector2i(0, 0)), "item1 should still be at (0, 0)")
	assert_true(inventory_tab.items_at_position.has(Vector2i(2, 1)), "item2 should still be at (2, 1)")

	# Verifica che gli item fuori bounds siano stati ridistribuiti
	var found_potion = false
	var found_helmet = false
	var potion_pos = Vector2i(-1, -1)
	var helmet_pos = Vector2i(-1, -1)

	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		if item.item_id == "potion":
			found_potion = true
			potion_pos = pos
		elif item.item_id == "helmet":
			found_helmet = true
			helmet_pos = pos

	assert_true(found_potion, "Potion should be redistributed")
	assert_true(found_helmet, "Helmet should be redistributed")

	# Verifica che siano dentro i bounds (row < 4)
	assert_lt(potion_pos.y, 4, "Potion should be within bounds (row < 4)")
	assert_lt(helmet_pos.y, 4, "Helmet should be within bounds (row < 4)")

	print("\nRedistribution results:")
	print("  potion redistributed to (%d, %d)" % [potion_pos.x, potion_pos.y])
	print("  helmet redistributed to (%d, %d)" % [helmet_pos.x, helmet_pos.y])

# ==================== TEST 3: Verifica che items non si sovrappongano ====================

func test_no_items_overlap_after_redistribution():
	print("\n========== TEST: No items overlap after redistribution ==========")

	# Setup: 2 bags
	_setup_bags(20, 20)
	print("Setup: 2 bags equipped (40 slots total = 7 rows)")

	# Riempi completamente le prime 3 righe (18 slot)
	var items = []
	for i in range(18):
		var item = _create_item("item_%d" % i, Vector2i(1, 1))
		var pos = Vector2i(i % 6, i / 6)
		inventory_tab.items_at_position[pos] = item
		items.append(item)

	# Aggiungi 2 items fuori bounds (riga 5)
	var item_outside1 = _create_item("outside_1", Vector2i(1, 1))
	var item_outside2 = _create_item("outside_2", Vector2i(1, 1))
	inventory_tab.items_at_position[Vector2i(0, 5)] = item_outside1
	inventory_tab.items_at_position[Vector2i(1, 5)] = item_outside2

	print("\nPlaced 18 items in first 3 rows + 2 items in row 5 (outside bounds)")
	print("Total items: 20")

	# Rimuovi la seconda bag
	print("\nRemoving bag from slot 1...")
	# CRITICAL: Call _on_bag_removed() instead of _recalculate_inventory_size()
	inventory_tab._on_bag_removed(1)

	print("\nAfter bag removal:")
	print("  Cols: %d, Rows: %d" % [inventory_tab.cols, inventory_tab.rows])
	print("  Total items in items_at_position: %d" % inventory_tab.items_at_position.size())

	# Verifica che non ci siano duplicati nelle posizioni
	var position_count = {}
	for pos in inventory_tab.items_at_position.keys():
		var pos_str = "(%d,%d)" % [pos.x, pos.y]
		if position_count.has(pos_str):
			position_count[pos_str] += 1
		else:
			position_count[pos_str] = 1

	print("\nPosition occupancy:")
	for pos_str in position_count.keys():
		var count = position_count[pos_str]
		print("  %s: %d item%s" % [pos_str, count, "s" if count > 1 else ""])
		if count > 1:
			print("  ❌ ERROR: Multiple items at same position!")

	# Assert: Nessuna posizione dovrebbe avere più di un item
	for pos_str in position_count.keys():
		assert_eq(position_count[pos_str], 1, "Each position should have only 1 item: %s" % pos_str)

	# Verifica che tutti gli item siano ancora presenti
	assert_eq(inventory_tab.items_at_position.size(), 20, "All 20 items should still exist")

# ==================== HELPER FUNCTIONS ====================

func _setup_bags(starter_slots: int, second_slots: int):
	"""Setup 2 bag slots con le bag equipaggiate"""
	# Create BagSlot 0 (starter - locked)
	var bag_slot_0 = BagSlot.new()
	bag_slot_0.slot_index = 0
	bag_slot_0.is_locked = true
	bag_slot_0.inventory_tab = inventory_tab

	var starter_bag = _create_item("starter_bag", Vector2i(1, 1))
	bag_slot_0.equipped_bag = starter_bag

	# Create BagSlot 1 (removable)
	var bag_slot_1 = BagSlot.new()
	bag_slot_1.slot_index = 1
	bag_slot_1.is_locked = false
	bag_slot_1.inventory_tab = inventory_tab

	var second_bag = _create_item("bag_20slot", Vector2i(1, 1))
	bag_slot_1.equipped_bag = second_bag

	# Add to inventory_tab
	inventory_tab.bag_slots = [bag_slot_0, bag_slot_1]

	# CRITICAL: Setup bag_equipped_slots array
	inventory_tab.bag_equipped_slots.clear()
	inventory_tab.bag_equipped_slots.resize(5)
	for i in range(5):
		inventory_tab.bag_equipped_slots[i] = 0
	inventory_tab.bag_equipped_slots[0] = starter_slots
	inventory_tab.bag_equipped_slots[1] = second_slots

	inventory_tab.total_inventory_slots = starter_slots + second_slots
	inventory_tab._recalculate_inventory_size()

func _create_item(item_id: String, size: Vector2i) -> Item:
	"""Crea un Item semplice per i test"""
	var item = Item.new()
	item.item_id = item_id
	item.item_size = size
	return item
