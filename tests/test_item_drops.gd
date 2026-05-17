extends GutTest

## Test Item Drops System
## Verifies that all items from loot tables exist in item database

var item_database: Node
var loot_tables: Array


func before_all():
	"""Setup"""
	if has_node("/root/IData"):
		item_database = get_node("/root/IData")
	else:
		fail_test("ItemDatabase (IData) not found")

	# Load loot tables
	_load_loot_tables()


func _load_loot_tables():
	"""Load loot tables from JSON"""
	var file = FileAccess.open("res://data/loot_tables.json", FileAccess.READ)
	if not file:
		fail_test("Could not open loot_tables.json")
		return

	var json_text = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed is Array:
		loot_tables = parsed
	else:
		fail_test("Invalid loot_tables.json format")


func test_all_loot_table_items_exist_in_database():
	"""Verify all items in loot tables exist in item database"""
	print("\n[TEST] ========== CHECKING LOOT TABLE ITEMS ==========")

	var missing_items = []
	var checked_items = {}  # Track unique items

	for loot_table in loot_tables:
		var table_id = loot_table.get("id", "unknown")
		var drops = loot_table.get("drops", [])

		print("[TEST] Checking loot table: %s (%d drops)" % [table_id, drops.size()])

		for drop in drops:
			var item_id = drop.get("item_id", "")
			if item_id == "":
				continue

			# Skip if already checked
			if checked_items.has(item_id):
				continue

			checked_items[item_id] = true

			# Check if item exists in database
			if not item_database.items.has(item_id):
				missing_items.append({
					"item_id": item_id,
					"loot_table": table_id,
					"chance": drop.get("chance", 0)
				})
				print("[TEST]   ❌ MISSING: %s (chance: %.2f)" % [item_id, drop.get("chance", 0)])
			else:
				print("[TEST]   ✅ Found: %s" % item_id)

	print("\n[TEST] ========== SUMMARY ==========")
	print("[TEST] Total unique items in loot tables: %d" % checked_items.size())
	print("[TEST] Missing from item database: %d" % missing_items.size())

	if missing_items.size() > 0:
		print("\n[TEST] ❌ MISSING ITEMS:")
		for missing in missing_items:
			print("[TEST]   - %s (from %s, chance: %.2f%%)" %
				  [missing.item_id, missing.loot_table, missing.chance * 100])

	assert_eq(missing_items.size(), 0,
			  "All loot table items should exist in item database. Missing: %d" % missing_items.size())


func test_quest_reward_items_exist():
	"""Verify all quest reward items exist in item database"""
	print("\n[TEST] ========== CHECKING QUEST REWARD ITEMS ==========")

	# Load quests
	var file = FileAccess.open("res://data/quests.json", FileAccess.READ)
	if not file:
		print("[TEST] Could not open quests.json, skipping")
		return

	var json_text = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if not parsed is Dictionary or not parsed.has("quests"):
		fail_test("Invalid quests.json format")
		return

	var quests = parsed["quests"]
	var missing_items = []
	var checked_items = {}

	for quest in quests:
		var quest_id = quest.get("id", "unknown")
		var reward_items = quest.get("reward_items", [])

		if reward_items.size() > 0:
			print("[TEST] Checking quest: %s (%d rewards)" % [quest_id, reward_items.size()])

		for item_id in reward_items:
			if checked_items.has(item_id):
				continue

			checked_items[item_id] = true

			if not item_database.items.has(item_id):
				missing_items.append({
					"item_id": item_id,
					"quest_id": quest_id
				})
				print("[TEST]   ❌ MISSING: %s" % item_id)
			else:
				print("[TEST]   ✅ Found: %s" % item_id)

	print("\n[TEST] ========== SUMMARY ==========")
	print("[TEST] Total unique quest reward items: %d" % checked_items.size())
	print("[TEST] Missing from item database: %d" % missing_items.size())

	if missing_items.size() > 0:
		print("\n[TEST] ❌ MISSING QUEST REWARD ITEMS:")
		for missing in missing_items:
			print("[TEST]   - %s (from quest: %s)" % [missing.item_id, missing.quest_id])

	assert_eq(missing_items.size(), 0,
			  "All quest reward items should exist in item database. Missing: %d" % missing_items.size())


func test_simulate_enemy_drops():
	"""Simulate enemy drops and check if items are added to inventory"""
	print("\n[TEST] ========== SIMULATING ENEMY DROPS ==========")

	var game_state = get_node("/root/GameState")
	if not game_state:
		fail_test("GameState not found")
		return

	# Get initial inventory size
	var initial_inventory_size = game_state.inventory.size()
	print("[TEST] Initial inventory size: %d items" % initial_inventory_size)

	# Try to add each loot table item
	var successful_adds = 0
	var failed_adds = []

	for loot_table in loot_tables:
		var drops = loot_table.get("drops", [])
		for drop in drops:
			var item_id = drop.get("item_id", "")
			if item_id == "":
				continue

			# Check if item exists in database
			if not item_database.items.has(item_id):
				print("[TEST] Skipping missing item: %s" % item_id)
				continue

			# Try to add item using GameState method
			var initial_count = game_state.inventory.get(item_id, 0)
			game_state._add_item(item_id, 1)
			var new_count = game_state.inventory.get(item_id, 0)

			if new_count > initial_count:
				successful_adds += 1
				print("[TEST] ✅ Successfully added: %s (%d → %d)" % [item_id, initial_count, new_count])
			else:
				failed_adds.append(item_id)
				print("[TEST] ❌ Failed to add: %s (count unchanged: %d)" % [item_id, initial_count])

	print("\n[TEST] ========== RESULTS ==========")
	print("[TEST] Successful additions: %d" % successful_adds)
	print("[TEST] Failed additions: %d" % failed_adds.size())

	if failed_adds.size() > 0:
		print("[TEST] Failed items:")
		for item_id in failed_adds:
			print("[TEST]   - %s" % item_id)

	# Note: This test is informational, doesn't fail
	# It helps identify which items work with _add_item() and which don't
