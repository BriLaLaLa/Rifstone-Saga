# File: res://scripts/battle/effects/SwordVortexEffect.gd
#
# Vortice della Spada — layered vortex attack effect.
# Inspired by Hades / Diablo / Path of Exile spinning weapon aesthetics.
#
# Layers (back to front):
#   0  – Slash ring & wind vortex  (_draw on this node, drawn before children)
#   1-5 – Ghost trail copies        (5 Sprite2D pivots, angular offset behind sword)
#   6  – Radial sparks              (CPUParticles2D)
#   7  – Main sword pivot           (Sprite2D, depth-scaled)
#
# Key design choices:
#   • Pivot at the HILT, not center of blade
#   • ELLIPTICAL apparent path (scale-based depth illusion, not a flat circle)
#   • VARIABLE SPEED: sin bell-curve — starts slow, peaks, decelerates out
#   • GHOST TRAIL: 5 angular-offset copies fading to transparent
#   • VORTEX RING: counter-rotating wind arcs layered in _draw()
#   • SCREEN SHAKE: subtle 0.1 s impulse via viewport canvas_transform

extends Node2D

# =========================================================
#  TUNABLE CONSTANTS  (tweak here without touching logic)
# =========================================================

## Scene-space blade length (pommel → tip).  Controls overall size.
const SWORD_VISUAL_LENGTH: float = 290.0

## Total animation duration in seconds.  3 rotations fit inside this window.
const TOTAL_DURATION: float = 1.50

## How many full rotations (and damage hits) the skill performs.
const ROTATIONS: int = 3

## Number of ghost trail copies behind the main sword.
const GHOST_COUNT: int = 5

## Angular gap (radians) between each successive ghost.
const GHOST_STEP: float = 0.32

## Ghost opacities, index 0 = closest trail, index 4 = oldest.
const GHOST_ALPHAS: Array = [0.52, 0.36, 0.22, 0.11, 0.04]

## Depth perspective: scale multiplier range (behind → in-front).
const DEPTH_SCALE_MIN: float = 0.78
const DEPTH_SCALE_MAX: float = 1.16

## Vortex ring drawn at this fraction of SWORD_VISUAL_LENGTH.
const VORTEX_RING_MULT: float = 1.30

# =========================================================
#  IMAGE-DERIVED CONSTANTS  (from 1536×1024 PNG analysis)
#    Pommel pixel: (1260, 157)  Image centre: (768, 512)
#    Sword length in image: ≈1277 px
# =========================================================
const _IMG_SCALE: float  = SWORD_VISUAL_LENGTH / 1277.0
# Move sprite so pommel (relative offset from centre) lands at node origin
const _SPRITE_POS: Vector2 = Vector2(-108.0, 78.0)   # pivot = pommel
# Blade tip in local space at rotation = 0
const _TIP_BASE: Vector2  = Vector2(-232.0, 156.0)

# PEAK_SPEED calibrated so integral(sin(t·π), 0→1) · PEAK_SPEED · TOTAL_DURATION = 3·TAU
# integral = 2/π ≈ 0.6366
const PEAK_SPEED: float = 3.0 * TAU / (0.6366 * TOTAL_DURATION)   # ≈ 19.8 rad/s

## Tilt amplitude in radians.  ~10° gives a subtle, readable lean without overdoing it.
const TILT_AMP: float   = deg_to_rad(10.0)
## Phase offset so the maximum tilt is 90° ahead of the orbit position.
## This makes the sword lean INTO its direction of travel (leading-edge inertia illusion).
## Adjust sign to flip the lean direction if it looks reversed on your screen.
const TILT_PHASE: float = PI * 0.5

## Maximum rotational lag in radians (~10°) reached at peak spin speed.
const LAG_MAX: float = deg_to_rad(10.0)
## Spring stiffness.  Higher = lag snaps to target faster.
const LAG_SPRING_K: float = 40.0
## Damping coefficient.  ζ ≈ 0.71 → slightly under-damped → subtle overshoot
## when decelerating, giving the blade a "weight and momentum" feel.
const LAG_DAMPING_K: float = 9.0

## Orbit-phase tilt amplitude.
## Blade tilts DOWN when it is "in front" (lower orbit, closer to viewer)
## and UP when it is "behind" (upper orbit, farther away).
## Relationship: orbit_tilt = ORBIT_TILT_AMP × sin(depth_cycle_phase)
## Keep within 10–14° to remain readable without looking exaggerated.
const ORBIT_TILT_AMP: float = deg_to_rad(11.0)

## Constant inward bias: rotates the blade slightly toward the vortex centre at all times.
## Prevents the blade from looking tangential / fan-like.
## Negative = lean tip inward (toward origin).
const INWARD_BIAS: float = deg_to_rad(-5.0)

# =========================================================
#  STATE
# =========================================================
var _angle: float = 0.0
var _total_angle: float = 0.0
var _time: float = 0.0
var _running: bool = false
var _rotations_done: int = 0
var _speed_factor: float = 0.0   # 0–1, updated every frame
var _lag_angle: float    = 0.0   # Current lag offset (rad), driven by spring below
var _lag_velocity: float = 0.0   # Spring velocity for lag system
var _on_damage: Callable
var _on_complete: Callable

# =========================================================
#  NODES
# =========================================================
var _main_pivot: Node2D
var _sword_sprite: Sprite2D
var _ghost_pivots: Array = []    # Array of Node2D
var _ghost_sprites: Array = []   # Array of Sprite2D
var _sparks: CPUParticles2D


# =========================================================
#  PUBLIC API
# =========================================================

func initialize(tex: Texture2D, on_damage: Callable, on_complete: Callable) -> void:
	_on_damage   = on_damage
	_on_complete = on_complete
	_build_nodes(tex)
	_apply_screen_shake()
	_play_entry()


# =========================================================
#  CONSTRUCTION
# =========================================================

func _build_nodes(tex: Texture2D) -> void:
	# ── Ghost trail pivots (lowest z, behind sword) ──────────────────────
	for i in range(GHOST_COUNT):
		var pivot := Node2D.new()
		pivot.z_index = i + 1
		add_child(pivot)

		var ghost := Sprite2D.new()
		ghost.texture  = tex
		ghost.centered = true
		ghost.position = _SPRITE_POS
		ghost.scale    = Vector2(_IMG_SCALE, _IMG_SCALE)
		# Colour grades from warm-green nearest to cyan farthest
		var t := float(i) / float(GHOST_COUNT - 1)
		var tint := Color(
			lerp(0.75, 0.25, t),
			1.0,
			lerp(0.70, 1.0, t),
			GHOST_ALPHAS[i]
		)
		ghost.modulate = tint
		pivot.add_child(ghost)

		_ghost_pivots.append(pivot)
		_ghost_sprites.append(ghost)

	# ── Radial sparks from hilt ──────────────────────────────────────────
	_sparks = CPUParticles2D.new()
	_sparks.z_index        = 6
	_sparks.emitting       = false
	_sparks.amount         = 55
	_sparks.lifetime       = 0.38
	_sparks.one_shot       = false
	_sparks.explosiveness  = 0.0
	_sparks.randomness     = 0.85
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 22.0
	_sparks.direction      = Vector2(0.0, -1.0)
	_sparks.spread         = 360.0
	_sparks.gravity        = Vector2(0.0, 0.0)
	_sparks.initial_velocity_min = 55.0
	_sparks.initial_velocity_max = 180.0
	_sparks.scale_amount_min = 0.8
	_sparks.scale_amount_max = 3.0
	_sparks.damping_min    = 90.0
	_sparks.damping_max    = 190.0
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.97, 0.45, 1.0))   # Gold burst
	sg.set_color(1, Color(0.05, 1.0,  0.30, 0.0))  # Green fade-out
	_sparks.color_ramp = sg
	add_child(_sparks)

	# ── Main sword pivot (highest z) ────────────────────────────────────
	_main_pivot = Node2D.new()
	_main_pivot.z_index = 7
	add_child(_main_pivot)

	_sword_sprite = Sprite2D.new()
	_sword_sprite.texture  = tex
	_sword_sprite.centered = true
	_sword_sprite.position = _SPRITE_POS
	_sword_sprite.scale    = Vector2(_IMG_SCALE, _IMG_SCALE)
	_sword_sprite.modulate = Color(0.92, 1.0, 0.92, 1.0)
	_main_pivot.add_child(_sword_sprite)


# =========================================================
#  ENTRY  (charge-up then release)
# =========================================================

func _play_entry() -> void:
	scale      = Vector2(0.04, 0.04)
	modulate.a = 0.0
	_running   = false

	var tw := create_tween()
	tw.set_parallel(true)
	# Aura swells in before spin starts
	tw.tween_property(self, "modulate:a", 0.68, 0.16)
	tw.tween_property(self, "scale", Vector2(1.10, 1.10), 0.20)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Release: snap to full size and start spinning
	tw.chain().set_parallel(true)
	tw.tween_callback(func():
		_running = true
		_sparks.emitting = true
	)
	tw.tween_property(self, "modulate:a", 1.0, 0.07)
	tw.tween_property(self, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


# =========================================================
#  SCREEN SHAKE  (very light, ~0.12 s impulse)
# =========================================================

func _apply_screen_shake() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var orig := vp.canvas_transform
	# Hand-written offsets: avoids loop-closure capture issues
	var tw := create_tween()
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2( 4.5, -2.5)))
	tw.tween_interval(0.022)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2(-3.5,  2.0)))
	tw.tween_interval(0.022)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2( 2.5, -1.5)))
	tw.tween_interval(0.022)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2(-1.5,  1.0)))
	tw.tween_interval(0.022)
	tw.tween_callback(func(): vp.canvas_transform = orig.translated(Vector2( 0.7, -0.4)))
	tw.tween_interval(0.022)
	tw.tween_callback(func(): vp.canvas_transform = orig)


# =========================================================
#  PROCESS
# =========================================================

func _process(delta: float) -> void:
	if not _running:
		return

	_time += delta
	var progress: float = clamp(_time / TOTAL_DURATION, 0.0, 1.0)

	# ── Variable-speed bell curve ─────────────────────────────────────────
	_speed_factor = sin(progress * PI)   # 0 → 1 → 0

	var rot_delta: float = PEAK_SPEED * _speed_factor * delta
	_angle       += rot_delta
	_total_angle += rot_delta

	# ── Rotational lag  (spring-mass, slightly under-damped) ─────────────
	# target_lag is negative: blade always trails opposite to the spin direction.
	# Proportional to current speed so lag fades naturally at start/end.
	var target_lag: float    = -LAG_MAX * _speed_factor
	var spring_force: float  = (target_lag - _lag_angle) * LAG_SPRING_K \
	                           - _lag_velocity * LAG_DAMPING_K
	_lag_velocity += spring_force * delta
	_lag_angle    += _lag_velocity * delta

	# ── Main sword ──────────────────────────────────────────────────────
	_main_pivot.rotation = _angle
	var tip: Vector2 = _TIP_BASE.rotated(_angle)

	# Depth illusion: scale sword larger when blade is "in front" (pointing down)
	var depth: float = (tip.normalized().y + 1.0) * 0.5           # 0=behind, 1=front
	var d_scale: float = lerp(DEPTH_SCALE_MIN, DEPTH_SCALE_MAX, depth)
	_sword_sprite.scale    = Vector2(_IMG_SCALE * d_scale, _IMG_SCALE * d_scale)
	# depth ∈ [0,1] → depth*2-1 ∈ [-1,+1] = tip.normalized().y
	# This is the true orbit-phase tilt: positive (tip leans down) when blade is "in front",
	# negative (tip leans up) when blade is "behind" — synchronized with the depth cycle.
	var orbit_tilt: float  = ORBIT_TILT_AMP * (depth * 2.0 - 1.0)
	_sword_sprite.rotation = TILT_AMP * sin(_angle + TILT_PHASE) + _lag_angle \
	                       + orbit_tilt + INWARD_BIAS

	# ── Ghost trail ───────────────────────────────────────────────────────
	for i in range(GHOST_COUNT):
		var ga: float    = _angle - GHOST_STEP * float(i + 1)
		var g_tip: Vector2 = _TIP_BASE.rotated(ga)
		var g_depth: float = (g_tip.normalized().y + 1.0) * 0.5
		var gs: float    = lerp(DEPTH_SCALE_MIN, DEPTH_SCALE_MAX, g_depth)

		_ghost_pivots[i].rotation    = ga
		_ghost_sprites[i].scale      = Vector2(_IMG_SCALE * gs, _IMG_SCALE * gs)
		var g_orbit_tilt: float      = ORBIT_TILT_AMP * (g_depth * 2.0 - 1.0)
		_ghost_sprites[i].rotation   = TILT_AMP * sin(ga + TILT_PHASE) + _lag_angle \
		                             + g_orbit_tilt + INWARD_BIAS
		# Fade ghosts with speed: invisible when sword is near-still
		_ghost_sprites[i].modulate.a = GHOST_ALPHAS[i] * _speed_factor

	# ── Redraw slash-ring layer ───────────────────────────────────────────
	queue_redraw()

	# ── Per-rotation damage & burst ───────────────────────────────────────
	while _total_angle >= TAU * float(_rotations_done + 1) and _rotations_done < ROTATIONS:
		_rotations_done += 1
		if not _on_damage.is_null():
			_on_damage.call()
		_spawn_impact_burst(tip)
		_flash_hit()

	# ── End of animation ──────────────────────────────────────────────────
	if progress >= 1.0:
		# Safety: fire any damage that didn't tick due to floating-point
		while _rotations_done < ROTATIONS:
			_rotations_done += 1
			if not _on_damage.is_null():
				_on_damage.call()
		_finish()


# =========================================================
#  DRAW  — Slash ring & wind vortex (rendered below children)
# =========================================================

func _draw() -> void:
	if not _running and _time <= 0.0:
		return

	var sf: float = _speed_factor
	var p1: float = (sin(_time * 8.5) + 1.0) * 0.5
	var p2: float = (sin(_time * 5.8 + 1.57) + 1.0) * 0.5

	var r: float  = SWORD_VISUAL_LENGTH            # blade reach
	var vr: float = r * VORTEX_RING_MULT           # outer ring radius  ≈ 377 px

	# ── Background hazard disc (very faint) ──────────────────────────
	draw_circle(Vector2.ZERO, vr * 0.94,
		Color(0.0, 0.35, 0.08, (0.035 + p2 * 0.025) * sf))

	# ── Main blade-path ring ──────────────────────────────────────────
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 80,
		Color(0.10, 1.00, 0.28, (0.28 + p1 * 0.22) * sf), 22.0)

	# ── Inner secondary ring ──────────────────────────────────────────
	draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 72,
		Color(0.05, 0.80, 0.20, (0.14 + p2 * 0.12) * sf), 12.0)

	# ── Outer halo ────────────────────────────────────────────────────
	draw_arc(Vector2.ZERO, vr, 0.0, TAU, 72,
		Color(0.20, 0.90, 0.15, (0.09 + p1 * 0.08) * sf), 9.0)

	# ── 3 counter-rotating thick wind slashes ────────────────────────
	# They spin faster than the sword in the opposite direction → vortex feel
	var slash_rot: float = -_angle * 1.35
	for i in range(3):
		var a0: float = slash_rot + (TAU / 3.0) * float(i)
		var a1: float = a0 + TAU * 0.52
		draw_arc(Vector2.ZERO, vr * 0.86, a0, a1, 52,
			Color(0.35, 1.0, 0.45, (0.20 + p2 * 0.14) * sf), 24.0)
		# Bright inner edge of each slash
		draw_arc(Vector2.ZERO, vr * 0.78, a0, a0 + TAU * 0.28, 32,
			Color(0.80, 1.0, 0.85, (0.12 + p1 * 0.10) * sf), 10.0)

	# ── 6 fast-spinning inner detail arcs ────────────────────────────
	var inner_rot: float = _angle * 2.4
	for i in range(6):
		var a0: float = inner_rot + (TAU / 6.0) * float(i)
		draw_arc(Vector2.ZERO, r * 0.48, a0, a0 + TAU * 0.18, 22,
			Color(0.55, 1.0, 0.65, (0.14 + p2 * 0.10) * sf), 9.0)

	# ── Hilt / pommel glow (always rendered, pulses with speed) ──────
	var hilt_a: float = 0.10 + sf * 0.40 + p1 * 0.15
	draw_circle(Vector2.ZERO, 20.0, Color(0.20, 1.0, 0.45, hilt_a))
	draw_circle(Vector2.ZERO,  8.0, Color(0.85, 1.0, 0.90, hilt_a * 1.2))


# =========================================================
#  HIT FLASH  (bright sword flash on each rotation hit)
# =========================================================

func _flash_hit() -> void:
	# Momentary overbright white flash, then back to tinted normal
	_sword_sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
	var tw := create_tween()
	tw.tween_property(_sword_sprite, "modulate",
		Color(0.92, 1.0, 0.92, 1.0), 0.14)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# =========================================================
#  IMPACT BURST  (particles at blade tip on each hit)
# =========================================================

func _spawn_impact_burst(tip_pos: Vector2) -> void:
	var b := CPUParticles2D.new()
	b.z_index             = 8
	b.position            = tip_pos
	b.emitting            = true
	b.one_shot            = true
	b.amount              = 32
	b.lifetime            = 0.52
	b.explosiveness       = 0.95
	b.randomness          = 0.4
	b.emission_shape      = CPUParticles2D.EMISSION_SHAPE_SPHERE
	b.emission_sphere_radius = 10.0
	b.direction           = Vector2(0.0, -1.0)
	b.spread              = 180.0
	b.gravity             = Vector2(0.0, 160.0)
	b.initial_velocity_min = 110.0
	b.initial_velocity_max = 270.0
	b.scale_amount_min    = 1.8
	b.scale_amount_max    = 4.5
	var bg := Gradient.new()
	bg.set_color(0, Color(1.0, 1.0, 0.6, 1.0))
	bg.set_color(1, Color(0.0, 1.0, 0.4, 0.0))
	b.color_ramp = bg
	add_child(b)
	get_tree().create_timer(0.95).timeout.connect(
		func(): if is_instance_valid(b): b.queue_free()
	)


# =========================================================
#  FINISH
# =========================================================

func _finish() -> void:
	if not _running:
		return
	_running = false
	_sparks.emitting = false

	if not _on_complete.is_null():
		_on_complete.call()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.08, 0.08), 0.24)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.20)
	tw.chain().tween_callback(queue_free)
