extends Resource
class_name Quest

## Quest resource
## Represents a complete quest with objectives and rewards

enum QuestStatus {
	AVAILABLE,        # Quest is available to accept from NPC
	ACTIVE,           # Quest is accepted and in progress
	READY_TO_TURN_IN, # All objectives complete, ready to claim rewards
	COMPLETED         # Quest turned in, rewards claimed
}

## Unique quest ID
@export var quest_id: String = ""

## Display name of the quest
@export var title: String = ""

## Quest description shown in dialog
@export var description: String = ""

## ID of the NPC that gives this quest
@export var giver_npc_id: String = ""

## Array of quest objectives
@export var objectives: Array[QuestObjective] = []

## Gold reward for completing the quest
@export var reward_gold: int = 0

## XP reward for completing the quest
@export var reward_xp: int = 0

## Item rewards (array of item IDs)
@export var reward_items: Array[String] = []

## Current status of this quest
var status: QuestStatus = QuestStatus.AVAILABLE


## Check if all objectives are complete
func are_all_objectives_complete() -> bool:
	if objectives.is_empty():
		return false

	for objective in objectives:
		if not objective.is_complete():
			return false

	return true


## Update quest status based on objectives
func update_status() -> void:
	if status == QuestStatus.ACTIVE:
		if are_all_objectives_complete():
			status = QuestStatus.READY_TO_TURN_IN


## Accept the quest (change status from AVAILABLE to ACTIVE)
func accept() -> void:
	if status == QuestStatus.AVAILABLE:
		status = QuestStatus.ACTIVE
		print("[Quest] Accepted quest: %s" % title)


## Complete the quest (change status from READY_TO_TURN_IN to COMPLETED)
func complete() -> void:
	if status == QuestStatus.READY_TO_TURN_IN:
		status = QuestStatus.COMPLETED
		print("[Quest] Completed quest: %s" % title)


## Reset quest progress
func reset() -> void:
	status = QuestStatus.AVAILABLE
	for objective in objectives:
		objective.reset()


## Get a formatted objective list as string
func get_objectives_text() -> String:
	var text = ""
	for i in range(objectives.size()):
		var obj = objectives[i]
		text += "• " + obj.description + " (" + obj.get_progress_string() + ")"
		if i < objectives.size() - 1:
			text += "\n"
	return text


## Get a formatted rewards text
func get_rewards_text() -> String:
	var rewards = []

	if reward_gold > 0:
		rewards.append("%d Gold" % reward_gold)

	if reward_xp > 0:
		rewards.append("%d XP" % reward_xp)

	for item_id in reward_items:
		rewards.append(item_id)

	return ", ".join(rewards)


## Serialize quest to dictionary for save/load
func to_dict() -> Dictionary:
	var objectives_data = []
	for obj in objectives:
		objectives_data.append(obj.to_dict())

	return {
		"quest_id": quest_id,
		"title": title,
		"description": description,
		"giver_npc_id": giver_npc_id,
		"objectives": objectives_data,
		"reward_gold": reward_gold,
		"reward_xp": reward_xp,
		"reward_items": reward_items,
		"status": status
	}


## Deserialize quest from dictionary
static func from_dict(data: Dictionary) -> Quest:
	var quest = Quest.new()
	quest.quest_id = data.get("quest_id", "")
	quest.title = data.get("title", "")
	quest.description = data.get("description", "")
	quest.giver_npc_id = data.get("giver_npc_id", "")
	quest.reward_gold = data.get("reward_gold", 0)
	quest.reward_xp = data.get("reward_xp", 0)
	quest.reward_items = data.get("reward_items", [])
	quest.status = data.get("status", QuestStatus.AVAILABLE)

	# Deserialize objectives
	var objectives_data = data.get("objectives", [])
	for obj_data in objectives_data:
		quest.objectives.append(QuestObjective.from_dict(obj_data))

	return quest
