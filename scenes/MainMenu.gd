# File: res://scenes/MainMenu.gd
# Main menu con selezione di 4 slot di salvataggio

extends Control

const MAIN_SCENE_PATH         := "res://scenes/Main.tscn"
const SLOT_OVERLAY_SCENE_PATH := "res://scenes/ui/SlotSelectOverlay.tscn"
const SLOT_COUNT              := 4

@onready var new_game_btn   := $CenterContainer/MenuPanel/VBox/ButtonsContainer/NewGameButton
@onready var load_game_btn  := $CenterContainer/MenuPanel/VBox/ButtonsContainer/LoadGameButton
@onready var settings_btn   := $CenterContainer/MenuPanel/VBox/ButtonsContainer/SettingsButton
@onready var quit_btn       := $CenterContainer/MenuPanel/VBox/ButtonsContainer/QuitButton
@onready var confirm_dialog := $ConfirmDialog

var _slot_overlay:  Control = null
var _overlay_title: Label   = null
var _slot_buttons:  Array   = []
var _mode:          String  = ""
var _selected_slot: int     = -1

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
	load_game_btn.disabled     = not any_save
	load_game_btn.tooltip_text = "Continua la tua avventura" if any_save else "Nessun salvataggio trovato"

# ============================================================
# BUILD SLOT OVERLAY — struttura da .tscn, dati dal codice
# ============================================================

func _build_slot_overlay() -> void:
	var packed: PackedScene = load(SLOT_OVERLAY_SCENE_PATH)
	_slot_overlay = packed.instantiate()
	add_child(_slot_overlay)

	_overlay_title = _slot_overlay.get_node("Center/Panel/Margin/VBox/Title") as Label

	var grid := _slot_overlay.get_node("Center/Panel/Margin/VBox/SlotGrid") as GridContainer

	_slot_buttons.clear()
	for i in range(SLOT_COUNT):
		var btn := grid.get_node("Slot%d" % (i + 1)) as Button
		var slot := i + 1
		btn.pressed.connect(func(): _on_slot_selected(slot))
		_slot_buttons.append(btn)

	var cancel_btn := _slot_overlay.get_node("Center/Panel/Margin/VBox/CancelRow/CancelButton") as Button
	cancel_btn.pressed.connect(_on_slot_cancel)


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
