# File: res://scripts/battle/effects/SibilareEffect.gd
#
# Sibilare — fast forward dash + single powerful slash.
# Inspired by the "Sibilare" skill from Metin2.
#
# Phases:
#   0  Anticipation  (0.07 s) — brief pullback, sword fades in
#   1  Dash          (0.12 s) — EXPO ease, sword rockets to target
#   2  Impact        (0.10 s) — spark burst, air-slice crescent, screen shake, damage
#   3  Recovery      (0.22 s) — fade everything out

extends Node2D

# =====================================================================
#  TUNABLE
# =====================================================================

const SWORD_TEX_PATH: String = \
	"res://Item_Texture/Skills/Vortice della spada/ChatGPT Image 8 mar 2026, 12_12_10.png"

## Sword sprite size for this effect (smaller than vortex — it dashes, not spins).
const SWORD_SCALE: float        = 0.14

## Phase durations in seconds.
const DUR_ANTICIPATION: float   = 0.07
const DUR_DASH: float           = 0.12
const DUR_IMPACT_PAUSE: float   = 0.10
const DUR_RECOVERY: float       = 0.22

## Pullback distance (pixels backwards along the dash axis) during anticipation.
const PULLBACK_DIST: float      = 26.0

## How much the slash arc curves perpendicular to the dash direction.
const TRAIL_CURVE_LIFT: float   = 48.0

## Width of the slash trail Line2D.
const TRAIL_WIDTH: float        = 18.0

## Number of motion-blur ghost copies spawned at dash start.
const GHOST_COUNT: int          = 3

# =====================================================================
#  STATE
# =====================================================================

var _start_pos:   Vector2   # Where the dash begins (battle_area local space)
var _target_pos:  Vector2   # Where the hit lands
var _dash_dir:    Vector2   # Normalised direction of the dash
var _perp_dir:    Vector2   # Perpendicular (for curve lift and arc orientation)

var _on_damage: Callable
var _on_stun:   Callable

# _draw() state for the air-slice crescent
var _slice_alpha: float = 0.0
var _slice_scale: float = 0.0

# =====================================================================
#  NODES
# =====================================================================

var _sword_pivot:  Node2D
var _sword_sprite: Sprite2D
var _slash_trail:  Line2D
var _sparks:       CPUParticles2D


# =====================================================================
#  PUBLIC API
# =====================================================================

func initialize(
		start_pos:  Vector2,
		target_pos: Vector2,
		on_damage:  Callable,
		on_stun:    Callable
) -> void:
	_start_pos  = start_pos
	_target_pos = target_pos
	_dash_dir   = (target_pos - start_pos).normalized()
	# Perpendicular that lifts the arc "upward" relative to the slash direction
	_perp_dir   = _dash_dir.rotated(-PI * 0.5)
	_on_damage  = on_damage
	_on_stun    = on_stun

	_build_nodes()
	_run_animation()


# =====================================================================
#  SCENE CONSTRUCTION
# =====================================================================

func _build_nodes() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(SWORD_TEX_PATH):
		tex = ResourceLoader.load(SWORD_TEX_PATH)

	# ── Sword pivot ──────────────────────────────────────────────────
	_sword_pivot          = Node2D.new()
	_sword_pivot.z_index  = 6
	_sword_pivot.position = _start_pos
	# Natural image diagonal (~-45°) looks like a ready slash; align to dash axis
	_sword_pivot.rotation = _dash_dir.angle()
	add_child(_sword_pivot)

	_sword_sprite          = Sprite2D.new()
	_sword_sprite.texture  = tex
	_sword_sprite.centered = true
	_sword_sprite.scale    = Vector2(SWORD_SCALE, SWORD_SCALE)
	_sword_sprite.modulate = Color(1.1, 1.1, 1.1, 0.0)   # Start invisible
	_sword_pivot.add_child(_sword_sprite)

	# ── Slash arc trail ──────────────────────────────────────────────
	_slash_trail                  = Line2D.new()
	_slash_trail.z_index          = 4
	_slash_trail.width            = TRAIL_WIDTH
	_slash_trail.joint_mode       = Line2D.LINE_JOINT_ROUND
	_slash_trail.begin_cap_mode   = Line2D.LINE_CAP_ROUND
	_slash_trail.end_cap_mode     = Line2D.LINE_CAP_ROUND
	# Gradient: transparent tail → bright tip
	var tg := Gradient.new()
	tg.set_color(0, Color(0.75, 0.95, 1.0, 0.0))
	tg.set_color(1, Color(1.00, 1.00, 1.0, 0.95))
	_slash_trail.gradient = tg
	# Width curve: widens toward the tip to show direction and speed
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 0.0))
	wc.add_point(Vector2(0.55, 0.85))
	wc.add_point(Vector2(1.0,  1.0))
	_slash_trail.width_curve = wc
	add_child(_slash_trail)

	# ── Impact sparks ────────────────────────────────────────────────
	_sparks                       = CPUParticles2D.new()
	_sparks.z_index               = 8
	_sparks.position              = _target_pos
	_sparks.emitting              = false
	_sparks.one_shot              = true
	_sparks.amount                = 28
	_sparks.lifetime              = 0.42
	_sparks.explosiveness         = 0.95
	_sparks.randomness            = 0.45
	_sparks.emission_shape        = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 9.0
	_sparks.direction             = -_dash_dir          # Scatter back against slash
	_sparks.spread                = 140.0
	_sparks.gravity               = Vector2(0.0, 210.0)
	_sparks.initial_velocity_min  = 85.0
	_sparks.initial_velocity_max  = 230.0
	_sparks.scale_amount_min      = 1.5
	_sparks.scale_amount_max      = 4.0
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.95, 0.5, 1.0))   # Gold
	sg.set_color(1, Color(0.45, 0.75, 1.0, 0.0))   # Blue-white fade
	_sparks.color_ramp = sg
	add_child(_sparks)


# =====================================================================
#  ANIMATION  (pure tween state machine)
# =====================================================================

func _run_animation() -> void:
	var tw := create_tween()

	# ── Phase 0: Anticipation — fade in + pullback ────────────────────
	tw.parallel()
	tw.tween_property(_sword_sprite, "modulate:a", 1.0, DUR_ANTICIPATION * 0.8)
	tw.tween_property(
		_sword_pivot, "position",
		_start_pos - _dash_dir * PULLBACK_DIST,
		DUR_ANTICIPATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Flash overbright + build the curved trail just as the dash fires
	tw.chain()
	tw.tween_callback(func():
		_sword_sprite.modulate = Color(1.6, 1.6, 1.6, 1.0)
		_build_slash_trail()
		_spawn_motion_ghosts()
	)

	# ── Phase 1: Dash — EXPO ease creates the "blink" sensation ───────
	tw.tween_property(
		_sword_pivot, "position",
		_target_pos,
		DUR_DASH
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	# ── Phase 2: Impact ────────────────────────────────────────────────
	tw.tween_callback(_hit)

	# Freeze on impact
	tw.tween_interval(DUR_IMPACT_PAUSE)

	# ── Phase 3: Recovery ──────────────────────────────────────────────
	tw.tween_callback(_recover)


func _hit() -> void:
	# Return sword to normal tint
	_sword_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Spark burst
	_sparks.emitting = true

	# Air-slice crescent appears and quickly expands
	_slice_alpha = 1.0
	_slice_scale = 0.5
	queue_redraw()
	var expand := create_tween()
	expand.tween_method(
		func(v: float): _slice_scale = v; queue_redraw(),
		0.5, 1.2, DUR_IMPACT_PAUSE
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_screen_shake()

	# Apply damage and stun
	if not _on_damage.is_null():
		_on_damage.call()
	if not _on_stun.is_null():
		_on_stun.call()


func _recover() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sword_sprite,  "modulate:a", 0.0, DUR_RECOVERY)
	tw.tween_property(_slash_trail,   "modulate:a", 0.0, DUR_RECOVERY * 0.8)
	tw.tween_method(
		func(v: float): _slice_alpha = v; queue_redraw(),
		1.0, 0.0, DUR_RECOVERY
	)
	tw.chain().tween_callback(queue_free)


# =====================================================================
#  SLASH TRAIL  (quadratic Bézier arc)
# =====================================================================

func _build_slash_trail() -> void:
	# Control point lifts the curve perpendicular to the dash for a cutting-arc feel
	var ctrl := (_start_pos + _target_pos) * 0.5 + _perp_dir * TRAIL_CURVE_LIFT
	_slash_trail.clear_points()
	var N := 22
	for i in range(N + 1):
		var t := float(i) / float(N)
		_slash_trail.add_point(_bezier(t, _start_pos, ctrl, _target_pos))


func _bezier(t: float, p0: Vector2, p1: Vector2, p2: Vector2) -> Vector2:
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


# =====================================================================
#  MOTION-BLUR GHOSTS  (spawned at dash start, fade during recovery)
# =====================================================================

func _spawn_motion_ghosts() -> void:
	var tex: Texture2D = _sword_sprite.texture
	if not tex:
		return
	for i in range(GHOST_COUNT):
		var frac := (float(i) + 1.0) / float(GHOST_COUNT + 1)
		var ghost := Sprite2D.new()
		ghost.texture  = tex
		ghost.centered = true
		ghost.position = lerp(_start_pos, _target_pos, frac)
		ghost.rotation = _sword_pivot.rotation
		ghost.scale    = Vector2(SWORD_SCALE * 0.9, SWORD_SCALE * 0.9)
		ghost.z_index  = 3
		# Opacity decreases toward the origin (oldest ghost = most faded)
		var alpha := lerpf(0.35, 0.12, frac)
		ghost.modulate = Color(0.75, 1.0, 0.85, alpha)
		add_child(ghost)
		# Fade out alongside the main recovery
		var tw := create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, DUR_RECOVERY * 0.75)
		tw.tween_callback(ghost.queue_free)


# =====================================================================
#  SCREEN SHAKE  (lighter than vortex — single hit)
# =====================================================================

func _screen_shake() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var orig := vp.canvas_transform
	var tw := create_tween()
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2( 3.5, -2.0)))
	tw.tween_interval(0.020)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2(-2.5,  1.5)))
	tw.tween_interval(0.020)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2( 1.5, -0.8)))
	tw.tween_interval(0.020)
	tw.tween_callback(func(): vp.canvas_transform = orig)


# =====================================================================
#  DRAW  — Air-slice crescent at impact location
# =====================================================================

func _draw() -> void:
	if _slice_alpha <= 0.001:
		return

	var center  := _target_pos
	var radius  := 55.0 * _slice_scale
	# Arc faces opposite to the dash so it reads as the "cut plane" facing the attacker
	var arc_dir := (-_dash_dir).angle()
	var span    := PI * 0.62   # ± 112°

	# Outer bright crescent
	draw_arc(center, radius,
		arc_dir - span, arc_dir + span, 52,
		Color(1.00, 1.00, 1.00, _slice_alpha * 0.85), 18.0)

	# Inner thinner ring
	draw_arc(center, radius * 0.68,
		arc_dir - span * 0.75, arc_dir + span * 0.75, 36,
		Color(0.65, 0.88, 1.00, _slice_alpha * 0.55), 10.0)

	# Outer faint halo
	draw_arc(center, radius * 1.30,
		arc_dir - span * 0.55, arc_dir + span * 0.55, 28,
		Color(0.45, 0.70, 1.00, _slice_alpha * 0.22), 6.0)

	# Impact flash disc (strongest at beginning of impact phase)
	var flash := clampf((_slice_alpha - 0.55) * 2.2, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(center, 32.0 * _slice_scale,
			Color(1.0, 1.0, 1.0, flash * 0.50))
