# scripts/combat/SpawnPoint.gd
# Punto di spawn stile Metin2 "regen": lo piazzi sulla mappa (in red_plains_map.tscn)
# e definisce COSA spawna, QUANTO, in che RAGGIO e con quale TIMER di respawn.
# ZoneCombatController scansiona questi nodi e gestisce spawn + respawn.
# @tool: disegna un gizmo nell'editor per vederlo/posizionarlo.
@tool
extends Node2D
class_name SpawnPoint

enum Kind { MOB, METIN, RESOURCE }

# --- Comune ---
@export var kind: Kind = Kind.MOB:
	set(v):
		kind = v
		queue_redraw()
## Raggio entro cui spawnano le entità attorno al punto (px world)
@export_range(0.0, 1024.0, 1.0) var spawn_radius: float = 100.0:
	set(v):
		spawn_radius = v
		queue_redraw()
## Secondi prima di rigenerare dopo che il punto è stato "ripulito"
@export var respawn_time: float = 15.0

# --- MOB / GRUPPO ---
## Pool di nemici (id da enemies.json). count > 1 o più id = gruppo/branco
@export var enemy_ids: Array[String] = ["lupo"]
@export var count: int = 4
@export var level_min: int = 1
@export var level_max: int = 10

# --- METIN ---
@export var metin_id: String = "metin"
## Mob che spawnano quando la pietra viene distrutta (ondata)
@export var metin_adds_ids: Array[String] = ["lupo"]
@export var metin_adds_count: int = 5

# --- RISORSA ---
## Tipo di nodo gathering (mining_node / gathering_node / fishing_pond)
@export var resource_node_id: String = "mining_node"

func _ready() -> void:
	if not Engine.is_editor_hint():
		# A runtime il gizmo non serve; il controller usa solo i dati.
		visible = false

# Gizmo nell'editor: cerchio del raggio + etichetta colorata per tipo
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := _kind_color()
	draw_circle(Vector2.ZERO, spawn_radius, Color(col.r, col.g, col.b, 0.12))
	draw_arc(Vector2.ZERO, spawn_radius, 0.0, TAU, 48, col, 2.0, true)
	draw_circle(Vector2.ZERO, 8.0, col)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10, -10), _label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

func _kind_color() -> Color:
	match kind:
		Kind.METIN:    return Color(0.9, 0.4, 0.2)
		Kind.RESOURCE: return Color(0.4, 0.8, 0.9)
		_:             return Color(0.9, 0.3, 0.3)

func _label() -> String:
	match kind:
		Kind.MOB:      return "MOB x%d (%s)" % [count, ", ".join(enemy_ids)]
		Kind.METIN:    return "METIN (%s)" % metin_id
		Kind.RESOURCE: return "RES (%s)" % resource_node_id
		_:             return "SPAWN"
