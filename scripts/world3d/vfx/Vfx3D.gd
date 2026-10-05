class_name Vfx3D
extends RefCounted
## Effetti visivi riutilizzabili delle skill 3D: anelli a terra, sbuffi di particelle, polvere, lampi di luce,
## immagini fantasma e strati luminosi sopra le mesh. Stile toon: colori pieni, forme semplici e leggibili
## dalla camera di gioco (52° dall'alto). Gli effetti si eliminano da soli.

const RING_SHADER := preload("res://shaders/world3d/vfx/vfx_ring.gdshader")
const GLOW_SHADER := preload("res://shaders/world3d/vfx/vfx_glow_layer.gdshader")
const GHOST_SHADER := preload("res://shaders/world3d/vfx/vfx_ghost.gdshader")
const SOFT_SHADER := preload("res://shaders/world3d/vfx/vfx_soft.gdshader")
const SPARK_SHADER := preload("res://shaders/world3d/spark.gdshader")

## Palette degli effetti (SKILLS_WARRIOR.md)
const SILVER := Color(0.82, 0.93, 1.0)
const VORTEX_TIP := Color(0.55, 1.0, 0.7)
const AURA := Color(0.2, 0.95, 1.0)
const RAGE := Color(1.0, 0.36, 0.08)
const RAGE_CORE := Color(1.0, 0.75, 0.2)
const CHARGE := Color(1.0, 0.92, 0.55)
const SHOCK := Color(0.85, 0.95, 1.0)
const DUST := Color(0.78, 0.68, 0.5, 0.55)
const SPARK := Color(1.0, 0.9, 0.55)

const FX_META := &"skill_fx"

static var _ring_mats: Dictionary = {}
static var _spark_mesh: QuadMesh
static var _soft_mesh: QuadMesh


# ==================== ANELLI A TERRA ====================

## Anello che si allarga e svanisce, appoggiato a terra (y del punto + 0.04)
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, duration: float = 0.45,
		width: float = 0.16, fill: float = 0.0) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius * 2.0
	mi.mesh = pm
	mi.material_override = _ring_material(color, width, fill)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, pos.y + 0.04, pos.z)
	mi.set_instance_shader_parameter("progress", 0.0)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, duration)
	tw.tween_callback(mi.queue_free)
	return mi


static func _ring_material(color: Color, width: float, fill: float) -> ShaderMaterial:
	var key := "%s_%.2f_%.2f" % [color.to_html(), width, fill]
	if _ring_mats.has(key):
		return _ring_mats[key]
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill", fill)
	_ring_mats[key] = m
	return m


# ==================== PARTICELLE ====================

## Sbuffo singolo di scintille luminose (additive). dir/spread: direzione principale e apertura in gradi.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 16, speed: float = 2.5,
		lifetime: float = 0.45, size: float = 0.07, dir: Vector3 = Vector3.UP, spread: float = 180.0,
		gravity: float = -3.0) -> GPUParticles3D:
	var p := _particles(parent, pos, amount, lifetime, true)
	if p == null:
		return null
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color_ramp = _ramp(Color(1, 1, 1, 1).lerp(color, 0.35), Color(color.r, color.g, color.b, 0.0))
	p.draw_pass_1 = _spark_quad(size)
	p.emitting = true
	return p


## Polvere / vento ai piedi (particelle morbide non luminose)
static func dust(parent: Node, pos: Vector3, color: Color = DUST, amount: int = 10, radius: float = 0.35,
		lifetime: float = 0.6, size: float = 0.26) -> GPUParticles3D:
	var p := _particles(parent, pos + Vector3(0, 0.08, 0), amount, lifetime, true)
	if p == null:
		return null
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.5
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 0.4, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.scale_curve = _curve_tex([Vector2(0, 0.5), Vector2(0.3, 1.0), Vector2(1, 1.2)])
	pm.color_ramp = _ramp(color, Color(color.r, color.g, color.b, 0.0))
	p.draw_pass_1 = _soft_quad(size)
	p.emitting = true
	return p


## Particelle continue agganciate a un nodo (aura che sale lungo la lama, braci di rabbia...).
## Restituisce il nodo: chi lo crea lo spegne/elimina.
static func emitter(parent: Node3D, color: Color, amount: int, lifetime: float, box: Vector3,
		velocity: Vector3, size: float = 0.06, additive: bool = true, local: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.set_meta(FX_META, true)
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = local
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = velocity.normalized() if velocity.length() > 0.001 else Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = velocity.length() * 0.6
	pm.initial_velocity_max = velocity.length()
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _curve_tex([Vector2(0, 0.3), Vector2(0.25, 1.0), Vector2(1, 0.0)])
	pm.color_ramp = _ramp(Color(1, 1, 1, 1).lerp(color, 0.5), Color(color.r, color.g, color.b, 0.0)) if additive \
		else _ramp(color, Color(color.r, color.g, color.b, 0.0))
	p.process_material = pm
	p.draw_pass_1 = _spark_quad(size) if additive else _soft_quad(size)
	parent.add_child(p)
	return p


static func _particles(parent: Node, pos: Vector3, amount: int, lifetime: float, one_shot: bool) -> GPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.95
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	p.process_material = ParticleProcessMaterial.new()
	parent.add_child(p)
	p.global_position = pos
	if one_shot:
		p.finished.connect(p.queue_free)
		# sicurezza: alcuni driver non emettono "finished"
		p.get_tree().create_timer(lifetime + 1.0).timeout.connect(func() -> void:
			if is_instance_valid(p): p.queue_free())
	return p


static func _spark_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		var sm := ShaderMaterial.new()
		sm.shader = SPARK_SHADER
		_spark_mesh.material = sm
	q.material = _spark_mesh.material
	return q


static func _soft_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	if _soft_mesh == null:
		_soft_mesh = QuadMesh.new()
		var sm := ShaderMaterial.new()
		sm.shader = SOFT_SHADER
		_soft_mesh.material = sm
	q.material = _soft_mesh.material
	return q


static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


# ==================== LUCE ====================

## Lampo di luce colorata che si spegne (impatti, esplosione)
static func flash(parent: Node, pos: Vector3, color: Color, energy: float = 2.0, radius: float = 2.5, duration: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


# ==================== STRATI LUMINOSI E FANTASMI ====================

## Copia di una mesh (stessa posa, stessa skin) con lo shader luminoso: si somma agli altri materiali
## e al bagliore del potenziamento. params: parametri dello shader. Restituisce la copia (figlia di mi).
static func glow_layer(mi: MeshInstance3D, color: Color, params: Dictionary = {}) -> MeshInstance3D:
	if mi == null or mi.mesh == null:
		return null
	var layer := MeshInstance3D.new()
	layer.set_meta(FX_META, true)
	layer.name = "GlowLayer"
	layer.mesh = mi.mesh
	layer.skin = mi.skin
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("glow_color", color)
	for k in params:
		m.set_shader_parameter(k, params[k])
	layer.material_override = m
	mi.add_child(layer)
	if mi.skin != null:
		layer.skeleton = layer.get_path_to(mi.get_node(mi.skeleton)) if not mi.skeleton.is_empty() else NodePath("")
	layer.set_instance_shader_parameter("intensity", 1.0)
	return layer


## Immagine fantasma del warrior nella posa attuale: copie "congelate" delle mesh che svaniscono
static func afterimage(meshes: Array, parent: Node, color: Color, life: float = 0.28) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	# senza renderer (test headless) la posa delle mesh skinnate non si può copiare
	if DisplayServer.get_name() == "headless":
		return
	var mat := ShaderMaterial.new()
	mat.shader = GHOST_SHADER
	mat.set_shader_parameter("ghost_color", color)
	var holder := Node3D.new()
	parent.add_child(holder)
	for mi in meshes:
		if not is_instance_valid(mi) or (mi as MeshInstance3D).mesh == null:
			continue
		var src := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = src.bake_mesh_from_current_skeleton_pose() if src.skin != null else src.mesh
		if copy.mesh == null:
			copy.queue_free()
			continue
		copy.material_override = mat
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(copy)
		copy.global_transform = src.global_transform
		copy.set_instance_shader_parameter("fade", 1.0)
	var tw := holder.create_tween()
	tw.tween_method(func(v: float) -> void:
		for c in holder.get_children():
			(c as GeometryInstance3D).set_instance_shader_parameter("fade", v), 1.0, 0.0, life)
	tw.tween_callback(holder.queue_free)


## Numero di cura verde sopra il warrior
static func heal_number(parent: Node, pos: Vector3, amount: float) -> void:
	FloatingText3D.spawn(parent, pos, "+%d" % int(round(amount)), FloatingText3D.HEAL, 80)
