class_name CameraRig3D
extends Node3D
## Camera fissa dall'alto a 3/4, stessi comandi del combat 2D:
## segue il bersaglio, tasto destro trascina (pan), rotella zoom. Nessuna rotazione.

@export var target: Node3D
@export var pitch_deg: float = 52.0
@export var distance: float = 11.0
@export var min_distance: float = 5.0
@export var max_distance: float = 32.0
@export var follow_speed: float = 6.0
@export var zoom_step: float = 1.12
@export var fov: float = 35.0

var follow: bool = true
var camera: Camera3D

var _pan: Vector3 = Vector3.ZERO
var _dragging: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.far = 300.0
	add_child(camera)
	camera.current = true
	if target:
		global_position = target.global_position
	_update_camera()


func _process(delta: float) -> void:
	if target and follow:
		var goal := target.global_position + _pan
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
	_update_camera()


func _update_camera() -> void:
	var p := deg_to_rad(pitch_deg)
	camera.position = Vector3(0.0, sin(p), cos(p)) * distance
	camera.rotation = Vector3(-p, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance / zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * zoom_step)
	elif event is InputEventMouseMotion and _dragging:
		var rel := (event as InputEventMouseMotion).relative
		var step := Vector3(-rel.x, 0.0, -rel.y) * distance * 0.0016
		_pan += step
		if not follow:
			global_position += step


func reset_pan() -> void:
	_pan = Vector3.ZERO
