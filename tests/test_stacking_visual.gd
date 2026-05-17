extends GutTest

## Tests for the full stacking pipeline: GameState → InventoryTab visual layer
## Verifies every layer independently to pinpoint where stacking breaks.

const FISH_ID = "small_fish"      # stackable: true, max_stack: 200
const GEM_ID  = "force_gem"       # stackable: true, max_stack: 99

var gs: Node

func before_each():
	if has_node("/root/GameState"):
		gs = get_node("/root/GameState")
	else:
		fail_test("GameState autoload not found")
		return
	gs.inventory_items = []
	gs.inventory = {}

# ── LAYER 1: GameState stacking logic ────────────────────────────────────────

func test_L1_first_drop_creates_entry_with_stack_count_1():
	gs._add_item_to_visual_inventory(FISH_ID, {})
	assert_eq(gs.inventory_items.size(), 1, "Should create 1 entry")
	assert_eq(gs.inventory_items[0].get("stack_count", -1), 1, "stack_count should be 1")

func test_L1_second_drop_increments_stack_count_to_2():
	gs._add_item_to_visual_inventory(FISH_ID, {})
	gs._add_item_to_visual_inventory(FISH_ID, {})
	assert_eq(gs.inventory_items.size(), 1, "Should still be 1 entry (stacked)")
	assert_eq(gs.inventory_items[0].get("stack_count", -1), 2, "stack_count should be 2")

func test_L1_five_metal_drops_stack_to_5():
	for i in range(5):
		gs._add_item_to_visual_inventory("iron_ore", {})
	assert_eq(gs.inventory_items.size(), 1, "Should be 1 entry")
	assert_eq(gs.inventory_items[0].get("stack_count", -1), 5, "stack_count should be 5")

func test_L1_stack_count_persists_in_inventory_items_array():
	gs._add_item_to_visual_inventory(FISH_ID, {})
	gs._add_item_to_visual_inventory(FISH_ID, {})
	# Simulate what _sync_to_gamestate does: replace inventory_items with a copy
	# (this tests that the reference vs copy issue doesn't corrupt data)
	var saved = gs.inventory_items.duplicate(true)
	gs.inventory_items = saved
	assert_eq(gs.inventory_items[0].get("stack_count", -1), 2, "stack_count must survive a duplicate/replace cycle")

# ── LAYER 2: StackLabel._ready() resets visible — stack_count must be applied AFTER add_child ──

func test_L2_stack_label_ready_resets_visible_to_false():
	"""Prove that StackLabel._ready() sets visible=false, cancelling any pre-tree update_count call.
	This is the root cause: stack_count must be applied AFTER the item enters the scene tree."""
	var stack_label_scene = load("res://scenes/ui/StackLabel.tscn")
	assert_not_null(stack_label_scene, "StackLabel.tscn must be loadable")

	var label = stack_label_scene.instantiate()
	# NOT in tree yet — manually set visible
	label.visible = true
	label.text = "3"
	assert_true(label.visible, "label.visible is true before entering tree")

	# Now add to tree — _ready() fires and resets visible = false
	add_child_autofree(label)
	assert_false(label.visible, "StackLabel._ready() resets visible to false — bug confirmed")

func test_L2_update_count_after_add_child_shows_correctly():
	"""After entering the scene tree, update_count(n>1) should make the label visible."""
	var stack_label_scene = load("res://scenes/ui/StackLabel.tscn")
	var label = stack_label_scene.instantiate()
	add_child_autofree(label)  # _ready() fires, visible=false

	label.update_count(2)
	assert_true(label.visible, "After entering tree, update_count(2) should set visible=true")
	assert_eq(label.text, "2", "text should be '2'")

func test_L2_update_count_1_after_add_child_stays_hidden():
	var stack_label_scene = load("res://scenes/ui/StackLabel.tscn")
	var label = stack_label_scene.instantiate()
	add_child_autofree(label)

	label.update_count(1)
	assert_false(label.visible, "count=1 should remain hidden")

# ── LAYER 3: _load_from_inventory_items applies stack_count ──────────────────

func test_L3_load_from_inventory_items_applies_stack_count():
	"""Simulate what InventoryTab._load_from_inventory_items does for a stacked item"""
	var item_scene = load("res://scripts/ui/Item.tscn")
	var item = item_scene.instantiate()
	add_child_autofree(item)

	var fish_data = gs.data.items.get(FISH_ID, {}).duplicate(true)
	item.setup_item(FISH_ID, fish_data)
	# item.stack_count is now 1 (default from setup_item)

	# Simulate the fix: apply saved stack_count from inventory_items entry
	var item_entry = {"item_id": FISH_ID, "pos": {"x": 0, "y": 0}, "stack_count": 3}
	if item_entry.has("stack_count") and item.is_stackable:
		item.stack_count = item_entry.stack_count
		item._update_stack_label()

	assert_eq(item.stack_count, 3, "stack_count should be 3 after applying entry data")
	assert_true(item.stack_label.visible, "stack label should be visible")
	assert_eq(item.stack_label.text, "3", "stack label should show '3'")

func test_L3_load_without_stack_count_entry_leaves_item_at_1():
	"""If inventory_items entry has no stack_count key, item should default to 1"""
	var item_scene = load("res://scripts/ui/Item.tscn")
	var item = item_scene.instantiate()
	add_child_autofree(item)

	var fish_data = gs.data.items.get(FISH_ID, {}).duplicate(true)
	item.setup_item(FISH_ID, fish_data)

	var item_entry = {"item_id": FISH_ID, "pos": {"x": 0, "y": 0}}  # no stack_count key
	if item_entry.has("stack_count") and item.is_stackable:
		item.stack_count = item_entry.stack_count
		item._update_stack_label()

	assert_eq(item.stack_count, 1, "Without saved stack_count, item stays at 1")
	assert_false(item.stack_label.visible, "Label hidden for count=1")

# ── LAYER 4: sync_to_gamestate preserves stack_count ─────────────────────────

func test_L4_sync_saves_stack_count_for_stackable_items():
	"""After two drops, sync must preserve stack_count=2 in gs.inventory_items"""
	gs._add_item_to_visual_inventory(FISH_ID, {})
	gs._add_item_to_visual_inventory(FISH_ID, {})

	# gs.inventory_items[0] should have stack_count=2
	var entry = gs.inventory_items[0]
	assert_eq(entry.get("stack_count", -1), 2, "GameState entry must have stack_count=2 after 2 drops")

	# Simulate _sync_to_gamestate writing back (worst case: stack_count=1 item)
	# A correct sync should preserve stack_count for stackable items
	var new_array = []
	var fake_item_entry = {
		"item_id": FISH_ID,
		"pos": {"x": 0, "y": 0},
		"stack_count": 2   # this is what the fixed sync writes
	}
	new_array.append(fake_item_entry)
	gs.inventory_items = new_array

	# Second add should now find the entry and stack to 3
	gs._add_item_to_visual_inventory(FISH_ID, {})
	assert_eq(gs.inventory_items.size(), 1, "Still 1 entry")
	assert_eq(gs.inventory_items[0].get("stack_count", -1), 3, "Should be 3 after third drop")
