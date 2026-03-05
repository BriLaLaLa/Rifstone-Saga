extends Control

## EnhancementTestUI - UI di test per visualizzare gli effetti di enhancement
##
## Aggiungi questo nodo alla scena Main per testare visivamente
## gli effetti +7, +8, +9 su un'arma

# Item scene da istanziare
const ITEM_SCENE = preload("res://scripts/ui/Item.tscn")

@onready var test_container = $VBoxContainer/TestContainer
@onready var level_label = $VBoxContainer/LevelLabel
@onready var increase_button = $VBoxContainer/HBoxContainer/IncreaseButton
@onready var decrease_button = $VBoxContainer/HBoxContainer/DecreaseButton
@onready var level_info = $VBoxContainer/LevelInfo

var test_item: Item = null
var current_level: int = 0

func _ready() -> void:
	# Create test item (Novice Sword)
	_create_test_item()

	# Connect buttons
	increase_button.pressed.connect(_on_increase_pressed)
	decrease_button.pressed.connect(_on_decrease_pressed)

	# Update display
	_update_display()


func _create_test_item() -> void:
	"""Create a test weapon to apply enhancements to"""
	test_item = ITEM_SCENE.instantiate()
	test_item.item_id = "novice_sword_lvl1"
	test_item.item_size = Vector2i(1, 2)

	# Load weapon texture
	var icon_path = "res://Item_Texture/Equip/Swords/Novice_Sword_LvL1.png"
	if ResourceLoader.exists(icon_path):
		test_item.texture = load(icon_path)

	# Center it in container
	test_item.position = Vector2(100, 50)

	test_container.add_child(test_item)


func _on_increase_pressed() -> void:
	"""Increase enhancement level"""
	if current_level < 9:
		current_level += 1
		test_item.set_enhancement_level(current_level)
		_update_display()


func _on_decrease_pressed() -> void:
	"""Decrease enhancement level"""
	if current_level > 0:
		current_level -= 1
		test_item.set_enhancement_level(current_level)
		_update_display()


func _update_display() -> void:
	"""Update UI labels"""
	level_label.text = "Enhancement Level: +%d" % current_level

	# Update info text
	var info_text = ""
	match current_level:
		0, 1, 2, 3, 4, 5, 6:
			info_text = "Standard weapon - no special effects"
		7:
			info_text = "[color=orange]CONTROLLED ENERGY[/color]\nL'arma pulsa con energia contenuta, come una brace viva"
		8:
			info_text = "[color=magenta]UNSTABLE ENERGY[/color]\nL'energia si muove da sola, vibra e lotta per essere contenuta"
		9:
			info_text = "[color=cyan]MANIFESTED ARTIFACT[/color]\nNon sembra più un'arma forgiata, ma manifestata. Distorce lo spazio"

	level_info.text = info_text

	# Update stat multiplier info
	var multiplier = EnhancementSystem.get_stat_multiplier(current_level)
	var stats_text = "Stats Multiplier: %.2fx" % multiplier
	$VBoxContainer/StatsInfo.text = stats_text
