@tool
class_name DualGridTerrain3D
extends Node3D
## Terreno a tessere 3D. Si dipinge solo terra/acqua nel GridMap figlio "LandPaint" (1 cella = 1 m,
## piano Y = 0): le tessere visive (erba, bordi, angoli, scogliere) vengono scelte e ruotate da sole
## e rigenerate mentre dipingi nell'editor. "LandPaint" è visibile solo nell'editor.

@export_tool_button("Rigenera tessere", "Reload") var regenerate_button: Callable = regenerate
@export var auto_regenerate_in_editor: bool = true

var _tiles: GridMap
var _land: Dictionary = {}
var _last_hash: int = 0
var _check_timer: float = 0.0


func _ready() -> void:
	regenerate()
	var paint := _paint()
	if paint and not Engine.is_editor_hint():
		paint.visible = false


func _process(delta: float) -> void:
	if not (Engine.is_editor_hint() and auto_regenerate_in_editor):
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.3
	var paint := _paint()
	if paint and hash(paint.get_used_cells()) != _last_hash:
		regenerate()


func _paint() -> GridMap:
	return get_node_or_null("LandPaint") as GridMap


func regenerate() -> void:
	var paint := _paint()
	if paint == null:
		return
	var cells := paint.get_used_cells()
	_last_hash = hash(cells)
	_land.clear()
	for c in cells:
		_land[Vector2i(c.x, c.z)] = true
	if _tiles == null or not is_instance_valid(_tiles):
		_tiles = get_node_or_null("Tiles") as GridMap
	if _tiles == null:
		_tiles = GridMap.new()
		_tiles.name = "Tiles"
		_tiles.cell_size = Vector3.ONE
		_tiles.cell_center_x = false
		_tiles.cell_center_y = false
		_tiles.cell_center_z = false
		add_child(_tiles)
	if _tiles.mesh_library == null:
		_tiles.mesh_library = TerrainTiles.build_library()
	_tiles.clear()
	if _land.is_empty():
		return
	var r := land_rect()
	var i0 := int(r.position.x)
	var j0 := int(r.position.y)
	for j in range(j0, int(r.end.y) + 1):
		for i in range(i0, int(r.end.x) + 1):
			var m := _mask(i, j)
			if m == 0:
				continue
			var item: int
			var turns: int
			if m == 15:
				var h := absi(hash(Vector2i(i, j)))
				item = TerrainTiles.Item.FULL if h % 10 < 7 else (TerrainTiles.Item.FULL_B if h % 10 < 9 else TerrainTiles.Item.FULL_C)
				turns = (h / 10) % 4
			else:
				var lk := TerrainTiles.lookup(m)
				item = lk[0]
				turns = lk[1]
			var orient := _tiles.get_orthogonal_index_from_basis(Basis(Vector3.UP, turns * PI * 0.5))
			_tiles.set_cell_item(Vector3i(i, 0, j), item, orient)


## Maschera dei 4 quarti della tessera sull'angolo (i, j): NO=1, NE=2, SE=4, SO=8
func _mask(i: int, j: int) -> int:
	var m := 0
	if is_land(Vector2i(i - 1, j - 1)):
		m |= TerrainTiles.NW
	if is_land(Vector2i(i, j - 1)):
		m |= TerrainTiles.NE
	if is_land(Vector2i(i, j)):
		m |= TerrainTiles.SE
	if is_land(Vector2i(i - 1, j)):
		m |= TerrainTiles.SW
	return m


func is_land(cell: Vector2i) -> bool:
	return _land.has(cell)


func land_cells() -> Array:
	return _land.keys()


## Rettangolo XZ (in metri) che contiene tutta la terra
func land_rect() -> Rect2:
	if _land.is_empty():
		return Rect2()
	var mn := Vector2i(1 << 30, 1 << 30)
	var mx := Vector2i(-(1 << 30), -(1 << 30))
	for c in _land:
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	return Rect2(Vector2(mn), Vector2(mx - mn + Vector2i.ONE))
