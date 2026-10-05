extends GutTest
## Nuovo set di skill del warrior (SKILLS_WARRIOR.md): Aura della Spada, Estasi da Combattimento,
## Volontà di Vivere, conversione dei loadout vecchi (Guardia, Grido di Battaglia) e skill sincronizzate
## con gli eventi delle animazioni nel combattimento 3D.


class FakeStats:
	extends RefCounted
	var current_mana: float = 500.0
	var healed: float = 0.0
	var modifiers: Array = []

	func get_stat(_name: String) -> float:
		return 0.0

	func heal(amount: float) -> float:
		healed += amount
		return amount

	func consume_mana(_amount: float) -> bool:
		return true

	func restore_mana(_amount: float) -> void:
		pass

	func add_temporary_modifier(m: Dictionary, _duration: float = 0.0) -> void:
		modifiers.append(m)

	func remove_temporary_modifier(id: String) -> void:
		modifiers = modifiers.filter(func(m): return m.get("id", "") != id)


class FakeEnemy:
	extends Node3D
	var damage_taken: int = 0
	var hits: int = 0
	var stunned: float = 0.0

	func take_damage(amount: float) -> void:
		damage_taken += int(amount)
		hits += 1

	func stun(d: float) -> void:
		stunned = d

	func is_alive() -> bool:
		return true

	func get_radius() -> float:
		return 0.3


class FakeSlots:
	extends RefCounted
	var enemies: Array = []

	func get_all_alive_enemies() -> Array:
		return enemies.duplicate()

	func get_random_alive_enemy():
		return enemies[0] if not enemies.is_empty() else null

	func get_alive_enemy_count() -> int:
		return enemies.size()


## Esecutore finto degli eventi (al posto di PlayerCharacter3D)
class FakeDriver:
	extends Node
	var queued: Array = []

	func accepts_skill_events() -> bool:
		return true

	func queue_skill_events(skill_id: String, targets: Array, cb: Callable) -> void:
		queued.append({"skill_id": skill_id, "targets": targets, "cb": cb})


var _scc: SkillCastController
var _stats: FakeStats
var _slots: FakeSlots


func before_each() -> void:
	_scc = SkillCastController.new()
	add_child_autofree(_scc)
	_stats = FakeStats.new()
	_slots = FakeSlots.new()
	_scc.set_player(_stats)
	_scc.set_slot_manager(_slots)


func _enemy() -> FakeEnemy:
	var e := FakeEnemy.new()
	add_child_autofree(e)
	_slots.enemies.append(e)
	return e


func _fixed(skill_id: String, dmg: int) -> WarriorSkill:
	var s := _scc.skill_db.get_skill(skill_id)
	s.damage_min = dmg
	s.damage_max = dmg
	return s


# ==================== DATABASE ====================

func test_database_has_new_set() -> void:
	var db := SkillDatabase.new()
	for id in ["basic_attack", "sword_aura", "berserk", "sword_vortex", "three_way_slash", "hiss", "life_force"]:
		assert_true(db.skills.has(id), "Manca la skill %s" % id)
	assert_false(db.skills.has("guard"), "Guardia deve essere tolta")
	assert_false(db.skills.has("battle_cry"), "Grido di Battaglia è diventato Estasi")
	var b := db.get_skill("berserk")
	assert_eq(b.get_effect_value("attack_percent"), 40.0)
	assert_eq(b.get_effect_value("defense_percent"), -30.0)
	assert_eq(b.get_effect_value("attack_speed_percent"), 20.0)


func test_legacy_ids_map_to_new_skills() -> void:
	var db := SkillDatabase.new()
	assert_eq(db.get_skill("guard").id, "sword_aura", "Guardia → Aura della Spada")
	assert_eq(db.get_skill("battle_cry").id, "berserk", "Grido di Battaglia → Estasi")


func test_migrate_loadout_slots() -> void:
	var out := SkillDatabase.migrate_loadout_slots(["warrior_guard", "warrior_battle_cry", "warrior_hiss", "", "guard"])
	assert_eq(out, ["warrior_sword_aura", "warrior_berserk", "warrior_hiss", "", "sword_aura"])


func test_skills_json_cards_match_database() -> void:
	var cards: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	var ids := cards.map(func(c): return c["id"])
	for id in ["warrior_sword_aura", "warrior_berserk", "warrior_life_force"]:
		assert_true(id in ids, "Carta skill mancante: %s" % id)
	assert_false("warrior_guard" in ids)
	assert_false("warrior_battle_cry" in ids)
	var db := SkillDatabase.new()
	for c in cards:
		if c.has("skill_data"):
			assert_true(db.skills.has(c["skill_data"]["skill_id"]), "skill_id sconosciuto in %s" % c["id"])
	# ogni id convertito dai loadout vecchi esiste davvero
	for new_id in SkillDatabase.LEGACY_CARD_IDS.values():
		assert_true(new_id in ids)


func test_equip_legacy_id_in_controller() -> void:
	assert_true(_scc.equip_skill_to_slot(0, "guard"))
	assert_true(_scc.equip_skill_to_slot(1, "battle_cry"))
	assert_eq(_scc.loadout[0].id, "sword_aura")
	assert_eq(_scc.loadout[1].id, "berserk")


# ==================== AURA / ESTASI / VOLONTÀ DI VIVERE ====================

func test_aura_adds_fixed_damage_to_every_hit() -> void:
	var e := _enemy()
	var basic := _fixed("basic_attack", 20)
	_scc._apply_damage(basic, [e])
	assert_eq(e.damage_taken, 20, "Senza aura: danno base")
	_scc._apply_aura_buff(_scc.skill_db.get_skill("sword_aura"))
	assert_true(_scc.has_buff("sword_aura"))
	_scc._apply_damage(basic, [e])
	assert_eq(e.damage_taken, 20 + 28, "Con l'aura: +8 a colpo")


func test_berserk_buff_and_faster_casts() -> void:
	var base := _scc.get_cast_interval()
	_scc._apply_berserk_buff(_scc.skill_db.get_skill("berserk"))
	assert_true(_scc.has_buff("berserk"))
	assert_almost_eq(_scc.get_cast_interval(), base / 1.2, 0.001, "+20% velocità d'attacco")
	assert_eq(_stats.modifiers.size(), 1)
	# rilanciata: il modificatore non si somma
	_scc._apply_berserk_buff(_scc.skill_db.get_skill("berserk"))
	assert_eq(_stats.modifiers.size(), 1)


func test_life_force_heals_part_of_damage() -> void:
	_enemy()
	_enemy()
	var lf := _fixed("life_force", 50)
	var res := _scc.apply_skill_event(lf, [], "hit")
	assert_eq(res["damage"], 100, "Due nemici colpiti")
	assert_eq(res["heal"], 30.0, "Cura il 30% del danno")
	assert_eq(_stats.healed, 30.0)


func test_life_force_2d_path_heals() -> void:
	_enemy()
	var lf := _fixed("life_force", 40)
	_scc._apply_skill_effects(lf, [_slots.enemies[0]])
	assert_eq(_stats.healed, 12.0)


# ==================== EVENTI DELLE ANIMAZIONI ====================

func test_three_way_single_target_splits_damage() -> void:
	var e := _enemy()
	var tw := _fixed("three_way_slash", 30)
	for ev in ["hit1", "hit2", "hit3"]:
		_scc.apply_skill_event(tw, [e], ev)
	assert_eq(e.hits, 3, "Tre fendenti sullo stesso bersaglio")
	assert_eq(e.damage_taken, 30, "Il danno totale resta quello di un colpo")


func test_three_way_three_targets_one_hit_each() -> void:
	var a := _enemy()
	var b := _enemy()
	var c := _enemy()
	var tw := _fixed("three_way_slash", 30)
	for ev in ["hit1", "hit2", "hit3"]:
		_scc.apply_skill_event(tw, [a, b, c], ev)
	assert_eq([a.damage_taken, b.damage_taken, c.damage_taken], [30, 30, 30])


func test_hiss_event_damages_and_stuns() -> void:
	var e := _enemy()
	_scc.apply_skill_event(_fixed("hiss", 25), [e], "hit")
	assert_eq(e.damage_taken, 25)
	assert_eq(e.stunned, 1.5)


func test_event_mode_defers_effects_to_animation_events() -> void:
	var driver := FakeDriver.new()
	add_child_autofree(driver)
	_scc.set_event_driver(driver)
	var e := _enemy()
	_scc.equip_skill_to_slot(0, "hiss")
	_scc.start_combat()
	_scc.force_check_cast()
	assert_eq(driver.queued.size(), 1, "La skill va all'esecutore 3D")
	assert_eq(driver.queued[0]["skill_id"], "hiss")
	_scc._complete_casting()
	assert_eq(e.damage_taken, 0, "Nessun danno a fine cast: arriva con l'evento hit")
	var res: Dictionary = driver.queued[0]["cb"].call("hit", 0)
	assert_gt(e.damage_taken, 0, "Danno all'evento hit")
	assert_eq(res["targets"], [e])
	assert_eq(e.stunned, 1.5)


func test_buff_applied_on_event_not_at_cast() -> void:
	var driver := FakeDriver.new()
	add_child_autofree(driver)
	_scc.set_event_driver(driver)
	_enemy()
	_scc.equip_skill_to_slot(0, "sword_aura")
	_scc.start_combat()
	_scc.force_check_cast()
	_scc._complete_casting()
	assert_false(_scc.has_buff("sword_aura"), "L'aura parte all'evento on")
	driver.queued[0]["cb"].call("on", 0)
	assert_true(_scc.has_buff("sword_aura"))


func test_without_driver_effects_apply_at_cast_end() -> void:
	var e := _enemy()
	_scc.equip_skill_to_slot(0, "three_way_slash")
	_scc.start_combat()
	_scc.force_check_cast()
	_scc._complete_casting()
	assert_gt(e.damage_taken, 0, "Combat 2D: tutto a fine cast come prima")


# ==================== TABELLA EVENTI 3D ====================

func test_event_table_covers_three_styles() -> void:
	for prefix in ["", "gs_", "dual_"]:
		for anim in ["skill_sword_aura", "skill_berserk", "skill_sword_vortex", "skill_three_way_slash", "skill_hiss", "skill_life_force", "attack1", "attack2"]:
			assert_false(SkillEvents3D.events(prefix + anim).is_empty(), "Eventi mancanti per %s" % (prefix + anim))
	var ev := SkillEvents3D.events("gs_skill_three_way_slash")
	assert_eq(ev.map(func(e): return e[1]), ["hit1", "hit2", "hit3"])
	assert_almost_eq(float(ev[2][0]), 1.0, 0.001)
	assert_eq(SkillEvents3D.events("skill_sword_vortex").filter(func(e): return e[1] == "hit").size(), 3)


func test_event_windows() -> void:
	assert_eq(SkillEvents3D.window_progress("skill_hiss", "dash", 0.05), -1.0)
	assert_almost_eq(SkillEvents3D.window_progress("skill_hiss", "dash", 0.22), 0.5, 0.01)
	assert_eq(SkillEvents3D.trail_blades("dual_skill_three_way_slash", 0.35), "L")
	assert_eq(SkillEvents3D.trail_blades("dual_skill_three_way_slash", 0.7), "RL")


# ==================== PLAYER 3D COME ESECUTORE ====================

func _player3d() -> PlayerCharacter3D:
	var world := Node3D.new()
	add_child_autofree(world)
	var p := PlayerCharacter3D.new()
	world.add_child(p)
	await get_tree().process_frame
	return p


func test_player3d_is_event_driver() -> void:
	var p := await _player3d()
	assert_true(p.is_in_group(SkillCastController.EVENT_DRIVER_GROUP))
	assert_true(p.accepts_skill_events())
	assert_eq(_scc.get_event_driver(), p, "Il controller trova il player 3D visibile")
	p.visible = false
	assert_null(_scc.get_event_driver(), "Nascosto: si torna al comportamento 2D")


func test_player3d_cone_keeps_only_enemies_in_front() -> void:
	var p := await _player3d()
	p.visual.rotation.y = 0.0  # guarda verso +Z
	var front := _enemy()
	front.global_position = Vector3(0, 0, 1.5)
	var back := _enemy()
	back.global_position = Vector3(0, 0, -1.5)
	var far := _enemy()
	far.global_position = Vector3(0, 0, 6.0)
	var picked := p.filter_cone_targets([front, back, far], 3.0, 100.0, 5)
	assert_eq(picked, [front])


func test_player3d_applies_queued_events_if_animation_never_starts() -> void:
	var p := await _player3d()
	var calls: Array = []
	p.queue_skill_events("three_way_slash", [], func(ev: String, _i: int) -> Dictionary:
		calls.append(ev)
		return {})
	await get_tree().create_timer(0.4).timeout
	assert_eq(calls, ["hit1", "hit2", "hit3"], "Gli eventi non vanno persi")


func test_player3d_runs_events_with_animation() -> void:
	var p := await _player3d()
	var calls: Array = []
	p.queue_skill_events("hiss", [], func(ev: String, _i: int) -> Dictionary:
		calls.append(ev)
		return {})
	p.play_cast("hiss")
	await get_tree().create_timer(0.15).timeout
	assert_eq(calls, [], "Prima dell'evento hit non succede niente")
	await get_tree().create_timer(0.55).timeout
	assert_eq(calls, ["hit"], "Il colpo arriva con l'animazione")
