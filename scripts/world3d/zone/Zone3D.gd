@tool
class_name Zone3D
extends Node3D
## Zona 3D: terreno a tessere (Terrain), props (Props), punti di spawn (SpawnPoints), luce e ambiente.
## Acqua e fondale vengono generati attorno all'isola. In gioco costruisce la navigazione come il 2D:
## erba = camminabile, acqua = vuoto, alberi/rocce/ceppi = ostacoli, cespugli calpestabili.

const WATER_SHADER := preload("res://shaders/world3d/water.gdshader")
const WATER_LEVEL := -0.45
const SEABED_LEVEL := -1.1
const SEABED := Color(0.22, 0.52, 0.56)

@export var water_margin: float = 60.0
@export var agent_radius: float = 0.25
## Griglia della navmesh: 12.5 cm per aggirare bene anche sassi e ceppi piccoli
const NAV_CELL := 0.125

var nav_region: NavigationRegion3D


func _ready() -> void:
	_build_water()
	if not Engine.is_editor_hint():
		build_navigation()


func terrain() -> DualGridTerrain3D:
	return $Terrain as DualGridTerrain3D


func land_rect() -> Rect2:
	return terrain().land_rect()


func spawn_points() -> Array[SpawnPoint3D]:
	var out: Array[SpawnPoint3D] = []
	for c in $SpawnPoints.get_children():
		if c is SpawnPoint3D:
			out.append(c)
	return out


func _build_water() -> void:
	for n in ["Water", "Seabed"]:
		var old := get_node_or_null(n)
		if old:
			remove_child(old)
			old.queue_free()
	var r := land_rect()
	if r.size == Vector2.ZERO:
		r = Rect2(-20, -20, 40, 40)
	r = r.grow(water_margin)
	var center := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var plane := PlaneMesh.new()
	plane.size = r.size
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = center + Vector3(0, WATER_LEVEL, 0)
	add_child(water)
	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	seabed.mesh = plane
	seabed.material_override = ToonMaterials.get_material(SEABED)
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seabed.position = center + Vector3(0, SEABED_LEVEL, 0)
	add_child(seabed)


func build_navigation() -> void:
	var src := NavigationMeshSourceGeometryData3D.new()
	var faces := PackedVector3Array()
	for c in terrain().land_cells():
		var x0 := float(c.x)
		var z0 := float(c.y)
		var x1 := x0 + 1.0
		var z1 := z0 + 1.0
		faces.append_array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1),
			Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)])
	src.add_faces(faces, Transform3D.IDENTITY)
	for p in $Props.get_children():
		if p is Prop3D and (p as Prop3D).is_solid():
			var r := (p as Prop3D).footprint_radius()
			var outline := PackedVector3Array()
			for k in 8:
				var a := TAU * k / 8.0
				outline.append(p.position + Vector3(cos(a), 0.0, sin(a)) * r)
			# carve = false: l'ostacolo viene allargato del raggio del personaggio, come nel 2D
			src.add_projected_obstruction(outline, -0.5, 3.0, false)
	var nm := NavigationMesh.new()
	nm.cell_size = NAV_CELL
	nm.cell_height = NAV_CELL
	nm.agent_radius = agent_radius
	nm.agent_max_climb = 0.25
	nm.agent_height = 1.25
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	if nav_region and is_instance_valid(nav_region):
		nav_region.queue_free()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.navigation_mesh = nm
	# il bake mette i poligoni qualche voxel sopra l'erba: li riporto a Y = 0 così percorsi e terreno coincidono
	var verts := nm.get_vertices()
	if not verts.is_empty():
		var y := 0.0
		for v in verts:
			y += v.y
		nav_region.position.y = -y / verts.size()
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, NAV_CELL)
	add_child(nav_region)


## Punto camminabile a caso sull'isola (agganciato alla navmesh)
func random_land_point(rng: RandomNumberGenerator) -> Vector3:
	var cells := terrain().land_cells()
	if cells.is_empty():
		return Vector3.ZERO
	var c: Vector2i = cells[rng.randi() % cells.size()]
	var p := Vector3(c.x + rng.randf(), 0.0, c.y + rng.randf())
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, p)
