extends GutTest

## Complete Quest Flow Integration Test
## Tests the full quest cycle: accept -> combat -> kill/collect -> turn in

var quest_system: Node
var game_state: Node
var slot_manager: Node


func before_all():
	"""Setup before all tests"""
	# Get autoloads
	if has_node("/root/QuestSystem"):
		quest_system = get_node("/root/QuestSystem")
	else:
		fail_test("QuestSystem autoload not found")

	if has_node("/root/GameState"):
		game_state = get_node("/root/GameState")
	else:
		fail_test("GameState autoload not found")

	# SlotManager might not be autoloaded, check both
	if has_node("/root/SlotManager"):
		slot_manager = get_node("/root/SlotManager")
	else:
		print("[TEST] SlotManager not found as autoload, will create instance")


func before_each():
	"""Reset quest system before each test"""
	# Reset all quests to available
	for quest in quest_system.all_quests:
		quest.reset()

	quest_system.active_quests.clear()
	quest_system.completed_quests.clear()
	quest_system.available_quests.clear()

	# Re-populate available quests
	for quest in quest_system.all_quests:
		quest_system.available_quests.append(quest)


func test_complete_kill_quest_flow():
	"""Test full flow: accept quest -> kill enemies -> turn in"""
	print("\n[TEST] ========== KILL QUEST FLOW ==========")

	# STEP 1: Find a kill quest
	var kill_quest: Quest = null
	for quest in quest_system.available_quests:
		for obj in quest.objectives:
			if obj.type == QuestObjective.ObjectiveType.KILL:
				kill_quest = quest
				break
		if kill_quest:
			break

	assert_not_null(kill_quest, "Should find a kill quest")
	print("[TEST] STEP 1: Found kill quest: %s" % kill_quest.title)

	var kill_objective = kill_quest.objectives[0]
	print("[TEST]   Objective: %s (target: %s, count: %d)" %
		  [kill_objective.description, kill_objective.target_id, kill_objective.target_count])

	# STEP 2: Accept the quest
	assert_eq(kill_quest.status, Quest.QuestStatus.AVAILABLE, "Quest should be AVAILABLE")
	quest_system.accept_quest(kill_quest)
	assert_eq(kill_quest.status, Quest.QuestStatus.ACTIVE, "Quest should be ACTIVE after accept")
	assert_true(quest_system.active_quests.has(kill_quest), "Quest should be in active_quests")
	assert_false(quest_system.available_quests.has(kill_quest), "Quest should NOT be in available_quests")
	print("[TEST] STEP 2: Quest accepted successfully")

	# STEP 3: Simulate killing enemies
	var target_enemy = kill_objective.target_id
	var target_count = kill_objective.target_count
	print("[TEST] STEP 3: Simulating combat - killing %d %s..." % [target_count, target_enemy])

	for i in range(target_count):
		# Simulate enemy death by emitting the signal
		var enemy_data = {
			"type": target_enemy,
			"name": target_enemy.capitalize(),
			"level": 1
		}
		var death_position = Vector2(100, 100)

		# Trigger the quest system's enemy killed handler
		quest_system._on_enemy_killed(enemy_data, death_position)

		print("[TEST]   Killed %d/%d %s - Progress: %s" %
			  [i + 1, target_count, target_enemy, kill_objective.get_progress_string()])

	# STEP 4: Verify objective completion
	assert_true(kill_objective.is_complete(), "Kill objective should be complete")
	assert_eq(kill_objective.current_progress, target_count, "Progress should equal target")
	print("[TEST] STEP 4: Objective completed!")

	# STEP 5: Update quest status
	kill_quest.update_status()
	assert_eq(kill_quest.status, Quest.QuestStatus.READY_TO_TURN_IN,
			  "Quest should be READY_TO_TURN_IN")
	print("[TEST] STEP 5: Quest ready to turn in")

	# STEP 6: Turn in quest
	var initial_gold = game_state.resources.get("gold", 0)
	quest_system.turn_in_quest(kill_quest)

	assert_eq(kill_quest.status, Quest.QuestStatus.COMPLETED, "Quest should be COMPLETED")
	assert_true(quest_system.completed_quests.has(kill_quest), "Quest should be in completed_quests")
	assert_false(quest_system.active_quests.has(kill_quest), "Quest should NOT be in active_quests")

	var final_gold = game_state.resources.get("gold", 0)
	var expected_gold = initial_gold + kill_quest.reward_gold
	assert_eq(final_gold, expected_gold, "Should receive gold reward")

	print("[TEST] STEP 6: Quest turned in successfully!")
	print("[TEST]   Gold: %d → %d (+%d)" % [initial_gold, final_gold, kill_quest.reward_gold])
	print("[TEST] ========== KILL QUEST FLOW COMPLETE ==========\n")


func test_complete_collect_quest_flow():
	"""Test full flow: accept quest -> collect items -> turn in"""
	print("\n[TEST] ========== COLLECT QUEST FLOW ==========")

	# STEP 1: Find a collect quest
	var collect_quest: Quest = null
	for quest in quest_system.available_quests:
		for obj in quest.objectives:
			if obj.type == QuestObjective.ObjectiveType.COLLECT:
				collect_quest = quest
				break
		if collect_quest:
			break

	assert_not_null(collect_quest, "Should find a collect quest")
	print("[TEST] STEP 1: Found collect quest: %s" % collect_quest.title)

	var collect_objective = collect_quest.objectives[0]
	print("[TEST]   Objective: %s (target: %s, count: %d)" %
		  [collect_objective.description, collect_objective.target_id, collect_objective.target_count])

	# STEP 2: Accept the quest
	quest_system.accept_quest(collect_quest)
	assert_eq(collect_quest.status, Quest.QuestStatus.ACTIVE, "Quest should be ACTIVE")
	print("[TEST] STEP 2: Quest accepted successfully")

	# STEP 3: Store initial inventory state
	var target_item = collect_objective.target_id
	var target_count = collect_objective.target_count
	var initial_item_count = game_state.inventory.get(target_item, 0)

	print("[TEST] STEP 3: Simulating item collection...")
	print("[TEST]   Initial %s count: %d" % [target_item, initial_item_count])

	# STEP 4: Simulate collecting items
	for i in range(target_count):
		# Add item to inventory
		game_state._add_item(target_item, 1)

		# The quest system listens to on_inventory_changed signal
		# which is emitted by _add_item()

		print("[TEST]   Collected %d/%d %s - Progress: %s" %
			  [i + 1, target_count, target_item, collect_objective.get_progress_string()])

		# Small delay to allow signal processing
		await get_tree().process_frame

	# STEP 5: Verify objective completion
	assert_true(collect_objective.is_complete(), "Collect objective should be complete")
	assert_eq(collect_objective.current_progress, target_count, "Progress should equal target")

	var final_item_count = game_state.inventory.get(target_item, 0)
	var expected_count = initial_item_count + target_count
	assert_eq(final_item_count, expected_count, "Inventory should have collected items")

	print("[TEST] STEP 4: Objective completed!")
	print("[TEST]   %s: %d → %d (+%d)" % [target_item, initial_item_count, final_item_count, target_count])

	# STEP 6: Update quest status
	collect_quest.update_status()
	assert_eq(collect_quest.status, Quest.QuestStatus.READY_TO_TURN_IN,
			  "Quest should be READY_TO_TURN_IN")
	print("[TEST] STEP 5: Quest ready to turn in")

	# STEP 7: Turn in quest
	var initial_gold = game_state.resources.get("gold", 0)
	quest_system.turn_in_quest(collect_quest)

	assert_eq(collect_quest.status, Quest.QuestStatus.COMPLETED, "Quest should be COMPLETED")

	var final_gold = game_state.resources.get("gold", 0)
	var expected_gold = initial_gold + collect_quest.reward_gold
	assert_eq(final_gold, expected_gold, "Should receive gold reward")

	print("[TEST] STEP 6: Quest turned in successfully!")
	print("[TEST]   Gold: %d → %d (+%d)" % [initial_gold, final_gold, collect_quest.reward_gold])
	print("[TEST] ========== COLLECT QUEST FLOW COMPLETE ==========\n")


func test_multistep_quest_flow():
	"""Test quest with multiple objectives (kill + collect)"""
	print("\n[TEST] ========== MULTI-STEP QUEST FLOW ==========")

	# STEP 1: Find multi-step quest (has both kill and collect objectives)
	var multi_quest: Quest = null
	for quest in quest_system.available_quests:
		var has_kill = false
		var has_collect = false
		for obj in quest.objectives:
			if obj.type == QuestObjective.ObjectiveType.KILL:
				has_kill = true
			if obj.type == QuestObjective.ObjectiveType.COLLECT:
				has_collect = true
		if has_kill and has_collect:
			multi_quest = quest
			break

	if multi_quest == null:
		print("[TEST] No multi-step quest found, skipping test")
		return

	print("[TEST] STEP 1: Found multi-step quest: %s" % multi_quest.title)
	for i in range(multi_quest.objectives.size()):
		var obj = multi_quest.objectives[i]
		print("[TEST]   Objective %d: %s" % [i + 1, obj.description])

	# STEP 2: Accept quest
	quest_system.accept_quest(multi_quest)
	print("[TEST] STEP 2: Quest accepted")

	# STEP 3: Complete each objective
	for i in range(multi_quest.objectives.size()):
		var obj = multi_quest.objectives[i]
		print("[TEST] STEP 3.%d: Completing objective: %s" % [i + 1, obj.description])

		if obj.type == QuestObjective.ObjectiveType.KILL:
			# Simulate kills
			for j in range(obj.target_count):
				var enemy_data = {"type": obj.target_id, "name": obj.target_id, "level": 1}
				quest_system._on_enemy_killed(enemy_data, Vector2.ZERO)
			print("[TEST]   Killed %d %s" % [obj.target_count, obj.target_id])

		elif obj.type == QuestObjective.ObjectiveType.COLLECT:
			# Simulate collection
			for j in range(obj.target_count):
				game_state._add_item(obj.target_id, 1)
				await get_tree().process_frame
			print("[TEST]   Collected %d %s" % [obj.target_count, obj.target_id])

		assert_true(obj.is_complete(), "Objective %d should be complete" % (i + 1))

	# STEP 4: Verify all objectives complete
	assert_true(multi_quest.are_all_objectives_complete(), "All objectives should be complete")
	multi_quest.update_status()
	assert_eq(multi_quest.status, Quest.QuestStatus.READY_TO_TURN_IN,
			  "Quest should be READY_TO_TURN_IN")
	print("[TEST] STEP 4: All objectives completed!")

	# STEP 5: Turn in
	quest_system.turn_in_quest(multi_quest)
	assert_eq(multi_quest.status, Quest.QuestStatus.COMPLETED, "Quest should be COMPLETED")
	print("[TEST] STEP 5: Multi-step quest completed!")
	print("[TEST] ========== MULTI-STEP QUEST FLOW COMPLETE ==========\n")


func test_quest_signals_emitted():
	"""Test that quest signals are properly emitted during flow"""
	print("\n[TEST] ========== QUEST SIGNALS TEST ==========")

	var quest = quest_system.available_quests[0]

	# Watch for signals
	watch_signals(quest_system)

	# Accept quest
	quest_system.accept_quest(quest)
	assert_signal_emitted(quest_system, "quest_accepted", "quest_accepted signal should emit")

	# Complete objective
	if quest.objectives.size() > 0:
		var obj = quest.objectives[0]
		if obj.type == QuestObjective.ObjectiveType.KILL:
			var enemy_data = {"type": obj.target_id, "name": obj.target_id, "level": 1}
			for i in range(obj.target_count):
				quest_system._on_enemy_killed(enemy_data, Vector2.ZERO)
		elif obj.type == QuestObjective.ObjectiveType.COLLECT:
			for i in range(obj.target_count):
				game_state._add_item(obj.target_id, 1)
				await get_tree().process_frame

		assert_signal_emitted(quest_system, "quest_objective_progressed",
							  "quest_objective_progressed signal should emit")

	# Update and check ready signal
	quest.update_status()
	if quest.status == Quest.QuestStatus.READY_TO_TURN_IN:
		assert_signal_emitted(quest_system, "quest_ready_to_turn_in",
							  "quest_ready_to_turn_in signal should emit")

		# Turn in
		quest_system.turn_in_quest(quest)
		assert_signal_emitted(quest_system, "quest_completed",
							  "quest_completed signal should emit")

	print("[TEST] All quest signals emitted correctly")
	print("[TEST] ========== QUEST SIGNALS TEST COMPLETE ==========\n")
