extends Node

## QuestSystem - Autoload singleton for managing quests
## Tracks quest progress, handles objectives (kill/collect), and manages quest lifecycle

# Signals
signal quest_accepted(quest: Quest)
signal quest_objective_progressed(quest: Quest, objective: QuestObjective)
signal quest_ready_to_turn_in(quest: Quest)
signal quest_completed(quest: Quest)
signal quests_loaded()

# Quest storage
var all_quests: Array[Quest] = []  # All quests loaded from JSON
var available_quests: Array[Quest] = []
var active_quests: Array[Quest] = []
var completed_quests: Array[Quest] = []

# Inventory tracking for collect objectives
var _previous_inventory: Dictionary = {}

# Data file path
const QUESTS_DATA_PATH = "res://data/quests.json"


func _ready() -> void:
	# Load quest data
	_load_quests_from_json()

	# Connect to game systems
	_connect_to_game_systems()

	print("[QuestSystem] Initialized with %d quests" % all_quests.size())


## Load quests from JSON file
func _load_quests_from_json() -> void:
	if not FileAccess.file_exists(QUESTS_DATA_PATH):
		print("[QuestSystem] ⚠️ Quest data file not found: %s" % QUESTS_DATA_PATH)
		return

	var file = FileAccess.open(QUESTS_DATA_PATH, FileAccess.READ)
	if file == null:
		print("[QuestSystem] ❌ Failed to open quest data file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("[QuestSystem] ❌ Failed to parse JSON: %s" % json.get_error_message())
		return

	var data = json.data
	if not data is Dictionary or not data.has("quests"):
		print("[QuestSystem] ❌ Invalid quest data format")
		return

	# Parse quests
	var quests_array = data["quests"]
	for quest_data in quests_array:
		var quest = _parse_quest_from_json(quest_data)
		if quest:
			all_quests.append(quest)
			available_quests.append(quest)

	print("[QuestSystem] Loaded %d quests from JSON" % all_quests.size())
	quests_loaded.emit()


## Parse a single quest from JSON data
func _parse_quest_from_json(data: Dictionary) -> Quest:
	var quest = Quest.new()
	quest.quest_id = data.get("id", "")
	quest.title = data.get("title", "")
	quest.description = data.get("description", "")
	quest.giver_npc_id = data.get("giver_npc", "")
	quest.reward_gold = data.get("reward_gold", 0)
	quest.reward_xp = data.get("reward_xp", 0)
	quest.reward_items = data.get("reward_items", [])

	# Parse objectives
	var objectives_data = data.get("objectives", [])
	for obj_data in objectives_data:
		var objective = QuestObjective.new()

		var type_string = obj_data.get("type", "kill")
		if type_string == "kill":
			objective.type = QuestObjective.ObjectiveType.KILL
		elif type_string == "collect":
			objective.type = QuestObjective.ObjectiveType.COLLECT

		objective.target_id = obj_data.get("target", "")
		objective.target_count = obj_data.get("count", 1)
		objective.description = obj_data.get("description", "")

		quest.objectives.append(objective)

	return quest


## Connect to game system signals
func _connect_to_game_systems() -> void:
	# Wait for autoloads to be ready
	await get_tree().process_frame

	# Connect to SlotManager for kill tracking
	if has_node("/root/SlotManager"):
		var slot_manager = get_node("/root/SlotManager")
		if not slot_manager.enemy_killed.is_connected(_on_enemy_killed):
			slot_manager.enemy_killed.connect(_on_enemy_killed)
			print("[QuestSystem] Connected to SlotManager.enemy_killed")

	# Connect to GameState for inventory tracking
	if has_node("/root/GameState"):
		var game_state = get_node("/root/GameState")
		if not game_state.on_inventory_changed.is_connected(_on_inventory_changed):
			game_state.on_inventory_changed.connect(_on_inventory_changed)
			print("[QuestSystem] Connected to GameState.on_inventory_changed")

			# Initialize previous inventory
			_previous_inventory = game_state.inventory.duplicate()


## Handle enemy killed event
func _on_enemy_killed(enemy_data: Dictionary, _death_position: Vector2) -> void:
	var enemy_id = enemy_data.get("type", "")
	if enemy_id == "":
		return

	# Update kill objectives in active quests
	for quest in active_quests:
		for objective in quest.objectives:
			if objective.type == QuestObjective.ObjectiveType.KILL and objective.target_id == enemy_id:
				if not objective.is_complete():
					var just_completed = objective.add_progress(1)
					quest_objective_progressed.emit(quest, objective)
					print("[QuestSystem] Kill progress: %s - %s" % [quest.title, objective.get_progress_string()])

					if just_completed:
						print("[QuestSystem] ✅ Objective complete: %s" % objective.description)

		# Check if all objectives complete
		quest.update_status()
		if quest.status == Quest.QuestStatus.READY_TO_TURN_IN:
			quest_ready_to_turn_in.emit(quest)
			print("[QuestSystem] 🎉 Quest ready to turn in: %s" % quest.title)


## Handle inventory changed event
func _on_inventory_changed() -> void:
	if not has_node("/root/GameState"):
		return

	var game_state = get_node("/root/GameState")
	var current_inventory = game_state.inventory

	# Find items that increased
	for item_id in current_inventory:
		var previous_count = _previous_inventory.get(item_id, 0)
		var current_count = current_inventory.get(item_id, 0)
		var gained = current_count - previous_count

		if gained > 0:
			_check_collect_objectives(item_id, gained)

	# Update previous inventory
	_previous_inventory = current_inventory.duplicate()


## Check collect objectives for item collection
func _check_collect_objectives(item_id: String, amount: int) -> void:
	for quest in active_quests:
		for objective in quest.objectives:
			if objective.type == QuestObjective.ObjectiveType.COLLECT and objective.target_id == item_id:
				if not objective.is_complete():
					var just_completed = objective.add_progress(amount)
					quest_objective_progressed.emit(quest, objective)
					print("[QuestSystem] Collect progress: %s - %s" % [quest.title, objective.get_progress_string()])

					if just_completed:
						print("[QuestSystem] ✅ Objective complete: %s" % objective.description)

		# Check if all objectives complete
		quest.update_status()
		if quest.status == Quest.QuestStatus.READY_TO_TURN_IN:
			quest_ready_to_turn_in.emit(quest)
			print("[QuestSystem] 🎉 Quest ready to turn in: %s" % quest.title)


## Get all quests for a specific NPC
func get_quests_for_npc(npc_id: String) -> Array[Quest]:
	var npc_quests: Array[Quest] = []

	# Available quests
	for quest in available_quests:
		if quest.giver_npc_id == npc_id:
			npc_quests.append(quest)

	# Active quests (to show turn-in dialog)
	for quest in active_quests:
		if quest.giver_npc_id == npc_id:
			npc_quests.append(quest)

	return npc_quests


## Get quest status for NPC indicator
## Returns: "available", "in_progress", "ready", or "none"
func get_npc_quest_status(npc_id: String) -> String:
	# Check for ready to turn in quests first (highest priority)
	for quest in active_quests:
		if quest.giver_npc_id == npc_id and quest.status == Quest.QuestStatus.READY_TO_TURN_IN:
			return "ready"

	# Check for active quests
	for quest in active_quests:
		if quest.giver_npc_id == npc_id:
			return "in_progress"

	# Check for available quests
	for quest in available_quests:
		if quest.giver_npc_id == npc_id:
			return "available"

	return "none"


## Accept a quest
func accept_quest(quest: Quest) -> void:
	if quest.status != Quest.QuestStatus.AVAILABLE:
		print("[QuestSystem] ⚠️ Cannot accept quest, status: %d" % quest.status)
		return

	quest.accept()
	available_quests.erase(quest)
	active_quests.append(quest)
	quest_accepted.emit(quest)
	print("[QuestSystem] ✅ Quest accepted: %s" % quest.title)


## Turn in a quest (complete and give rewards)
func turn_in_quest(quest: Quest) -> void:
	if quest.status != Quest.QuestStatus.READY_TO_TURN_IN:
		print("[QuestSystem] ⚠️ Cannot turn in quest, status: %d" % quest.status)
		return

	quest.complete()
	active_quests.erase(quest)
	completed_quests.append(quest)

	# Give rewards
	_give_quest_rewards(quest)

	quest_completed.emit(quest)
	print("[QuestSystem] 🎉 Quest completed: %s" % quest.title)


## Give quest rewards to player
func _give_quest_rewards(quest: Quest) -> void:
	if not has_node("/root/GameState"):
		return

	var game_state = get_node("/root/GameState")

	# Gold reward
	if quest.reward_gold > 0:
		game_state.add_gold(quest.reward_gold)
		print("[QuestSystem] Rewarded %d gold" % quest.reward_gold)

	# XP reward
	if quest.reward_xp > 0:
		# TODO: Add XP system when implemented
		print("[QuestSystem] Rewarded %d XP (not yet implemented)" % quest.reward_xp)

	# Item rewards
	for item_id in quest.reward_items:
		var item_data = ItemDatabase.get_item(item_id)
		if not item_data.is_empty():
			game_state._add_item_to_visual_inventory(item_id, item_data)
			print("[QuestSystem] Rewarded item: %s" % item_id)


## Get quest by ID
func get_quest_by_id(quest_id: String) -> Quest:
	for quest in all_quests:
		if quest.quest_id == quest_id:
			return quest
	return null


## Serialize quests for save
func to_dict() -> Dictionary:
	var active_quests_data = []
	for quest in active_quests:
		active_quests_data.append(quest.to_dict())

	var completed_quest_ids = []
	for quest in completed_quests:
		completed_quest_ids.append(quest.quest_id)

	return {
		"active_quests": active_quests_data,
		"completed_quest_ids": completed_quest_ids
	}


## Deserialize quests from save
func from_dict(data: Dictionary) -> void:
	# Clear current state
	active_quests.clear()
	completed_quests.clear()
	available_quests.clear()

	# Restore completed quests
	var completed_ids = data.get("completed_quest_ids", [])
	for quest_id in completed_ids:
		var quest = get_quest_by_id(quest_id)
		if quest:
			quest.status = Quest.QuestStatus.COMPLETED
			completed_quests.append(quest)

	# Restore active quests
	var active_quests_data = data.get("active_quests", [])
	for quest_data in active_quests_data:
		var quest = Quest.from_dict(quest_data)
		active_quests.append(quest)

	# Rebuild available quests
	for quest in all_quests:
		if quest.status == Quest.QuestStatus.AVAILABLE:
			available_quests.append(quest)

	print("[QuestSystem] Loaded save: %d active, %d completed quests" % [active_quests.size(), completed_quests.size()])
