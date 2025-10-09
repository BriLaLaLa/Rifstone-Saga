extends TextureRect
class_name ItemDraggable

@export var item_id: String = "unknown"
@export var item_texture: Texture2D = preload("res://icon.svg")

var last_valid_parent: Node = null
var last_valid_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# TextureRect usa 'texture', non 'icon'
	texture = item_texture
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_PASS
	print("[ItemDraggable] ready id=%s node=%s size=%s" % [item_id, name, size])

# --- DRAG HANDLING ---

func _get_drag_data(at_position: Vector2) -> Variant:
	print("[ItemDraggable] START DRAG id=%s at %s" % [item_id, at_position])
	
	var drag_preview := TextureRect.new()
	drag_preview.texture = texture
	drag_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_preview.custom_minimum_size = Vector2(64, 64)
	set_drag_preview(drag_preview)

	# salva ultima posizione valida
	last_valid_parent = get_parent()
	last_valid_position = position

	return {"id": item_id, "node": self}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# un item non accetta drop sopra di sé
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# non usato sugli item
	pass

# --- FALLBACK ---

func return_to_last_valid() -> void:
	if last_valid_parent:
		if get_parent() != last_valid_parent:
			if get_parent():
				get_parent().remove_child(self)
			last_valid_parent.add_child(self)
		position = last_valid_position
		print("[ItemDraggable] RETURN fallback id=%s -> pos=%s" % [item_id, position])
