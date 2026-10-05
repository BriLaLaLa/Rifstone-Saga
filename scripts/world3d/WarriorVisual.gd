class_name WarriorVisual
extends Node3D
## Parte visiva del warrior 3D: modello glTF con materiali toon, animazioni, equip visibile
## e bagliore del potenziamento. Il movimento lo decide chi lo usa (controller), qui solo la resa.
##
## Equip: ogni slot monta una "skin" del catalogo EquipmentVisuals (data/equipment_visuals.json).
## I pezzi skinnati (elmo, corazza, stivali, cintura) vengono legati allo scheletro del warrior,
## quelli rigidi (armi, scudo) agganciati all'osso. Le parti del corpo coperte vengono nascoste.
## Lo stile di combattimento (spada+scudo / due spade / spadone) dipende dalle armi montate e
## sceglie le animazioni con prefisso (dual_ / gs_) quando esistono.

signal hit_moment(anim_name: String)
signal animation_done(anim_name: String)
signal style_changed(style: String)

const MODEL_PATH := "res://assets/3d/characters/warrior/warrior.glb"
const MODEL_SCENE := preload("res://assets/3d/characters/warrior/warrior.glb")

const LOOPING: Array[String] = ["idle", "run", "gather"]
## Momento del colpo in secondi (tabelle in PIANO_3D.md e SKILLS_WARRIOR.md)
const HIT_TIMES := {"attack1": 0.30, "attack2": 0.37, "gather": 0.40, "gs_attack1": 0.50, "gs_attack2": 0.60}
const SLOTS := ["weapon", "shield", "helmet", "chest", "boots", "belt"]
const RIGID_SLOTS := ["weapon", "shield"]
const DEFAULT_BONES := {"weapon": "hand.R", "shield": "hand.L", "helmet": "head"}

const STYLE_SWORD_SHIELD := "sword_shield"
const STYLE_DUAL := "dual"
const STYLE_GREATSWORD := "greatsword"
const STYLE_PREFIX := {STYLE_SWORD_SHIELD: "", STYLE_DUAL: "dual_", STYLE_GREATSWORD: "gs_"}

@export var tint: Color = Color.WHITE
@export var turn_speed: float = 12.0
## Monta le skin base di tutti gli slot all'avvio (prototipi, nemici di prova). Il gioco vero usa
## invece l'equipaggiamento di GameState (EquipmentSync3D).
@export var equip_defaults: bool = true

var style: String = STYLE_SWORD_SHIELD

var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _body: Dictionary = {}       # nome -> MeshInstance3D del corpo base
var _sources: Dictionary = {}    # nome nodo -> MeshInstance3D sorgente nel modello del warrior (nascosto)
var _pieces: Dictionary = {}     # slot -> {"visual", "piece", "node", "meshes", "rigid"}
var _levels: Dictionary = {}
var _last_visual: Dictionary = {}
var _last_pos: float = 0.0
var _hit_fired: bool = false
var _target_yaw: float = 0.0

static var _scene_cache: Dictionary = {}


func _ready() -> void:
	_model = MODEL_SCENE.instantiate()
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	_skeleton = _model.find_child("Skeleton3D", true, false)
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).begins_with("Eq_"):
			_sources[String(mi.name)] = mi
			mi.visible = false
		else:
			_body[String(mi.name)] = mi
			ToonMaterials.apply_to_mesh(mi, tint)
	for a in _anim.get_animation_list():
		var base := _base_name(a)
		if base in LOOPING:
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.animation_finished.connect(func(a: StringName) -> void: animation_done.emit(String(a)))
	if equip_defaults:
		for slot in SLOTS:
			equip_visual(slot, EquipmentVisuals.default_for(slot))
	play("idle")


func _process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-turn_speed * delta))
	var cur: String = _anim.current_animation
	var hit_key := cur if HIT_TIMES.has(cur) else _base_name(cur)
	if HIT_TIMES.has(hit_key):
		var pos := _anim.current_animation_position
		if pos < _last_pos:
			_hit_fired = false
		if not _hit_fired and pos >= HIT_TIMES[hit_key]:
			_hit_fired = true
			hit_moment.emit(cur)
		_last_pos = pos


# ==================== ANIMAZIONI ====================

## Riproduce un'animazione per nome base ("attack1", "skill_hiss"...): nello stile due spade / spadone
## usa la versione con prefisso se esiste, altrimenti quella base.
func play(anim_name: String, blend: float = 0.12, restart: bool = false) -> void:
	var resolved := styled_animation(anim_name)
	if not restart and _anim.current_animation == resolved and _anim.is_playing():
		return
	if restart:
		_anim.stop()
	_anim.play(resolved, blend)
	_hit_fired = false
	_last_pos = 0.0


func styled_animation(anim_name: String) -> String:
	var prefixed: String = STYLE_PREFIX.get(style, "") + anim_name
	return prefixed if prefixed != anim_name and _anim.has_animation(prefixed) else anim_name


func current_animation() -> String:
	return _anim.current_animation


func has_animation(anim_name: String) -> bool:
	return _anim.has_animation(anim_name)


func _base_name(anim_name: String) -> String:
	for p in ["dual_", "gs_"]:
		if anim_name.begins_with(p):
			return anim_name.substr(p.length())
	return anim_name


func face_direction(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		_target_yaw = atan2(dir.x, dir.z)


# ==================== EQUIP ====================

## Monta in uno slot la skin indicata (id del catalogo). level = potenziamento (+7/+8/+9 brillano).
func equip_visual(slot: String, visual_id: String, level: int = -1) -> bool:
	var piece := EquipmentVisuals.piece_for(visual_id, slot)
	if piece.is_empty():
		push_warning("[WarriorVisual] Skin '%s' sconosciuta per lo slot %s" % [visual_id, slot])
		return false
	# stesse regole di GameState: con lo spadone la mano sinistra è bloccata, e montarlo toglie scudo/seconda spada
	if slot == "shield" and _two_handed():
		return false
	if slot == "weapon" and str(piece.get("weapon_type", "one_hand")) == "two_hand":
		unequip("shield")
	var src := _source_mesh(piece)
	if src == null:
		push_warning("[WarriorVisual] Modello per la skin '%s' non trovato (%s)" % [visual_id, piece.get("node", "?")])
		return false
	unequip(slot)
	var node := src.duplicate() as MeshInstance3D
	node.visible = true
	var rigid := src.skin == null
	if rigid:
		var bone := str(piece.get("bone", _source_bone(src, slot)))
		var attach := _attachment(bone)
		attach.add_child(node)
		node.transform = src.transform if src.get_parent() is BoneAttachment3D and (src.get_parent() as BoneAttachment3D).bone_name == bone else Transform3D.IDENTITY
	else:
		_skeleton.add_child(node)
		node.transform = Transform3D.IDENTITY
		node.skeleton = NodePath("..")
		node.skin = src.skin
	var sc := float(piece.get("scale", 1.0))
	if not is_equal_approx(sc, 1.0):
		node.scale *= sc
	ToonMaterials.apply_to_mesh(node, tint * piece.get("tint", Color.WHITE), false, piece.get("colors", {}))
	_pieces[slot] = {"visual": visual_id, "piece": piece, "node": node, "meshes": [node], "rigid": rigid}
	_last_visual[slot] = visual_id
	_update_body_visibility()
	set_enhancement(slot, level if level >= 0 else int(_levels.get(slot, 0)))
	_update_style()
	return true


func unequip(slot: String) -> void:
	if not _pieces.has(slot):
		return
	var node: Node = _pieces[slot]["node"]
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()
	_pieces.erase(slot)
	_update_body_visibility()
	_update_style()


func get_slot_visual(slot: String) -> String:
	return str(_pieces[slot]["visual"]) if _pieces.has(slot) else ""


func is_slot_equipped(slot: String) -> bool:
	return _pieces.has(slot)


## Compatibilità con il prototipo: accende/spegne uno slot con l'ultima skin usata (o quella base)
func set_slot_equipped(slot: String, on: bool) -> void:
	if on:
		equip_visual(slot, str(_last_visual.get(slot, EquipmentVisuals.default_for(slot))))
	else:
		unequip(slot)


func set_enhancement(slot: String, level: int) -> void:
	_levels[slot] = level
	if not _pieces.has(slot):
		return
	for mi in _pieces[slot]["meshes"]:
		Enhancement3D.apply(mi, level, _pieces[slot]["rigid"])


func get_enhancement(slot: String) -> int:
	return int(_levels.get(slot, 0))


## Mesh montata in uno slot (es. per mostrare la spada da sola in vetrina); null se vuoto
func get_slot_mesh(slot: String) -> MeshInstance3D:
	if _pieces.has(slot):
		return _pieces[slot]["node"]
	var v := EquipmentVisuals.piece_for(EquipmentVisuals.default_for(slot), slot)
	return _source_mesh(v) if not v.is_empty() else null


## Parte del corpo base visibile? (per test e debug)
func is_body_part_visible(part: String) -> bool:
	return _body.has(part) and (_body[part] as MeshInstance3D).visible


func _update_body_visibility() -> void:
	var hidden := {}
	for slot in _pieces:
		for part in _pieces[slot]["piece"].get("hides", []):
			hidden[part] = true
	for part in _body:
		(_body[part] as MeshInstance3D).visible = not hidden.has(part)


func _two_handed() -> bool:
	return _pieces.has("weapon") and str(_pieces["weapon"]["piece"].get("weapon_type", "one_hand")) == "two_hand"


func _update_style() -> void:
	var new_style := STYLE_SWORD_SHIELD
	if _pieces.has("weapon") and str(_pieces["weapon"]["piece"].get("weapon_type", "one_hand")) == "two_hand":
		new_style = STYLE_GREATSWORD
	elif _pieces.has("shield") and str(_pieces["shield"]["piece"].get("offhand", "shield")) == "weapon":
		new_style = STYLE_DUAL
	if new_style != style:
		style = new_style
		style_changed.emit(style)


## Mesh sorgente di una skin: dal modello del warrior (già caricato) o da un altro .glb
func _source_mesh(piece: Dictionary) -> MeshInstance3D:
	var scene_path := str(piece.get("scene", MODEL_PATH))
	var names := [str(piece.get("node", ""))]
	if piece.has("fallback_node"):
		names.append(str(piece["fallback_node"]))
	if scene_path == MODEL_PATH:
		for n in names:
			if _sources.has(n):
				return _sources[n]
		return null
	var holder := _external_scene(scene_path)
	if holder == null:
		return null
	for n in names:
		var found := holder.find_child(n, true, false) as MeshInstance3D
		if found:
			return found
	return null


## I .glb esterni (skin nuove) vengono istanziati una volta per warrior, nascosti, e usati come sorgente.
## I pezzi skinnati di un .glb esterno devono usare lo stesso scheletro (stessi nomi e ordine delle ossa).
func _external_scene(path: String) -> Node3D:
	var holder_name := "Src_" + path.get_file().get_basename()
	var holder := get_node_or_null(holder_name) as Node3D
	if holder:
		return holder
	if not ResourceLoader.exists(path):
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	holder = (_scene_cache[path] as PackedScene).instantiate()
	holder.name = holder_name
	holder.visible = false
	add_child(holder)
	return holder


func _source_bone(src: MeshInstance3D, slot: String) -> String:
	if src.get_parent() is BoneAttachment3D:
		return (src.get_parent() as BoneAttachment3D).bone_name
	return str(DEFAULT_BONES.get(slot, "hand.R"))


func _attachment(bone: String) -> BoneAttachment3D:
	for c in _skeleton.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == bone:
			return c
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skeleton.add_child(att)
	return att
