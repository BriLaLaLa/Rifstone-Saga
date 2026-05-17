extends Control
class_name MapClickableArea

signal clicked()

@export var kingdom_id: String = ""
@export var zone_id: String = ""
@export var is_unlocked: bool = true
@export var unlock_requirement: int = 1
@export var zone_name: String = ""
@export var polygon_points: PackedVector2Array = PackedVector2Array()

var _lock_icon: Label = null
var _name_label: Label = null
var _is_hovered: bool = false
var _flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	tooltip_text = zone_name if is_unlocked else "🔒 Locked - Level %d Required" % unlock_requirement

	_build_labels()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition_labels()
		queue_redraw()

# ── Labels ────────────────────────────────────────────────────────────────────

func _build_labels() -> void:
	if not zone_name.is_empty():
		_name_label = Label.new()
		_name_label.name = "ZoneNameLabel"
		_name_label.text = zone_name
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_label.layout_mode = 0
		_name_label.add_theme_font_size_override("font_size", 11)
		_name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		_name_label.add_theme_constant_override("shadow_outline_size", 2)
		add_child(_name_label)

	if not is_unlocked:
		_build_lock_icon()

	_reposition_labels()

func _build_lock_icon() -> void:
	_lock_icon = Label.new()
	_lock_icon.name = "LockIcon"
	_lock_icon.text = "🔒"
	_lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_icon.layout_mode = 0
	_lock_icon.add_theme_font_size_override("font_size", 26)
	_lock_icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_child(_lock_icon)

func _reposition_labels() -> void:
	var sz = get_size()
	var c = _centroid()
	var px = Vector2(c.x * sz.x, c.y * sz.y)

	if _name_label:
		_name_label.position = px + Vector2(-60, 8)
		_name_label.size = Vector2(120, 20)

	if _lock_icon:
		_lock_icon.position = px + Vector2(-15, -22)
		_lock_icon.size = Vector2(32, 38)

func _centroid() -> Vector2:
	if polygon_points.size() == 0:
		return Vector2(0.5, 0.5)
	var s := Vector2.ZERO
	for p in polygon_points:
		s += p
	return s / float(polygon_points.size())

# ── Rendering ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	if polygon_points.size() < 3:
		return
	var sz = get_size()
	var pts := PackedVector2Array()
	for p in polygon_points:
		pts.append(Vector2(p.x * sz.x, p.y * sz.y))

	if not is_unlocked:
		draw_colored_polygon(pts, Color(0, 0, 0, 0.30))

	if _is_hovered:
		var col := Color(1.0, 0.85, 0.3, 0.22) if is_unlocked else Color(0.8, 0.1, 0.0, 0.18)
		draw_colored_polygon(pts, col)

	if _flash > 0.0:
		draw_colored_polygon(pts, Color(1, 1, 1, 0.4 * _flash))

# ── Hit testing ───────────────────────────────────────────────────────────────

func _has_point(point: Vector2) -> bool:
	if polygon_points.size() < 3:
		return super._has_point(point)
	var sz = get_size()
	if sz.x == 0 or sz.y == 0:
		return false
	return Geometry2D.is_point_in_polygon(
		Vector2(point.x / sz.x, point.y / sz.y),
		polygon_points
	)

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if is_unlocked else CURSOR_FORBIDDEN

func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()
	mouse_default_cursor_shape = CURSOR_ARROW

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_unlocked:
			_do_click()
		else:
			_do_locked()

func _do_click() -> void:
	_flash = 1.0
	var tw = create_tween()
	tw.tween_method(func(v: float) -> void: _flash = v; queue_redraw(), 1.0, 0.0, 0.25)
	clicked.emit()
	if GameLogger.ENABLED:
		print("[MapClickableArea] Clicked: %s" % zone_name)

func _do_locked() -> void:
	var orig := position
	var tw = create_tween()
	tw.tween_property(self, "position", orig + Vector2(5, 0), 0.05)
	tw.tween_property(self, "position", orig + Vector2(-5, 0), 0.05)
	tw.tween_property(self, "position", orig, 0.05)

# ── State management ──────────────────────────────────────────────────────────

func unlock() -> void:
	is_unlocked = true
	if _lock_icon:
		_lock_icon.queue_free()
		_lock_icon = null
	tooltip_text = zone_name
	queue_redraw()
	if GameLogger.ENABLED:
		print("[MapClickableArea] Unlocked: %s" % zone_name)

func lock() -> void:
	is_unlocked = false
	if _lock_icon == null:
		_build_lock_icon()
		_reposition_labels()
	tooltip_text = "🔒 Locked - Level %d Required" % unlock_requirement
	queue_redraw()
	if GameLogger.ENABLED:
		print("[MapClickableArea] Locked: %s" % zone_name)

func setup(data: Dictionary) -> void:
	if data.has("id"):
		if data.has("zones"):
			kingdom_id = data["id"]
			zone_name = data.get("name", kingdom_id)
		else:
			zone_id = data["id"]
			zone_name = data.get("name", zone_id)
	is_unlocked = data.get("unlocked", true)
	unlock_requirement = data.get("unlock_requirement", 1)
	tooltip_text = zone_name if is_unlocked else "🔒 Locked - Level %d Required" % unlock_requirement

func get_kingdom_id() -> String:
	return kingdom_id

func get_zone_id() -> String:
	return zone_id

func check_unlock_status(player_level: int) -> void:
	if not is_unlocked and player_level >= unlock_requirement:
		unlock()
	elif is_unlocked and player_level < unlock_requirement:
		lock()
