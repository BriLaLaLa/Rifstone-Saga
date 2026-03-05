extends ScrollContainer
class_name StatsScrollPanel

# Stats Scroll Panel - Shows all character stats in Combat tab
# Updates in real-time when stats change

# UI Elements
var stats_container: VBoxContainer = null

func _ready() -> void:
	_create_ui()
	_connect_signals()

	# Initial update after a small delay
	await get_tree().create_timer(0.5).timeout
	update_stats_display()

func _create_ui() -> void:
	"""Create the stats display UI"""
	# This ScrollContainer properties
	custom_minimum_size = Vector2(380, 300)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# Main container
	stats_container = VBoxContainer.new()
	stats_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(stats_container)

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	add_theme_stylebox_override("panel", style)

func _connect_signals() -> void:
	"""Connect to GameState signals for updates"""
	if has_node("/root/GameState"):
		var gs = get_node("/root/GameState")

		# Update when stats change
		if gs.has_signal("on_stats_changed"):
			gs.on_stats_changed.connect(update_stats_display)

		# Update when equipment changes
		if gs.has_signal("on_inventory_changed"):
			gs.on_inventory_changed.connect(update_stats_display)

func update_stats_display() -> void:
	"""Update the stats display with current values"""
	if not stats_container:
		return

	# Clear existing
	for child in stats_container.get_children():
		child.queue_free()

	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		_add_label("⚠️ Stats not available", Color.RED)
		return

	var stats = gs.character_stats

	# Title
	_add_title("⚔️ CHARACTER STATS")
	_add_separator()

	# Current HP/Mana
	_add_section_header("💚 CURRENT STATUS")
	_add_stat_row("HP", "%d / %d" % [stats.current_hp, stats.get_stat("max_hp")], _get_hp_color(stats.current_hp, stats.get_stat("max_hp")))
	_add_stat_row("Mana", "%d / %d" % [stats.current_mana, stats.get_stat("max_mana")], Color(0.3, 0.5, 1.0))
	_add_separator()

	# Combat Stats
	_add_section_header("⚔️ OFFENSIVE STATS")

	# Total Attack (calculated)
	var total_attack = gs.get_total_attack()
	_add_stat_row("Total Attack", "%.1f" % total_attack, Color(1.0, 0.8, 0.2))

	# Breakdown
	var phys_dmg = stats.get_stat("physical_damage")
	var strength = stats.get_stat("strength")
	_add_stat_breakdown("Physical Damage", phys_dmg, stats.base_stats["physical_damage"], stats.equipment_bonuses["physical_damage"])
	_add_stat_breakdown("Strength", strength, stats.base_stats["strength"], stats.equipment_bonuses["strength"])
	_add_label("  └─ Strength × 0.5 = +%.1f ATK" % (strength * 0.5), Color(0.7, 0.7, 0.7))

	_add_stat_breakdown("Magic Damage", stats.get_stat("magic_damage"), stats.base_stats["magic_damage"], stats.equipment_bonuses["magic_damage"])
	_add_stat_simple("Attack Speed", "%.2fx" % stats.get_stat("attack_speed"))
	_add_stat_simple("Crit Chance", "%.1f%%" % stats.get_stat("crit_chance"))
	_add_stat_simple("Crit Damage", "%.0f%%" % stats.get_stat("crit_damage"))
	_add_separator()

	# Defensive Stats
	_add_section_header("🛡️ DEFENSIVE STATS")

	# Total Defense (calculated)
	var total_defense = gs.get_total_defense()
	_add_stat_row("Total Defense", "%.1f" % total_defense, Color(0.3, 0.8, 1.0))

	_add_stat_breakdown("Physical Defense", stats.get_stat("physical_defense"), stats.base_stats["physical_defense"], stats.equipment_bonuses["physical_defense"])
	_add_stat_breakdown("Magic Defense", stats.get_stat("magic_defense"), stats.base_stats["magic_defense"], stats.equipment_bonuses["magic_defense"])
	_add_stat_breakdown("Vitality", stats.get_stat("vitality"), stats.base_stats["vitality"], stats.equipment_bonuses["vitality"])
	_add_label("  └─ Vitality × 0.3 = +%.1f DEF" % (stats.get_stat("vitality") * 0.3), Color(0.7, 0.7, 0.7))

	_add_stat_simple("Evasion", "%.1f%%" % stats.get_stat("evasion"))
	_add_stat_simple("Block Chance", "%.1f%%" % stats.get_stat("block_chance"))
	if stats.get_stat("block_amount") > 0:
		_add_stat_simple("Block Amount", "%.0f" % stats.get_stat("block_amount"))
	_add_separator()

	# Primary Stats
	_add_section_header("📊 PRIMARY STATS")
	_add_stat_breakdown("Dexterity", stats.get_stat("dexterity"), stats.base_stats["dexterity"], stats.equipment_bonuses["dexterity"])
	_add_stat_breakdown("Intelligence", stats.get_stat("intelligence"), stats.base_stats["intelligence"], stats.equipment_bonuses["intelligence"])
	_add_stat_breakdown("Luck", stats.get_stat("luck"), stats.base_stats["luck"], stats.equipment_bonuses["luck"])
	_add_separator()

	# Utility Stats
	_add_section_header("⚡ UTILITY STATS")
	_add_stat_simple("HP Regen", "%.1f/s" % stats.get_stat("hp_regen"))
	_add_stat_simple("Mana Regen", "%.1f/s" % stats.get_stat("mana_regen"))
	_add_stat_simple("Movement Speed", "%.0f" % stats.get_stat("movement_speed"))
	_add_stat_simple("Cooldown Reduction", "%.1f%%" % stats.get_stat("cooldown_reduction"))

	# Show elemental/bonus stats only if > 0
	var has_elemental = stats.get_stat("fire_damage") > 0 or stats.get_stat("ice_damage") > 0 or stats.get_stat("lightning_damage") > 0
	if has_elemental:
		_add_separator()
		_add_section_header("🔥 ELEMENTAL DAMAGE")
		if stats.get_stat("fire_damage") > 0:
			_add_stat_simple("Fire Damage", "%.0f" % stats.get_stat("fire_damage"))
		if stats.get_stat("ice_damage") > 0:
			_add_stat_simple("Ice Damage", "%.0f" % stats.get_stat("ice_damage"))
		if stats.get_stat("lightning_damage") > 0:
			_add_stat_simple("Lightning Damage", "%.0f" % stats.get_stat("lightning_damage"))

	var has_resistance = stats.get_stat("fire_resistance") > 0 or stats.get_stat("ice_resistance") > 0 or stats.get_stat("lightning_resistance") > 0
	if has_resistance:
		_add_separator()
		_add_section_header("🛡️ ELEMENTAL RESISTANCE")
		if stats.get_stat("fire_resistance") > 0:
			_add_stat_simple("Fire Resistance", "%.1f%%" % stats.get_stat("fire_resistance"))
		if stats.get_stat("ice_resistance") > 0:
			_add_stat_simple("Ice Resistance", "%.1f%%" % stats.get_stat("ice_resistance"))
		if stats.get_stat("lightning_resistance") > 0:
			_add_stat_simple("Lightning Resistance", "%.1f%%" % stats.get_stat("lightning_resistance"))

	var has_bonus = stats.get_stat("lifesteal") > 0 or stats.get_stat("gold_find") > 0 or stats.get_stat("magic_find") > 0
	if has_bonus:
		_add_separator()
		_add_section_header("💰 BONUS STATS")
		if stats.get_stat("lifesteal") > 0:
			_add_stat_simple("Lifesteal", "%.1f%%" % stats.get_stat("lifesteal"))
		if stats.get_stat("gold_find") > 0:
			_add_stat_simple("Gold Find", "%.1f%%" % stats.get_stat("gold_find"))
		if stats.get_stat("magic_find") > 0:
			_add_stat_simple("Magic Find", "%.1f%%" % stats.get_stat("magic_find"))

# ==================== UI HELPERS ====================

func _add_title(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	stats_container.add_child(label)

func _add_section_header(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)
	stats_container.add_child(label)

func _add_separator() -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	stats_container.add_child(sep)

func _add_label(text: String, color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	stats_container.add_child(label)

func _add_stat_row(stat_name: String, value: String, color: Color = Color.WHITE) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(name_label)

	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", color)
	hbox.add_child(value_label)

	stats_container.add_child(hbox)

func _add_stat_simple(stat_name: String, value: String) -> void:
	_add_stat_row(stat_name, value, Color.WHITE)

func _add_stat_breakdown(stat_name: String, total: float, base: float, bonus: float) -> void:
	var color = Color.WHITE if bonus == 0 else Color(0.3, 1.0, 0.3)

	if bonus != 0:
		_add_stat_row(stat_name, "%.0f (%.0f + %.0f)" % [total, base, bonus], color)
	else:
		_add_stat_row(stat_name, "%.0f" % total, color)

func _get_hp_color(current: float, maximum: float) -> Color:
	var percent = current / maximum if maximum > 0 else 0
	if percent > 0.6:
		return Color(0.3, 1.0, 0.3)  # Green
	elif percent > 0.3:
		return Color(1.0, 0.8, 0.0)  # Yellow
	else:
		return Color(1.0, 0.3, 0.3)  # Red
