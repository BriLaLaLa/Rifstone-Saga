extends Control
class_name ItemTooltip

const LOG := true

@onready var background: NinePatchRect = $Background
@onready var content_container: VBoxContainer = $Background/Margin/Content
@onready var item_name_label: RichTextLabel = $Background/Margin/Content/ItemName
@onready var level_label: Label = $Background/Margin/Content/LevelReq
@onready var stats_container: VBoxContainer = $Background/Margin/Content/Stats
@onready var description_label: RichTextLabel = $Background/Margin/Content/Description

# Colori per rarità
const RARITY_COLORS = {
	"common": Color.WHITE,
	"uncommon": Color.GREEN,
	"rare": Color.BLUE,
	"epic": Color.PURPLE,
	"legendary": Color.ORANGE,
	"artifact": Color.RED
}

var current_item_data: Dictionary = {}
var is_visible: bool = false

func _ready() -> void:
	# Inizialmente nascosto
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 9999  # Sopra tutto
	
	# Stile del background
	if background:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.4, 0.4, 0.5, 1.0)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		background.add_theme_stylebox_override("panel", style)

func show_tooltip(item_data: Dictionary, mouse_position: Vector2) -> void:
	if item_data.is_empty():
		hide_tooltip()
		return
	
	current_item_data = item_data
	_populate_tooltip()
	_position_tooltip(mouse_position)
	
	visible = true
	is_visible = true
	
	if LOG:
		print("[ItemTooltip] Showing tooltip for: %s" % item_data.get("name", "Unknown"))

func hide_tooltip() -> void:
	visible = false
	is_visible = false
	current_item_data.clear()
	
	if LOG:
		print("[ItemTooltip] Hiding tooltip")

func _populate_tooltip() -> void:
	if not current_item_data.has("name"):
		return
	
	# Nome dell'item con colore basato sulla rarità
	var item_name = str(current_item_data.get("name", "Unknown Item"))
	var rarity = str(current_item_data.get("rarity", "common")).to_lower()
	var name_color = RARITY_COLORS.get(rarity, Color.WHITE)
	
	if item_name_label:
		var name_text = "[color=#%s][b]%s[/b][/color]" % [name_color.to_html(), item_name]
		item_name_label.text = name_text
	
	# Livello richiesto
	if level_label:
		var required_level = int(current_item_data.get("required_level", 1))
		level_label.text = "Requires Level %d" % required_level
		
		# Colore rosso se il giocatore non ha il livello
		var player_level = _get_player_level()
		if player_level < required_level:
			level_label.modulate = Color.RED
		else:
			level_label.modulate = Color.WHITE
	
	# Statistiche
	_populate_stats()
	
	# Descrizione
	if description_label:
		var description = str(current_item_data.get("description", ""))
		if description != "":
			description_label.text = "[color=#CCCCCC][i]%s[/i][/color]" % description
			description_label.visible = true
		else:
			description_label.visible = false
	
	# Ridimensiona il tooltip
	await get_tree().process_frame
	_resize_tooltip()

func _populate_stats() -> void:
	if not stats_container:
		return
	
	# Pulisci le statistiche precedenti
	for child in stats_container.get_children():
		child.queue_free()
	
	# Statistiche da mostrare
	var stats_to_show = [
		{"key": "attack", "name": "Attack", "color": Color.RED},
		{"key": "defense", "name": "Defense", "color": Color.BLUE},
		{"key": "heal", "name": "Healing", "color": Color.GREEN},
		{"key": "magic_power", "name": "Magic Power", "color": Color.PURPLE},
		{"key": "critical_chance", "name": "Critical Chance", "color": Color.YELLOW, "suffix": "%"},
		{"key": "durability", "name": "Durability", "color": Color.GRAY}
	]
	
	for stat_info in stats_to_show:
		var key = stat_info.key
		if current_item_data.has(key):
			var value = current_item_data[key]
			if value is int and value > 0:
				_add_stat_line(stat_info.name, value, stat_info.color, stat_info.get("suffix", ""))
			elif value is float and value > 0.0:
				_add_stat_line(stat_info.name, value, stat_info.color, stat_info.get("suffix", ""))

func _add_stat_line(stat_name: String, value, color: Color, suffix: String = "") -> void:
	var stat_label = RichTextLabel.new()
	stat_label.fit_content = true
	stat_label.scroll_active = false
	stat_label.custom_minimum_size.y = 20
	
	var value_str = str(value) + suffix
	var stat_text = "[color=#FFFFFF]%s: [/color][color=#%s]+%s[/color]" % [stat_name, color.to_html(), value_str]
	stat_label.text = stat_text
	
	stats_container.add_child(stat_label)

func _get_player_level() -> int:
	# Ottieni il livello del giocatore dal GameState
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs and gs.has("player_level"):
			return int(gs.get("player_level"))
	return 1  # Default level

func _position_tooltip(mouse_pos: Vector2) -> void:
	# Posiziona il tooltip vicino al mouse ma dentro lo schermo
	var screen_size = get_viewport().get_visible_rect().size
	var tooltip_size = size
	
	var x = mouse_pos.x + 15  # Offset dal mouse
	var y = mouse_pos.y - 10
	
	# Assicurati che non esca dallo schermo
	if x + tooltip_size.x > screen_size.x:
		x = mouse_pos.x - tooltip_size.x - 15
	
	if y + tooltip_size.y > screen_size.y:
		y = screen_size.y - tooltip_size.y - 10
	
	if x < 0:
		x = 10
	if y < 0:
		y = 10
	
	global_position = Vector2(x, y)

func _resize_tooltip() -> void:
	# Ridimensiona automaticamente il tooltip in base al contenuto
	if content_container:
		var content_size = Vector2.ZERO
		
		# Calcola l'altezza totale necessaria
		for child in content_container.get_children():
			if child.visible:
				content_size.y += child.size.y
		
		# Larghezza minima
		content_size.x = max(250, content_size.x)
		content_size.y = max(100, content_size.y)
		
		# Aggiungi padding
		content_size.x += 20
		content_size.y += 20
		
		custom_minimum_size = content_size
		size = content_size

func update_position(mouse_pos: Vector2) -> void:
	if is_visible:
		_position_tooltip(mouse_pos)
