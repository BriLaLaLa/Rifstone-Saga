# File: res://scripts/ui/VillageMap.gd
# Mappa centrata + marker NPC. Emette npc_clicked(npc_id).
class_name VillageMap
extends Control

signal npc_clicked(npc_id: String)

const VILLAGE_MAP: String = "res://Icons/mappa villaggio.png"
const NPCS_JSON: String   = "res://data/npcs.json"
const NPC_MARKER_ICON: String = "res://Icons/marker.png"
const NPC_MARKER_SIZE_PX: int = 48
const NPC_QUEST_INDICATOR_SCENE: String = "res://scenes/ui/NPCQuestIndicator.tscn"

@onready var _map_root: Control = $Frame/AspectRatioContainer/MapRoot
@onready var _layer: Control = $Frame/AspectRatioContainer/MapRoot/Layer
@onready var _ar: AspectRatioContainer = $Frame/AspectRatioContainer
@onready var _map_image: TextureRect = $Frame/AspectRatioContainer/MapRoot/MapImage

func _ready() -> void:
	if ResourceLoader.exists(VILLAGE_MAP):
		var tex: Texture2D = load(VILLAGE_MAP)
		if tex:
			_map_image.texture = tex
			var s: Vector2 = tex.get_size()
			if s.y != 0.0:
				_ar.ratio = s.x / s.y

	_map_root.resized.connect(_reposition_markers)
	_ar.resized.connect(_reposition_markers)
	_spawn_markers()

func get_map_root() -> Control:
	return _map_root

# ----- Markers -----
func _spawn_markers() -> void:
	if not is_instance_valid(_layer):
		return
	for c in _layer.get_children():
		c.queue_free()

	var npcs: Array = _load_json_array(NPCS_JSON)
	var use_icon: bool = NPC_MARKER_ICON != "" and ResourceLoader.exists(NPC_MARKER_ICON)
	var icon_tex: Texture2D = load(NPC_MARKER_ICON) if use_icon else null

	for npc in npcs:
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		if not (npc as Dictionary).has("id") or not (npc as Dictionary).has("name") or not (npc as Dictionary).has("pos"):
			continue

		var pos: Dictionary = (npc as Dictionary)["pos"] if typeof((npc as Dictionary)["pos"]) == TYPE_DICTIONARY else {}
		var ax: float = clamp(float(pos.get("x", 0.5)), 0.0, 1.0)
		var ay: float = clamp(float(pos.get("y", 0.5)), 0.0, 1.0)
		var anch := Vector2(ax, ay)

		var marker: Control
		if use_icon and icon_tex:
			var tb := TextureButton.new()
			tb.texture_normal = icon_tex
			tb.expand = true
			tb.stretch_mode = TextureButton.STRETCH_SCALE
			tb.custom_minimum_size = Vector2(NPC_MARKER_SIZE_PX, NPC_MARKER_SIZE_PX)
			marker = tb
		else:
			var b := Button.new()
			b.text = str((npc as Dictionary).get("name","NPC"))
			b.custom_minimum_size = Vector2(NPC_MARKER_SIZE_PX * 1.6, NPC_MARKER_SIZE_PX * 0.9)
			marker = b

		marker.set_meta("anchor", anch)
		marker.set_meta("npc_id", str((npc as Dictionary)["id"]))
		if marker is BaseButton:
			(marker as BaseButton).pressed.connect(func() -> void:
				emit_signal("npc_clicked", str((npc as Dictionary)["id"]))
			)

		# Add quest indicator above the marker (position is anchor-based in the scene)
		var indicator_scene = load(NPC_QUEST_INDICATOR_SCENE)
		if indicator_scene:
			var quest_indicator = indicator_scene.instantiate()
			quest_indicator.npc_id = str((npc as Dictionary)["id"])
			marker.add_child(quest_indicator)

		_layer.add_child(marker)

	_reposition_markers()

func _reposition_markers() -> void:
	if not is_instance_valid(_map_root) or not is_instance_valid(_layer):
		return
	var area: Vector2 = _map_root.size
	for c in _layer.get_children():
		var ctrl := c as Control
		if ctrl == null:
			continue
		var anchor: Vector2 = ctrl.get_meta("anchor", Vector2(0.5,0.5))
		var target: Vector2 = area * anchor
		var sz: Vector2 = ctrl.size
		if sz == Vector2.ZERO:
			sz = ctrl.get_combined_minimum_size()
			if sz == Vector2.ZERO:
				sz = Vector2(NPC_MARKER_SIZE_PX, NPC_MARKER_SIZE_PX)
		ctrl.position = target - (sz * 0.5)

# ----- Utils -----
func _load_json_array(path: String) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return (data as Array) if typeof(data) == TYPE_ARRAY else []
