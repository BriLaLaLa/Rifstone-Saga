extends GutTest
## Test suite per ZoneCombatController (Step 2-4 — combat overhaul)
## Testa: spawn ondata, costruzione route, targeting, clear_combat.

var _zcc: Node = null

const ZONE := {
	"id":          "test_zone",
	"name":        "Test Zone",
	"level_range": [1, 1],
	"enemies":     ["test_dummy"],
	"gold_min":    1, "gold_max": 1, "xp_min": 1, "xp_max": 1,
	"default_routes": [
		{"id": "r1", "name": "Route 1", "loop": true,
			"waypoints": [{"x": 100, "y": 100}, {"x": 200, "y": 100}]},
		{"id": "r2", "name": "Route 2", "loop": true,
			"waypoints": [{"x": 300, "y": 300}, {"x": 400, "y": 300}]},
	],
}

func before_each() -> void:
	var scene = preload("res://scenes/combat/ZoneCombatScene.tscn")
	_zcc = scene.instantiate()
	add_child_autofree(_zcc)
	await get_tree().process_frame
	await _zcc.setup(ZONE, ZONE["default_routes"][0])
	await get_tree().process_frame

# ==================== SPAWN ====================

func test_wave_spawns_enemies_in_range() -> void:
	assert_between(_zcc._enemies.size(), 3, 6,
		"Un'ondata deve avere tra 3 e 6 nemici")

func test_spawned_enemies_are_alive() -> void:
	for e in _zcc._enemies:
		assert_true(e.is_alive(), "Ogni nemico spawnato deve essere vivo")

# ==================== ROUTES ====================

func test_routes_built_from_defaults() -> void:
	assert_eq(_zcc._available_routes.size(), 2,
		"Devono esserci 2 route default")

func test_current_route_is_first_by_default() -> void:
	assert_eq(str(_zcc.current_route.get("id", "")), "r1",
		"Senza scelta salvata deve usare la prima route")

# ==================== TARGETING ====================

func test_get_alive_enemy_count_non_negative() -> void:
	assert_gt(_zcc.get_alive_enemy_count() + 1, 0,
		"get_alive_enemy_count non deve essere negativo")

func test_get_all_alive_enemies_returns_array() -> void:
	assert_typeof(_zcc.get_all_alive_enemies(), TYPE_ARRAY,
		"get_all_alive_enemies deve ritornare un Array")

# ==================== CLEANUP ====================

func test_clear_combat_empties_enemies() -> void:
	_zcc.clear_combat()
	assert_eq(_zcc._enemies.size(), 0,
		"clear_combat deve svuotare la lista nemici")
