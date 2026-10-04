extends Node3D
## Prototipo 3D (Fase 2 di PIANO_3D.md): isola, warrior in autoplay contro manichini, raccolta,
## vetrina spade +0/+7/+8/+9, camera fissa, contorno toon, test prestazioni.
## Tasti: 1-4 spada +0/+7/+8/+9 · 5-8 armatura +0/+7/+8/+9 · H C B L S X equip on/off
##        K animazione morte · N +50 unità (prestazioni) · F camera segue on/off
##        F1-F6 animazioni delle skill (solo animazione: effetti e gameplay arrivano in Fase 5b)

enum State { IDLE, RUN, ATTACK, GATHER, HIT, DEAD, SKILL }

const RUN_SPEED := 3.2
const ATTACK_RANGE := 1.35
const GATHER_RANGE := 1.3
const ISLAND_RADIUS := 16.0
const KILLS_BEFORE_GATHER := 3
const GATHER_STROKES := 3
const ARMOR_SLOTS := ["helmet", "chest", "boots", "belt", "shield"]
const STATE_NAMES := ["IDLE", "RUN", "ATTACK", "GATHER", "HIT", "DEAD", "SKILL"]
const SKILL_ANIMS := ["skill_sword_aura", "skill_berserk", "skill_sword_vortex", "skill_three_way_slash", "skill_hiss", "skill_life_force"]

const GRASS := Color(0.56, 0.76, 0.33)
const CLIFF := Color(0.82, 0.68, 0.47)
const WATER := Color(0.28, 0.66, 0.66)
const TRUNK := Color(0.55, 0.38, 0.25)
const LEAVES := Color(0.32, 0.6, 0.3)
const LEAVES_LIGHT := Color(0.42, 0.7, 0.32)
const ROCK := Color(0.63, 0.65, 0.7)
const CRYSTAL := Color(0.45, 0.78, 0.98)

var warrior: WarriorVisual
var camera_rig: CameraRig3D
var dummies: Array[TrainingDummy3D] = []
var state: State = State.IDLE
var kills_total: int = 0

var _target: Node3D
var _attack_flip: bool = false
var _kills_since_gather: int = 0
var _hits: int = 0
var _counter_pending: bool = false
var _gather_strokes: int = 0
var _idle_timer: float = 0.6
var _ore: Node3D
var _showcase: Node3D
var _blocked: Array[Vector3] = []
var _stress: Array[WarriorVisual] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build_environment()
	_build_island()
	warrior = WarriorVisual.new()
	add_child(warrior)
	warrior.hit_moment.connect(_on_hit_moment)
	warrior.animation_done.connect(_on_animation_done)
	_ore = _build_ore(Vector3(6.5, 0, -5.0))
	_showcase = _build_sword_showcase(Vector3(-5.5, 0, 4.5))
	_blocked = [Vector3.ZERO, _ore.position, _showcase.position]
	_build_props()
	for i in 3:
		_spawn_dummy()
	camera_rig = CameraRig3D.new()
	camera_rig.target = warrior
	add_child(camera_rig)


## Opzioni dal contenitore (argomenti da riga di comando, usati per screenshot e misure)
func configure(opts: Dictionary) -> void:
	if opts.has("weapon"):
		warrior.set_enhancement("weapon", int(opts["weapon"]))
	if opts.has("armor"):
		for s in ARMOR_SLOTS:
			warrior.set_enhancement(s, int(opts["armor"]))
	if opts.has("stress"):
		spawn_stress(int(opts["stress"]))
	if opts.get("focus", "") == "showcase":
		camera_rig.target = _showcase
		camera_rig.global_position = _showcase.global_position
	elif opts.get("focus", "") == "warrior_close":
		camera_rig.pitch_deg = 30.0
	if opts.has("cam"):
		camera_rig.distance = float(opts["cam"])
	if opts.get("pose", "") == "death":
		_play_death()
	if opts.has("skill"):
		play_skill(String(opts["skill"]))


func state_name() -> String:
	return STATE_NAMES[state]


func hud_text() -> String:
	return "PROTOTIPO 3D  |  %s  |  spada +%d  |  armatura +%d  |  uccisioni %d  |  unità extra %d" % [
		state_name(), warrior.get_enhancement("weapon"), warrior.get_enhancement("chest"), kills_total, _stress.size()]


func help_text() -> String:
	return "F1-F6 skill · 1-4 spada +0/7/8/9 · 5-8 armatura · H C B L S X equip · K morte · N +50 unità"


# ==================== AUTOPLAY ====================

func _process(delta: float) -> void:
	_update_stress(delta)
	match state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_choose_next()
		State.RUN:
			_update_run(delta)
		State.ATTACK, State.GATHER, State.HIT:
			if is_instance_valid(_target):
				warrior.face_direction(_target.global_position - warrior.global_position)


func _choose_next() -> void:
	if _kills_since_gather >= KILLS_BEFORE_GATHER:
		_target = _ore
	else:
		_target = _nearest_dummy()
	if _target == null:
		_set_idle(0.5)
		return
	state = State.RUN
	warrior.play("run")


func _update_run(delta: float) -> void:
	if _target == null or (_target is TrainingDummy3D and not (_target as TrainingDummy3D).alive):
		_choose_next()
		return
	var to := _target.global_position - warrior.global_position
	to.y = 0.0
	var reach := GATHER_RANGE if _target == _ore else ATTACK_RANGE
	warrior.face_direction(to)
	if to.length() <= reach:
		if _target == _ore:
			state = State.GATHER
			_gather_strokes = 0
			warrior.play("gather", 0.1)
		else:
			state = State.ATTACK
			_play_attack()
		return
	warrior.position += to.normalized() * minf(RUN_SPEED * delta, to.length() - reach)


func _play_attack() -> void:
	warrior.play("attack2" if _attack_flip else "attack1", 0.08, true)
	_attack_flip = not _attack_flip


func _on_hit_moment(anim_name: String) -> void:
	if anim_name.begins_with("attack") and _target is TrainingDummy3D:
		var d := _target as TrainingDummy3D
		if d.alive:
			d.take_hit(_rng.randi_range(8, 15), d.global_position - warrior.global_position)
			_hits += 1
			_counter_pending = d.alive and _hits % 5 == 0
	elif anim_name == "gather" and state == State.GATHER:
		_gather_strokes += 1
		_punch(_ore)
		if _gather_strokes >= GATHER_STROKES:
			_kills_since_gather = 0
			_set_idle(0.4)


func _on_animation_done(anim_name: String) -> void:
	if state == State.ATTACK and anim_name.begins_with("attack"):
		var alive := _target is TrainingDummy3D and (_target as TrainingDummy3D).alive
		if _counter_pending and alive:
			_counter_pending = false
			state = State.HIT
			warrior.play("hit", 0.05, true)
		elif alive:
			_play_attack()
		else:
			_set_idle(0.35)
	elif state == State.SKILL and anim_name.begins_with("skill_"):
		_set_idle(0.3)
	elif state == State.HIT and anim_name == "hit":
		if _target is TrainingDummy3D and (_target as TrainingDummy3D).alive:
			state = State.ATTACK
			_play_attack()
		else:
			_set_idle(0.3)


func _set_idle(wait: float) -> void:
	state = State.IDLE
	_idle_timer = wait
	warrior.play("idle")


## Riproduce l'animazione di una skill (prova visiva: niente effetti né danni per ora)
func play_skill(anim_name: String) -> void:
	state = State.SKILL
	warrior.play(anim_name, 0.08, true)


func _play_death() -> void:
	state = State.DEAD
	warrior.play("death", 0.05, true)
	await get_tree().create_timer(2.5).timeout
	_set_idle(0.3)


func _nearest_dummy() -> TrainingDummy3D:
	var best: TrainingDummy3D = null
	var best_d := INF
	for d in dummies:
		if d.alive:
			var dist := d.global_position.distance_squared_to(warrior.global_position)
			if dist < best_d:
				best_d = dist
				best = d
	return best


func _spawn_dummy() -> void:
	var d := TrainingDummy3D.new()
	add_child(d)
	d.position = _random_free_pos(3.0, 10.0)
	d.died.connect(_on_dummy_died)
	dummies.append(d)


func _on_dummy_died(d: TrainingDummy3D) -> void:
	kills_total += 1
	_kills_since_gather += 1
	await get_tree().create_timer(2.0).timeout
	d.respawn_at(_random_free_pos(3.0, 10.0))


func _random_free_pos(r_min: float, r_max: float) -> Vector3:
	for attempt in 40:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(r_min, r_max)
		var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var ok := true
		for b in _blocked:
			if p.distance_to(b) < 2.0:
				ok = false
		for d in dummies:
			if d.alive and p.distance_to(d.position) < 2.0:
				ok = false
		if ok:
			return p
	return Vector3(r_min, 0, 0)


func _punch(n: Node3D) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(1.12, 0.88, 1.12), 0.06)
	tw.tween_property(n, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)


# ==================== INPUT ====================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var levels := [0, 7, 8, 9]
	var k := (event as InputEventKey).keycode
	if k >= KEY_F1 and k <= KEY_F6:
		play_skill(SKILL_ANIMS[k - KEY_F1])
	elif k >= KEY_1 and k <= KEY_4:
		warrior.set_enhancement("weapon", levels[k - KEY_1])
	elif k >= KEY_5 and k <= KEY_8:
		for s in ARMOR_SLOTS:
			warrior.set_enhancement(s, levels[k - KEY_5])
	else:
		var toggles := {KEY_H: "helmet", KEY_C: "chest", KEY_B: "boots", KEY_L: "belt", KEY_S: "shield", KEY_X: "weapon"}
		if toggles.has(k):
			var slot: String = toggles[k]
			warrior.set_slot_equipped(slot, not warrior.is_slot_equipped(slot))
		elif k == KEY_K:
			_play_death()
		elif k == KEY_N:
			spawn_stress(50)
		elif k == KEY_F:
			camera_rig.follow = not camera_rig.follow


# ==================== PRESTAZIONI ====================

func spawn_stress(count: int) -> void:
	for i in count:
		var u := WarriorVisual.new()
		u.tint = Color(1.0, 0.78, 0.72)
		add_child(u)
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(3.0, 14.0)
		u.position = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		u.set_meta("center", u.position)
		u.set_meta("phase", _rng.randf() * TAU)
		u.set_meta("radius", _rng.randf_range(0.8, 2.0))
		u.set_meta("mode", i % 3)
		match i % 3:
			0: u.play("run")
			1: u.play("gather")
			2: u.play("idle")
		if i % 5 == 0:
			u.set_enhancement("weapon", 9)
		_stress.append(u)


func _update_stress(delta: float) -> void:
	for u in _stress:
		if u.get_meta("mode") != 0:
			continue
		var r: float = u.get_meta("radius")
		var ph: float = u.get_meta("phase") + delta * RUN_SPEED / r
		u.set_meta("phase", ph)
		var c: Vector3 = u.get_meta("center")
		u.position = c + Vector3(cos(ph), 0.0, sin(ph)) * r
		u.face_direction(Vector3(-sin(ph), 0.0, cos(ph)))


func stress_count() -> int:
	return _stress.size()


# ==================== COSTRUZIONE SCENA ====================

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = WorldLook3D.make_environment()
	add_child(we)
	add_child(WorldLook3D.make_sun())


func _mesh(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ToonMaterials.get_material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_island() -> void:
	var water := PlaneMesh.new()
	water.size = Vector2(300, 300)
	_mesh(water, WATER, Vector3(0, -0.7, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cliff := CylinderMesh.new()
	cliff.top_radius = ISLAND_RADIUS
	cliff.bottom_radius = ISLAND_RADIUS + 0.4
	cliff.height = 1.0
	cliff.radial_segments = 40
	_mesh(cliff, CLIFF, Vector3(0, -0.56, 0))
	var grass := CylinderMesh.new()
	grass.top_radius = ISLAND_RADIUS + 0.05
	grass.bottom_radius = ISLAND_RADIUS + 0.05
	grass.height = 0.08
	grass.radial_segments = 40
	_mesh(grass, GRASS, Vector3(0, -0.04, 0))


func _build_props() -> void:
	for i in 16:
		var p := _random_free_pos(5.0, ISLAND_RADIUS - 1.0)
		_blocked.append(p)
		_build_tree(p, _rng.randf_range(0.8, 1.35))
	for i in 9:
		var rock := SphereMesh.new()
		rock.radius = 0.35
		rock.height = 0.5
		rock.radial_segments = 6
		rock.rings = 3
		var mi := _mesh(rock, ROCK, _random_free_pos(3.0, ISLAND_RADIUS - 0.8) + Vector3(0, 0.08, 0))
		mi.rotation.y = _rng.randf() * TAU
		mi.scale = Vector3.ONE * _rng.randf_range(0.6, 1.4)


func _build_tree(pos: Vector3, s: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * s
	tree.rotation.y = _rng.randf() * TAU
	add_child(tree)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.13
	trunk.height = 0.7
	trunk.radial_segments = 6
	_mesh(trunk, TRUNK, Vector3(0, 0.35, 0), tree)
	var crown := SphereMesh.new()
	crown.radius = 0.62
	crown.height = 1.1
	crown.radial_segments = 7
	crown.rings = 4
	_mesh(crown, LEAVES, Vector3(0, 1.15, 0), tree)
	var top := SphereMesh.new()
	top.radius = 0.42
	top.height = 0.75
	top.radial_segments = 7
	top.rings = 4
	_mesh(top, LEAVES_LIGHT, Vector3(0.12, 1.65, 0.05), tree)


func _build_ore(pos: Vector3) -> Node3D:
	var ore := Node3D.new()
	ore.position = pos
	add_child(ore)
	var rock := SphereMesh.new()
	rock.radius = 0.6
	rock.height = 0.9
	rock.radial_segments = 7
	rock.rings = 4
	_mesh(rock, ROCK, Vector3(0, 0.3, 0), ore)
	for i in 4:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.12
		c.height = 0.55
		c.radial_segments = 5
		var mi := _mesh(c, CRYSTAL, Vector3(cos(i * 1.7) * 0.3, 0.65, sin(i * 1.7) * 0.3), ore)
		mi.rotation = Vector3(sin(i * 2.1) * 0.5, 0.0, cos(i * 1.3) * 0.5)
	return ore


func _build_sword_showcase(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var sword_mesh := warrior.get_slot_mesh("weapon").mesh
	var aabb := sword_mesh.get_aabb()
	var levels := [0, 7, 8, 9]
	for i in levels.size():
		var x := (i - 1.5) * 1.3
		var ped := CylinderMesh.new()
		ped.top_radius = 0.28
		ped.bottom_radius = 0.34
		ped.height = 0.3
		ped.radial_segments = 8
		_mesh(ped, ROCK, Vector3(x, 0.15, 0), root)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.95, 0)
		pivot.scale = Vector3.ONE * 1.8
		pivot.set_meta("spin", true)
		root.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = sword_mesh
		ToonMaterials.apply_to_mesh(mi)
		mi.rotation = _upright_rotation(aabb.size)
		mi.position = -(Basis.from_euler(mi.rotation) * aabb.get_center())
		pivot.add_child(mi)
		Enhancement3D.apply(mi, levels[i], true)
		var label := Label3D.new()
		label.text = "+%d" % levels[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.outline_size = 14
		label.pixel_size = 0.004
		label.position = Vector3(x, 0.45, 0.45)
		root.add_child(label)
	return root


## Ruota la spada in verticale: l'asse più lungo del suo AABB diventa Y
func _upright_rotation(size: Vector3) -> Vector3:
	if size.x >= size.y and size.x >= size.z:
		return Vector3(0, 0, PI * 0.5)
	if size.z >= size.y and size.z >= size.x:
		return Vector3(PI * 0.5, 0, 0)
	return Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _showcase:
		for c in _showcase.get_children():
			if c.has_meta("spin"):
				(c as Node3D).rotation.y += delta * 0.8
