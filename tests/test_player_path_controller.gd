extends GutTest
## Test suite per PlayerPathController (Step 1 — combat overhaul)
## Testa: state machine, path following logic, nearest waypoint, fallback movement.

var _player: PlayerCharacter = null

# ==================== SETUP ====================

func before_each() -> void:
	var scene = preload("res://scenes/combat/ZoneCombatScene.tscn")
	var instance = scene.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame
	# Gerarchia: ZoneCombatScene/SubViewportContainer/SubViewport/GameWorld/PlayerCharacter
	_player = instance.get_node_or_null("SubViewportContainer/SubViewport/GameWorld/PlayerCharacter") as PlayerCharacter
	if not _player:
		fail_test("PlayerCharacter non trovato in GameWorld/PlayerCharacter")

# ==================== STATE MACHINE ====================

func test_initial_state_is_idle() -> void:
	assert_eq(_player.get_state(), PlayerCharacter.PlayerState.IDLE,
		"Il player deve partire in IDLE")

func test_set_path_transitions_to_following() -> void:
	var path: Array[Vector2] = [Vector2(100, 100), Vector2(200, 100)]
	_player.set_path(path)
	assert_eq(_player.get_state(), PlayerCharacter.PlayerState.FOLLOWING_PATH,
		"Dopo set_path deve essere FOLLOWING_PATH")

func test_set_empty_path_stays_idle() -> void:
	var empty: Array[Vector2] = []
	_player.set_path(empty)
	assert_eq(_player.get_state(), PlayerCharacter.PlayerState.IDLE,
		"Path vuoto non deve cambiare stato")

func test_on_all_enemies_dead_from_engaging_goes_returning() -> void:
	# Simula stato ENGAGING
	_player._set_state(PlayerCharacter.PlayerState.ENGAGING)
	var path: Array[Vector2] = [Vector2(100, 100), Vector2(300, 100)]
	_player._path = path
	_player._path_index = 0
	_player._target = path[0]
	_player.on_all_enemies_dead()
	assert_true(
		_player.get_state() == PlayerCharacter.PlayerState.RETURNING or
		_player.get_state() == PlayerCharacter.PlayerState.FOLLOWING_PATH,
		"Dopo on_all_enemies_dead deve essere RETURNING o FOLLOWING_PATH")

func test_is_in_combat_engaging() -> void:
	_player._set_state(PlayerCharacter.PlayerState.ENGAGING)
	assert_true(_player.is_in_combat(), "ENGAGING deve dare is_in_combat() = true")

func test_is_in_combat_deviating() -> void:
	_player._set_state(PlayerCharacter.PlayerState.DEVIATING)
	assert_true(_player.is_in_combat(), "DEVIATING deve dare is_in_combat() = true")

func test_is_not_in_combat_following() -> void:
	_player._set_state(PlayerCharacter.PlayerState.FOLLOWING_PATH)
	assert_false(_player.is_in_combat(), "FOLLOWING_PATH non deve dare is_in_combat() = true")

# ==================== PATH LOGIC ====================

func test_nearest_waypoint_returns_zero_on_empty_path() -> void:
	_player._path = []
	var idx = _player._nearest_wp_index()
	assert_eq(idx, 0, "Path vuoto deve ritornare indice 0")

func test_nearest_waypoint_finds_closest() -> void:
	_player.global_position = Vector2(310, 100)
	_player._path = [
		Vector2(100, 100),   # dist ~210
		Vector2(300, 100),   # dist ~10  ← più vicino
		Vector2(600, 100),   # dist ~290
	]
	var idx = _player._nearest_wp_index()
	assert_eq(idx, 1, "Deve trovare il waypoint più vicino (indice 1)")

func test_get_path_copy_returns_duplicate() -> void:
	var path: Array[Vector2] = [Vector2(50, 50), Vector2(200, 50)]
	_player.set_path(path)
	var copy = _player.get_path_copy()
	assert_eq(copy.size(), 2, "La copia del path deve avere 2 elementi")
	# Verifica che sia una copia, non lo stesso riferimento
	copy.append(Vector2(999, 999))
	assert_eq(_player._path.size(), 2, "Modificare la copia non deve alterare il path interno")

func test_path_loops_after_last_waypoint() -> void:
	var path: Array[Vector2] = [Vector2(100, 100), Vector2(200, 100)]
	_player.set_path(path, true)   # loop = true
	_player._path_index = 1        # ultimo waypoint
	_player._advance_wp()
	assert_eq(_player._path_index, 0, "Con loop=true deve tornare all'indice 0")

func test_path_stops_at_end_when_no_loop() -> void:
	var path: Array[Vector2] = [Vector2(100, 100), Vector2(200, 100)]
	_player.set_path(path, false)  # loop = false
	_player._path_index = 1
	_player._advance_wp()
	assert_eq(_player.get_state(), PlayerCharacter.PlayerState.IDLE,
		"Senza loop deve andare in IDLE alla fine del path")

# ==================== REACHED TARGET ====================

func test_reached_nav_target_when_close() -> void:
	_player.global_position = Vector2(100, 100)
	_player._target         = Vector2(110, 100)   # 10px di distanza < 22 (reach dist)
	assert_true(_player._reached(),
		"Deve considerare target raggiunto se distanza < waypoint_reach_dist")

func test_not_reached_nav_target_when_far() -> void:
	_player.global_position = Vector2(100, 100)
	_player._target         = Vector2(200, 100)   # 100px > 22
	assert_false(_player._reached(),
		"Non deve considerare target raggiunto se distanza > waypoint_reach_dist")

# ==================== SIGNAL EMISSION ====================

func test_state_changed_signal_emitted() -> void:
	watch_signals(_player)
	_player._set_state(PlayerCharacter.PlayerState.FOLLOWING_PATH)
	assert_signal_emitted(_player, "state_changed",
		"state_changed deve essere emesso al cambio di stato")

func test_state_changed_not_emitted_on_same_state() -> void:
	_player._set_state(PlayerCharacter.PlayerState.IDLE)
	watch_signals(_player)
	_player._set_state(PlayerCharacter.PlayerState.IDLE)
	assert_signal_not_emitted(_player, "state_changed",
		"state_changed NON deve essere emesso se lo stato non cambia")
