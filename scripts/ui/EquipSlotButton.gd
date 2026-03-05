# File: res://scripts/ui/EquipSlotButton.gd
# Reusable equip slot button for warrior skills
# Replaces Button.new() manual creation

extends Button
class_name EquipSlotButton

var slot_index: int = 0

signal slot_pressed(slot_index: int)

func setup(index: int) -> void:
	"""Setup button for specific slot"""
	slot_index = index
	text = "Slot %d" % (index + 1)

	if GameLogger.ENABLED:
		print("[EquipSlotButton] Setup for slot %d" % index)

func _ready() -> void:
	# Connect button press
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	"""Emit signal when pressed"""
	slot_pressed.emit(slot_index)
