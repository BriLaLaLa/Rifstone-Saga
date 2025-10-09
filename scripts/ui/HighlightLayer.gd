extends Control
class_name HighlightLayer

const LOG := true

var _rects: Array[Rect2] = []
var _valid: bool = false
var _has_preview: bool = false

const COL_VALID_FILL := Color(0.15, 1.0, 0.15, 0.28)
const COL_INVALID_FILL := Color(1.0, 0.2, 0.2, 0.28)
const COL_VALID_LINE := Color(0.15, 1.0, 0.15, 0.85)
const COL_INVALID_LINE := Color(1.0, 0.2, 0.2, 0.85)
const OUTLINE_W := 2.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	clip_contents = false

func clear_preview() -> void:
	if _has_preview:
		_rects.clear()
		_has_preview = false
		queue_redraw()
		if LOG:
			print("[HighlightLayer] clear_preview")

func show_preview_rects(rects: Array[Rect2], is_valid: bool) -> void:
	_rects = []
	for r in rects:
		if r is Rect2:
			_rects.append(r)
	_valid = is_valid
	_has_preview = _rects.size() > 0
	queue_redraw()
	if LOG:
		print("[HighlightLayer] show_preview_rects count=", _rects.size(), " valid=", is_valid)

func _draw() -> void:
	if not _has_preview:
		return
	var fill_col: Color = (COL_VALID_FILL if _valid else COL_INVALID_FILL)
	var line_col: Color = (COL_VALID_LINE if _valid else COL_INVALID_LINE)
	for r in _rects:
		draw_rect(r, fill_col, true)
		draw_rect(r.grow(-1), line_col, false, OUTLINE_W)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_preview()
