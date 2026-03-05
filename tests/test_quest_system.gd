extends GutTest

## Test for Quest System
## Verifies quest loading, progress tracking, and completion

var quest_system: Node


func before_all():
	"""Setup before all tests"""
	# QuestSystem is autoloaded, get reference
	if has_node("/root/QuestSystem"):
		quest_system = get_node("/root/QuestSystem")
	else:
		fail_test("QuestSystem autoload not found")


func test_quest_system_loads():
	"""Test that QuestSystem loads and initializes"""
	assert_not_null(quest_system, "QuestSystem should exist")
	assert_true(quest_system.all_quests.size() > 0, "Should load quests from JSON")
	print("[TEST] Loaded %d quests" % quest_system.all_quests.size())


func test_quest_data_structure():
	"""Test that quests have correct data structure"""
	assert_true(quest_system.all_quests.size() > 0, "Should have quests loaded")

	var quest = quest_system.all_quests[0]
	assert_not_null(quest, "Quest should not be null")
	assert_true(quest.quest_id != "", "Quest should have ID")
	assert_true(quest.title != "", "Quest should have title")
	assert_true(quest.description != "", "Quest should have description")
	assert_true(quest.giver_npc_id != "", "Quest should have NPC giver")
	assert_true(quest.objectives.size() > 0, "Quest should have objectives")

	print("[TEST] Quest structure OK: %s" % quest.title)


func test_quest_objectives():
	"""Test that quest objectives are properly structured"""
	var quest = quest_system.all_quests[0]
	var objective = quest.objectives[0]

	assert_not_null(objective, "Objective should not be null")
	assert_true(objective.target_id != "", "Objective should have target")
	assert_true(objective.target_count > 0, "Objective should have count > 0")
	assert_true(objective.description != "", "Objective should have description")

	print("[TEST] Objective OK: %s" % objective.description)


func test_quest_status_flow():
	"""Test quest status transitions"""
	var quest = quest_system.all_quests[0]

	# Initial status should be AVAILABLE
	assert_eq(quest.status, Quest.QuestStatus.AVAILABLE, "New quest should be AVAILABLE")

	# Accept quest
	quest.accept()
	assert_eq(quest.status, Quest.QuestStatus.ACTIVE, "Accepted quest should be ACTIVE")

	# Complete all objectives
	for objective in quest.objectives:
		objective.current_progress = objective.target_count

	# Update status
	quest.update_status()
	assert_eq(quest.status, Quest.QuestStatus.READY_TO_TURN_IN, "Completed quest should be READY_TO_TURN_IN")

	# Complete quest
	quest.complete()
	assert_eq(quest.status, Quest.QuestStatus.COMPLETED, "Turned in quest should be COMPLETED")

	print("[TEST] Quest status flow OK")


func test_objective_progress():
	"""Test objective progress tracking"""
	var objective = QuestObjective.new()
	objective.type = QuestObjective.ObjectiveType.KILL
	objective.target_id = "lupo"
	objective.target_count = 10
	objective.current_progress = 0

	assert_false(objective.is_complete(), "Objective should not be complete initially")
	assert_eq(objective.get_progress_string(), "0/10", "Progress string should be 0/10")

	# Add progress
	var just_completed = objective.add_progress(5)
	assert_false(just_completed, "Should not be complete after 5/10")
	assert_eq(objective.current_progress, 5, "Progress should be 5")

	# Complete objective
	just_completed = objective.add_progress(5)
	assert_true(just_completed, "Should be complete after 10/10")
	assert_true(objective.is_complete(), "Objective should be complete")

	print("[TEST] Objective progress OK")


func test_get_quests_for_npc():
	"""Test getting quests for specific NPC"""
	# Find a quest with known NPC
	var test_npc_id = ""
	if quest_system.all_quests.size() > 0:
		test_npc_id = quest_system.all_quests[0].giver_npc_id

	var npc_quests = quest_system.get_quests_for_npc(test_npc_id)
	assert_true(npc_quests.size() > 0, "Should find quests for NPC")

	for q in npc_quests:
		assert_eq(q.giver_npc_id, test_npc_id, "All quests should be from same NPC")

	print("[TEST] NPC quest filtering OK")


func test_npc_quest_status():
	"""Test NPC quest status indicator logic"""
	# Test with NPC that has no quests
	var status = quest_system.get_npc_quest_status("nonexistent_npc")
	assert_eq(status, "none", "NPC with no quests should have 'none' status")

	# Test with NPC that has available quest
	if quest_system.available_quests.size() > 0:
		var quest = quest_system.available_quests[0]
		var npc_id = quest.giver_npc_id
		status = quest_system.get_npc_quest_status(npc_id)
		assert_eq(status, "available", "NPC with available quest should have 'available' status")

	print("[TEST] NPC quest status OK")


func test_quest_serialization():
	"""Test quest save/load serialization"""
	var quest = quest_system.all_quests[0]
	quest.accept()

	# Add some progress
	if quest.objectives.size() > 0:
		quest.objectives[0].add_progress(5)

	# Serialize
	var quest_dict = quest.to_dict()
	assert_not_null(quest_dict, "Quest should serialize to dictionary")
	assert_eq(quest_dict["quest_id"], quest.quest_id, "Serialized ID should match")
	assert_eq(quest_dict["status"], quest.status, "Serialized status should match")

	# Deserialize
	var restored_quest = Quest.from_dict(quest_dict)
	assert_not_null(restored_quest, "Should restore quest from dict")
	assert_eq(restored_quest.quest_id, quest.quest_id, "Restored ID should match")
	assert_eq(restored_quest.status, quest.status, "Restored status should match")

	if restored_quest.objectives.size() > 0:
		assert_eq(restored_quest.objectives[0].current_progress,
				  quest.objectives[0].current_progress,
				  "Restored progress should match")

	print("[TEST] Quest serialization OK")


func test_reward_items_array():
	"""Test that reward_items is properly typed as Array[String]"""
	var quest = quest_system.all_quests[0]

	# Check that reward_items is an Array
	assert_true(typeof(quest.reward_items) == TYPE_ARRAY, "reward_items should be an Array")

	# Check that it's properly accessible
	for item in quest.reward_items:
		assert_true(typeof(item) == TYPE_STRING, "Each reward item should be a String")

	print("[TEST] reward_items array type OK")
