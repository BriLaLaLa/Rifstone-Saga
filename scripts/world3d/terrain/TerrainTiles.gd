@tool
class_name TerrainTiles
extends RefCounted
## Kit di tessere del terreno (dual grid). Ogni tessera copre 1x1 m centrata su un angolo delle celle
## logiche; i suoi quarti sono le 4 celle attorno. 16 combinazioni terra/acqua = 5 tessere canoniche ruotate.
## Usa le tessere fatte in Blender (assets/3d/tiles/terrain_tiles.glb) se esistono, altrimenti segnaposto.
## Specifica completa in PIANO_3D.md, sezione "Kit tessere e props".

const TILES_GLB := "res://assets/3d/tiles/terrain_tiles.glb"
const GRASS := Color(0.56, 0.76, 0.33)
const CLIFF := Color(0.82, 0.68, 0.47)
const CLIFF_HEIGHT := 0.7

enum Item { FULL, FULL_B, FULL_C, EDGE, CORNER_OUTER, CORNER_INNER, DIAGONAL }
const ITEM_NAMES := ["tile_full", "tile_full_b", "tile_full_c", "tile_edge", "tile_corner_outer", "tile_corner_inner", "tile_diagonal"]

## Bit dei quarti: NO = 1, NE = 2, SE = 4, SO = 8 (nord = -Z in Godot)
const NW := 1
const NE := 2
const SE := 4
const SW := 8
const CANONICAL := {Item.FULL: 15, Item.EDGE: 3, Item.CORNER_OUTER: 2, Item.CORNER_INNER: 7, Item.DIAGONAL: 10}

static var _lookup: Dictionary = {}


## Maschera dei quarti dopo una rotazione di +90° attorno a Y (NE->NO, NO->SO, SO->SE, SE->NE)
static func rotate_mask(m: int) -> int:
	return ((m & NW) << 3) | ((m & (NE | SE | SW)) >> 1)


## [tessera, quarti di giro] per una maschera; [] se vuota
static func lookup(mask: int) -> Array:
	if _lookup.is_empty():
		for item in CANONICAL:
			var m: int = CANONICAL[item]
			for k in 4:
				if not _lookup.has(m):
					_lookup[m] = [item, k]
				m = rotate_mask(m)
	return _lookup.get(mask, [])


static func uses_placeholders() -> bool:
	return not ResourceLoader.exists(TILES_GLB)


static func build_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var from_glb := _load_glb_meshes()
	for i in ITEM_NAMES.size():
		var mesh: Mesh = from_glb.get(ITEM_NAMES[i])
		if mesh == null:
			var canonical: int = CANONICAL.get(i, 15)
			mesh = _placeholder(canonical)
		lib.create_item(i)
		lib.set_item_name(i, ITEM_NAMES[i])
		lib.set_item_mesh(i, mesh)
	return lib


static func _load_glb_meshes() -> Dictionary:
	var out := {}
	if uses_placeholders():
		return out
	var scene: Node = (load(TILES_GLB) as PackedScene).instantiate()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var key := String(mi.name)
		if key not in ITEM_NAMES:
			key = String(mi.get_parent().name)
		if key in ITEM_NAMES and mi.mesh:
			out[key] = _toonified(mi.mesh)
	scene.free()
	return out


## Copia della mesh con i materiali toon dello stesso colore
static func _toonified(mesh: Mesh) -> Mesh:
	var m := mesh.duplicate() as Mesh
	for s in m.get_surface_count():
		var src := m.surface_get_material(s)
		var col := Color.WHITE
		if src is BaseMaterial3D:
			col = (src as BaseMaterial3D).albedo_color
		m.surface_set_material(s, ToonMaterials.get_material(col))
	return m


## Tessera segnaposto squadrata: erba sui quarti di terra, scogliera sui bordi interni verso i quarti vuoti
static func _placeholder(mask: int) -> ArrayMesh:
	var quads := {
		NW: Rect2(-0.5, -0.5, 0.5, 0.5), NE: Rect2(0.0, -0.5, 0.5, 0.5),
		SE: Rect2(0.0, 0.0, 0.5, 0.5), SW: Rect2(-0.5, 0.0, 0.5, 0.5),
	}
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_wall := false
	for bit in quads:
		if mask & bit:
			_add_top(top, quads[bit])
	var edges := [
		[NW, NE, Vector2(0.0, -0.5), Vector2(0.0, 0.0)],
		[SW, SE, Vector2(0.0, 0.0), Vector2(0.0, 0.5)],
		[NW, SW, Vector2(-0.5, 0.0), Vector2(0.0, 0.0)],
		[NE, SE, Vector2(0.0, 0.0), Vector2(0.5, 0.0)],
	]
	for e in edges:
		var a_land: bool = mask & e[0] != 0
		var b_land: bool = mask & e[1] != 0
		if a_land == b_land:
			continue
		var land_c: Vector2 = (quads[e[0]] if a_land else quads[e[1]]).get_center()
		var empty_c: Vector2 = (quads[e[1]] if a_land else quads[e[0]]).get_center()
		var n := (empty_c - land_c).normalized()
		_add_wall(wall, e[2], e[3], Vector3(n.x, 0.0, n.y))
		has_wall = true
	var mesh := ArrayMesh.new()
	top.set_material(ToonMaterials.get_material(GRASS))
	top.commit(mesh)
	if has_wall:
		wall.set_material(ToonMaterials.get_material(CLIFF))
		wall.commit(mesh)
	return mesh


static func _add_top(st: SurfaceTool, r: Rect2) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	st.set_normal(Vector3.UP)
	for v in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]:
		st.add_vertex(v)


## Parete verticale lungo il segmento p1-p2 (in XZ), rivolta verso n
static func _add_wall(st: SurfaceTool, p1: Vector2, p2: Vector2, n: Vector3) -> void:
	var right := Vector3.UP.cross(n)
	var a := p1
	var b := p2
	if Vector3(a.x, 0, a.y).dot(right) > Vector3(b.x, 0, b.y).dot(right):
		a = p2
		b = p1
	var h := -CLIFF_HEIGHT
	var ta := Vector3(a.x, 0, a.y)
	var tb := Vector3(b.x, 0, b.y)
	var bb := Vector3(b.x, h, b.y)
	var ba := Vector3(a.x, h, a.y)
	st.set_normal(n)
	for v in [ta, tb, bb, ta, bb, ba]:
		st.add_vertex(v)
