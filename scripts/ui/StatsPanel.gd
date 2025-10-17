# StatsPanel.gd
# Pannello scrollabile con tutte le statistiche del personaggio
# Con animazioni smooth quando cambiano!
# Path: res://scripts/ui/StatsPanel.gd

extends ScrollContainer
class_name StatsPanel

const LOG := false

# Stats display structure
var stat_labels := {}  # stat_name -> Label node
var stat_current_values := {}  # Per animazioni
var stat_target_values := {}

# Animation
var animation_speed := 2.0  # Velocità interpolazione

# Colors
const COLOR_NORMAL := Color.WHITE
const COLOR_BONUS := Color.GREEN
const COLOR_MALUS := Color.RED
const COLOR_MODIFIED := Color.YELLOW
const COLOR_CATEGORY := Color(1.0, 0.8, 0.3)  # Gold

@onready var stats_container: VBoxContainer = $StatsContainer

func _ready() -> void:
	_build_stats_ui()
	_connect_to_gamestate()
	
	# First update
	call_deferred("_update_all_stats")
	
	if LOG:
		print("[StatsPanel] Ready")

func _process(delta: float) -> void:
	_animate_stats(delta)

# ============================================
# BUILD UI
# ============================================

func _build_stats_ui() -> void:
	"""Costruisce l'interfaccia delle stats"""
	if stats_container == null:
		# Create container if not in scene
		stats_container = VBoxContainer.new()
		stats_container.name = "StatsContainer"
		stats_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(stats_container)
	
	# Clear existing
	for child in stats_container.get_children():
		child.queue_free()
	stat_labels.clear()
	
	# Title
	var title = _create_title("⚔️ CHARACTER STATS ⚔️")
	stats_container.add_child(title)
	_add_spacer(10)
	
	# HP/Mana Bars
	_create_resource_bars()
	_add_separator()
	
	# Primary Stats
	_create_category_section("💪 PRIMARY", [
		"strength", "dexterity", "intelligence", "vitality", "luck"
	])
	
	# Offensive Stats
	_create_category_section("⚔️ OFFENSIVE", [
		"physical_damage", "magic_damage", "attack_speed", 
		"crit_chance", "crit_damage"
	])
	
	# Defensive Stats
	_create_category_section("🛡️ DEFENSIVE", [
		"physical_defense", "magic_defense", "evasion",
		"block_chance", "block_amount"
	])
	
	# Utility Stats
	_create_category_section("✨ UTILITY", [
		"hp_regen", "mana_regen", "movement_speed", "cooldown_reduction"
	])
	
	# Elemental Stats
	_create_category_section("🔥 ELEMENTAL", [
		"fire_damage", "ice_damage", "lightning_damage",
		"fire_resistance", "ice_resistance", "lightning_resistance"
	])
	
	# Bonus Stats
	_create_category_section("💰 BONUS", [
		"lifesteal", "gold_find", "magic_find"
	])
	
	if LOG:
		print("[StatsPanel] UI built with %d stat labels" % stat_labels.size())

func _create_title(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COLOR_CATEGORY)
	return label

func _create_resource_bars() -> void:
	"""Crea HP e Mana bars"""
	# HP Bar
	var hp_container = VBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 2)
	
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "HP: 100 / 100"
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(0, 24)
	hp_bar.value = 100
	hp_bar.max_value = 100
	hp_bar.show_percentage = false
	hp_bar.modulate = Color.GREEN
	
	hp_container.add_child(hp_label)
	hp_container.add_child(hp_bar)
	stats_container.add_child(hp_container)
	
	# Mana Bar
	var mana_container = VBoxContainer.new()
	mana_container.add_theme_constant_override("separation", 2)
	
	var mana_label = Label.new()
	mana_label.name = "ManaLabel"
	mana_label.text = "Mana: 50 / 50"
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var mana_bar = ProgressBar.new()
	mana_bar.name = "ManaBar"
	mana_bar.custom_minimum_size = Vector2(0, 24)
	mana_bar.value = 50
	mana_bar.max_value = 50
	mana_bar.show_percentage = false
	mana_bar.modulate = Color.DODGER_BLUE
	
	mana_container.add_child(mana_label)
	mana_container.add_child(mana_bar)
	stats_container.add_child(mana_container)

func _create_category_section(title: String, stats: Array) -> void:
	"""Crea una sezione di stats con titolo"""
	_add_spacer(5)
	
	# Category header
	var header = Label.new()
	header.text = title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COLOR_CATEGORY)
	stats_container.add_child(header)
	
	# Stats rows
	for stat_name in stats:
		_create_stat_row(stat_name)
	
	_add_separator()

func _create_stat_row(stat_name: String) -> void:
	"""Crea una riga per una singola stat"""
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 22
	row.add_theme_constant_override("separation", 10)
	
	# Name label
	var name_label = Label.new()
	name_label.text = _format_stat_name(stat_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 150
	row.add_child(name_label)
	
	# Value label (con animazione)
	var value_label = Label.new()
	value_label.name = "Value"
	value_label.text = "0"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size.x = 80
	value_label.add_theme_color_override("font_color", COLOR_NORMAL)
	row.add_child(value_label)
	
	stats_container.add_child(row)
	
	# Save reference
	stat_labels[stat_name] = value_label
	stat_current_values[stat_name] = 0.0
	stat_target_values[stat_name] = 0.0

func _add_spacer(height: int) -> void:
	var spacer = Control.new()
	spacer.custom_minimum_size.y = height
	stats_container.add_child(spacer)

func _add_separator() -> void:
	var sep = HSeparator.new()
	sep.custom_minimum_size.y = 2
	stats_container.add_child(sep)

# ============================================
# GAMESTATE CONNECTION
# ============================================

func _connect_to_gamestate() -> void:
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if gs == null:
		return
	
	# Stats changed
	if gs.has_signal("on_stats_changed"):
		if not gs.on_stats_changed.is_connected(_update_all_stats):
			gs.on_stats_changed.connect(_update_all_stats)
	
	# HP/Mana changed
	if gs.has("character_stats") and gs.character_stats:
		var stats = gs.character_stats
		if stats.has_signal("hp_changed"):
			if not stats.hp_changed.is_connected(_update_hp):
				stats.hp_changed.connect(_update_hp)
		if stats.has_signal("mana_changed"):
			if not stats.mana_changed.is_connected(_update_mana):
				stats.mana_changed.connect(_update_mana)
	
	if LOG:
		print("[StatsPanel] Connected to GameState")

# ============================================
# UPDATE STATS
# ============================================

func _update_all_stats() -> void:
	"""Aggiorna tutte le stats con animazione"""
	if not Engine.has_singleton("GameState"):
		return
	
	var gs = Engine.get_singleton("GameState")
	if gs == null or not gs.has("character_stats") or gs.character_stats == null:
		return
	
	var stats = gs.character_stats
	
	# Aggiorna ogni stat
	for stat_name in stat_labels.keys():
		var value = stats.get_stat(stat_name)
		var base = stats.base_stats.get(stat_name, 0)
		var bonus = stats.equipment_bonuses.get(stat_name, 0)
		
		# Set target per animazione
		stat_target_values[stat_name] = value
		
		# Update color based on bonus
		_update_stat_color(stat_name, base, bonus)
	
	# Update HP/Mana
	_update_hp(stats.current_hp, stats.get_stat("max_hp"))
	_update_mana(stats.current_mana, stats.get_stat("max_mana"))
	
	if LOG:
		print("[StatsPanel] Stats updated")

func _animate_stats(delta: float) -> void:
	"""Anima le stats verso i valori target"""
	for stat_name in stat_current_values.keys():
		var current = stat_current_values[stat_name]
		var target = stat_target_values[stat_name]
		
		if abs(current - target) > 0.1:
			# Smooth interpolation
			current = lerp(current, target, animation_speed * delta)
			stat_current_values[stat_name] = current
			
			# Update label
			if stat_labels.has(stat_name):
				var label = stat_labels[stat_name]
				label.text = _format_stat_value(stat_name, current)

func _update_stat_color(stat_name: String, base: float, bonus: float) -> void:
	"""Aggiorna il colore di una stat in base al bonus"""
	if not stat_labels.has(stat_name):
		return
	
	var label = stat_labels[stat_name]
	
	if bonus > 0:
		label.add_theme_color_override("font_color", COLOR_BONUS)
	elif bonus < 0:
		label.add_theme_color_override("font_color", COLOR_MALUS)
	else:
		label.add_theme_color_override("font_color", COLOR_NORMAL)

func _update_hp(current: float, maximum: float) -> void:
	"""Aggiorna HP bar"""
	var hp_label = stats_container.get_node_or_null("VBoxContainer/HPLabel")
	var hp_bar = stats_container.get_node_or_null("VBoxContainer/HPBar")
	
	if hp_label:
		hp_label.text = "HP: %d / %d" % [int(current), int(maximum)]
	
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
		
		# Color based on %
		var percent = current / maximum if maximum > 0 else 0
		if percent > 0.5:
			hp_bar.modulate = Color.GREEN
		elif percent > 0.25:
			hp_bar.modulate = Color.YELLOW
		else:
			hp_bar.modulate = Color.RED

func _update_mana(current: float, maximum: float) -> void:
	"""Aggiorna Mana bar"""
	var mana_label = stats_container.get_node_or_null("VBoxContainer2/ManaLabel")
	var mana_bar = stats_container.get_node_or_null("VBoxContainer2/ManaBar")
	
	if mana_label:
		mana_label.text = "Mana: %d / %d" % [int(current), int(maximum)]
	
	if mana_bar:
		mana_bar.max_value = maximum
		mana_bar.value = current

# ============================================
# FORMATTING
# ============================================

func _format_stat_name(stat_name: String) -> String:
	"""Formatta il nome della stat (snake_case -> Title Case)"""
	var words = stat_name.split("_")
	var formatted = ""
	for word in words:
		formatted += word.capitalize() + " "
	return formatted.strip_edges()

func _format_stat_value(stat_name: String, value: float) -> String:
	"""Formatta il valore della stat"""
	# Percentage stats
	if stat_name in [
		"crit_chance", "crit_damage", "evasion", "block_chance",
		"fire_resistance", "ice_resistance", "lightning_resistance",
		"lifesteal", "cooldown_reduction", "gold_find", "magic_find"
	]:
		return "%.1f%%" % value
	
	# Decimal stats
	if stat_name in ["attack_speed", "hp_regen", "mana_regen", "movement_speed"]:
		return "%.2f" % value
	
	# Integer stats
	return str(int(value))

# ============================================
# PUBLIC API
# ============================================

func refresh() -> void:
	"""Force refresh di tutte le stats"""
	_update_all_stats()
