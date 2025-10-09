# Drag source per i bottoni item in inventario/equip
extends TextureButton

# Nota: questo script viene applicato via set_script() in InventoryTab._place_item()

func _ready() -> void:
	# sicurezza per il DnD
	mouse_filter = Control.MOUSE_FILTER_STOP
	# di solito li imposto già da InventoryTab, ma nel dubbio:
	ignore_texture_size = true

func _get_drag_data(at_position: Vector2) -> Variant:
	# Recupero metadati impostati da InventoryTab
	var item_id: String = String(get_meta("item_id"))
	var size_wh: Vector2i = get_meta("size_wh") as Vector2i
	var cell: Vector2i = Vector2i()
	if has_meta("cell"):
		cell = get_meta("cell") as Vector2i
	var cell_px: int = int(get_meta("cell_px"))

	# Pacchetto dati standardizzato per i drop target
	var data: Dictionary = {
		"type": "inv_item",
		"item_id": item_id,
		"size_wh": size_wh,
		"cell": str(cell),
		"node": self, # importantissimo: spostiamo il NODO originale
	}

	# Preview compatta e non invasiva
	var p := TextureRect.new()
	p.texture = texture_normal
	p.custom_minimum_size = Vector2(cell_px, cell_px)
	p.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.modulate.a = 0.9
	set_drag_preview(p)

	print("[DragSource] start item=%s size=%s cell=%s cell_px=%d" %
		[item_id, str(size_wh), str(cell), cell_px])

	return data
