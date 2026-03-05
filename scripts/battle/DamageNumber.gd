extends Label
class_name DamageNumber

# Floating Damage Number (Diablo/Metin2 style)
# Shows damage with scale animation and fade out

# const LOG removed - using GameLogger

var damage_value: int = 0
var is_critical: bool = false
var is_basic_attack: bool = false

func _ready() -> void:
	# Start invisible
	modulate = Color(1, 1, 1, 0)

	# Start animation
	_animate()

func setup(damage: int, critical: bool = false, basic_attack: bool = false) -> void:
	"""Setup damage number with value, critical flag, and basic attack indicator"""
	damage_value = damage
	is_critical = critical
	is_basic_attack = basic_attack

	# Set text
	if is_basic_attack:
		text = "Basic Attack\n%d" % damage
	else:
		text = str(damage)

	# Set color based on type
	if is_basic_attack:
		add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White for basic attack
	elif is_critical:
		add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))  # Gold for critical
	else:
		add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))  # Yellow for normal skills

	# Set font size
	var base_size = 36
	if is_critical:
		base_size = 48
	elif is_basic_attack:
		base_size = 28  # Slightly smaller for basic attack with text

	add_theme_font_size_override("font_size", base_size)

	# Outline nero SPESSO per contrasto
	add_theme_constant_override("outline_size", 12)
	add_theme_color_override("font_outline_color", Color.BLACK)

	if GameLogger.ENABLED:
		print("[DamageNumber] Setup: %d (Critical: %s, BasicAttack: %s)" % [damage, critical, basic_attack])

func _animate() -> void:
	"""Animate the damage number (scale up, then fade out while moving up)"""
	var tween = create_tween()
	tween.set_parallel(true)

	# Phase 1: Fade in + Scale up (0.2s - più lento)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Phase 2: Stay at peak (0.3s - più lungo)
	await get_tree().create_timer(0.2).timeout

	# Phase 3: Scale down + Move + Fade out (1.2s - MOLTO più lungo)
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Movimento: Up + Left/Right in base alla posizione del parent
	var parent_global_x = get_parent().global_position.x if get_parent() else 0
	var screen_center_x = get_viewport_rect().size.x / 2

	# Se il nemico è a sinistra dello schermo, va verso sinistra
	# Se è a destra, va verso destra
	var horizontal_offset = -80 if parent_global_x < screen_center_x else 80

	tween.tween_property(self, "position:y", position.y - 120, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:x", position.x + horizontal_offset, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Fade più lento alla fine (rimane visibile più a lungo)
	tween.tween_property(self, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.2)

	# Clean up after animation
	await tween.finished
	queue_free()

static func create_at_position(parent: Node, pos: Vector2, damage: int, critical: bool = false, basic_attack: bool = false) -> DamageNumber:
	"""Create a damage number at a specific position"""
	var dmg_num = DamageNumber.new()
	parent.add_child(dmg_num)

	dmg_num.position = pos
	dmg_num.setup(damage, critical, basic_attack)

	# Center the label
	dmg_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dmg_num.z_index = 100  # Always on top

	return dmg_num


