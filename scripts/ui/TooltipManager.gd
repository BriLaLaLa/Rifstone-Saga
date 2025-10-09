extends Node

# TooltipManager completo per il sistema inventario
# Salva questo file come res://scripts/ui/TooltipManager.gd

func show_item_tooltip(item_data: Dictionary, mouse_pos: Vector2) -> void:
	print("[tooltipManager] Would show tooltip for: %s at pos %s" % [item_data.get("name", "Unknown"), mouse_pos])

func hide_item_tooltip() -> void:
	print("[tooltipManager] Would hide tooltip")

func update_mouse_position(mouse_pos: Vector2) -> void:
	# Stub per aggiornamento posizione mouse
	pass

func get_extended_item_data(item_id: String, base_data: Dictionary) -> Dictionary:
	# Ritorna i dati base con alcune aggiunte semplici
	var extended = base_data.duplicate()
	extended.merge({
		"rarity": "common",
		"required_level": 1,
		"description": "A basic item for your adventure."
	})
	return extended
