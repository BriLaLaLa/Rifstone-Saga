# File: res://scripts/battle/EnemySlot.gd
# Singolo slot nemico con HP bar, sprite e targeting

extends Control
class_name EnemySlot

const LOG := true  # Cambiato a true per debug

# Enemy data
var enemy_id: String = ""
var enemy_name: String = ""
var current_hp: float = 0.0
var max_hp: float = 100.0
var is_boss: bool = false
var is_alive: bool = false

# Visual references
@onready var background: Panel = $Background
@onready var enemy_sprite: TextureRect = $EnemySprite
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPBar/HPLabel
@onready var name_label: Label = $NameLabel
@onready var damage_label: Label = $DamageLabel

# State
var is_targeted: bool = false

# Signals
signal enemy_clicked(slot: EnemySlot)
signal enemy_died(slot: EnemySlot)

func _ready() -> void:
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
	
	if LOG:
		print("[EnemySlot] Ready at position: %s, size: %s" % [position, size])

# ==================== SETUP NEMICO ====================

func spawn_enemy(mob_id: String, mob_data: Dictionary) -> void:
	"""Spawna un nemico in questo slot"""
	enemy_id = mob_id
	enemy_name = mob_data.get("name", "Unknown Enemy")
	max_hp = float(mob_data.get("hp", 100))
	current_hp = max_hp
	is_boss = bool(mob_data.get("is_boss", false))
	is_alive = true
	
	# Setup visuals
	_setup_visuals(mob_data)
	_update_hp_display()
	
	# Mostra lo slot
	visible = true
	
	# Animazione spawn
	_play_spawn_animation()
	
	if LOG:
		print("[EnemySlot] Spawned '%s' (HP: %d) at global: %s, local: %s" % 
			[enemy_name, max_hp, global_position, position])

func _setup_visuals(mob_data: Dictionary) -> void:
	"""Configura l'aspetto del nemico"""
	
	# Nome
	if name_label:
		name_label.text = enemy_name
		
		# Colore nome in base al tipo
		if is_boss:
			name_label.add_theme_color_override("font_color", Color.RED)
		else:
			name_label.add_theme_color_override("font_color", Color.WHITE)
	
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
	
	# Background style (boss = più grande/diverso)
	if background:
		var style = StyleBoxFlat.new()
		if is_boss:
			style.bg_color = Color(0.5, 0.1, 0.1, 0.95)  # Rosso scuro
			style.border_color = Color.RED
		else:
			style.bg_color = Color(0.2, 0.2, 0.3, 0.95)  # Grigio scuro
			style.border_color = Color(0.6, 0.6, 0.7)
		
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
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
		return Color(0.9, 0.1, 0.1, 1.0)  # Rosso brillante per boss
	else:
		return Color(0.7, 0.3, 0.3, 1.0)  # Rosso medio per nemici normali

# ==================== HP MANAGEMENT ====================

func take_damage(amount: float) -> void:
	"""Il nemico subisce danno"""
	if not is_alive:
		return
	
	current_hp -= amount
	current_hp = max(0.0, current_hp)
	
	_update_hp_display()
	_show_damage_number(amount)
	
	# Animazione hit
	_play_hit_animation()
	
	# Check morte
	if current_hp <= 0.0:
		_die()
	
	if LOG:
		print("[EnemySlot] %s took %d damage (HP: %d/%d)" % [enemy_name, amount, current_hp, max_hp])

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
	
	# Cambia colore in base alla % di HP
	var hp_percent = current_hp / max_hp
	if hp_percent > 0.6:
		hp_bar.modulate = Color.GREEN
	elif hp_percent > 0.3:
		hp_bar.modulate = Color.YELLOW
	else:
		hp_bar.modulate = Color.RED

func _die() -> void:
	"""Il nemico muore"""
	is_alive = false
	
	if LOG:
		print("[EnemySlot] %s died!" % enemy_name)
	
	# Animazione morte
	_play_death_animation()
	
	# Emetti signal
	enemy_died.emit(self)

# ==================== TARGETING ====================

func set_targeted(targeted: bool) -> void:
	"""Imposta/rimuove il targeting visuale"""
	is_targeted = targeted
	
	if background:
		var style = background.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			if is_targeted:
				# Highlight giallo brillante
				style.border_color = Color.YELLOW
				style.border_width_left = 5
				style.border_width_right = 5
				style.border_width_top = 5
				style.border_width_bottom = 5
			else:
				# Normale
				if is_boss:
					style.border_color = Color.RED
				else:
					style.border_color = Color(0.6, 0.6, 0.7)
				style.border_width_left = 3
				style.border_width_right = 3
				style.border_width_top = 3
				style.border_width_bottom = 3

func _on_gui_input(event: InputEvent) -> void:
	"""Gestisci click sul nemico"""
	if not is_alive:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			enemy_clicked.emit(self)
			if LOG:
				print("[EnemySlot] Clicked on %s" % enemy_name)

func _on_mouse_entered() -> void:
	"""Hover effect"""
	if not is_alive:
		return
	
	modulate = Color(1.2, 1.2, 1.2)

func _on_mouse_exited() -> void:
	"""Remove hover effect"""
	modulate = Color.WHITE

# ==================== ANIMATIONS ====================

func _play_spawn_animation() -> void:
	"""Animazione di spawn (fade-in + scale)"""
	modulate.a = 0.0
	scale = Vector2(0.5, 0.5)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3)

func _play_hit_animation() -> void:
	"""Animazione quando subisce danno (flash rosso)"""
	var original_modulate = modulate
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.1)
	tween.tween_property(self, "modulate", original_modulate, 0.1)

func _play_death_animation() -> void:
	"""Animazione di morte (fade-out + scale down)"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.5)
	
	await tween.finished
	visible = false

func _show_damage_number(amount: float) -> void:
	"""Mostra il numero del danno che sale"""
	if not damage_label:
		return
	
	damage_label.text = "-%d" % int(amount)
	damage_label.add_theme_color_override("font_color", Color.RED)
	damage_label.add_theme_font_size_override("font_size", 24)
	damage_label.visible = true
	damage_label.position = Vector2(size.x / 2, size.y / 2)
	damage_label.modulate.a = 1.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "position:y", damage_label.position.y - 50, 0.8)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.8)
	
	await tween.finished
	damage_label.visible = false

func _show_heal_number(amount: float) -> void:
	"""Mostra il numero della cura"""
	if not damage_label:
		return
	
	damage_label.text = "+%d" % int(amount)
	damage_label.add_theme_color_override("font_color", Color.GREEN)
	damage_label.add_theme_font_size_override("font_size", 24)
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
	enemy_id = ""
	enemy_name = ""
	current_hp = 0.0
	max_hp = 100.0
	is_boss = false
	is_alive = false
	is_targeted = false
	visible = false
