extends GutTest
## Test di PlayerCharacter3D (port 3D di PlayerPathController): macchina a stati e rotta.

var _player: PlayerCharacter3D = null


func before_each() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_player = PlayerCharacter3D.new()
	world.add_child(_player)
	await get_tree().process_frame


func _path(points: Array) -> Array[Vector3]:
	var p: Array[Vector3] = []
	for v in points:
		p.append(v)
	return p


func test_initial_state_is_idle() -> void:
	assert_eq(_player.get_state(), PlayerCharacter3D.PlayerState.IDLE, "Il player deve partire in IDLE")


func test_set_path_transitions_to_following() -> void:
	_player.set_path(_path([Vector3(1, 0, 1), Vector3(3, 0, 1)]))
	assert_eq(_player.get_state(), PlayerCharacter3D.PlayerState.FOLLOWING_PATH, "Dopo set_path deve essere FOLLOWING_PATH")


func test_set_empty_path_stays_idle() -> void:
	_player.set_path(_path([]))
	assert_eq(_player.get_state(), PlayerCharacter3D.PlayerState.IDLE, "Path vuoto non deve cambiare stato")


func test_follows_path_without_navigation() -> void:
	_player.set_path(_path([Vector3(2, 0, 0), Vector3(2, 0, 2)]), false)
	for i in 30:
		await get_tree().physics_frame
	assert_gt(_player.global_position.x, 0.2, "Senza navmesh deve muoversi in linea retta verso il waypoint")


func test_on_all_enemies_dead_goes_returning() -> void:
	_player.set_path(_path([Vector3(1, 0, 1), Vector3(5, 0, 1)]))
	_player._set_state(PlayerCharacter3D.PlayerState.ENGAGING)
	_player.on_all_enemies_dead()
	assert_true(_player.get_state() == PlayerCharacter3D.PlayerState.RETURNING or _player.get_state() == PlayerCharacter3D.PlayerState.FOLLOWING_PATH,
		"Dopo on_all_enemies_dead deve tornare alla rotta")


func test_is_in_combat_states() -> void:
	_player._set_state(PlayerCharacter3D.PlayerState.ENGAGING)
	assert_true(_player.is_in_combat(), "ENGAGING = in combattimento")
	_player._set_state(PlayerCharacter3D.PlayerState.DEVIATING)
	assert_true(_player.is_in_combat(), "DEVIATING = in combattimento")
	_player._set_state(PlayerCharacter3D.PlayerState.FOLLOWING_PATH)
	assert_false(_player.is_in_combat(), "FOLLOWING_PATH non è combattimento")


func test_aggro_on_enemy_in_range() -> void:
	_player.set_path(_path([Vector3(0, 0, 0), Vector3(10, 0, 0)]))
	var enemy := Enemy3D.new()
	_player.get_parent().add_child(enemy)
	enemy.setup("lupo", 1, _player)
	enemy.global_position = Vector3(1.5, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_player.is_in_combat(), "Un nemico nel raggio d'aggro deve far deviare il player")


func test_nearest_waypoint() -> void:
	_player.global_position = Vector3(4.9, 0, 0)
	_player._path = _path([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(10, 0, 0)])
	assert_eq(_player._nearest_wp_index(), 1, "Deve trovare il waypoint più vicino")


func test_play_cast_maps_skills_to_animations() -> void:
	_player.play_cast("sword_vortex")
	assert_eq(_player.visual.current_animation(), "skill_sword_vortex", "Il Vortice della Spada deve usare la sua animazione")
	_player.play_cast("basic_attack")
	assert_true(_player.visual.current_animation().begins_with("attack"), "L'attacco base usa attack1/attack2")
