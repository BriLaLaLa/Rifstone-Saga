extends Control
class_name HighlightLayer

# const LOG removed - using GameLogger

var _rects: Array[Rect2] = []
var _valid: bool = false
var _has_preview: bool = false

# Highlight colors for drag preview
const COL_VALID_FILL := Color(0.15, 1.0, 0.15, 0.3)  # Green fill with transparency
const COL_INVALID_FILL := Color(1.0, 0.2, 0.2, 0.3)  # Red fill with transparency
const COL_VALID_LINE := Color(0.15, 1.0, 0.15, 0.8)  # Bright green border
const COL_INVALID_LINE := Color(1.0, 0.2, 0.2, 0.8)  # Bright red border
const OUTLINE_W := 3.0  # Thicker border for better visibility

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	clip_contents = false

func clear_preview() -> void:
	if _has_preview:
		_rects.clear()
		_has_preview = false
		queue_redraw()
		if GameLogger.ENABLED:
			print("[HighlightLayer] clear_preview")

func show_preview_rects(rects: Array[Rect2], is_valid: bool) -> void:
	_rects = []
	for r in rects:
		if r is Rect2:
			_rects.append(r)
	_valid = is_valid
	_has_preview = _rects.size() > 0
	queue_redraw()

	# DEBUG: Always print to see if highlight is being triggered
	print("[HighlightLayer] 🟢 show_preview_rects count=%d, valid=%s" % [_rects.size(), is_valid])
	if _rects.size() > 0:
		print("  → First rect: pos=%s, size=%s" % [_rects[0].position, _rects[0].size])

func _draw() -> void:
	if not _has_preview:
		return

	print("[HighlightLayer] 🎨 _draw() called with %d rects, valid=%s" % [_rects.size(), _valid])

	var fill_col: Color = (COL_VALID_FILL if _valid else COL_INVALID_FILL)
	var line_col: Color = (COL_VALID_LINE if _valid else COL_INVALID_LINE)

	for i in range(_rects.size()):
		var r = _rects[i]
		print("  → Drawing rect %d: pos=%s, size=%s, fill=%s, line=%s" % [i, r.position, r.size, fill_col, line_col])
		draw_rect(r, fill_col, true)
		draw_rect(r.grow(-1), line_col, false, OUTLINE_W)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_preview()
