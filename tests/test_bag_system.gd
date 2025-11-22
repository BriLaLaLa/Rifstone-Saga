extends GutTest

var inventory_tab: InventoryTab
var game_state: Node

func before_each():
	# Get GameState
	game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		gut.p("ERROR: GameState not found!")
		return

	# Clear any existing inventory
	if "inventory_items" in game_state:
		game_state.inventory_items.clear()
	if "equipped_bags" in game_state:
		game_state.equipped_bags.clear()

	# Create InventoryTab
	var scene = load("res://scripts/ui/InventoryTab.tscn")
	inventory_tab = scene.instantiate()
	add_child(inventory_tab)

	# Wait for ready
	await get_tree().process_frame
	await get_tree().process_frame

func after_each():
	if inventory_tab:
		inventory_tab.queue_free()
		inventory_tab = null

func test_starter_bag_is_equipped():
	"""Test that starter bag is automatically equipped in slot 0"""
	gut.p("=== TEST: Starter bag is equipped ===")

	# Check bag_slots array exists
	assert_true(inventory_tab.bag_slots.size() > 0, "Should have bag slots")
	gut.p("Bag slots count: %d" % inventory_tab.bag_slots.size())

	# Check slot 0 is locked
	var slot_0 = inventory_tab.bag_slots[0]
	assert_true(slot_0.is_locked, "Slot 0 should be locked")
	gut.p("Slot 0 is_locked: %s" % slot_0.is_locked)

	# Check slot 0 has equipped bag
	assert_not_null(slot_0.equipped_bag, "Slot 0 should have equipped bag")
	gut.p("Slot 0 equipped_bag: %s" % (slot_0.equipped_bag.item_id if slot_0.equipped_bag else "null"))

	# Check bag is tracked in GameState (not through equipped_bags array anymore)
	# The new architecture uses bag_slots[i].equipped_bag directly

	# Check total slots
	gut.p("Total inventory slots: %d" % inventory_tab.total_inventory_slots)
	assert_eq(inventory_tab.total_inventory_slots, 20, "Should have 20 slots from starter bag")

func test_bag_slot_1_is_available():
	"""Test that slot 1 is available for equipping bags"""
	gut.p("=== TEST: Bag slot 1 is available ===")

	var slot_1 = inventory_tab.bag_slots[1]
	assert_false(slot_1.is_locked, "Slot 1 should NOT be locked")
	assert_null(slot_1.equipped_bag, "Slot 1 should be empty")
	gut.p("Slot 1 is_locked: %s, equipped_bag: %s" % [slot_1.is_locked, slot_1.equipped_bag])

func test_equip_bag_manually():
	"""Test manually equipping a bag in slot 1"""
	gut.p("=== TEST: Manual bag equipping ===")

	# Create a bag item
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	gut.p("Created bag item: %s" % bag_item.item_id)

	# Get slot 1
	var slot_1 = inventory_tab.bag_slots[1]
	gut.p("Slot 1 before equip - is_locked: %s, equipped_bag: %s" % [slot_1.is_locked, slot_1.equipped_bag])

	# Check initial state
	var initial_slots = inventory_tab.total_inventory_slots
	gut.p("Initial total slots: %d" % initial_slots)

	# Simulate equipping - call _equip_bag directly
	slot_1._equip_bag(bag_item)

	# Wait for signals to process
	await get_tree().process_frame
	await get_tree().process_frame

	# Check results
	gut.p("Slot 1 after equip - equipped_bag: %s" % (slot_1.equipped_bag.item_id if slot_1.equipped_bag else "null"))
	gut.p("Total slots after: %d" % inventory_tab.total_inventory_slots)

	assert_not_null(slot_1.equipped_bag, "Slot 1 should have equipped bag")
	assert_eq(slot_1.equipped_bag.item_id, "bag_20slot", "Should be bag_20slot")
	assert_eq(inventory_tab.total_inventory_slots, 40, "Should have 40 slots (20+20)")

func test_bag_signal_flow():
	"""Test that bag_equipped signal properly triggers slot expansion"""
	gut.p("=== TEST: Bag signal flow ===")

	var signal_received = false
	var received_slot_index = -1
	var received_bag_slots = -1

	# Connect to signal
	var slot_1 = inventory_tab.bag_slots[1]
	slot_1.bag_equipped.connect(func(slot_idx, bag_slots):
		signal_received = true
		received_slot_index = slot_idx
		received_bag_slots = bag_slots
		gut.p("Signal received: slot=%d, bag_slots=%d" % [slot_idx, bag_slots])
	)

	# Create and equip bag
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	gut.p("Calling _equip_bag...")
	slot_1._equip_bag(bag_item)

	await get_tree().process_frame

	assert_true(signal_received, "bag_equipped signal should be emitted")
	assert_eq(received_slot_index, 1, "Signal should have slot_index=1")
	assert_eq(received_bag_slots, 20, "Signal should have bag_slots=20")

func test_drag_drop_simulation():
	"""Test simulating drag and drop of a bag"""
	gut.p("=== TEST: Drag drop simulation ===")

	# Create a bag item in inventory first
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	# Add to items_layer (simulating it being in inventory)
	inventory_tab.items_layer.add_child(bag_item)
	bag_item.position = Vector2(0, 0)

	await get_tree().process_frame

	# Get slot 1
	var slot_1 = inventory_tab.bag_slots[1]

	# Create drag data like Item._get_drag_data would
	var drag_data = {
		"type": "inventory_item",
		"item": bag_item,
		"origin": null
	}

	gut.p("Testing _can_drop_data...")
	var can_drop = slot_1._can_drop_data(Vector2.ZERO, drag_data)
	gut.p("_can_drop_data result: %s" % can_drop)
	assert_true(can_drop, "Should be able to drop bag on slot 1")

	gut.p("Testing _drop_data...")
	var initial_slots = inventory_tab.total_inventory_slots
	gut.p("Initial slots: %d" % initial_slots)

	slot_1._drop_data(Vector2.ZERO, drag_data)

	await get_tree().process_frame
	await get_tree().process_frame

	gut.p("After drop - equipped_bag: %s" % (slot_1.equipped_bag.item_id if slot_1.equipped_bag else "null"))
	gut.p("After drop - total_slots: %d" % inventory_tab.total_inventory_slots)

	assert_not_null(slot_1.equipped_bag, "Bag should be equipped after drop")
	assert_eq(inventory_tab.total_inventory_slots, 40, "Should have 40 slots after equipping second bag")

func test_count_equipped_bags_of_type():
	"""Test the _count_equipped_bags_of_type function"""
	gut.p("=== TEST: Count equipped bags of type ===")

	# Initially should have 1 bag_20slot equipped (starter bag)
	var count = inventory_tab._count_equipped_bags_of_type("bag_20slot")
	gut.p("Initial count of bag_20slot: %d" % count)
	assert_eq(count, 1, "Should have 1 bag_20slot equipped initially")

	# Equip another bag in slot 1
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	var slot_1 = inventory_tab.bag_slots[1]
	slot_1._equip_bag(bag_item)

	await get_tree().process_frame

	count = inventory_tab._count_equipped_bags_of_type("bag_20slot")
	gut.p("Count after equipping second bag: %d" % count)
	assert_eq(count, 2, "Should have 2 bag_20slot equipped after adding second")

func test_get_bag_slots_from_item():
	"""Test that _get_bag_slots correctly reads bag_slots from items.json"""
	gut.p("=== TEST: Get bag slots from item data ===")

	# Check that bag_20slot exists in items.json and has bag_slots=20
	var item_data = inventory_tab._get_item_data("bag_20slot")
	gut.p("bag_20slot data: %s" % item_data)

	assert_false(item_data.is_empty(), "bag_20slot should exist in items.json")
	assert_true(item_data.has("bag_slots"), "bag_20slot should have bag_slots field")
	assert_eq(item_data.get("bag_slots", 0), 20, "bag_20slot should have 20 slots")

func test_bag_removal_preserves_items():
	"""Test that removing a bag preserves inventory items including the bag itself"""
	gut.p("=== TEST: Bag removal preserves items ===")

	# First equip a second bag
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	var slot_1 = inventory_tab.bag_slots[1]
	slot_1._equip_bag(bag_item)

	await get_tree().process_frame
	await get_tree().process_frame

	gut.p("After equipping second bag - total_slots: %d" % inventory_tab.total_inventory_slots)
	assert_eq(inventory_tab.total_inventory_slots, 40, "Should have 40 slots after equipping")

	# Count items before removal
	var items_before = inventory_tab.items_at_position.size()
	gut.p("Items in inventory before removal: %d" % items_before)

	# Now remove the bag (drag it back to inventory)
	# Simulate what happens when bag is unequipped
	slot_1._unequip_current_bag()

	await get_tree().process_frame
	await get_tree().process_frame

	gut.p("After removing second bag - total_slots: %d" % inventory_tab.total_inventory_slots)
	gut.p("Items in inventory after removal: %d" % inventory_tab.items_at_position.size())

	assert_eq(inventory_tab.total_inventory_slots, 20, "Should have 20 slots after removing bag")

	# The bag should now be in the inventory
	var bag_found = false
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		if is_instance_valid(item) and item.item_id == "bag_20slot":
			bag_found = true
			gut.p("Found bag at position: %s" % pos)
			break

	assert_true(bag_found, "The removed bag should be in the inventory")

func test_cannot_remove_bag_if_items_dont_fit():
	"""Test that bag cannot be removed if items would be outside the smaller grid"""
	gut.p("=== TEST: Cannot remove bag if items don't fit ===")

	# First equip a second bag to have 40 slots (7 rows)
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	var slot_1 = inventory_tab.bag_slots[1]
	slot_1._equip_bag(bag_item)

	await get_tree().process_frame
	await get_tree().process_frame

	gut.p("Total slots: %d, rows: %d" % [inventory_tab.total_inventory_slots, inventory_tab.rows])
	assert_eq(inventory_tab.total_inventory_slots, 40, "Should have 40 slots")

	# Place an item in the last row (row 6, which is index 6)
	# With 40 slots / 6 cols = ~7 rows (0-6)
	var test_item: Item = item_scene.instantiate()
	test_item.item_id = "test_item"
	test_item.item_size = Vector2i(1, 1)

	# Place at row 5 (which won't exist in 20-slot grid with 4 rows: 0-3)
	var far_position = Vector2i(0, 5)
	inventory_tab._place_item_internal(test_item, far_position)

	await get_tree().process_frame

	gut.p("Placed test item at position: %s" % far_position)
	gut.p("Current rows: %d" % inventory_tab.rows)

	# Check if bag can be removed - should be FALSE because item is in row 5
	var can_remove = inventory_tab.can_remove_bag(1)
	gut.p("can_remove_bag(1): %s" % can_remove)

	assert_false(can_remove, "Should NOT be able to remove bag - item at row 5 won't fit in 4-row grid")

func test_items_stay_in_position_after_bag_removal():
	"""Test that items stay in their exact positions after bag removal (no rearrange)"""
	gut.p("=== TEST: Items stay in position after bag removal ===")

	# Equip second bag
	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	var slot_1 = inventory_tab.bag_slots[1]
	slot_1._equip_bag(bag_item)

	await get_tree().process_frame
	await get_tree().process_frame

	# Place items at specific positions
	var positions_before: Dictionary = {}
	var test_positions = [Vector2i(2, 1), Vector2i(4, 2), Vector2i(1, 3)]

	for i in range(test_positions.size()):
		var test_item: Item = item_scene.instantiate()
		test_item.item_id = "position_test_%d" % i
		test_item.item_size = Vector2i(1, 1)
		inventory_tab._place_item_internal(test_item, test_positions[i])
		positions_before[test_item.item_id] = test_positions[i]
		gut.p("Placed %s at %s" % [test_item.item_id, test_positions[i]])

	await get_tree().process_frame

	# Remove the second bag
	slot_1._unequip_current_bag()

	await get_tree().process_frame
	await get_tree().process_frame

	# Check that items are still at their original positions
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		if is_instance_valid(item) and item.item_id.begins_with("position_test_"):
			var expected_pos = positions_before.get(item.item_id)
			gut.p("Item %s: expected %s, actual %s" % [item.item_id, expected_pos, pos])
			assert_eq(pos, expected_pos, "Item should stay at original position")

func test_complete_bag_workflow():
	"""
	Test completo workflow bag:
	1. Spawn bag nell'inventario
	2. Equip bag nello slot
	3. Sposta item nei nuovi slot
	4. Unequip bag e verifica comportamento
	"""
	gut.p("=== TEST: Complete bag workflow ===")

	# STEP 1: Spawn bag in inventory
	gut.p("\n--- STEP 1: Spawn bag in inventory ---")

	# First, clear all items from inventory to start fresh
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		if is_instance_valid(item):
			inventory_tab._remove_item_if_exists(item)

	await get_tree().process_frame

	var item_scene = load("res://scripts/ui/Item.tscn")
	var bag_item: Item = item_scene.instantiate()
	bag_item.item_id = "bag_20slot"
	bag_item.item_size = Vector2i(1, 1)

	# Find first free position
	var bag_pos = inventory_tab._find_next_free_position(Vector2i(0, 0), bag_item.item_size)
	gut.p("Found free position for bag: %s" % bag_pos)

	var placed = inventory_tab.place_item(bag_item, bag_pos)
	assert_true(placed, "Bag should be placed in inventory")
	gut.p("✓ Bag spawned at position %s" % bag_pos)

	await get_tree().process_frame

	# Verify bag is in inventory
	var bag_in_inv = inventory_tab.get_item_at(bag_pos)
	assert_not_null(bag_in_inv, "Bag should be in inventory grid")
	assert_eq(bag_in_inv.item_id, "bag_20slot", "Should be the correct bag")
	gut.p("✓ Bag verified in inventory: %s" % bag_in_inv.item_id)

	var initial_slots = inventory_tab.total_inventory_slots
	var initial_rows = inventory_tab.rows
	gut.p("Initial state: %d slots, %d rows" % [initial_slots, initial_rows])

	# STEP 2: Equip bag in slot
	gut.p("\n--- STEP 2: Equip bag in slot ---")
	var slot_1 = inventory_tab.bag_slots[1]

	# Simulate drag & drop
	var drag_data = {
		"type": "inventory_item",
		"item": bag_item,
		"origin": null
	}

	slot_1._drop_data(Vector2.ZERO, drag_data)

	await get_tree().process_frame
	await get_tree().process_frame

	# Verify bag is equipped
	assert_not_null(slot_1.equipped_bag, "Bag should be equipped")
	assert_eq(slot_1.equipped_bag.item_id, "bag_20slot", "Correct bag equipped")
	gut.p("✓ Bag equipped in slot 1: %s" % slot_1.equipped_bag.item_id)

	# Verify inventory expanded
	var expanded_slots = inventory_tab.total_inventory_slots
	var expanded_rows = inventory_tab.rows
	gut.p("After equip: %d slots (+%d), %d rows (+%d)" %
		[expanded_slots, expanded_slots - initial_slots, expanded_rows, expanded_rows - initial_rows])
	assert_eq(expanded_slots, 40, "Should have 40 total slots (20+20)")

	# STEP 3: Place item in new slots (row that didn't exist before)
	gut.p("\n--- STEP 3: Place item in new slots ---")
	var test_item: Item = item_scene.instantiate()
	test_item.item_id = "test_item_in_new_row"
	test_item.item_size = Vector2i(1, 1)

	# Place in row 5 (which exists with 40 slots but not with 20)
	# With 20 slots: 4 rows (0-3)
	# With 40 slots: 7 rows (0-6)
	var item_pos = Vector2i(2, 5)
	placed = inventory_tab.place_item(test_item, item_pos)
	assert_true(placed, "Item should be placed in new row")
	gut.p("✓ Item placed at row 5 (new row): %s" % item_pos)

	await get_tree().process_frame

	# Verify item is there
	var item_in_inv = inventory_tab.get_item_at(item_pos)
	assert_not_null(item_in_inv, "Item should be at position")
	assert_eq(item_in_inv.item_id, "test_item_in_new_row", "Should be correct item")
	gut.p("✓ Item verified in inventory at %s" % item_pos)

	# STEP 4: Try to remove bag - should FAIL because item in row 5
	gut.p("\n--- STEP 4: Try to remove bag with item in new row ---")
	var can_remove = inventory_tab.can_remove_bag(1)
	gut.p("can_remove_bag(1) = %s" % can_remove)
	assert_false(can_remove, "Should NOT be able to remove bag - item at row 5 won't fit")
	gut.p("✓ Bag removal correctly blocked")

	# STEP 5: Move item to safe position and try again
	gut.p("\n--- STEP 5: Move item to safe position and remove bag ---")
	# Remove item from row 5
	inventory_tab._remove_item_if_exists(test_item)

	# Place it in row 2 (safe for 20-slot grid)
	var safe_pos = Vector2i(3, 2)
	placed = inventory_tab.place_item(test_item, safe_pos)
	assert_true(placed, "Item should be placed in safe position")
	gut.p("✓ Item moved to safe position: %s" % safe_pos)

	await get_tree().process_frame

	# Now try to remove bag - should SUCCEED
	can_remove = inventory_tab.can_remove_bag(1)
	gut.p("can_remove_bag(1) = %s" % can_remove)
	assert_true(can_remove, "Should be able to remove bag now")

	# Actually remove the bag
	slot_1._unequip_current_bag()

	await get_tree().process_frame
	await get_tree().process_frame

	# Verify bag is unequipped
	assert_null(slot_1.equipped_bag, "Bag should be unequipped")
	gut.p("✓ Bag unequipped from slot 1")

	# Verify inventory shrunk back
	var final_slots = inventory_tab.total_inventory_slots
	var final_rows = inventory_tab.rows
	gut.p("After unequip: %d slots, %d rows" % [final_slots, final_rows])
	assert_eq(final_slots, 20, "Should be back to 20 slots")
	assert_eq(final_rows, 4, "Should be back to 4 rows")

	# Verify item stayed in safe position
	var item_after = inventory_tab.get_item_at(safe_pos)
	assert_not_null(item_after, "Item should still be at safe position")
	assert_eq(item_after.item_id, "test_item_in_new_row", "Should be same item")
	gut.p("✓ Item remained at safe position %s" % safe_pos)

	# Verify bag returned to inventory
	var bag_found = false
	for pos in inventory_tab.items_at_position.keys():
		var item = inventory_tab.items_at_position[pos]
		if is_instance_valid(item) and item.item_id == "bag_20slot":
			bag_found = true
			gut.p("✓ Bag returned to inventory at position: %s" % pos)
			break
	assert_true(bag_found, "Bag should be back in inventory")

	gut.p("\n=== ✅ Complete workflow test PASSED ===")

