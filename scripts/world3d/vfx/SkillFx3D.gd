class_name SkillFx3D
extends Node3D
## Effetti delle skill del warrior 3D, sincronizzati con le animazioni.
## Segue l'animazione corrente di un WarriorVisual: quando la posizione passa un evento della tabella
## (SkillEvents3D: hit / hit1-3 / on) emette `skill_event` (chi lo usa applica danni, buff, cure) e fa partire
## gli effetti di quell'evento. Gestisce anche le scie delle lame, le finestre (scatto, giro, carica)
## e gli effetti che durano (aura della spada, rabbia di Estasi).
##
## Uso: fx = SkillFx3D.new(); fx.setup(visual, nodo_del_mondo); add_child(fx)
## Gli effetti che dipendono dal risultato (scintille sui bersagli colpiti, numeri di cura) arrivano con
## on_event_result() dopo aver applicato il gameplay.

signal skill_event(anim_base: String, event_name: String, index: int)

const AURA_PARAMS := {"metal_mask": 1.0, "inflate": 0.006, "base_glow": 0.9, "rim_power": 1.2, "flow_speed": 1.3,
	"flow_scale": 16.0, "flow_amount": 0.55, "flicker": 0.08}
const RAGE_PARAMS := {"inflate": 0.016, "base_glow": 0.1, "rim_power": 2.2, "flow_speed": 1.8,
	"flow_scale": 7.0, "flow_amount": 0.7, "flicker": 0.3}
const CHARGE_PARAMS := {"inflate": 0.012, "base_glow": 0.35, "rim_power": 1.6, "flow_speed": 2.4,
	"flow_scale": 11.0, "flow_amount": 0.35, "flicker": 0.0}

## Velocità di Estasi (se il database non risponde)
const RAGE_ANIM_SPEED := 1.3
const RAGE_MOVE_MULT := 1.2

var visual: WarriorVisual
## Dove mettere gli effetti che restano fermi nel mondo (anelli a terra, scintille, immagini fantasma)
var world_root: Node3D
## Livello della skill (effetti più ricchi ai livelli alti)
var skill_level: int = 1

var _anim: String = ""
var _base: String = ""
var _events: Array = []
var _next: int = 0
var _last_t: float = -1.0
var _trails: Dictionary = {}          # "R"/"L" -> BladeTrail3D
var _arc: MeshInstance3D
var _arc_last_angle: float = 0.0
var _arc_has_angle: bool = false
var _dust_t: float = 0.0
var _ghost_t: float = 0.0
var _aura_end_ms: int = 0
var _aura_nodes: Array = []
var _aura_key: String = ""
var _rage_end_ms: int = 0
var _rage_nodes: Array = []
var _rage_key: String = ""
var _speed_lines: GPUParticles3D
var _charge_nodes: Array = []
var _charge_light: OmniLight3D

static var _db: SkillDatabase


func setup(p_visual: WarriorVisual, p_world_root: Node3D) -> void:
	visual = p_visual
	world_root = p_world_root


func _ready() -> void:
	if visual == null:
		visual = get_parent() as WarriorVisual
	if world_root == null and visual:
		world_root = visual.get_parent() as Node3D
	visual.animation_started.connect(_on_anim_started)
	for hand in ["R", "L"]:
		var tr := BladeTrail3D.new()
		tr.name = "Trail" + hand
		add_child(tr)
		_trails[hand] = tr


# ==================== TIMELINE ====================

func _on_anim_started(anim_name: String) -> void:
	_flush_events()
	_end_charge()
	_anim = anim_name
	_base = SkillEvents3D.base_name(anim_name)
	_events = SkillEvents3D.events(anim_name)
	_next = 0
	_last_t = -1.0
	_arc_has_angle = false
	if _base == "skill_life_force":
		_begin_charge()


## Eventi non ancora arrivati quando l'animazione viene interrotta: il gameplay non si perde (senza effetti)
func _flush_events() -> void:
	while _next < _events.size():
		var ev: Array = _events[_next]
		_next += 1
		skill_event.emit(_base, ev[1], ev[2])


## Posizione nell'animazione seguita (-1 se è finita o cambiata)
func current_time() -> float:
	if _anim == "" or visual == null or visual.current_animation() != _anim:
		return -1.0
	return visual.get_animation_position()


func current_animation_base() -> String:
	return _base if current_time() >= 0.0 else ""


## Avanzamento 0..1 della finestra (dash / spin / charge) dell'animazione in corso, -1 se fuori
func window_progress(window: String) -> float:
	var t := current_time()
	if t < 0.0:
		return -1.0
	return SkillEvents3D.window_progress(_anim, window, t)


func _process(delta: float) -> void:
	if visual == null:
		return
	var t := current_time()
	if t < 0.0 and _anim != "":
		# animazione finita: gli eventi rimasti (es. ultimo frame saltato) partono comunque
		_flush_events()
		_end_charge()
		_anim = ""
		_base = ""
	if t >= 0.0:
		while _next < _events.size() and t >= float(_events[_next][0]):
			var ev: Array = _events[_next]
			_next += 1
			skill_event.emit(_base, ev[1], ev[2])
			_event_vfx(ev[1], ev[2])
		_last_t = t
	_update_trails(t)
	_update_windows(t, delta)
	_update_buffs(delta)


# ==================== SCIE ====================

func _update_trails(t: float) -> void:
	var blades := SkillEvents3D.trail_blades(_anim, t) if t >= 0.0 else ""
	var vortex := _base == "skill_sword_vortex"
	for hand in _trails:
		var tr: BladeTrail3D = _trails[hand]
		var want: bool = hand in blades
		if want and not tr.emitting:
			var seg := visual.blade_segment(hand)
			if seg.is_empty():
				want = false
			else:
				tr.set_blade(seg["node"], seg["base"], seg["tip"])
				tr.duration = 0.32 if vortex else (0.24 if _base == "skill_three_way_slash" else 0.16)
				if vortex:
					tr.set_colors(Vfx3D.SILVER, Vfx3D.VORTEX_TIP)
				else:
					tr.set_colors(Color(0.72, 0.9, 1.0), Color(0.9, 1.0, 1.0))
		tr.emitting = want


# ==================== EFFETTI DEGLI EVENTI ====================

func _event_vfx(event_name: String, index: int) -> void:
	var root := _root()
	var pos := visual.global_position
	match _base:
		"skill_sword_aura":
			if event_name == "on":
				Vfx3D.ring(root, pos, 1.25, Vfx3D.AURA, 0.55, 0.12, 0.25)
				for mi in visual.blade_meshes():
					Vfx3D.burst(root, mi.global_transform * mi.get_aabb().get_center(), Vfx3D.AURA, 22, 1.6, 0.6, 0.07)
				Vfx3D.flash(root, pos + Vector3(0, 1.0, 0), Vfx3D.AURA, 0.7, 3.0, 0.4)
				start_aura(buff_duration("sword_aura"))
		"skill_berserk":
			if event_name == "on":
				Vfx3D.ring(root, pos, 1.5, Vfx3D.RAGE, 0.5, 0.2, 0.35)
				Vfx3D.burst(root, _bone_pos("chest"), Vfx3D.RAGE_CORE, 34, 3.2, 0.55, 0.09)
				Vfx3D.flash(root, pos + Vector3(0, 0.9, 0), Vfx3D.RAGE, 1.0, 3.0, 0.45)
				start_rage(buff_duration("berserk"))
		"skill_sword_vortex":
			if event_name == "on":
				Vfx3D.ring(root, pos, 1.9, Vfx3D.SILVER, 0.5, 0.14, 0.15)
				Vfx3D.ring(root, pos, 1.2, Vfx3D.VORTEX_TIP, 0.4, 0.1)
				Vfx3D.dust(root, pos, Vfx3D.DUST, 16, 0.7, 0.7, 0.32)
			elif event_name == "hit":
				Vfx3D.dust(root, pos, Vfx3D.DUST, 6, 0.5, 0.5, 0.24)
		"skill_life_force":
			if event_name == "hit":
				_end_charge()
				var fwd := forward()
				var front := pos + fwd * 0.9 + Vector3(0, 0.55, 0)
				Vfx3D.burst(root, front, Vfx3D.CHARGE, 60, 6.0, 0.6, 0.11, fwd + Vector3(0, 0.25, 0), 38.0, -2.0)
				Vfx3D.burst(root, front, Color(1, 1, 1), 24, 3.0, 0.35, 0.08, fwd, 70.0, 0.0)
				Vfx3D.ring(root, pos + fwd * 1.0, 2.4, Vfx3D.CHARGE, 0.55, 0.16, 0.3)
				Vfx3D.ring(root, pos, 1.3, Color(1, 1, 1), 0.3, 0.1, 0.5)
				Vfx3D.flash(root, front, Vfx3D.CHARGE, 1.8, 4.0, 0.5)


## Effetti che dipendono dal gameplay (bersagli colpiti, cura): chiamato da chi applica l'evento
func on_event_result(anim_base: String, event_name: String, _index: int, result: Dictionary) -> void:
	var root := _root()
	var targets: Array = result.get("targets", [])
	for t in targets:
		if not is_instance_valid(t) or not (t is Node3D):
			continue
		var hp := hit_point(t)
		match anim_base:
			"skill_hiss":
				Vfx3D.ring(root, (t as Node3D).global_position, 1.1, Vfx3D.SHOCK, 0.4, 0.18, 0.2)
				Vfx3D.burst(root, hp, Vfx3D.SPARK, 26, 3.5, 0.4, 0.08)
				Vfx3D.flash(root, hp, Vfx3D.SHOCK, 0.9, 2.5, 0.25)
			"skill_three_way_slash":
				Vfx3D.burst(root, hp, Vfx3D.SPARK, 24 if event_name != "hit3" else 40, 3.6, 0.4, 0.1)
				Vfx3D.flash(root, hp, Color(1, 1, 1), 0.6, 2.0, 0.18)
			"skill_sword_vortex":
				Vfx3D.burst(root, hp, Vfx3D.SPARK, 10, 2.5, 0.3, 0.07)
			"skill_life_force":
				Vfx3D.burst(root, hp, Vfx3D.CHARGE, 18, 2.8, 0.4, 0.09)
			_:
				Vfx3D.burst(root, hp, Vfx3D.SPARK, 10, 2.4, 0.3, 0.06)
	var heal := float(result.get("heal", 0.0))
	if heal > 0.0:
		Vfx3D.heal_number(root, visual.global_position + Vector3(0, 1.75, 0), heal)
		Vfx3D.burst(root, visual.global_position + Vector3(0, 0.8, 0), FloatingText3D.HEAL, 16, 1.2, 0.6, 0.07, Vector3.UP, 40.0, 1.0)


## Punto d'impatto su un bersaglio (centro del corpo)
static func hit_point(target: Node3D) -> Vector3:
	if target.has_method("get_hit_point"):
		return target.get_hit_point()
	return target.global_position + Vector3(0, 0.45, 0)


func forward() -> Vector3:
	var f := visual.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _root() -> Node:
	return world_root if is_instance_valid(world_root) else visual.get_parent()


func _bone_pos(bone: String) -> Vector3:
	var n := visual.bone_node(bone)
	return n.global_position if n else visual.global_position + Vector3(0, 0.8, 0)


# ==================== FINESTRE (giro, scatto, carica) ====================

func _update_windows(t: float, delta: float) -> void:
	var root := _root()
	# Vortice: arco luminoso attorno al warrior che segue la punta della lama + polvere ai piedi
	var spin := SkillEvents3D.window_progress(_anim, "spin", t) if t >= 0.0 else -1.0
	if spin >= 0.0:
		_update_arc(spin)
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.07
			Vfx3D.dust(root, visual.global_position, Vfx3D.DUST, 4, 0.45, 0.55, 0.22)
	elif _arc and _arc.visible:
		_arc.visible = false
	# Sibilare: immagini fantasma durante lo scatto
	var dash := SkillEvents3D.window_progress(_anim, "dash", t) if t >= 0.0 else -1.0
	if dash >= 0.0:
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.04
			Vfx3D.afterimage(visual.visible_meshes(), root, Color(0.55, 0.85, 1.0), 0.26)
	else:
		_ghost_t = 0.0
	# Volontà di Vivere: corpo e lama brillano sempre di più
	var charge := SkillEvents3D.window_progress(_anim, "charge", t) if t >= 0.0 else -1.0
	if charge >= 0.0 and not _charge_nodes.is_empty():
		var k := pow(charge, 1.4)
		for n in _charge_nodes:
			if is_instance_valid(n) and n is GeometryInstance3D:
				(n as GeometryInstance3D).set_instance_shader_parameter("intensity", 0.15 + 2.2 * k)
		if is_instance_valid(_charge_light):
			_charge_light.light_energy = 0.3 + 2.5 * k
			_charge_light.omni_range = 1.5 + 1.5 * k


func _update_arc(_progress: float) -> void:
	var seg := visual.blade_segment("R")
	if seg.is_empty():
		seg = visual.blade_segment("L")
	if seg.is_empty():
		return
	if _arc == null:
		_arc = _make_arc()
		add_child(_arc)
	var tip: Vector3 = (seg["node"] as Node3D).global_transform * (seg["tip"] as Vector3)
	var center := visual.global_position
	var d := Vector2(tip.x - center.x, tip.z - center.z)
	var r := maxf(d.length() + 0.08, 0.5)
	var ang := atan2(d.x, d.y)
	var dir := 1.0
	if _arc_has_angle:
		dir = signf(angle_difference(_arc_last_angle, ang))
		if dir == 0.0:
			dir = 1.0
	_arc_last_angle = ang
	_arc_has_angle = true
	_arc.visible = true
	_arc.global_transform = Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(r * dir, 1.0, r)), Vector3(center.x, tip.y, center.z))


## Corona circolare (raggio esterno 1, interno 0.55): UV.x = frazione di giro dalla testa all'indietro
func _make_arc() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	var inner := 0.55
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var a0 := -u0 * TAU
		var a1 := -u1 * TAU
		var o0 := Vector3(sin(a0), 0, cos(a0))
		var o1 := Vector3(sin(a1), 0, cos(a1))
		var quad := [[o0 * inner, Vector2(u0, 0)], [o0, Vector2(u0, 1)], [o1, Vector2(u1, 1)],
			[o0 * inner, Vector2(u0, 0)], [o1, Vector2(u1, 1)], [o1 * inner, Vector2(u1, 0)]]
		for v in quad:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "VortexArc"
	mi.top_level = true
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/world3d/vfx/vfx_arc.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	return mi


func _begin_charge() -> void:
	_end_charge()
	for mi in visual.visible_meshes():
		var layer := Vfx3D.glow_layer(mi, Vfx3D.CHARGE, CHARGE_PARAMS)
		if layer:
			layer.set_instance_shader_parameter("intensity", 0.0)
			_charge_nodes.append(layer)
	# particelle che convergono sul warrior
	var em := Vfx3D.emitter(visual, Vfx3D.CHARGE, 40, 0.7, Vector3(0.7, 0.5, 0.7), Vector3(0, 0.2, 0), 0.06, true, true)
	em.position = Vector3(0, 0.7, 0)
	var pm := em.process_material as ParticleProcessMaterial
	pm.radial_accel_min = -4.0
	pm.radial_accel_max = -3.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	_charge_nodes.append(em)
	_charge_light = OmniLight3D.new()
	_charge_light.light_color = Vfx3D.CHARGE
	_charge_light.light_energy = 0.0
	_charge_light.position = Vector3(0, 0.9, 0)
	visual.add_child(_charge_light)
	_charge_nodes.append(_charge_light)


func _end_charge() -> void:
	for n in _charge_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_charge_nodes.clear()
	_charge_light = null


# ==================== BUFF CHE DURANO ====================

## Aura ciano sulle lame (Aura della Spada) per `seconds` secondi
func start_aura(seconds: float) -> void:
	_aura_end_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_aura_key = ""


## Rabbia rosso-arancio (Estasi): corpo che brucia, braci dal torace, animazioni e corsa più veloci
func start_rage(seconds: float) -> void:
	_rage_end_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_rage_key = ""


func is_aura_active() -> bool:
	return Time.get_ticks_msec() < _aura_end_ms


func is_rage_active() -> bool:
	return Time.get_ticks_msec() < _rage_end_ms


## Moltiplicatore della velocità di corsa (Estasi: +20%)
func move_speed_multiplier() -> float:
	if not is_rage_active():
		return 1.0
	return 1.0 + _skill_value("berserk", "move_speed_percent", (RAGE_MOVE_MULT - 1.0) * 100.0) / 100.0


func stop_buffs() -> void:
	_aura_end_ms = 0
	_rage_end_ms = 0
	_update_buffs(0.0)


func _update_buffs(_delta: float) -> void:
	# aura: si ricostruisce se cambiano le armi (equip, stile)
	if is_aura_active():
		var key := _meshes_key(visual.blade_meshes())
		if key != _aura_key or not _nodes_alive(_aura_nodes):
			_clear(_aura_nodes)
			_aura_key = key
			_build_aura()
	elif not _aura_nodes.is_empty():
		_clear(_aura_nodes)
		_aura_key = ""
	# rabbia
	if is_rage_active():
		var key := _meshes_key(visual.visible_meshes())
		if key != _rage_key or not _nodes_alive(_rage_nodes):
			_clear(_rage_nodes)
			_rage_key = key
			_build_rage()
		visual.set_animation_speed(_skill_value("berserk", "anim_speed", RAGE_ANIM_SPEED))
		var amp := 0.012
		visual.set_shake_offset(Vector3(randf_range(-amp, amp), randf_range(0.0, amp * 0.5), randf_range(-amp, amp)))
		if is_instance_valid(_speed_lines):
			_speed_lines.emitting = SkillEvents3D.base_name(visual.current_animation()) == "run"
	elif not _rage_nodes.is_empty():
		_clear(_rage_nodes)
		_rage_key = ""
		visual.set_animation_speed(1.0)
		visual.set_shake_offset(Vector3.ZERO)
	elif _base == "skill_berserk" and current_time() >= 0.0:
		# vibrazione mentre si raccoglie prima dell'urlo
		var amp2 := 0.008
		visual.set_shake_offset(Vector3(randf_range(-amp2, amp2), 0.0, randf_range(-amp2, amp2)))


func _build_aura() -> void:
	var lvl := float(maxi(skill_level, 1))
	for mi in visual.blade_meshes():
		var params := AURA_PARAMS.duplicate()
		params["inflate"] = 0.006 + 0.003 * (lvl - 1.0)
		var layer := Vfx3D.glow_layer(mi, Vfx3D.AURA, params)
		if layer:
			layer.set_instance_shader_parameter("intensity", 1.0 + 0.3 * (lvl - 1.0))
			_aura_nodes.append(layer)
		# particelle luminose che salgono lente lungo la lama
		var seg := {}
		for hand in ["R", "L"]:
			var s := visual.blade_segment(hand)
			if not s.is_empty() and s["node"] == mi:
				seg = s
		if seg.is_empty():
			continue
		var base: Vector3 = seg["base"]
		var tip: Vector3 = seg["tip"]
		var axis := (tip - base)
		var em := Vfx3D.emitter(mi, Vfx3D.AURA, 18 + 8 * (skill_level - 1), 1.1, Vector3(0.025, axis.length() * 0.5, 0.025),
			Vector3(0, 0.22, 0), 0.05, true, false)
		var y := axis.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		em.transform = Transform3D(Basis(x, y, x.cross(y)), (base + tip) * 0.5)
		var pm := em.process_material as ParticleProcessMaterial
		pm.gravity = Vector3(0, 0.35, 0)
		pm.spread = 60.0
		_aura_nodes.append(em)


func _build_rage() -> void:
	for mi in visual.visible_meshes():
		var layer := Vfx3D.glow_layer(mi, Vfx3D.RAGE, RAGE_PARAMS)
		if layer:
			layer.set_instance_shader_parameter("intensity", 0.9)
			_rage_nodes.append(layer)
	var chest := visual.bone_node("chest")
	if chest:
		var embers := Vfx3D.emitter(chest, Vfx3D.RAGE_CORE, 26, 0.8, Vector3(0.2, 0.15, 0.2), Vector3(0, 0.9, 0), 0.07, true, false)
		(embers.process_material as ParticleProcessMaterial).spread = 50.0
		_rage_nodes.append(embers)
		var smoke := Vfx3D.emitter(chest, Color(0.85, 0.22, 0.08, 0.45), 10, 0.9, Vector3(0.22, 0.2, 0.22), Vector3(0, 0.7, 0), 0.28, false, false)
		_rage_nodes.append(smoke)
	# scie di velocità quando corre (accese solo nell'animazione di corsa)
	_speed_lines = Vfx3D.emitter(visual, Color(1.0, 0.6, 0.3), 16, 0.3, Vector3(0.25, 0.4, 0.1), Vector3(0, 0, -0.01), 0.05, true, false)
	_speed_lines.position = Vector3(0, 0.6, 0)
	_speed_lines.emitting = false
	_rage_nodes.append(_speed_lines)


static func _meshes_key(list: Array) -> String:
	var ids: Array[String] = []
	for m in list:
		ids.append(str((m as Object).get_instance_id()))
	return ",".join(ids)


static func _nodes_alive(list: Array) -> bool:
	for n in list:
		if not is_instance_valid(n):
			return false
	return true


static func _clear(list: Array) -> void:
	for n in list:
		if is_instance_valid(n):
			n.queue_free()
	list.clear()


# ==================== DATI DELLE SKILL ====================

static func _database() -> SkillDatabase:
	if _db == null:
		_db = SkillDatabase.new()
	return _db


## Durata del buff di una skill (secondi), dal database
static func buff_duration(skill_id: String) -> float:
	var s := _database().get_skill(skill_id)
	return s.duration if s else 10.0


static func _skill_value(skill_id: String, key: String, default: float) -> float:
	var s := _database().get_skill(skill_id)
	return s.get_effect_value(key, default) if s else default
