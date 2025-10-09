# File: res://scripts/ui/VillageMap.gd
# Mappa centrata + marker NPC. Emette npc_clicked(npc_id).
class_name VillageMap
extends Control

signal npc_clicked(npc_id: String)

const VILLAGE_MAP: String = "res://Icons/mappa villaggio.png"
const NPCS_JSON: String   = "res://data/npcs.json"
const NPC_MARKER_ICON: String = "res://Icons/marker.png"
const NPC_MARKER_SIZE_PX: int = 48

var _map_root: Control
var _layer: Control

func _ready() -> void:
	_build()

func get_map_root() -> Control:
	return _map_root

# ----- Build -----
func _build() -> void:
	for c in get_children():
		c.queue_free()

	var frame := PanelContainer.new()
	frame.clip_contents = true
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)

	var ar := AspectRatioContainer.new()
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	ar.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	ar.alignment_vertical   = AspectRatioContainer.ALIGNMENT_CENTER
	ar.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(ar)

	var ratio: float = 16.0 / 9.0
	if ResourceLoader.exists(VILLAGE_MAP):
		var tex: Texture2D = load(VILLAGE_MAP)
		if tex:
			var s: Vector2 = tex.get_size()
			if s.y != 0.0:
				ratio = s.x / s.y
	ar.ratio = ratio

	_map_root = Control.new()
	_map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ar.add_child(_map_root)
	_map_root.resized.connect(_reposition_markers)
	ar.resized.connect(_reposition_markers)

	var img := TextureRect.new()
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(VILLAGE_MAP):
		img.texture = load(VILLAGE_MAP)
	_map_root.add_child(img)

	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_root.add_child(_layer)

	_spawn_markers()

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
