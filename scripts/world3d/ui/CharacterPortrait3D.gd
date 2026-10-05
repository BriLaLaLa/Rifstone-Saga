class_name CharacterPortrait3D
extends SubViewportContainer
## Ritratto 3D del personaggio per il pannello equipaggiamento: il warrior con l'equip di GameState
## (stesse skin e bagliore +7/+8/+9 del combattimento), luci da vetrina, animazione idle.
## Si ruota trascinando col tasto sinistro. Sfondo trasparente: la cornice la disegna chi lo contiene.

const OUTLINE_SHADER := preload("res://shaders/world3d/outline_post.gdshader")
const LOOK_AT := Vector3(0.0, 0.62, 0.0)

@export var start_yaw: float = 0.35
@export var camera_distance: float = 2.9
@export var camera_height: float = 0.95

var warrior: WarriorVisual
var equipment_sync: EquipmentSync3D

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _yaw: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_yaw = start_yaw
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)

	var env := WorldLook3D.make_environment()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.fog_enabled = false
	env.ambient_light_energy = 0.42
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -28.0, 0.0)
	key.light_energy = 0.75
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	rim.light_energy = 0.3
	rim.light_color = Color(0.8, 0.9, 1.0)
	world.add_child(rim)

	# ombra morbida finta sotto i piedi
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.01
	cyl.radial_segments = 32
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(disc)

	_pivot = Node3D.new()
	world.add_child(_pivot)
	warrior = WarriorVisual.new()
	var has_game_state := get_node_or_null("/root/GameState") != null
	warrior.equip_defaults = not has_game_state
	_pivot.add_child(warrior)
	if has_game_state:
		equipment_sync = EquipmentSync3D.new(warrior)
		_viewport.add_child(equipment_sync)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	world.add_child(_camera)
	_camera.position = Vector3(0.0, camera_height, camera_distance)
	_camera.look_at(LOOK_AT)
	_camera.current = true
	_add_outline()


func _process(_delta: float) -> void:
	if _pivot:
		_pivot.rotation.y = _yaw


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw += (event as InputEventMouseMotion).relative.x * 0.012
		accept_event()


## Contorno toon come nel mondo di gioco (stesso shader a schermo intero)
func _add_outline() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	_camera.add_child(mi)
