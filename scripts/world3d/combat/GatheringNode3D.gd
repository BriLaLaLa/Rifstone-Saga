class_name GatheringNode3D
extends Node3D
## Nodo di raccolta nel mondo 3D (port di GatheringNode2D, stessa logica e API).
## Raccoglie solo se il player lo ha scelto come bersaglio ed è nel raggio; esauriti i tentativi
## mostra la variante esaurita, emette `depleted` e sparisce.

signal depleted(node)

const PX := 64.0
## id nodo -> [scena, nodo pieno, nodo esaurito]
const MODELS := {
	"mining_node": ["res://assets/3d/resources/mining_node.glb", "mining_node", "mining_node_depleted"],
}
## Tipi senza modello Blender: prop segnaposto
const PLACEHOLDER_PROPS := {"gathering": "bush_c", "fishing": "water_rock_b", "mining": "rock_c"}

@export var gather_range: float = 90.0 / PX

var node_id: String = ""
var node_type: String = ""
var node_name: String = ""
var attempts_remaining: int = 5
var attempt_duration: float = 3.0

var _player: Node3D = null
var _timer: float = 0.0
var _depleted: bool = false
var _full: Node3D
var _empty: Node3D
var _bar: Bar3D
var _label: Label3D


func setup(node_data: Dictionary, p_player: Node3D) -> void:
	node_id = str(node_data.get("id", ""))
	node_type = str(node_data.get("type", "mining"))
	node_name = str(node_data.get("name", node_id))
	attempts_remaining = int(node_data.get("base_attempts", 5))
	attempt_duration = float(node_data.get("attempt_duration", 3.0))
	_player = p_player
	_build_visual()


func _build_visual() -> void:
	var height := 1.1
	if MODELS.has(node_id):
		var info: Array = MODELS[node_id]
		var scene: Node3D = (load(info[0]) as PackedScene).instantiate()
		_full = _extract(scene, info[1])
		_empty = _extract(scene, info[2])
		scene.free()
	else:
		_full = PropLibrary.make_visual(PLACEHOLDER_PROPS.get(node_type, "rock_c"))
		add_child(_full)
	if _empty:
		_empty.visible = false
	_bar = Bar3D.create(Color(0.35, 0.8, 1.0), 0.8)
	_bar.position = Vector3(0, height + 0.25, 0)
	_bar.visible = false
	add_child(_bar)
	_label = Label3D.new()
	_label.text = node_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.004
	_label.modulate = Color(0.85, 0.95, 1.0)
	_label.position = Vector3(0, height + 0.45, 0)
	add_child(_label)


## Stacca un nodo del .glb e lo aggiunge qui con i materiali toon (il resto della scena viene liberato)
func _extract(scene: Node, node_name_in_glb: String) -> Node3D:
	var n := scene.find_child(node_name_in_glb, true, false) as Node3D
	if n == null:
		return null
	n.get_parent().remove_child(n)
	n.owner = null
	for c in n.find_children("*", "", true, false):
		c.owner = null
	n.transform = Transform3D.IDENTITY
	add_child(n)
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi in meshes:
		ToonMaterials.apply_to_mesh(mi)
	return n


func _process(delta: float) -> void:
	if _depleted or not is_visible_in_tree() or not is_instance_valid(_player):
		return
	var is_target: bool = _player.has_method("get_gather_target") and _player.get_gather_target() == self
	var d := Vector2(global_position.x - _player.global_position.x, global_position.z - _player.global_position.z).length()
	var in_range := is_target and d <= gather_range
	_bar.visible = in_range
	if not in_range:
		_timer = 0.0
		_bar.set_fraction(0.0)
		return
	_timer += delta
	_bar.set_fraction(_timer / attempt_duration)
	if _timer >= attempt_duration:
		_timer = 0.0
		_do_attempt()


func _do_attempt() -> void:
	var db = get_node_or_null("/root/GatheringDatabase")
	if db == null:
		return
	var drops: Array = db.calculate_node_drops(node_id, _get_tool_stats())
	_grant_drops(drops)
	_award_skill_exp()
	_punch()
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
		FloatingText3D.spawn(get_parent(), global_position + Vector3(0, 1.3, 0), "+%d %s" % [amount, item_data.get("name", item_id)], FloatingText3D.HEAL, 44)


func _award_skill_exp() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or gs.gathering_skills == null:
		return
	match node_type:
		"mining": gs.gathering_skills.add_mining_exp(20)
		"gathering": gs.gathering_skills.add_herbalism_exp(20)
		"fishing": gs.gathering_skills.add_fishing_exp(20)


func _get_tool_stats() -> Dictionary:
	var stats := {"yield_bonus": 0, "speed_bonus": 0.0, "critical_chance": 0.05}
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return stats
	var tool_slot := ""
	match node_type:
		"mining": tool_slot = "mining_tool"
		"gathering": tool_slot = "gathering_tool"
		"fishing": tool_slot = "fishing_tool"
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


func _punch() -> void:
	var tw := _full.create_tween()
	tw.tween_property(_full, "scale", Vector3(1.08, 0.92, 1.08), 0.05)
	tw.tween_property(_full, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func is_depleted() -> bool:
	return _depleted


func _finish() -> void:
	if _depleted:
		return
	_depleted = true
	_bar.visible = false
	depleted.emit(self)
	if _empty:
		_full.visible = false
		_empty.visible = true
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(self, "scale", Vector3(1.1, 0.0, 1.1), 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
