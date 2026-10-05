extends Control
## Prova della Fase 4: la zona di combattimento 3D con il vero SkillCastController (skill automatiche),
## la zona Red Plains dai dati di zones.json e le rotte salvate. I salvataggi automatici vanno su un
## file di prova, così il salvataggio vero non viene toccato. Vita e mana del player vengono ricaricati.
## Argomenti (dopo "--"): --shots=<cartella> --at=5,20  screenshot ai secondi indicati, poi esce con un resoconto.
##   --start=mob  parte accanto al branco di lupi (per provare subito il combattimento con i lupi)
##   --start=tree player fermo subito dietro un albero (prova della chioma trasparente)
##   --equip=defaults  indossa le skin base invece dell'equipaggiamento del salvataggio

const ZONE_SCENE := preload("res://scenes/world3d/ZoneCombat3D.tscn")
const TEST_SAVE := "user://test3d_save.dat"
const LOADOUT := ["hiss", "sword_vortex", "three_way_slash", "battle_cry", "guard"]

var zcc: ZoneCombatController3D
var scc: SkillCastController

var _shot_dir: String = ""
var _start: String = ""
var _shot_times: Array[float] = []
var _elapsed: float = 0.0
var _capturing: bool = false
var _kills: int = 0
var _casts: Dictionary = {}
var _states: Dictionary = {}
var _player_off_land: int = 0
var _enemy_off_land: int = 0
var _frames: int = 0
var _damage_taken: float = 0.0


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.SAVE_PATH = TEST_SAVE
	zcc = ZONE_SCENE.instantiate()
	add_child(zcc)
	scc = SkillCastController.new()
	add_child(scc)
	if gs:
		scc.set_player(gs.character_stats)
		gs.character_stats.hp_changed.connect(_on_hp_changed)
	for i in LOADOUT.size():
		scc.equip_skill_to_slot(i, LOADOUT[i])
	scc.set_slot_manager(zcc)
	scc.set_battle_area(null)
	scc.skill_cast_started.connect(func(skill) -> void: _casts[skill.id] = _casts.get(skill.id, 0) + 1)
	zcc.set_skill_cast_controller(scc)
	zcc.player.state_changed.connect(func(s) -> void: _states[PlayerCharacter3D.PlayerState.keys()[s]] = true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shot_dir = a.substr(8)
		elif a.begins_with("--start="):
			_start = a.substr(8)
		elif a.begins_with("--at="):
			for t in a.substr(5).split(","):
				_shot_times.append(float(t))
	await zcc.setup(_zone_dict(), {})
	if _start == "mob":
		for sp in zcc.zone.spawn_points():
			if sp.kind == SpawnPoint3D.Kind.MOB:
				zcc.player.global_position = zcc._snap_to_nav(sp.global_position + Vector3(-2.5, 0, 0))
	if "--equip=defaults" in OS.get_cmdline_user_args():
		for slot in WarriorVisual.SLOTS:
			zcc.player.visual.equip_visual(slot, EquipmentVisuals.default_for(slot))
	if _start == "tree":
		for p in zcc.zone.get_node("Props").get_children():
			if p is Prop3D and p.prop_id.begins_with("tree") and zcc._is_on_land(p.position + Vector3(0, 0, -0.9)) and p.position.z > 12.0:
				zcc.player.global_position = p.position + Vector3(0, 0, -0.9)
				zcc.player.set_physics_process(false)
				zcc.camera_rig.distance = 7.0
				break
	scc.start_combat()


## Prima zona con mappa (Red Plains), come la costruisce BattleTab
func _zone_dict() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/zones.json"))
	for k in data.get("kingdoms", []):
		for z in k.get("zones", []):
			if str(z.get("scene_3d", "")) != "":
				var zd := ZoneData.from_dict(z)
				return {
					"id": zd.id, "name": zd.name, "level_range": zd.level_range, "enemies": zd.enemies,
					"gold_min": zd.gold_min, "gold_max": zd.gold_max, "xp_min": zd.xp_min, "xp_max": zd.xp_max,
					"default_routes": zd.default_routes, "world_size": zd.world_size,
					"gathering_node_types": zd.gathering_node_types,
				}
	return {}


var _last_hp: float = -1.0


func _on_hp_changed(current: float, _maximum: float) -> void:
	if _last_hp >= 0.0 and current < _last_hp:
		_damage_taken += _last_hp - current
	_last_hp = current


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	var gs = get_node_or_null("/root/GameState")
	if gs and Engine.get_process_frames() % 30 == 0:
		gs.character_stats.current_hp = gs.character_stats.get_stat("max_hp")
		gs.character_stats.current_mana = gs.character_stats.get_stat("max_mana")
		_last_hp = gs.character_stats.current_hp
	if zcc.zone and zcc.player:
		if not zcc._is_on_land(zcc.player.global_position):
			_player_off_land += 1
		for e in zcc.get_alive_enemies():
			if not e.has_meta("counted"):
				e.set_meta("counted", true)
				e.died.connect(func(_x) -> void: _kills += 1)
			if not zcc._is_on_land(e.global_position):
				_enemy_off_land += 1
	if not _capturing and not _shot_times.is_empty() and _elapsed >= _shot_times[0]:
		_capture(_shot_times.pop_front())


func _capture(t: float) -> void:
	_capturing = true
	await RenderingServer.frame_post_draw
	var path := _shot_dir.path_join("combat_%05.1fs.png" % t)
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	_capturing = false
	if _shot_times.is_empty():
		print("REPORT kills=%d casts=%s states=%s damage_taken=%.0f player_off_land=%d enemy_off_land_frames=%d frames=%d alive=%d gathering_nodes=%d" % [
			_kills, _casts, _states.keys(), _damage_taken, _player_off_land, _enemy_off_land, _frames,
			zcc.get_alive_enemies().size(), zcc._gathering_nodes.size()])
		get_tree().quit()
