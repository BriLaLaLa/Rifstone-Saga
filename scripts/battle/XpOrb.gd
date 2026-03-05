# File: res://scripts/battle/XpOrb.gd
# XP orb that spawns from enemy death and flies to XP bar

extends Node2D
class_name XpOrb

signal orb_collected(xp_amount: int)

# References
@onready var orb_sprite: ColorRect = $OrbSprite
@onready var trail_particles: CPUParticles2D = $TrailParticles

# Data
var xp_amount: int = 0
var target_position: Vector2 = Vector2.ZERO

# State
enum State { SPAWNING, IDLE, MOVING, COLLECTING }
var current_state: State = State.SPAWNING
var idle_tween: Tween = null

func setup(p_xp_amount: int, spawn_pos: Vector2, target_pos: Vector2) -> void:
	"""Initialize XP orb with amount and positions"""
	xp_amount = p_xp_amount
	target_position = target_pos
	global_position = spawn_pos

	# Green color for XP
	if orb_sprite:
		orb_sprite.modulate = Color(0.2, 1.0, 0.2)  # Bright green

	if trail_particles:
		trail_particles.color = Color(0.2, 1.0, 0.2, 0.8)
		trail_particles.emitting = false

	# Start lifecycle
	_start_lifecycle()

func _start_lifecycle() -> void:
	"""Run through orb lifecycle: spawn → idle → move → collect"""
	current_state = State.SPAWNING
	await play_spawn_animation()

	current_state = State.IDLE
	await play_idle_animation()

	current_state = State.MOVING
	await play_magnetic_animation()

	current_state = State.COLLECTING
	await play_collection_effect()

func play_spawn_animation() -> void:
	"""Pop spawn with bounce effect (0.2s)"""
	# Initial state
	scale = Vector2.ZERO
	modulate.a = 0.0
	rotation = 0.0

	# Create tween for spawn
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# Scale: 0 → 1.0 (smaller than item orbs)
	tween.tween_property(self, "scale", Vector2.ONE * 0.8, 0.15)

	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

	# Start trail particles
	if trail_particles:
		trail_particles.emitting = true

	await tween.finished

func play_idle_animation() -> void:
	"""Brief float (0.3s)"""
	# Gentle floating bob
	idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE)
	idle_tween.set_ease(Tween.EASE_IN_OUT)

	var original_y = position.y
	idle_tween.tween_property(self, "position:y", original_y - 8, 0.2)
	idle_tween.tween_property(self, "position:y", original_y + 8, 0.2)

	# Wait 0.3s then stop idle
	await get_tree().create_timer(0.3).timeout

	if idle_tween:
		idle_tween.kill()
		idle_tween = null

func play_magnetic_animation() -> void:
	"""Fast movement toward XP bar (0.8-1.5s based on distance)"""
	# Calculate distance for duration scaling
	var distance = global_position.distance_to(target_position)
	var duration = lerp(0.8, 1.5, clamp(distance / 1000.0, 0.0, 1.0))

	# Accelerating curve
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Position: smooth movement toward target
	tween.tween_property(self, "global_position", target_position, duration)

	# Scale: shrink as it approaches
	tween.parallel().tween_property(self, "scale", Vector2.ONE * 0.3, duration)

	# Rotation: spin during flight
	tween.parallel().tween_property(self, "rotation", deg_to_rad(720), duration)

	await tween.finished

func play_collection_effect() -> void:
	"""Flash and vanish (0.15s)"""
	# Flash bright green
	var tween = create_tween()
	tween.set_parallel(true)

	if orb_sprite:
		tween.tween_property(orb_sprite, "modulate", Color(0.5, 2.0, 0.5), 0.1)

	# Particle burst
	if trail_particles:
		trail_particles.amount = 30
		trail_particles.initial_velocity_min = 80.0
		trail_particles.initial_velocity_max = 120.0
		trail_particles.restart()

	# Scale to zero
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_EXPO)

	await tween.finished

	# Emit signal and cleanup
	orb_collected.emit(xp_amount)
	queue_free()
