extends GutTest

# Test per verificare il bug della rimozione bag quando non c'è spazio
# Bug: Quando togli una bag slot e non c'è abbastanza spazio per redistribuire gli items,
# la bag va in posizione 0,0 e diventa intoccabile

var inventory_tab: InventoryTab
var bag_slot_1: BagSlot
var test_scene: Node

func before_each():
	print("\n========== TEST SETUP START ==========")

	# Create test scene root
	test_scene = Node.new()
	add_child_autofree(test_scene)

	# Load InventoryTab scene
	var inv_tab_scene = load("res://scripts/ui/InventoryTab.tscn")
	if inv_tab_scene == null:
		fail_test("Failed to load InventoryTab.tscn")
		return

	inventory_tab = inv_tab_scene.instantiate()
	test_scene.add_child(inventory_tab)

	# Wait for _ready to complete
	await wait_frames(2)

	# Get reference to bag slot 1 (not the locked starter bag)
	bag_slot_1 = inventory_tab.bag_slot_1
	assert_not_null(bag_slot_1, "BagSlot1 should exist")

	print("[TEST] InventoryTab ready with %d rows, %d cols" % [inventory_tab.rows, inventory_tab.cols])
	print("[TEST] Total slots: %d" % inventory_tab.total_inventory_slots)
	print("========== TEST SETUP COMPLETE ==========\n")

func after_each():
	print("\n========== TEST CLEANUP ==========")
	if test_scene:
		test_scene.queue_free()
	print("========== TEST CLEANUP COMPLETE ==========\n")

func test_bag_removal_with_insufficient_space():
	"""
	Test principale: Verifica che la bag NON venga rimossa quando non c'è abbastanza spazio
	e che NON vada in posizione 0,0
	"""
	print("\n========== TEST: Bag Removal With Insufficient Space ==========")

	# STEP 1: Verify starter bag is equipped (20 slots)
	var bag_slot_0 = inventory_tab.bag_slot_0
	assert_not_null(bag_slot_0.equipped_bag, "Starter bag should be equipped in slot 0")
	assert_eq(inventory_tab.total_inventory_slots, 20, "Should have 20 slots from starter bag")
	print("[STEP 1] ✅ Starter bag equipped: 20 slots")

	# STEP 2: Equip a second bag in slot 1 (20 more slots)
	var second_bag = _create_test_bag("test_bag", 20)
	assert_not_null(second_bag, "Second bag should be created")

	# Add to inventory first
	inventory_tab.items_layer.add_child(second_bag)
	second_bag.position = Vector2(0, 0)

	# Simulate drag and drop to bag slot 1
	bag_slot_1._equip_bag(second_bag)
	await wait_frames(2)

	assert_not_null(bag_slot_1.equipped_bag, "Second bag should be equipped")
	assert_eq(inventory_tab.total_inventory_slots, 40, "Should have 40 slots total (20+20)")
	assert_eq(inventory_tab.rows, 7, "Grid should have 7 rows (40 slots / 6 cols = 6.67 → 7)")
	print("[STEP 2] ✅ Second bag equipped: 40 slots total, grid = %dx%d" % [inventory_tab.cols, inventory_tab.rows])

	# STEP 3: Fill inventory beyond base capacity (30 slots)
	# Base capacity = 20 slots (starter bag only)
	# We'll add items that occupy rows 0-4 (30 cells), so when we remove the second bag,
	# items in rows 5-6 need to be redistributed but there's no space!
	print("\n[STEP 3] Filling inventory with items...")

	# Add 15 items of size 1x2 (occupying 30 cells total)
	# These will fill rows 0-4 completely (5 rows × 6 cols = 30 cells)
	var items_added = 0
	for row in range(5):  # Rows 0-4
		for col in range(0, 6, 2):  # Cols 0, 2, 4 (3 items per row)
			var item = _create_test_item("test_sword", Vector2i(2, 1))
			var pos = Vector2i(col, row)

			if inventory_tab._place_item_internal(item, pos):
				items_added += 1
				print("  → Added item #%d at (%d, %d)" % [items_added, pos.x, pos.y])
			else:
				print("  → FAILED to add item at (%d, %d)" % [pos.x, pos.y])

	assert_eq(items_added, 15, "Should have added 15 items (2x1 each)")
	print("[STEP 3] ✅ Added %d items filling 30 cells (rows 0-4)" % items_added)

	# STEP 4: Add critical items in row 5 and 6 (beyond base capacity)
	# These items CANNOT fit if we remove the second bag!
	var critical_items = []

	# Row 5: Add 3 items
	for col in range(0, 6, 2):
		var item = _create_test_item("critical_item_%d" % col, Vector2i(2, 1))
		var pos = Vector2i(col, 5)
		if inventory_tab._place_item_internal(item, pos):
			critical_items.append({"item": item, "pos": pos})
			print("  → Added critical item at (%d, %d)" % [pos.x, pos.y])

	# Row 6: Add 3 more items
	for col in range(0, 6, 2):
		var item = _create_test_item("critical_item_row6_%d" % col, Vector2i(2, 1))
		var pos = Vector2i(col, 6)
		if inventory_tab._place_item_internal(item, pos):
			critical_items.append({"item": item, "pos": pos})
			print("  → Added critical item at (%d, %d)" % [pos.x, pos.y])

	assert_eq(critical_items.size(), 6, "Should have 6 critical items in rows 5-6")
	print("[STEP 4] ✅ Added %d critical items in rows 5-6 (beyond base capacity)" % critical_items.size())

	print("\n[STEP 4 SUMMARY]")
	print("  Total items in inventory: %d" % inventory_tab.items_at_position.size())
	print("  Current grid: %dx%d = %d cells" % [inventory_tab.cols, inventory_tab.rows, inventory_tab.cols * inventory_tab.rows])
	print("  After bag removal: 6x4 = 24 cells (20 slots from starter bag)")
	print("  Items occupy: %d cells" % ((items_added + critical_items.size()) * 2))
	print("  → NOT ENOUGH SPACE to redistribute!")

	# STEP 5: Try to remove the second bag
	print("\n[STEP 5] Attempting to remove second bag from slot 1...")

	# First, check can_remove_bag
	var can_remove = inventory_tab.can_remove_bag(1)
	print("  can_remove_bag(1) = %s" % can_remove)

	# BUG TEST: can_remove should be FALSE because there's not enough space!
	assert_false(can_remove, "can_remove_bag should return FALSE (not enough space)")
	print("[STEP 5] ✅ can_remove_bag correctly returns FALSE")

	# STEP 6: Simulate actual removal attempt (drag bag away)
	print("\n[STEP 6] Simulating bag drag away from slot...")

	var bag_before_removal = bag_slot_1.equipped_bag
	assert_not_null(bag_before_removal, "Bag should be in slot before removal attempt")

	# Remove from slot (simulating drag start)
	bag_slot_1.remove_child(bag_before_removal)

	# Add to items_layer (simulating drop to inventory)
	inventory_tab.items_layer.add_child(bag_before_removal)

	# Wait for deferred _handle_bag_removed to execute
	await wait_frames(2)

	# STEP 7: Verify bag was NOT removed (should be back in slot!)
	print("\n[STEP 7] Verifying bag status after removal attempt...")

	var bag_after_attempt = bag_slot_1.equipped_bag
	print("  bag_slot_1.equipped_bag: %s" % (bag_after_attempt.item_id if bag_after_attempt else "null"))

	# BUG CHECK 1: Bag should still be equipped in slot
	assert_not_null(bag_after_attempt, "Bag should still be in slot (removal blocked)")
	assert_eq(bag_after_attempt, bag_before_removal, "Should be the same bag instance")
	print("[STEP 7] ✅ Bag correctly stayed in slot (not removed)")

	# BUG CHECK 2: Bag should NOT be in items_at_position (not in inventory)
	var bag_pos_in_inventory = inventory_tab.get_item_position(bag_before_removal)
	print("  Bag position in inventory: %s" % bag_pos_in_inventory)

	assert_eq(bag_pos_in_inventory, Vector2i(-1, -1), "Bag should NOT be in inventory")
	print("[STEP 7] ✅ Bag is NOT in inventory (correctly)")

	# BUG CHECK 3: Bag should NOT be at position 0,0
	if bag_pos_in_inventory != Vector2i(-1, -1):
		assert_ne(bag_pos_in_inventory, Vector2i(0, 0),
			"BUG: Bag should NOT go to position 0,0!")
		print("[STEP 7] ❌ BUG DETECTED: Bag is at position %s in inventory!" % bag_pos_in_inventory)

	# BUG CHECK 4: Inventory grid should still be 7 rows (not reduced)
	assert_eq(inventory_tab.rows, 7, "Grid should still have 7 rows (40 slots)")
	print("[STEP 7] ✅ Grid size unchanged: %dx%d" % [inventory_tab.cols, inventory_tab.rows])

	# BUG CHECK 5: All critical items should still be in their positions
	print("\n[STEP 7] Verifying critical items are still in place...")
	for critical_data in critical_items:
		var item = critical_data["item"]
		var expected_pos = critical_data["pos"]
		var actual_pos = inventory_tab.get_item_position(item)

		assert_eq(actual_pos, expected_pos,
			"Critical item should still be at %s (found at %s)" % [expected_pos, actual_pos])
		print("  ✅ Item at %s still in place" % expected_pos)

	print("\n========== TEST COMPLETE: BAG REMOVAL BLOCKED CORRECTLY ==========\n")

func test_can_remove_bag_calculation():
	"""
	Test isolato per verificare il calcolo di can_remove_bag
	"""
	print("\n========== TEST: can_remove_bag Calculation ==========")

	# Setup: starter bag (20 slots) + second bag (20 slots) = 40 slots total
	var second_bag = _create_test_bag("test_bag", 20)
	inventory_tab.items_layer.add_child(second_bag)
	bag_slot_1._equip_bag(second_bag)
	await wait_frames(2)

	# Fill exactly 20 cells (base capacity)
	var items_count = 0
	for row in range(4):  # 4 rows
		for col in range(0, 6, 2):  # 3 items per row, size 2x1
			var item = _create_test_item("item_%d_%d" % [row, col], Vector2i(2, 1))
			if inventory_tab._place_item_internal(item, Vector2i(col, row)):
				items_count += 1

	print("[TEST] Added %d items occupying 24 cells" % items_count)
	print("[TEST] Base capacity: 20 slots = 24 cells (4 rows × 6 cols)")
	print("[TEST] Items fit exactly in base capacity")

	# Should be able to remove bag (items fit in base capacity)
	var can_remove_when_fits = inventory_tab.can_remove_bag(1)
	assert_true(can_remove_when_fits, "Should be able to remove bag when items fit")
	print("[TEST] ✅ can_remove_bag = true when items fit in base capacity")

	# Add ONE more item in row 5 (beyond base capacity)
	var overflow_item = _create_test_item("overflow", Vector2i(2, 1))
	inventory_tab._place_item_internal(overflow_item, Vector2i(0, 4))
	print("[TEST] Added 1 overflow item in row 5")

	# Now should NOT be able to remove bag
	var can_remove_when_overflow = inventory_tab.can_remove_bag(1)
	assert_false(can_remove_when_overflow, "Should NOT be able to remove bag with overflow items")
	print("[TEST] ✅ can_remove_bag = false when items overflow base capacity")

	print("========== TEST COMPLETE ==========\n")

# Helper functions

func _create_test_bag(item_id: String, bag_slots: int) -> Item:
	"""Crea una bag di test"""
	var item_scene = load("res://scripts/ui/Item.tscn")
	if item_scene == null:
		fail_test("Failed to load Item.tscn")
		return null

	var bag = item_scene.instantiate()
	bag.item_id = item_id
	bag.item_size = Vector2i(1, 1)
	bag.cell_px = 64

	# Setup bag data
	var bag_data = {
		"name": "Test Bag",
		"type": "Bag",
		"bag_slots": bag_slots,
		"icon": "res://Item_Texture/inventoryPg.png"
	}

	bag.setup_item(item_id, bag_data)

	# Add to GameState items database (for BagSlot to recognize it)
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")
		if gs and "data" in gs and "items" in gs.data:
			gs.data.items[item_id] = bag_data

	return bag

func _create_test_item(item_id: String, item_size: Vector2i) -> Item:
	"""Crea un item di test"""
	var item_scene = load("res://scripts/ui/Item.tscn")
	if item_scene == null:
		fail_test("Failed to load Item.tscn")
		return null

	var item = item_scene.instantiate()
	item.item_id = item_id
	item.item_size = item_size
	item.cell_px = 64

	# Setup item data
	var item_data = {
		"name": "Test Item",
		"type": "Material",
		"size": [item_size.x, item_size.y]
	}

	item.setup_item(item_id, item_data)

	return item
