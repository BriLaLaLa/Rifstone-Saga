# Drop target generico: inoltra l'esito a 2 callback configurabili
extends Control

var _can_cb: Callable
var _drop_cb: Callable

func setup(can_cb: Callable, drop_cb: Callable) -> void:
	_can_cb = can_cb
	_drop_cb = drop_cb
	mouse_filter = Control.MOUSE_FILTER_PASS

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _can_cb.is_valid():
		# tipizza: il nostro flusso usa Dictionary
		var d: Dictionary = data as Dictionary
		return bool(_can_cb.call(at_position, d))
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _drop_cb.is_valid():
		var d: Dictionary = data as Dictionary
		_drop_cb.call(at_position, d)
