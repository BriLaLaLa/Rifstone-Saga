extends Resource
class_name QuestObjective

## Quest objective resource
## Represents a single objective within a quest (kill enemies or collect items)

enum ObjectiveType {
	KILL,    # Kill X enemies of a specific type
	COLLECT  # Collect Y items of a specific type
}

## Type of objective (KILL or COLLECT)
@export var type: ObjectiveType = ObjectiveType.KILL

## Target ID (enemy_id for KILL, item_id for COLLECT)
@export var target_id: String = ""

## How many kills/items needed to complete this objective
@export var target_count: int = 1

## Description text for this objective (e.g., "Kill 10 Wolves")
@export var description: String = ""

## Current progress (kills/items collected so far)
var current_progress: int = 0


## Check if this objective is complete
func is_complete() -> bool:
	return current_progress >= target_count


## Add progress to this objective
## Returns true if the objective was just completed
func add_progress(amount: int = 1) -> bool:
	var was_complete = is_complete()
	current_progress = min(current_progress + amount, target_count)
	var is_now_complete = is_complete()

	# Return true if objective was just completed
	return not was_complete and is_now_complete


## Get progress as a formatted string (e.g., "5/10")
func get_progress_string() -> String:
	return "%d/%d" % [current_progress, target_count]


## Get progress as a percentage (0.0 to 1.0)
func get_progress_ratio() -> float:
	if target_count <= 0:
		return 0.0
	return float(current_progress) / float(target_count)


## Reset progress to 0
func reset() -> void:
	current_progress = 0


## Serialize objective to dictionary for save/load
func to_dict() -> Dictionary:
	return {
		"type": type,
		"target_id": target_id,
		"target_count": target_count,
		"description": description,
		"current_progress": current_progress
	}


## Deserialize objective from dictionary
static func from_dict(data: Dictionary) -> QuestObjective:
	var obj = QuestObjective.new()
	obj.type = data.get("type", ObjectiveType.KILL)
	obj.target_id = data.get("target_id", "")
	obj.target_count = data.get("target_count", 1)
	obj.description = data.get("description", "")
	obj.current_progress = data.get("current_progress", 0)
	return obj
