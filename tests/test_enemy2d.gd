extends GutTest
## Test suite per Enemy2D (Step 2-3 — combat overhaul)
## Testa: setup stats, take_damage, morte, is_alive, reazione aggro.

var _enemy: Node = null
var _player: Node2D = null

func before_each() -> void:
	# Container Node2D: il nemico DEVE stare sotto un Node2D (come nel gioco),
	# altrimenti i DamageNumber accedono a global_position su un Node e falliscono.
	var world := Node2D.new()
	add_child_autofree(world)

	_player = Node2D.new()
	world.add_child(_player)
	_player.global_position = Vector2.ZERO

	var scene = preload("res://scenes/combat/Enemy2D.tscn")
	_enemy = scene.instantiate()
	world.add_child(_enemy)
	await get_tree().process_frame
	# id sconosciuto → EnemyDatabase usa il fallback (base_hp 100)
	_enemy.setup("test_dummy", 1, _player)

# ==================== SETUP / STATS ====================

func test_setup_populates_hp() -> void:
	assert_gt(_enemy.max_hp, 0.0, "max_hp deve essere > 0 dopo setup")
	assert_eq(_enemy.current_hp, _enemy.max_hp, "current_hp deve partire = max_hp")

func test_is_alive_initially() -> void:
	assert_true(_enemy.is_alive(), "Un nemico appena creato deve essere vivo")

# ==================== DAMAGE / DEATH ====================

func test_take_damage_reduces_hp() -> void:
	var before: float = _enemy.current_hp
	_enemy.take_damage(10.0)
	assert_eq(_enemy.current_hp, before - 10.0, "take_damage deve sottrarre l'HP")

func test_lethal_damage_kills_and_emits() -> void:
	watch_signals(_enemy)
	_enemy.take_damage(_enemy.max_hp + 100.0)
	assert_false(_enemy.is_alive(), "Dopo danno letale non deve essere vivo")
	assert_signal_emitted(_enemy, "died", "La morte deve emettere 'died'")

func test_dead_enemy_ignores_further_damage() -> void:
	_enemy.take_damage(_enemy.max_hp + 100.0)
	var hp_after_death: float = _enemy.current_hp
	_enemy.take_damage(10.0)
	assert_eq(_enemy.current_hp, hp_after_death,
		"Un nemico morto non deve subire altro danno")

# ==================== AGGRO ====================

func test_stays_idle_when_player_far() -> void:
	_enemy.position = Vector2(2000, 2000)  # ben oltre aggro_range
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_enemy.state, 0, "Con player lontano deve restare IDLE (0)")

func test_aggro_reacts_when_player_close() -> void:
	_enemy.position = Vector2(40, 0)  # player a (0,0), dist 40 < aggro_range
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_ne(_enemy.state, 0, "Con player vicino il nemico non deve restare IDLE")
