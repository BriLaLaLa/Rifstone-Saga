extends GutTest
## Test di Enemy3D (port 3D di Enemy2D): stats, danno, morte, aggro, stordimento.

var _world: Node3D = null
var _player: Node3D = null
var _enemy: Enemy3D = null


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_player = Node3D.new()
	_world.add_child(_player)
	_enemy = Enemy3D.new()
	_world.add_child(_enemy)
	await get_tree().process_frame
	_enemy.setup("lupo", 1, _player)


func test_setup_populates_hp() -> void:
	assert_gt(_enemy.max_hp, 0.0, "max_hp deve essere > 0 dopo setup")
	assert_eq(_enemy.current_hp, _enemy.max_hp, "current_hp deve partire = max_hp")


func test_is_alive_and_in_enemies_group() -> void:
	assert_true(_enemy.is_alive(), "Un nemico appena creato deve essere vivo")
	assert_true(_enemy.is_in_group("enemies"), "Deve stare nel gruppo 'enemies' (usato dal player per l'aggro)")


func test_take_damage_reduces_hp() -> void:
	var before := _enemy.current_hp
	_enemy.take_damage(10.0)
	assert_eq(_enemy.current_hp, before - 10.0, "take_damage deve sottrarre l'HP")


func test_lethal_damage_kills_and_emits() -> void:
	watch_signals(_enemy)
	_enemy.take_damage(_enemy.max_hp + 100.0)
	assert_false(_enemy.is_alive(), "Dopo danno letale non deve essere vivo")
	assert_signal_emitted(_enemy, "died", "La morte deve emettere 'died'")
	assert_false(_enemy.is_in_group("enemies"), "Da morto esce dal gruppo 'enemies'")


func test_dead_enemy_ignores_further_damage() -> void:
	_enemy.take_damage(_enemy.max_hp + 100.0)
	var hp_after_death := _enemy.current_hp
	_enemy.take_damage(10.0)
	assert_eq(_enemy.current_hp, hp_after_death, "Un nemico morto non deve subire altro danno")


func test_stays_idle_when_player_far() -> void:
	_enemy.global_position = Vector3(40, 0, 40)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_enemy.state, Enemy3D.EnemyState.IDLE, "Con player lontano deve restare IDLE")


func test_aggro_reacts_when_player_close() -> void:
	_enemy.global_position = Vector3(1.5, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_ne(_enemy.state, Enemy3D.EnemyState.IDLE, "Con player vicino il nemico non deve restare IDLE")


func test_stun_blocks_movement() -> void:
	_enemy.global_position = Vector3(2.5, 0, 0)
	_enemy.stun(1.0)
	var start := _enemy.global_position
	for i in 5:
		await get_tree().physics_frame
	assert_eq(_enemy.global_position, start, "Da stordito non deve muoversi")


func test_metin_is_static_and_emits_thresholds() -> void:
	var metin := Enemy3D.new()
	_world.add_child(metin)
	metin.setup("metin", 1, _player)
	metin.setup_metin()
	watch_signals(metin)
	metin.take_damage(metin.max_hp * 0.3)
	assert_true(metin.is_static, "La pietra Metin non si muove")
	assert_signal_emitted(metin, "hp_threshold_crossed", "Sotto il 75% deve chiamare l'ondata di adds")
