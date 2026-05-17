# File: res://scenes/MainMenu.gd
# Main menu con selezione di 4 slot di salvataggio

extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const SLOT_COUNT := 4

@onready var new_game_btn    := $CenterContainer/MenuPanel/VBox/ButtonsContainer/NewGameButton
@onready var load_game_btn   := $CenterContainer/MenuPanel/VBox/ButtonsContainer/LoadGameButton
@onready var settings_btn    := $CenterContainer/MenuPanel/VBox/ButtonsContainer/SettingsButton
@onready var quit_btn        := $CenterContainer/MenuPanel/VBox/ButtonsContainer/QuitButton
@onready var confirm_dialog  := $ConfirmDialog

# Slot overlay
var _slot_overlay:   Control = null
var _overlay_title:  Label   = null
var _slot_buttons:   Array   = []

var _mode:           String  = ""   # "new_game" | "load_game"
var _selected_slot:  int     = -1

# ============================================================
func _ready() -> void:
	print("[MainMenu] Initializing main menu")
	_build_slot_overlay()
	_update_buttons_state()

func _update_buttons_state() -> void:
	var any_save := false
	for i in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(GameState.get_save_path(i)):
			any_save = true
			break
	load_game_btn.disabled = not any_save
	load_game_btn.tooltip_text = "Continua la tua avventura" if any_save else "Nessun salvataggio trovato"

# ============================================================
# BUILD SLOT OVERLAY (fatto interamente via codice)
# ============================================================

func _build_slot_overlay() -> void:
	# Contenitore schermo intero (nascosto di default)
	_slot_overlay = Control.new()
	_slot_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_overlay.visible = false
	add_child(_slot_overlay)

	# Sfondo semitrasparente
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	_slot_overlay.add_child(bg)

	# Centro
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_overlay.add_child(center)

	# Pannello principale
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(740, 540)
	center.add_child(panel)

	# Margini interni
	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Titolo
	_overlay_title = Label.new()
	_overlay_title.text = "Seleziona Slot"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_overlay_title)

	vbox.add_child(HSeparator.new())

	# Grid 2x2 per i 4 slot
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	_slot_buttons.clear()
	for i in range(SLOT_COUNT):
		var btn := _create_slot_button(i + 1)
		grid.add_child(btn)
		_slot_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# Pulsante Annulla
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Annulla"
	cancel_btn.custom_minimum_size = Vector2(180, 40)
	cancel_btn.pressed.connect(_on_slot_cancel)
	hbox.add_child(cancel_btn)


func _create_slot_button(slot: int) -> Button:
	var btn := Button.new()
	btn.name = "Slot%d" % slot
	btn.custom_minimum_size = Vector2(330, 160)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	btn.clip_text = false
	btn.pressed.connect(func(): _on_slot_selected(slot))
	return btn


func _refresh_slot_buttons() -> void:
	for i in range(SLOT_COUNT):
		var slot  := i + 1
		var btn: Button = _slot_buttons[i]
		var info: Dictionary = GameState.read_slot_info(slot)

		if info.is_empty():
			btn.text     = "[ Slot %d ]\n\n    — Vuoto —\n    Clicca per iniziare qui" % slot
			btn.disabled = (_mode == "load_game")
		else:
			btn.text     = _format_slot_text(slot, info)
			btn.disabled = false


func _format_slot_text(slot: int, info: Dictionary) -> String:
	var level:     int   = info.get("level", 1)
	var gold:      int   = info.get("gold", 0)
	var kills:     int   = info.get("kills", 0)
	var play_secs: int   = int(info.get("play_time", 0.0))
	var save_time: int   = info.get("save_time", 0)
	var inv_count: int   = info.get("inventory_count", 0)

	var hours:    int    = play_secs / 3600
	var minutes:  int    = (play_secs % 3600) / 60
	var time_str: String = "%dh %02dm" % [hours, minutes]

	var date_str: String = "—"
	if save_time > 0:
		var dt := Time.get_datetime_dict_from_unix_time(save_time)
		date_str = "%02d/%02d/%d  %02d:%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute]

	var lines: Array = []
	lines.append("[ Slot %d ]  —  Lv. %d" % [slot, level])
	lines.append("  Oro: %d        Kills: %d" % [gold, kills])
	lines.append("  Oggetti: %d    Tempo: %s" % [inv_count, time_str])
	lines.append("  Salvato: %s" % date_str)
	return "\n".join(lines)

# ============================================================
# CALLBACKS PULSANTI MENU PRINCIPALE
# ============================================================

func _on_new_game_pressed() -> void:
	_mode = "new_game"
	_overlay_title.text = "Nuova Partita — Scegli Slot"
	_refresh_slot_buttons()
	_slot_overlay.visible = true


func _on_load_game_pressed() -> void:
	_mode = "load_game"
	_overlay_title.text = "Carica Partita — Scegli Slot"
	_refresh_slot_buttons()
	_slot_overlay.visible = true


func _on_settings_pressed() -> void:
	push_warning("[MainMenu] Settings non ancora implementato")


func _on_quit_pressed() -> void:
	get_tree().quit()

# ============================================================
# CALLBACKS OVERLAY SLOT
# ============================================================

func _on_slot_selected(slot: int) -> void:
	_selected_slot = slot
	var info: Dictionary = GameState.read_slot_info(slot)

	if _mode == "new_game":
		if not info.is_empty():
			# Slot occupato: chiede conferma prima di sovrascrivere
			confirm_dialog.dialog_text = "Il Slot %d contiene già un salvataggio.\nVuoi sovrascriverlo con una nuova partita?" % slot
			confirm_dialog.popup_centered()
		else:
			_start_new_game_in_slot(slot)
	elif _mode == "load_game":
		_load_game_from_slot(slot)


func _on_confirm_new_game() -> void:
	if _selected_slot >= 1:
		_start_new_game_in_slot(_selected_slot)


func _on_slot_cancel() -> void:
	_slot_overlay.visible = false
	_selected_slot = -1
	_mode = ""


func _start_new_game_in_slot(slot: int) -> void:
	print("[MainMenu] Starting new game in slot %d" % slot)
	_slot_overlay.visible = false
	GameState.start_new_game_slot(slot)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _load_game_from_slot(slot: int) -> void:
	print("[MainMenu] Loading game from slot %d" % slot)
	_slot_overlay.visible = false
	GameState.load_game_slot(slot)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
