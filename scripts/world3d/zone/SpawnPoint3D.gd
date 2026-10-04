@tool
class_name SpawnPoint3D
extends Node3D
## Punto di spawn 3D: stessi dati di SpawnPoint (2D) con le misure in metri (1 m = 64 px).
## Nell'editor mostra un anello colorato (rosso mob, viola Metin, azzurro risorse).
## La logica di spawn (regen dei mob) arriva con il port del combattimento (Fase 4).

enum Kind { MOB, METIN, RESOURCE }

const KIND_COLORS := [Color(0.95, 0.3, 0.25), Color(0.7, 0.35, 1.0), Color(0.3, 0.75, 1.0)]

@export var kind: Kind = Kind.MOB:
	set(value):
		kind = value
		_update_gizmo()
@export_range(0.0, 16.0, 0.05) var spawn_radius: float = 1.5:
	set(value):
		spawn_radius = value
		_update_gizmo()
@export var respawn_time: float = 15.0

@export_group("Mob")
@export var enemy_ids: Array[String] = ["lupo"]
@export var count: int = 4
@export var level_min: int = 1
@export var level_max: int = 10

@export_group("Metin")
@export var metin_id: String = "metin"
@export var metin_adds_ids: Array[String] = ["lupo"]
@export var metin_adds_count: int = 5

@export_group("Risorsa")
@export var resource_node_id: String = "mining_node"

var _ring: MeshInstance3D


func _ready() -> void:
	_update_gizmo()


func _update_gizmo() -> void:
	if not is_inside_tree():
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	_ring.visible = Engine.is_editor_hint()
	var torus := TorusMesh.new()
	torus.outer_radius = maxf(spawn_radius, 0.2)
	torus.inner_radius = maxf(spawn_radius - 0.06, 0.14)
	torus.rings = 48
	_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = KIND_COLORS[kind]
	_ring.material_override = mat
	_ring.position = Vector3(0, 0.03, 0)
