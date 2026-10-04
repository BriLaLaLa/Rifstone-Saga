@tool
class_name PropLibrary
extends RefCounted
## Props della zona (alberi, cespugli, rocce, ceppi, scogli). Usa i modelli Blender di
## assets/3d/props/props_plains.glb (un nodo per prop, nomi come IDS) se esistono, altrimenti segnaposto.

const PROPS_GLB := "res://assets/3d/props/props_plains.glb"
const IDS := ["tree_a", "tree_b", "tree_c", "bush_a", "bush_b", "bush_c", "rock_a", "rock_b", "rock_c",
	"stump_a", "stump_b", "water_rock_a", "water_rock_b"]
## Raggio d'ingombro per la navigazione (cespugli e scogli non bloccano, come nel 2D)
const FOOTPRINT := {"tree": 0.35, "rock": 0.3, "stump": 0.28}

const TRUNK := Color(0.55, 0.38, 0.25)
const LEAVES := Color(0.32, 0.6, 0.3)
const LEAVES_LIGHT := Color(0.42, 0.7, 0.32)
const BUSH := Color(0.38, 0.66, 0.3)
const ROCK := Color(0.63, 0.65, 0.7)
const STUMP_TOP := Color(0.85, 0.7, 0.5)

static var _glb_scene: Node
static var _glb_nodes: Dictionary = {}


static func kind(id: String) -> String:
	return id.get_slice("_", 0) if not id.begins_with("water_rock") else "water_rock"


static func is_solid(id: String) -> bool:
	return FOOTPRINT.has(kind(id))


static func footprint(id: String) -> float:
	return FOOTPRINT.get(kind(id), 0.0)


static func uses_placeholders() -> bool:
	return not ResourceLoader.exists(PROPS_GLB)


static func make_visual(id: String) -> Node3D:
	_load_glb()
	if _glb_nodes.has(id):
		var n := (_glb_nodes[id] as Node3D).duplicate() as Node3D
		n.transform = Transform3D.IDENTITY
		var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
		if n is MeshInstance3D:
			meshes.append(n)
		for mi in meshes:
			ToonMaterials.apply_to_mesh(mi)
		return n
	return _placeholder(id)


static func _load_glb() -> void:
	if _glb_scene != null or uses_placeholders():
		return
	_glb_scene = (load(PROPS_GLB) as PackedScene).instantiate()
	for n in _glb_scene.find_children("*", "Node3D", true, false):
		if String(n.name) in IDS:
			_glb_nodes[String(n.name)] = n


static func _placeholder(id: String) -> Node3D:
	var root := Node3D.new()
	var v := id.unicode_at(id.length() - 1) - "a".unicode_at(0)
	match kind(id):
		"tree":
			var s := 1.0 + v * 0.18
			_part(root, _cyl(0.1 * s, 0.15 * s, 0.9 * s, 6), TRUNK, Vector3(0, 0.45 * s, 0))
			_part(root, _sphere(0.75 * s, 1.3 * s, 7, 4), LEAVES, Vector3(0, 1.45 * s, 0))
			_part(root, _sphere(0.5 * s, 0.9 * s, 7, 4), LEAVES_LIGHT, Vector3(0.15 * s, 2.05 * s, 0.05 * s))
		"bush":
			var s := 0.8 + v * 0.15
			_part(root, _sphere(0.35 * s, 0.55 * s, 7, 4), BUSH, Vector3(0, 0.25 * s, 0))
			_part(root, _sphere(0.25 * s, 0.4 * s, 7, 4), LEAVES_LIGHT, Vector3(0.22 * s, 0.22 * s, 0.1 * s))
			_part(root, _sphere(0.22 * s, 0.36 * s, 7, 4), BUSH, Vector3(-0.2 * s, 0.18 * s, -0.08 * s))
		"rock":
			var s := 0.6 + v * 0.35
			_part(root, _sphere(0.4 * s, 0.55 * s, 6, 3), ROCK, Vector3(0, 0.12 * s, 0))
		"stump":
			_part(root, _cyl(0.24, 0.3, 0.35, 8), TRUNK, Vector3(0, 0.175, 0))
			_part(root, _cyl(0.22, 0.22, 0.02, 8), STUMP_TOP, Vector3(0, 0.36, 0))
		"water_rock":
			var s := 0.8 + v * 0.4
			_part(root, _sphere(0.45 * s, 1.2 * s, 6, 3), ROCK, Vector3(0, -0.35, 0))
	return root


static func _part(root: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ToonMaterials.get_material(color)
	mi.position = pos
	root.add_child(mi)


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	return m


static func _sphere(r: float, h: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m
