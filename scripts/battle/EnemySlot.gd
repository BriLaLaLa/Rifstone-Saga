# File: res://scripts/battle/EnemySlot.gd
# Singolo slot nemico con HP bar, sprite e targeting

extends Control
class_name EnemySlot

# const LOG removed - using GameLogger  # Cambiato a true per debug

# ==================== EXPORTED VARIABLES (Inspector) ====================
@export_group("Slot Size & Layout")
@export var slot_width: int = 180  # Width of entire slot
@export var slot_height: int = 220  # Height of entire slot
@export var sprite_size: int = 150  # Size of enemy sprite (square)
@export var sprite_margin_top: int = 35  # Space above sprite for name
@export var sprite_margin_sides: int = 15  # Space on left/right of sprite
@export var hp_bar_height: int = 20  # Height of HP bar
@export var hp_bar_margin_bottom: int = 10  # Space below HP bar

@export_group("Visual Style - Background")
@export var show_background: bool = false  # Set to true to show background panel
@export var normal_bg_color: Color = Color(0.2, 0.2, 0.3, 0.95)  # Grigio scuro
@export var normal_border_color: Color = Color(0.6, 0.6, 0.7)
@export var boss_bg_color: Color = Color(0.5, 0.1, 0.1, 0.95)  # Rosso scuro
@export var boss_border_color: Color = Color.RED
@export var border_width: int = 3
@export var corner_radius: int = 8

@export_group("Visual Style - Targeting")
@export var targeted_border_color: Color = Color.YELLOW
@export var targeted_border_width: int = 5

@export_group("Visual Style - Hover")
@export var hover_brightness: float = 1.2

@export_group("Visual Style - Placeholder")
@export var boss_placeholder_color: Color = Color(0.9, 0.1, 0.1, 1.0)  # Rosso brillante
@export var normal_placeholder_color: Color = Color(0.7, 0.3, 0.3, 1.0)  # Rosso medio

@export_group("HP Bar Colors")
@export var hp_high_color: Color = Color.GREEN  # > 60%
@export var hp_medium_color: Color = Color.YELLOW  # 30-60%
@export var hp_low_color: Color = Color.RED  # < 30%
@export var hp_high_threshold: float = 0.6
@export var hp_low_threshold: float = 0.3

@export_group("Name Label Colors")
@export var boss_name_color: Color = Color.RED
@export var normal_name_color: Color = Color.WHITE

@export_group("Animation Timings")
@export var spawn_duration: float = 0.3
@export var hit_flash_duration: float = 0.1
@export var death_duration: float = 0.5
@export var damage_number_font_size: int = 24
@export var heal_number_font_size: int = 24

# ==================== INTERNAL VARIABLES ====================
# Enemy data
var enemy_id: String = ""
var enemy_name: String = ""
var enemy_level: int = 1  # Enemy level for XP calculation
var current_hp: float = 0.0
var max_hp: float = 100.0
var is_boss: bool = false
var is_alive: bool = false

# Attack data
var attack_damage: float = 10.0
var attack_speed: float = 3.0  # Random 2.5-3.5 seconds (set on spawn)
var attack_timer: float = 0.0
var attack_duration: float = 3.0  # Current attack interval
const ATTACK_MIN: float = 2.5
const ATTACK_MAX: float = 3.5

# Visual references
@onready var background: Panel = $Background
@onready var enemy_sprite: TextureRect = $EnemySprite
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPBar/HPLabel
@onready var name_label: Label = $NameLabel
@onready var damage_label: Label = $DamageLabel
@onready var attack_bar: ProgressBar = $AttackBar

# State
var is_targeted: bool = false

# Hit animation state
var _hit_tween: Tween = null
var _base_pos_x: float = 0.0

# Metin spawn mechanic
var is_metin: bool = false
var special_mechanics: Dictionary = {}
var spawn_thresholds_triggered: Array = []  # Track which thresholds have been triggered

# Signals
signal enemy_clicked(slot: EnemySlot)
signal enemy_died(slot: EnemySlot)
signal metin_spawn_request(spawn_count: int, spawn_types: Array)

func _apply_layout_settings() -> void:
	"""Apply exported layout settings to slot size and element positions"""
	# Apply slot size
	custom_minimum_size = Vector2(slot_width, slot_height)
	size = custom_minimum_size

	# Apply background visibility
	if background:
		background.visible = show_background
		if show_background:
			background.size = custom_minimum_size

	# Apply sprite size and position (centered horizontally)
	if enemy_sprite:
		enemy_sprite.position = Vector2(sprite_margin_sides, sprite_margin_top)
		enemy_sprite.size = Vector2(sprite_size, sprite_size)

	# Apply name label position (full width, above sprite)
	if name_label:
		name_label.position = Vector2(0, 5)
		name_label.size = Vector2(slot_width, 25)

	# Apply HP bar position (below sprite, centered)
	if hp_bar:
		var hp_bar_y = sprite_margin_top + sprite_size + 5
		hp_bar.position = Vector2(sprite_margin_sides, hp_bar_y)
		hp_bar.size = Vector2(sprite_size, hp_bar_height)

func _ready() -> void:
	# Apply exported layout settings
	_apply_layout_settings()

	# Setup interattività
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Nascondi inizialmente
	visible = false

	# Setup damage label (nascosto inizialmente)
	if damage_label:
		damage_label.visible = false
		damage_label.modulate = Color.WHITE

	if GameLogger.ENABLED:
		print("[EnemySlot] Ready at position: %s, size: %s" % [position, size])

	# Check if spawn data was stored in metadata (from SlotManager)
	if has_meta("needs_spawn") and get_meta("needs_spawn"):
		var mob_id = get_meta("mob_id")
		var mob_data = get_meta("mob_data")

		if GameLogger.ENABLED:
			print("[EnemySlot] Auto-spawning from metadata: %s" % mob_id)

		# NOW we can safely call spawn_enemy because @onready vars are initialized
		spawn_enemy(mob_id, mob_data)

		# Clear metadata
		remove_meta("needs_spawn")

func _process(delta: float) -> void:
	"""Process enemy attacks on player"""
	if not is_alive:
		if attack_bar:
			attack_bar.visible = false
		return

	# Update attack timer
	attack_timer += delta
	_update_attack_bar()

	# Trigger attack when timer reaches duration
	if attack_timer >= attack_duration:
		_attack_player()
		_reset_attack_timer()

func _attack_player() -> void:
	"""Enemy attacks the player"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		return

	# Apply damage to player
	gs.character_stats.take_damage(attack_damage)

	if GameLogger.ENABLED:
		print("[EnemySlot] %s attacked player for %.1f damage" % [enemy_name, attack_damage])

func _update_attack_bar() -> void:
	"""Update the visual attack timer bar"""
	if not attack_bar or not is_alive:
		return

	# Show bar and update value
	attack_bar.visible = true
	attack_bar.max_value = attack_duration
	attack_bar.value = attack_timer

	# Color changes based on progress (yellow → orange → red)
	var percent = attack_timer / attack_duration
	if percent < 0.5:
		attack_bar.modulate = Color(1.0, 0.8, 0.0)  # Yellow
	elif percent < 0.8:
		attack_bar.modulate = Color(1.0, 0.5, 0.0)  # Orange
	else:
		attack_bar.modulate = Color(1.0, 0.2, 0.0)  # Red

func _reset_attack_timer() -> void:
	"""Reset attack timer with new random duration"""
	attack_duration = randf_range(ATTACK_MIN, ATTACK_MAX)
	attack_timer = 0.0
	attack_speed = attack_duration  # Keep for compatibility

	if GameLogger.ENABLED:
		print("[EnemySlot] %s attack timer reset (next attack in %.1fs)" % [enemy_name, attack_duration])

# ==================== SETUP NEMICO ====================

func spawn_enemy(mob_id: String, mob_data: Dictionary) -> void:
	"""Spawna un nemico in questo slot"""
	enemy_id = mob_id
	enemy_name = mob_data.get("name", "Unknown Enemy")
	max_hp = float(mob_data.get("hp", 100))
	current_hp = max_hp
	is_boss = bool(mob_data.get("is_boss", false))
	is_metin = bool(mob_data.get("is_metin", false))
	is_alive = true

	# Setup attack stats (use level-based scaling if no attack specified)
	enemy_level = int(mob_data.get("level", 1))  # Save to class property for XP calculation
	attack_damage = float(mob_data.get("attack", enemy_level * 5.0))  # 5 damage per level default

	# Randomize attack duration (2.5-3.5 seconds)
	attack_duration = randf_range(ATTACK_MIN, ATTACK_MAX)
	attack_timer = 0.0  # Reset attack timer
	attack_speed = attack_duration  # Keep for compatibility

	# Setup Metin special mechanics
	special_mechanics = mob_data.get("special_mechanics", {})
	spawn_thresholds_triggered = []  # Reset triggered thresholds

	# Enable _process to allow enemy attacks
	set_process(true)

	# Setup visuals
	_setup_visuals(mob_data)
	_update_hp_display()

	# Mostra lo slot
	visible = true

	# Animazione spawn
	_play_spawn_animation()

	# Cache base X for hit animation (position is set by SlotManager before spawn_enemy)
	_base_pos_x = position.x

	if GameLogger.ENABLED:
		print("[EnemySlot] Spawned '%s' (HP: %d, Attack: %.1fs) at global: %s, local: %s" %
			[enemy_name, max_hp, attack_duration, global_position, position])

func _setup_visuals(mob_data: Dictionary) -> void:
	"""Configura l'aspetto del nemico"""
	
	# Nome
	if name_label:
		name_label.text = enemy_name

		# Colore nome in base al tipo (usa valori dall'Inspector)
		if is_boss:
			name_label.add_theme_color_override("font_color", boss_name_color)
		else:
			name_label.add_theme_color_override("font_color", normal_name_color)
	
	# Sprite/Texture - USA PLACEHOLDER VISIBILE
	if enemy_sprite:
		if mob_data.has("icon"):
			var texture_path = mob_data.icon
			if ResourceLoader.exists(texture_path):
				enemy_sprite.texture = load(texture_path)
			else:
				# Placeholder colorato
				_create_placeholder_sprite()
		else:
			# Placeholder colorato
			_create_placeholder_sprite()
	
	# Background style (usa valori dall'Inspector)
	if background:
		var style = StyleBoxFlat.new()
		if is_boss:
			style.bg_color = boss_bg_color
			style.border_color = boss_border_color
		else:
			style.bg_color = normal_bg_color
			style.border_color = normal_border_color

		style.border_width_left = border_width
		style.border_width_right = border_width
		style.border_width_top = border_width
		style.border_width_bottom = border_width
		style.corner_radius_top_left = corner_radius
		style.corner_radius_top_right = corner_radius
		style.corner_radius_bottom_left = corner_radius
		style.corner_radius_bottom_right = corner_radius
		background.add_theme_stylebox_override("panel", style)

func _create_placeholder_sprite() -> void:
	"""Crea uno sprite placeholder visibile con ColorRect"""
	if not enemy_sprite:
		return
	
	# Rimuovi vecchi placeholder
	for child in enemy_sprite.get_children():
		child.queue_free()
	
	# Crea ColorRect come placeholder
	var placeholder = ColorRect.new()
	placeholder.color = _get_enemy_color()
	placeholder.size = Vector2(80, 80)
	placeholder.position = Vector2(
		(enemy_sprite.size.x - 80) / 2,
		(enemy_sprite.size.y - 80) / 2
	)
	enemy_sprite.add_child(placeholder)
	
	# Aggiungi una label al centro
	var label = Label.new()
	label.text = "?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.size = placeholder.size
	placeholder.add_child(label)

func _get_enemy_color() -> Color:
	"""Restituisce un colore basato sul tipo di nemico"""
	if is_boss:
		return boss_placeholder_color
	else:
		return normal_placeholder_color

# ==================== HP MANAGEMENT ====================

func take_damage(amount: float) -> void:
	"""Il nemico subisce danno"""
	if not is_alive:
		return

	current_hp -= amount
	current_hp = max(0.0, current_hp)

	# Log PRIMA del check di morte per chiarezza
	if GameLogger.ENABLED:
		print("[EnemySlot] %s took %d damage (HP: %d/%d)" % [enemy_name, amount, current_hp, max_hp])
		print("[EnemySlot] hp_bar exists: %s, visible: %s" % [hp_bar != null, hp_bar.visible if hp_bar else false])
		print("[EnemySlot] hp_label exists: %s, visible: %s" % [hp_label != null, hp_label.visible if hp_label else false])

	_update_hp_display()
	_show_damage_number(amount)

	# Animazione hit
	_play_hit_animation()

	# Check Metin spawn mechanic (HP thresholds)
	if is_metin and special_mechanics.get("spawn_adds", false):
		_check_metin_spawn_thresholds()

	# Check morte
	if current_hp <= 0.0:
		_die()

func heal(amount: float) -> void:
	"""Il nemico si cura"""
	if not is_alive:
		return
	
	current_hp += amount
	current_hp = min(max_hp, current_hp)
	
	_update_hp_display()
	_show_heal_number(amount)

func _update_hp_display() -> void:
	"""Aggiorna la HP bar"""
	if not hp_bar:
		return
	
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	
	if hp_label:
		hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]
	
	# Cambia colore in base alla % di HP (usa valori dall'Inspector)
	var hp_percent = current_hp / max_hp
	if hp_percent > hp_high_threshold:
		hp_bar.modulate = hp_high_color
	elif hp_percent > hp_low_threshold:
		hp_bar.modulate = hp_medium_color
	else:
		hp_bar.modulate = hp_low_color

func _die() -> void:
	"""Il nemico muore"""
	is_alive = false

	# Store death position BEFORE animation (for loot orb spawning)
	var death_position = global_position + Vector2(slot_width / 2, slot_height / 2)

	if GameLogger.ENABLED:
		print("[EnemySlot] %s died at position: %s" % [enemy_name, death_position])

	# Animazione morte
	_play_death_animation()

	# Emetti signal
	enemy_died.emit(self)

# ==================== METIN SPAWN MECHANIC ====================

func _check_metin_spawn_thresholds() -> void:
	"""Check if Metin has crossed any HP thresholds and trigger mob spawns"""
	if not is_metin or max_hp <= 0:
		return

	var hp_percent = current_hp / max_hp
	var spawn_thresholds = special_mechanics.get("spawn_thresholds", [])

	for threshold in spawn_thresholds:
		# Check if we've crossed this threshold and haven't triggered it yet
		if hp_percent <= threshold and not threshold in spawn_thresholds_triggered:
			spawn_thresholds_triggered.append(threshold)

			# Calculate how many mobs to spawn (1-8 random)
			var spawn_count_min = int(special_mechanics.get("spawn_count_min", 1))
			var spawn_count_max = int(special_mechanics.get("spawn_count_max", 8))
			var spawn_count = randi_range(spawn_count_min, spawn_count_max)

			# Get the types of mobs to spawn
			var spawn_types = special_mechanics.get("spawn_types", [])

			if GameLogger.ENABLED:
				print("[EnemySlot] 🔮 METIN THRESHOLD CROSSED: %.0f%% HP - Spawning %d mobs!" % [threshold * 100, spawn_count])

			# Emit signal to SlotManager to spawn the adds
			metin_spawn_request.emit(spawn_count, spawn_types)

			break  # Only trigger one threshold per damage instance

# ==================== TARGETING ====================

func set_targeted(targeted: bool) -> void:
	"""Imposta/rimuove il targeting visuale"""
	is_targeted = targeted

	if background:
		var style = background.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			if is_targeted:
				# Highlight (usa valori dall'Inspector)
				style.border_color = targeted_border_color
				style.border_width_left = targeted_border_width
				style.border_width_right = targeted_border_width
				style.border_width_top = targeted_border_width
				style.border_width_bottom = targeted_border_width
			else:
				# Normale (usa valori dall'Inspector)
				if is_boss:
					style.border_color = boss_border_color
				else:
					style.border_color = normal_border_color
				style.border_width_left = border_width
				style.border_width_right = border_width
				style.border_width_top = border_width
				style.border_width_bottom = border_width

func _on_gui_input(event: InputEvent) -> void:
	"""Gestisci click sul nemico"""
	if not is_alive:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			enemy_clicked.emit(self)
			if GameLogger.ENABLED:
				print("[EnemySlot] Clicked on %s" % enemy_name)

func _on_mouse_entered() -> void:
	"""Hover effect"""
	if not is_alive:
		return

	modulate = Color(hover_brightness, hover_brightness, hover_brightness)

func _on_mouse_exited() -> void:
	"""Remove hover effect"""
	modulate = Color.WHITE

# ==================== ANIMATIONS ====================

func _play_spawn_animation() -> void:
	"""Animazione di spawn epica (fade-in + scale + rotation + bounce)"""
	# Start invisible, small, and rotated
	modulate.a = 0.0
	scale = Vector2(0.3, 0.3)
	rotation = deg_to_rad(360)  # Full rotation

	# Phase 1: Fade in + scale up with rotation (fast)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	tween.tween_property(self, "modulate:a", 1.0, spawn_duration * 0.6)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), spawn_duration * 0.6)  # Overshoot
	tween.tween_property(self, "rotation", 0.0, spawn_duration * 0.6)

	# Phase 2: Bounce back to normal size (sequential)
	tween.chain().tween_property(self, "scale", Vector2.ONE, spawn_duration * 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)

	# Optional: Add a subtle "impact" effect at the end
	if enemy_sprite:
		tween.parallel().tween_property(enemy_sprite, "modulate", Color(1.5, 1.5, 1.5), spawn_duration * 0.2)
		tween.chain().tween_property(enemy_sprite, "modulate", Color.WHITE, spawn_duration * 0.2)

func _play_hit_animation() -> void:
	"""Animazione quando subisce danno: flash rosso + tick a sinistra."""
	# Kill any ongoing hit tween to avoid position drift
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
		position.x = _base_pos_x  # Snap back before restart

	var orig_mod := modulate
	var base_x := _base_pos_x

	# --- Red flash (independent tween) ---
	var flash := create_tween()
	flash.tween_property(self, "modulate", Color(1.0, 0.25, 0.25, orig_mod.a), 0.05)
	flash.tween_property(self, "modulate", orig_mod, 0.20)

	# --- Tick to the left then elastic spring back ---
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "position:x", base_x - 13.0, 0.05)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(self, "position:x", base_x, 0.22)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _play_death_animation() -> void:
	"""Animazione di morte (fade-out + scale down)"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(self, "modulate:a", 0.0, death_duration)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), death_duration)

	await tween.finished
	visible = false

func _show_damage_number(amount: float) -> void:
	"""Mostra il numero del danno con animazione stile Diablo/Metin2"""
	if GameLogger.ENABLED:
		print("[EnemySlot] Creating damage number: %d" % amount)

	# Load DamageNumber class
	var DamageNumber = load("res://scripts/battle/DamageNumber.gd")

	if DamageNumber:
		# Crea il damage number al centro dello slot
		var spawn_pos = Vector2(size.x / 2, size.y / 2)
		DamageNumber.create_at_position(self, spawn_pos, int(amount), false)
		if GameLogger.ENABLED:
			print("[EnemySlot] DamageNumber created at position: %s" % spawn_pos)
	else:
		if GameLogger.ENABLED:
			print("[EnemySlot] ERROR: Could not load DamageNumber script!")

func _show_heal_number(amount: float) -> void:
	"""Mostra il numero della cura"""
	if not damage_label:
		return

	damage_label.text = "+%d" % int(amount)
	damage_label.add_theme_color_override("font_color", Color.GREEN)
	damage_label.add_theme_font_size_override("font_size", heal_number_font_size)
	damage_label.visible = true
	damage_label.position = Vector2(size.x / 2, size.y / 2)
	damage_label.modulate.a = 1.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "position:y", damage_label.position.y - 50, 0.8)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.8)
	
	await tween.finished
	damage_label.visible = false

# ==================== API PUBBLICA ====================

func get_enemy_id() -> String:
	return enemy_id

func get_enemy_name() -> String:
	return enemy_name

func get_hp_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return current_hp / max_hp

func is_enemy_alive() -> bool:
	return is_alive

func clear() -> void:
	"""Pulisce lo slot"""
	if GameLogger.ENABLED:
		print("[EnemySlot] 🧹 Clearing slot - enemy: %s, was alive: %s" % [enemy_name, is_alive])

	enemy_id = ""
	enemy_name = ""
	current_hp = 0.0
	max_hp = 100.0
	is_boss = false
	is_alive = false
	is_targeted = false
	visible = false

	# CRITICAL: Stop attack timer and disable _process to prevent attacks after death
	attack_timer = 0.0
	set_process(false)

	# Hide attack bar
	if attack_bar:
		attack_bar.visible = false

	if GameLogger.ENABLED:
		print("[EnemySlot] ✅ Slot cleared and _process disabled")

func get_center_position() -> Vector2:
	"""Get global center position of enemy slot (for loot orb spawning)"""
	return global_position + Vector2(slot_width / 2, slot_height / 2)
