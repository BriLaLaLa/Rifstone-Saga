extends Label
class_name NPCQuestIndicator

## Visual quest indicator for NPCs
## Shows ! or ? above NPC buttons with color-coded status

## NPC ID this indicator is tracking
var npc_id: String = ""

## Colors for different quest states
const COLOR_YELLOW = Color(1.0, 0.9, 0.0)  # Available quest or ready to turn in
const COLOR_GREY = Color(0.6, 0.6, 0.6)    # Quest in progress


func _ready() -> void:
	# Connect to QuestSystem signals
	if has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		quest_system.quest_accepted.connect(_on_quest_updated)
		quest_system.quest_objective_progressed.connect(_on_quest_objective_progressed)
		quest_system.quest_ready_to_turn_in.connect(_on_quest_updated)
		quest_system.quest_completed.connect(_on_quest_updated)
		quest_system.quests_loaded.connect(_on_quests_loaded)

	# Initial update
	update_indicator()


## Update the indicator based on quest status
func update_indicator() -> void:
	if npc_id == "":
		visible = false
		return

	if not has_node("/root/QuestSystem"):
		visible = false
		return

	var quest_system = get_node("/root/QuestSystem")
	var status = quest_system.get_npc_quest_status(npc_id)

	match status:
		"available":
			text = "!"
			modulate = COLOR_YELLOW
			visible = true

		"in_progress":
			text = "?"
			modulate = COLOR_GREY
			visible = true

		"ready":
			text = "?"
			modulate = COLOR_YELLOW
			visible = true

		_:  # "none" or any other status
			visible = false


## Called when a quest is accepted, ready, or completed
func _on_quest_updated(_quest: Quest) -> void:
	update_indicator()


## Called when quest objective progresses
func _on_quest_objective_progressed(_quest: Quest, _objective: QuestObjective) -> void:
	update_indicator()


## Called when quests are loaded from JSON
func _on_quests_loaded() -> void:
	update_indicator()
