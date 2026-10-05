extends GutTest
## Test di ZoneCombatController3D: caricamento zona Red Plains 3D, rotte in pixel convertite in metri,
## spawn dai punti di spawn, interfaccia bersagli per SkillCastController, pulizia.

var _zcc: ZoneCombatController3D = null

const ZONE := {
	"id": "test_zone_3d",
	"name": "Test Zone 3D",
	"level_range": [1, 1],
	"enemies": ["lupo"],
	"gold_min": 1, "gold_max": 1, "xp_min": 1, "xp_max": 1,
	"default_routes": [
		{"id": "r1", "name": "Route 1", "loop": true,
			"waypoints": [{"x": 1100, "y": 900}, {"x": 2100, "y": 800}]},
		{"id": "r2", "name": "Route 2", "loop": true,
			"waypoints": [{"x": 1500, "y": 1100}, {"x": 2000, "y": 1300}]},
	],
}


func before_each() -> void:
	_zcc = preload("res://scenes/world3d/ZoneCombat3D.tscn").instantiate()
	add_child_autofree(_zcc)
	await get_tree().process_frame
	await _zcc.setup(ZONE, ZONE["default_routes"][0])
	await get_tree().process_frame


func test_zone_loaded() -> void:
	assert_not_null(_zcc.zone, "La zona 3D deve essere caricata")
	assert_gt(_zcc.zone.terrain().land_cells().size(), 0, "La zona deve avere celle di terra")


func test_routes_built_from_defaults() -> void:
	assert_eq(_zcc._available_routes.size(), 2, "Devono esserci 2 route default")


func test_route_converted_to_meters_on_land() -> void:
	var path := _zcc.player.get_path_copy()
	assert_eq(path.size(), 2, "La rotta deve avere 2 waypoint")
	assert_almost_eq(path[0].x, 1100.0 / 64.0, 0.6, "I pixel diventano metri (1 m = 64 px)")
	assert_true(_zcc._is_on_land(path[0]), "Il primo waypoint deve stare sull'erba")


func test_player_starts_at_route_start() -> void:
	assert_true(_zcc._is_on_land(_zcc.player.global_position), "Il player parte sull'erba, a inizio rotta")


func test_spawn_points_spawn_enemies() -> void:
	assert_gt(_zcc.get_alive_enemies().size(), 0, "I punti di spawn della zona devono creare nemici")
	for e in _zcc.get_alive_enemies():
		assert_true(_zcc._is_on_land(e.global_position), "Ogni nemico spawna sull'erba")


func test_targeting_api() -> void:
	assert_typeof(_zcc.get_all_alive_enemies(), TYPE_ARRAY, "get_all_alive_enemies deve ritornare un Array")
	assert_gt(_zcc.get_alive_enemy_count() + 1, 0, "get_alive_enemy_count non negativo")


func test_clear_combat_empties_enemies() -> void:
	_zcc.clear_combat()
	assert_eq(_zcc._enemies.size(), 0, "clear_combat deve svuotare la lista nemici")
