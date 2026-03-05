# File: res://scenes/MainMenu.gd
# Main menu scene with New Game, Load Game, Settings buttons

extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const SAVE_PATH := "user://save.dat"

@onready var new_game_btn := $CenterContainer/MenuPanel/VBox/ButtonsContainer/NewGameButton
@onready var load_game_btn := $CenterContainer/MenuPanel/VBox/ButtonsContainer/LoadGameButton
@onready var settings_btn := $CenterContainer/MenuPanel/VBox/ButtonsContainer/SettingsButton
@onready var quit_btn := $CenterContainer/MenuPanel/VBox/ButtonsContainer/QuitButton
@onready var confirm_dialog := $ConfirmDialog

func _ready() -> void:
	print("[MainMenu] Initializing main menu")
	_update_buttons_state()

func _update_buttons_state() -> void:
	# Check if save file exists
	var save_exists := FileAccess.file_exists(SAVE_PATH)

	if save_exists:
		load_game_btn.disabled = false
		load_game_btn.tooltip_text = "Continue your adventure"
		print("[MainMenu] Save file found - Load Game enabled")
	else:
		load_game_btn.disabled = true
		load_game_btn.tooltip_text = "No save file found"
		print("[MainMenu] No save file - Load Game disabled")

func _on_new_game_pressed() -> void:
	print("[MainMenu] New Game button pressed")

	# If save exists, show confirmation dialog
	if FileAccess.file_exists(SAVE_PATH):
		confirm_dialog.popup_centered()
	else:
		_start_new_game()

func _on_confirm_new_game() -> void:
	print("[MainMenu] New game confirmed - deleting old save")
	_start_new_game()

func _start_new_game() -> void:
	# Delete existing save file
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[MainMenu] ✅ Old save deleted")

	# Load main game scene
	print("[MainMenu] Loading game scene...")
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _on_load_game_pressed() -> void:
	print("[MainMenu] Load Game button pressed")

	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("[MainMenu] Save file not found!")
		return

	# Load main game scene (it will auto-load the save in GameState._ready)
	print("[MainMenu] Loading game with existing save...")
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _on_settings_pressed() -> void:
	print("[MainMenu] Settings button pressed")
	# TODO: Implement settings screen
	# For now, just show a placeholder
	push_warning("[MainMenu] Settings not implemented yet")

func _on_quit_pressed() -> void:
	print("[MainMenu] Quit button pressed")
	get_tree().quit()
