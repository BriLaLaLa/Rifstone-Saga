extends Control

@export var cell_size: int = 64
@export var cols: int = 8
@export var rows: int = 8

func _pos_to_cell(p: Vector2) -> Vector2i:
	var c: Vector2i = Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))
	return Vector2i(clampi(c.x, 0, cols - 1), clampi(c.y, 0, rows - 1))

func _can_place(cell: Vector2i, w: int, h: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x + w <= cols and cell.y + h <= rows

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var hotspot: Vector2 = data.get("hotspot", Vector2.ZERO)
	var w: int = int(data.get("w", 1))
	var h: int = int(data.get("h", 1))
	var cell: Vector2i = _pos_to_cell(at_position - hotspot)
	var ok: bool = _can_place(cell, w, h)
	print("[GridDrop] can_drop? pos=%s data=%s -> %s" %
		[at_position, data.get("id", "?"), ok])
	return ok

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var hotspot: Vector2 = data.get("hotspot", Vector2.ZERO)
	var w: int = int(data.get("w", 1))
	var h: int = int(data.get("h", 1))

	var cell: Vector2i = _pos_to_cell(at_position - hotspot)
	cell.x = clampi(cell.x, 0, cols - w)
	cell.y = clampi(cell.y, 0, rows - h)

	var snap_pos: Vector2 = Vector2(cell.x * cell_size, cell.y * cell_size)

	var item: Variant = data.get("node")
	if item and item is Control:
		var ctrl: Control = item as Control
		if ctrl.get_parent():
			ctrl.get_parent().remove_child(ctrl)
		add_child(ctrl)
		ctrl.position = snap_pos

	print("[GridDrop] DROPPED id=%s cell=(%d,%d) pos=%s" %
		[data.get("id","?"), cell.x, cell.y, snap_pos])

func _draw() -> void:
	for r in range(rows):
		for c in range(cols):
			var rect: Rect2 = Rect2(c * cell_size, r * cell_size, cell_size, cell_size)
			var is_dark: bool = ((r + c) % 2) == 0
			var col: Color = Color(0.10, 0.18, 0.25, 0.95) if is_dark \
				else Color(0.12, 0.22, 0.30, 0.95)
			draw_rect(rect, col, true)
