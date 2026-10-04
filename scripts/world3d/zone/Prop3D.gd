@tool
class_name Prop3D
extends Node3D
## Un prop piazzabile nell'editor: scegli il tipo da prop_id, spostalo e ruotalo.
## Il modello viene da PropLibrary (Blender o segnaposto) e non viene salvato nella scena.

const VISUAL_META := &"prop_visual"

@export_enum("tree_a", "tree_b", "tree_c", "bush_a", "bush_b", "bush_c", "rock_a", "rock_b", "rock_c",
	"stump_a", "stump_b", "water_rock_a", "water_rock_b") var prop_id: String = "tree_a":
	set(value):
		prop_id = value
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		if c.has_meta(VISUAL_META):
			remove_child(c)
			c.queue_free()
	var v := PropLibrary.make_visual(prop_id)
	v.set_meta(VISUAL_META, true)
	add_child(v)


func is_solid() -> bool:
	return PropLibrary.is_solid(prop_id)


func footprint_radius() -> float:
	return PropLibrary.footprint(prop_id) * maxf(scale.x, scale.z)
