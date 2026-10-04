extends SceneTree
## Converte una mappa zona 2D (Tiny Swords) nella scena zona 3D equivalente.
## Erba -> celle terra del LandPaint, props -> Prop3D, spawn -> SpawnPoint3D (1 m = 64 px).
## Uso (dalla cartella del progetto):
##   godot --headless --path . --script res://scripts/world3d/tools/convert_2d_zone.gd -- <mappa_2d.tscn> <zona_3d.tscn>
## Senza argomenti converte Red Plains. Sovrascrive la scena 3D: da usare una volta, poi si ritocca nell'editor.

const DEFAULT_SRC := "res://scenes/combat/zones/red_plains_map.tscn"
const DEFAULT_DST := "res://scenes/world3d/zones/red_plains_3d.tscn"
const LAND_PAINT_LIB := "res://assets/3d/tiles/land_paint_library.tres"
const PX := 64.0

## source id del TileSet props 2D -> prop 3D
const PROP_MAP := {
	0: "bush_a", 1: "bush_b", 2: "bush_c", 3: "bush_a",
	4: "rock_a", 5: "rock_b", 6: "rock_c", 7: "rock_b",
	8: "water_rock_a", 9: "water_rock_b", 10: "water_rock_a", 11: "water_rock_b",
	12: "stump_a", 13: "stump_b", 14: "stump_a", 15: "stump_b",
	16: "tree_a", 17: "tree_b", 18: "tree_c", 19: "tree_c",
}
const SPAWN_PROPS := ["kind", "respawn_time", "enemy_ids", "count", "level_min", "level_max",
	"metin_id", "metin_adds_ids", "metin_adds_count", "resource_node_id"]

var _root: Node3D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src_path: String = args[0] if args.size() > 0 else DEFAULT_SRC
	var dst_path: String = args[1] if args.size() > 1 else DEFAULT_DST
	var src: Node = (load(src_path) as PackedScene).instantiate()

	_root = Node3D.new()
	_root.name = dst_path.get_file().get_basename().to_pascal_case()
	_root.set_script(load("res://scripts/world3d/zone/Zone3D.gd"))

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = WorldLook3D.make_environment()
	_add(_root, we)
	var sun := WorldLook3D.make_sun()
	sun.name = "Sun"
	_add(_root, sun)

	var terrain := Node3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://scripts/world3d/terrain/DualGridTerrain3D.gd"))
	_add(_root, terrain)
	var paint := GridMap.new()
	paint.name = "LandPaint"
	paint.mesh_library = _land_paint_library()
	paint.cell_size = Vector3.ONE
	paint.cell_center_y = false
	_add(terrain, paint)
	var land := 0
	for c in (src.get_node("TerrainLayer") as TileMapLayer).get_used_cells():
		paint.set_cell_item(Vector3i(c.x, 0, c.y), 0)
		land += 1

	var props := Node3D.new()
	props.name = "Props"
	_add(_root, props)
	var props_layer := src.get_node("PropsLayer") as TileMapLayer
	var n_props := 0
	for c in props_layer.get_used_cells():
		var id: String = PROP_MAP.get(props_layer.get_cell_source_id(c), "rock_a")
		var p := Node3D.new()
		p.set_script(load("res://scripts/world3d/zone/Prop3D.gd"))
		p.set("prop_id", id)
		p.name = "%s_%d_%d" % [id, c.x, c.y]
		var h := absi(hash(c))
		p.position = Vector3(c.x + 0.5, 0.0, c.y + 0.5)
		p.rotation.y = (h % 360) * PI / 180.0
		p.scale = Vector3.ONE * (0.9 + (h / 360 % 30) / 100.0)
		_add(props, p)
		n_props += 1

	var spawns := Node3D.new()
	spawns.name = "SpawnPoints"
	_add(_root, spawns)
	for sp in src.get_node("SpawnPoints").get_children():
		var s3 := Node3D.new()
		s3.set_script(load("res://scripts/world3d/zone/SpawnPoint3D.gd"))
		s3.name = sp.name
		s3.position = Vector3(sp.position.x / PX, 0.0, sp.position.y / PX)
		s3.set("spawn_radius", float(sp.get("spawn_radius")) / PX)
		for key in SPAWN_PROPS:
			s3.set(key, sp.get(key))
		_add(spawns, s3)

	var ps := PackedScene.new()
	ps.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_path.get_base_dir()))
	var err := ResourceSaver.save(ps, dst_path)
	print("CONVERT %s -> %s  terra=%d props=%d spawn=%d  err=%d" % [src_path, dst_path, land, n_props, spawns.get_child_count(), err])
	src.free()
	_root.free()
	quit()


func _add(parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = _root


## Libreria del pennello "terra" per il LandPaint: un riquadro verde trasparente (solo editor)
func _land_paint_library() -> MeshLibrary:
	if ResourceLoader.exists(LAND_PAINT_LIB):
		return load(LAND_PAINT_LIB)
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.06, 0.96)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	box.material = mat
	var lib := MeshLibrary.new()
	lib.create_item(0)
	lib.set_item_name(0, "terra")
	lib.set_item_mesh(0, box)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAND_PAINT_LIB.get_base_dir()))
	ResourceSaver.save(lib, LAND_PAINT_LIB)
	return load(LAND_PAINT_LIB)
