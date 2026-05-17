extends Control
class_name NPCQuestIndicator

## Visual quest indicator for NPCs
## Shows ! or ? above NPC buttons with color-coded status

## NPC ID this indicator is tracking
var npc_id: String = ""

@onready var label_exclaim: Label = $LabelExclaim
@onready var label_question: Label = $LabelQuestion

## Colors for different quest states
const COLOR_YELLOW = Color(1.0, 0.9, 0.0)
const COLOR_GREY = Color(0.6, 0.6, 0.6)


func _ready() -> void:
	if has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		quest_system.quest_accepted.connect(_on_quest_updated)
		quest_system.quest_objective_progressed.connect(_on_quest_objective_progressed)
		quest_system.quest_ready_to_turn_in.connect(_on_quest_updated)
		quest_system.quest_completed.connect(_on_quest_updated)
		quest_system.quests_loaded.connect(_on_quests_loaded)

	update_indicator()


## Update the indicator based on quest status
func update_indicator() -> void:
	if not is_node_ready():
		return

	label_exclaim.visible = false
	label_question.visible = false

	if npc_id == "" or not has_node("/root/QuestSystem"):
		return

	var quest_system = get_node("/root/QuestSystem")
	var status = quest_system.get_npc_quest_status(npc_id)

	match status:
		"available":
			label_exclaim.modulate = COLOR_YELLOW
			label_exclaim.visible = true
		"ready":
			label_exclaim.modulate = COLOR_YELLOW
			label_exclaim.visible = true
		"in_progress":
			label_question.modulate = COLOR_GREY
			label_question.visible = true
		_:
			pass  # both hidden


func _on_quest_updated(_quest: Quest) -> void:
	update_indicator()


func _on_quest_objective_progressed(_quest: Quest, _objective: QuestObjective) -> void:
	update_indicator()


func _on_quests_loaded() -> void:
	update_indicator()
