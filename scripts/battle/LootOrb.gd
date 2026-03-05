# File: res://scripts/battle/LootOrb.gd
# Visual loot orb that spawns from enemy death, idles, then flies to player

extends Node2D
class_name LootOrb

signal orb_collected(item_data: Dictionary)

# References
@onready var orb_sprite: AnimatedSprite2D = $OrbSprite
@onready var glow_particles: CPUParticles2D = $GlowParticles

# Data
var item_data: Dictionary = {}
var rarity: String = "common"
var rarity_config: Dictionary = {}
var rarity_color: Color = Color.WHITE
var target_position: Vector2 = Vector2.ZERO

# State
enum State { SPAWNING, IDLE, MOVING, COLLECTING }
var current_state: State = State.SPAWNING
var idle_tween: Tween = null

func setup(p_item_data: Dictionary, p_rarity: String, spawn_pos: Vector2, target_pos: Vector2) -> void:
	"""Initialize orb with item data and positions"""
	print("[DEBUG] 🔵 LootOrb.setup() called - rarity: %s, spawn: %s, target: %s" % [p_rarity, spawn_pos, target_pos])

	item_data = p_item_data
	rarity = p_rarity
	target_position = target_pos
	global_position = spawn_pos

	print("[DEBUG] 🔵 Orb position set to: %s" % global_position)

	# Get rarity config from manager
	var manager = get_node_or_null("/root/LootOrbManager")
	if manager:
		rarity_config = manager.RARITY_CONFIG.get(rarity, manager.RARITY_CONFIG["common"])
		rarity_color = rarity_config.color
	else:
		# Fallback config
		rarity_color = Color.WHITE
		rarity_config = {
			"color": Color.WHITE,
			"particle_count": 15,
			"particle_speed": 50.0,
			"glow_scale": 1.0
		}

	# Apply visual config
	if orb_sprite:
		orb_sprite.modulate = rarity_color
	else:
		if GameLogger.ENABLED:
			print("[LootOrb] ⚠️ WARNING: orb_sprite is null!")

	if glow_particles:
		glow_particles.amount = rarity_config.particle_count
		glow_particles.initial_velocity_min = rarity_config.particle_speed * 0.5
		glow_particles.initial_velocity_max = rarity_config.particle_speed
	else:
		if GameLogger.ENABLED:
			print("[LootOrb] ⚠️ WARNING: glow_particles is null!")

	if GameLogger.ENABLED:
		print("[LootOrb] Setup: %s at %s → %s" % [rarity, spawn_pos, target_pos])

	# Start lifecycle immediately (nodes should be ready since we're added to tree)
	print("[DEBUG] 🔵 Calling _start_lifecycle()...")
	_start_lifecycle()

func _start_lifecycle() -> void:
	"""Run through orb lifecycle: spawn → idle → move → collect"""
	print("[DEBUG] 🟢 _start_lifecycle() STARTED")

	if GameLogger.ENABLED:
		print("[LootOrb] 🔄 Starting lifecycle...")

	current_state = State.SPAWNING
	print("[DEBUG] 🟢 State: SPAWNING, calling play_spawn_animation()...")
	await play_spawn_animation()

	current_state = State.IDLE
	await play_idle_animation()

	current_state = State.MOVING
	await play_magnetic_animation()

	current_state = State.COLLECTING
	await play_collection_effect()

func play_spawn_animation() -> void:
	"""Pop spawn with bounce effect (0.3s)"""
	# Initial state
	scale = Vector2.ZERO
	modulate.a = 0.0
	rotation = 0.0

	# Create tween for spawn
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# Scale: 0 → 1.2 → 1.0 (overshoot + settle)
	tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.2)
	var settle_tween = tween.chain()
	settle_tween.tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_ELASTIC)

	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

	# Rotation: slight spin during spawn
	tween.tween_property(self, "rotation", deg_to_rad(360), 0.3)

	# Particle burst
	if glow_particles:
		glow_particles.emitting = true

	await tween.finished

	if GameLogger.ENABLED:
		print("[LootOrb] Spawn animation complete")

func play_idle_animation() -> void:
	"""Gentle floating bob (0.5s loop, then stop)"""
	# Gentle floating bob (up/down)
	idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE)
	idle_tween.set_ease(Tween.EASE_IN_OUT)

	var original_y = position.y
	idle_tween.tween_property(self, "position:y", original_y - 10, 0.3)
	idle_tween.tween_property(self, "position:y", original_y + 10, 0.3)

	# Wait 0.5s then stop idle
	await get_tree().create_timer(0.5).timeout

	if idle_tween:
		idle_tween.kill()
		idle_tween = null

	if GameLogger.ENABLED:
		print("[LootOrb] Idle phase complete")

func play_magnetic_animation() -> void:
	"""Accelerating movement toward player (1-2s based on distance)"""
	# Calculate distance for duration scaling
	var distance = global_position.distance_to(target_position)
	var duration = lerp(1.0, 2.0, clamp(distance / 1000.0, 0.0, 1.0))

	# Accelerating curve (slow start → fast finish)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Position: smooth movement toward target
	tween.tween_property(self, "global_position", target_position, duration)

	# Scale: grow slightly as it approaches, then shrink
	tween.parallel().tween_property(self, "scale", Vector2.ONE * 1.5, duration * 0.6)
	var shrink_tween = tween.chain()
	shrink_tween.tween_property(self, "scale", Vector2.ZERO, duration * 0.4)

	# Rotation: fast spin during flight
	tween.parallel().tween_property(self, "rotation", deg_to_rad(720), duration)

	await tween.finished

	if GameLogger.ENABLED:
		print("[LootOrb] Magnetic movement complete")

func play_collection_effect() -> void:
	"""Instant collection - minimal effect"""
	# Instant fade and particle burst
	if glow_particles:
		glow_particles.direction = Vector2.ZERO
		glow_particles.spread = 180.0
		glow_particles.initial_velocity_min = 100.0
		glow_particles.initial_velocity_max = 150.0
		glow_particles.restart()

	# Instant disappear
	modulate.a = 0.0
	scale = Vector2.ZERO

	# Minimal wait for particles to start
	await get_tree().create_timer(0.05).timeout

	if GameLogger.ENABLED:
		print("[LootOrb] Collection effect complete - emitting signal")

	# Emit signal and cleanup
	orb_collected.emit(item_data)
	queue_free()
