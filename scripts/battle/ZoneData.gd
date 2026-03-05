extends Resource
class_name ZoneData

# Zone/Region Data Resource
# Represents a single combat zone with all its properties

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var level_range: Array[int] = [1, 10]
@export var unlocked: bool = false
@export var unlock_requirement: int = 1
@export var area_id: String = ""  # Links to existing battle area
@export var recommended_level: int = 1
@export var clickable_rect: Rect2 = Rect2(0, 0, 100, 100)
@export var enemies: Array[String] = []

# Rewards
@export var gold_min: int = 10
@export var gold_max: int = 25
@export var xp_min: int = 50
@export var xp_max: int = 100

func _init():
	pass

func get_level_display() -> String:
	"""Get formatted level range display"""
	return "Lv %d-%d" % [level_range[0], level_range[1]]

func is_player_eligible(player_level: int) -> bool:
	"""Check if player meets level requirement"""
	return player_level >= unlock_requirement

func get_reward_info() -> String:
	"""Get formatted reward info"""
	return "Gold: %d-%d | XP: %d-%d" % [gold_min, gold_max, xp_min, xp_max]

func contains_point(point: Vector2) -> bool:
	"""Check if point is within clickable area"""
	return clickable_rect.has_point(point)

static func from_dict(data: Dictionary) -> ZoneData:
	"""Create ZoneData from dictionary (from zones.json)"""
	var zone = ZoneData.new()

	zone.id = data.get("id", "")
	zone.name = data.get("name", "")
	zone.description = data.get("description", "")

	# Handle level_range array - Godot 4 typed arrays need special handling
	# JSON parses numbers as float, need to convert to int
	var level_range_array = data.get("level_range", [1, 10])
	if level_range_array is Array and level_range_array.size() >= 2:
		zone.level_range.clear()
		zone.level_range.append(int(level_range_array[0]))
		zone.level_range.append(int(level_range_array[1]))

	zone.unlocked = data.get("unlocked", false)
	zone.unlock_requirement = data.get("unlock_requirement", 1)
	zone.area_id = data.get("area_id", "")
	zone.recommended_level = data.get("recommended_level", 1)

	# Parse clickable area
	if data.has("clickable_area"):
		var area = data["clickable_area"]
		zone.clickable_rect = Rect2(
			area.get("x", 0),
			area.get("y", 0),
			area.get("width", 100),
			area.get("height", 100)
		)

	# Parse enemies - Godot 4 typed arrays need special handling
	if data.has("enemies"):
		var enemies_array = data["enemies"]
		if enemies_array is Array:
			zone.enemies.clear()
			for enemy in enemies_array:
				zone.enemies.append(enemy)

	# Parse rewards - Convert JSON floats to int
	if data.has("rewards"):
		var rewards = data["rewards"]
		if rewards.has("gold_range"):
			var gold = rewards["gold_range"]
			zone.gold_min = int(gold[0])
			zone.gold_max = int(gold[1])
		if rewards.has("xp_range"):
			var xp = rewards["xp_range"]
			zone.xp_min = int(xp[0])
			zone.xp_max = int(xp[1])

	return zone
