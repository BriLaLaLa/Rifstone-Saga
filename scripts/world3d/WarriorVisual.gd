class_name WarriorVisual
extends Node3D
## Parte visiva del warrior 3D: modello glTF con materiali toon, animazioni, equip visibile
## e bagliore del potenziamento. Il movimento lo decide chi lo usa (controller), qui solo la resa.

signal hit_moment(anim_name: String)
signal animation_done(anim_name: String)

const MODEL_SCENE := preload("res://assets/3d/characters/warrior/warrior.glb")

const LOOPING: Array[String] = ["idle", "run", "gather"]
## Momento del colpo in secondi (tabella animazioni in PIANO_3D.md)
const HIT_TIMES := {"attack1": 0.30, "attack2": 0.37, "gather": 0.40}

## slot -> [mesh equip, mesh del corpo coperta dall'equip ("" se nessuna)]
const SLOT_MESHES := {
	"helmet": ["Eq_Helmet", "Body_Head"],
	"chest": ["Eq_Chest", "Body_Torso"],
	"boots": ["Eq_Boots", "Body_Feet"],
	"belt": ["Eq_Belt", ""],
	"weapon": ["Eq_Sword", ""],
	"shield": ["Eq_Shield", ""],
}
const RIGID_SLOTS := ["weapon", "shield"]

@export var tint: Color = Color.WHITE
@export var turn_speed: float = 12.0

var _model: Node3D
var _anim: AnimationPlayer
var _meshes: Dictionary = {}
var _equipped: Dictionary = {}
var _levels: Dictionary = {}
var _last_pos: float = 0.0
var _hit_fired: bool = false
var _target_yaw: float = 0.0


func _ready() -> void:
	_model = MODEL_SCENE.instantiate()
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		_meshes[mi.name] = mi
		ToonMaterials.apply_to_mesh(mi, tint)
	for a in LOOPING:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.animation_finished.connect(func(a: StringName) -> void: animation_done.emit(String(a)))
	for slot in SLOT_MESHES:
		set_slot_equipped(slot, true)
	play("idle")


func _process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-turn_speed * delta))
	var cur: String = _anim.current_animation
	if HIT_TIMES.has(cur):
		var pos := _anim.current_animation_position
		if pos < _last_pos:
			_hit_fired = false
		if not _hit_fired and pos >= HIT_TIMES[cur]:
			_hit_fired = true
			hit_moment.emit(cur)
		_last_pos = pos


func play(anim_name: String, blend: float = 0.12, restart: bool = false) -> void:
	if not restart and _anim.current_animation == anim_name and _anim.is_playing():
		return
	if restart:
		_anim.stop()
	_anim.play(anim_name, blend)
	_hit_fired = false
	_last_pos = 0.0


func current_animation() -> String:
	return _anim.current_animation


func face_direction(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		_target_yaw = atan2(dir.x, dir.z)


func set_slot_equipped(slot: String, on: bool) -> void:
	var pair: Array = SLOT_MESHES[slot]
	_equipped[slot] = on
	_meshes[pair[0]].visible = on
	if pair[1] != "":
		_meshes[pair[1]].visible = not on


func is_slot_equipped(slot: String) -> bool:
	return _equipped.get(slot, false)


func set_enhancement(slot: String, level: int) -> void:
	_levels[slot] = level
	var mi: MeshInstance3D = _meshes[SLOT_MESHES[slot][0]]
	Enhancement3D.apply(mi, level, slot in RIGID_SLOTS)


func get_enhancement(slot: String) -> int:
	return _levels.get(slot, 0)


## Mesh dell'equip di uno slot (es. per mostrare la spada da sola in vetrina)
func get_slot_mesh(slot: String) -> MeshInstance3D:
	return _meshes[SLOT_MESHES[slot][0]]
