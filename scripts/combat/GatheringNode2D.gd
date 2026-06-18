# scripts/combat/GatheringNode2D.gd
# Nodo di raccolta del sistema combat top-down (oggetto nel mondo).
# Sta fermo nell'arena; quando il player entra nel raggio, la raccolta avanza
# automaticamente a tentativi temporizzati. Esauriti i tentativi si autodistrugge
# (emette `depleted`) e il controller ne rispawna un altro.
# I dati arrivano da GatheringDatabase.get_node_data(node_id).

extends Node2D
class_name GatheringNode2D

signal depleted(node)

# ==================== EXPORT ====================

# Raggio entro cui il player "raccoglie" (in world space 800×600)
@export var gather_range: float = 90.0

# ==================== NODES ====================

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var progress_bar: ProgressBar = $ProgressBar

# ==================== DATA ====================

var node_id: String = ""
var node_type: String = ""   # mining / gathering / fishing
var node_name: String = ""
var attempts_remaining: int = 5
var attempt_duration: float = 3.0

const FALLBACK_ICON := "res://icon.svg"

# ==================== STATE ====================

var _player: Node2D = null
var _timer: float = 0.0
var _depleted: bool = false

# ==================== SETUP ====================

func setup(node_data: Dictionary, p_player: Node2D) -> void:
	node_id            = str(node_data.get("id", ""))
	node_type          = str(node_data.get("type", "mining"))
	node_name          = str(node_data.get("name", node_id))
	attempts_remaining = int(node_data.get("base_attempts", 5))
	attempt_duration   = float(node_data.get("attempt_duration", 3.0))
	_player            = p_player

	if is_instance_valid(name_label):
		name_label.text = node_name
	if is_instance_valid(progress_bar):
		progress_bar.visible = false
		progress_bar.value = 0.0

	_apply_sprite(str(node_data.get("icon", "")))

func _apply_sprite(icon_path: String) -> void:
	if not is_instance_valid(sprite):
		return
	var tex: Texture2D = null
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path)
	if tex == null:
		tex = load(FALLBACK_ICON)
		# Tinta per tipo, così è riconoscibile anche col fallback
		match node_type:
			"mining":    sprite.modulate = Color(0.7, 0.7, 0.8)
			"gathering": sprite.modulate = Color(0.4, 0.85, 0.4)
			"fishing":   sprite.modulate = Color(0.4, 0.6, 0.9)
	sprite.texture = tex
	# Normalizza a ~44px di lato
	var tsize: Vector2 = tex.get_size()
	if tsize.x > 0.0 and tsize.y > 0.0:
		var target := 44.0
		sprite.scale = Vector2(target / tsize.x, target / tsize.y)

# ==================== PROCESS ====================

func _process(delta: float) -> void:
	if _depleted or not is_visible_in_tree() or not is_instance_valid(_player):
		return

	var in_range: bool = global_position.distance_to(_player.global_position) <= gather_range

	if is_instance_valid(progress_bar):
		progress_bar.visible = in_range

	if not in_range:
		_timer = 0.0
		if is_instance_valid(progress_bar):
			progress_bar.value = 0.0
		return

	_timer += delta
	if is_instance_valid(progress_bar):
		progress_bar.value = (_timer / attempt_duration) * 100.0

	if _timer >= attempt_duration:
		_timer = 0.0
		_do_attempt()

# ==================== GATHERING LOGIC ====================

func _do_attempt() -> void:
	var db = get_node_or_null("/root/GatheringDatabase")
	if db == null:
		return

	var drops: Array = db.calculate_node_drops(node_id, _get_tool_stats())
	_grant_drops(drops)
	_award_skill_exp()

	attempts_remaining -= 1
	if attempts_remaining <= 0:
		_finish()

func _grant_drops(drops: Array) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var notif = get_node_or_null("/root/LootNotificationManager")

	for drop in drops:
		var item_id: String = str(drop.get("item_id", ""))
		var amount: int = int(drop.get("amount", 1))
		if item_id == "":
			continue
		var item_data: Dictionary = _get_item_data(item_id)
		if item_data.is_empty():
			item_data = {"id": item_id, "name": item_id}
		for _i in range(max(1, amount)):
			gs._add_item_to_visual_inventory(item_id, item_data)
		if notif and notif.has_method("show_notification"):
			notif.show_notification(item_data)

func _award_skill_exp() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or gs.gathering_skills == null:
		return
	match node_type:
		"mining":    gs.gathering_skills.add_mining_exp(20)
		"gathering": gs.gathering_skills.add_herbalism_exp(20)
		"fishing":   gs.gathering_skills.add_fishing_exp(20)

func _get_tool_stats() -> Dictionary:
	var stats := {"yield_bonus": 0, "speed_bonus": 0.0, "critical_chance": 0.05}
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return stats
	var tool_slot := ""
	match node_type:
		"mining":    tool_slot = "mining_tool"
		"gathering": tool_slot = "gathering_tool"
		"fishing":   tool_slot = "fishing_tool"
	if "equipped_gathering_tools" in gs and gs.equipped_gathering_tools.has(tool_slot):
		var tool_id: String = gs.equipped_gathering_tools[tool_slot]
		if tool_id != "":
			var db = get_node_or_null("/root/GatheringDatabase")
			if db:
				var tool_data: Dictionary = db.get_tool_data(tool_id)
				if tool_data.has("stats"):
					stats = tool_data["stats"].duplicate()
	return stats

func _get_item_data(item_id: String) -> Dictionary:
	var idata = get_node_or_null("/root/IData")
	if idata and idata.has_method("get_item_data"):
		var d: Dictionary = idata.get_item_data(item_id)
		if not d.is_empty():
			var copy := d.duplicate(true)
			copy["id"] = item_id
			return copy
	return {}

func _finish() -> void:
	if _depleted:
		return
	_depleted = true
	depleted.emit(self)
	# Fade out e rimozione
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	await tw.finished
	queue_free()
