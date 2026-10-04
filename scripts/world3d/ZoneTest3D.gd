extends Node3D
## Test Fase 3: zona 3D convertita dal 2D, il warrior gira da solo sull'isola con la navigazione 3D
## (deve aggirare acqua, alberi, rocce e ceppi). Conta i frame passati fuori dall'erba.

const ZONE_SCENE := preload("res://scenes/world3d/zones/red_plains_3d.tscn")
const RUN_SPEED := 150.0 / 64.0  # stessa velocità del player 2D (150 px/s)

var zone: Zone3D
var warrior: WarriorVisual
var player: Node3D
var agent: NavigationAgent3D
var camera_rig: CameraRig3D

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.6
var _trips: int = 0
var _frames: int = 0
var _off_land: int = 0
var _in_obstacle: int = 0
var _started: bool = false
var _obstacles: Array = []  # [posizione, raggio] dei props solidi


func _ready() -> void:
	_rng.seed = 11
	zone = ZONE_SCENE.instantiate()
	add_child(zone)
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	warrior = WarriorVisual.new()
	player.add_child(warrior)
	agent = NavigationAgent3D.new()
	agent.radius = zone.agent_radius
	agent.path_desired_distance = 0.3
	agent.target_desired_distance = 0.3
	player.add_child(agent)
	var spawns := zone.spawn_points()
	player.position = spawns[spawns.size() - 1].position if not spawns.is_empty() else Vector3.ZERO
	camera_rig = CameraRig3D.new()
	camera_rig.target = player
	camera_rig.bounds = zone.land_rect()
	add_child(camera_rig)
	for p in zone.get_node("Props").get_children():
		if p is Prop3D and (p as Prop3D).is_solid():
			_obstacles.append([p.position, (p as Prop3D).footprint_radius()])


func configure(opts: Dictionary) -> void:
	if opts.has("cam"):
		camera_rig.distance = float(opts["cam"])
	if opts.get("focus", "") == "overview":
		var r := zone.land_rect()
		camera_rig.follow = false
		camera_rig.bounds = Rect2()
		camera_rig.global_position = Vector3(r.get_center().x, 0.0, r.get_center().y)
		camera_rig.distance = float(opts.get("cam", "34"))


func _process(delta: float) -> void:
	_frames += 1
	if not zone.terrain().is_land(Vector2i(floori(player.position.x), floori(player.position.z))):
		_off_land += 1
	for o in _obstacles if _started else []:
		if Vector2(player.position.x - o[0].x, player.position.z - o[0].z).length() < o[1]:
			_in_obstacle += 1
			break
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			if _trips == 0:
				# lo spawn 2D di partenza è sotto un albero: aggancio il player al punto camminabile più vicino
				var p := NavigationServer3D.map_get_closest_point(zone.get_world_3d().navigation_map, player.position)
				player.position = Vector3(p.x, 0.0, p.z)
				_started = true
			agent.target_position = zone.random_land_point(_rng)
		return
	if agent.is_navigation_finished():
		_trips += 1
		warrior.play("idle")
		_wait = 0.5
		return
	var to := agent.get_next_path_position() - player.position
	to.y = 0.0
	if to.length() > 0.001:
		player.position += to.normalized() * minf(RUN_SPEED * delta, to.length())
		warrior.face_direction(to)
		warrior.play("run")


func hud_text() -> String:
	var tiles := "segnaposto" if TerrainTiles.uses_placeholders() else "Blender"
	return "ZONA 3D Red Plains  |  tessere: %s  |  viaggi %d  |  frame fuori dall'erba %d  |  dentro ostacoli %d" % [tiles, _trips, _off_land, _in_obstacle]


func help_text() -> String:
	return "il warrior gira da solo con la navigazione · tasto destro pan · rotella zoom"


func report() -> void:
	print("NAV_TRIPS %d  OFF_LAND_FRAMES %d  IN_OBSTACLE_FRAMES %d  / %d" % [_trips, _off_land, _in_obstacle, _frames])
