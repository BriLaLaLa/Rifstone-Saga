extends Control
## Contenitore delle scene 3D di prova (prototipo, zone): barra HUD in alto (come ZoneCombatScene) + SubViewport con il mondo 3D.
## Argomenti da riga di comando dopo "--" (per screenshot e misure automatiche):
##   --shots=<cartella> --at=2,5,8   salva screenshot ai secondi indicati, poi esce
##   --stress=50 --weapon=9 --armor=7 --focus=showcase|warrior_close --cam=8 --pose=death
##   --fps                            vsync spento e media FPS stampata all'uscita

@onready var _world = $SubViewportContainer/SubViewport/World

var _status: Label
var _opts: Dictionary = {}
var _shot_dir: String = ""
var _shot_times: Array[float] = []
var _elapsed: float = 0.0
var _capturing: bool = false
var _frame_times: Array[float] = []


func _ready() -> void:
	_build_hud()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _world.has_method("configure"):
		_world.configure(_opts)
	if _opts.has("shots"):
		_shot_dir = _opts["shots"]
		for t in String(_opts.get("at", "3")).split(","):
			_shot_times.append(float(t))
	if _opts.has("fps"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _build_hud() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46.0
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	bar.add_child(row)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	var help := Label.new()
	help.text = _world.help_text() if _world.has_method("help_text") else ""
	help.modulate = Color(1, 1, 1, 0.7)
	row.add_child(help)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 2.0:
		_frame_times.append(delta)
	_status.text = "%s  |  FPS %d" % [_world.hud_text(), Engine.get_frames_per_second()]
	if not _capturing and not _shot_times.is_empty() and _elapsed >= _shot_times[0]:
		_capture(_shot_times.pop_front())


func _capture(t: float) -> void:
	_capturing = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("shot_%05.1fs.png" % t)
	img.save_png(path)
	print("SHOT ", path)
	_capturing = false
	if _shot_times.is_empty():
		_report_and_quit()


func _report_and_quit() -> void:
	if _world.has_method("report"):
		_world.report()
	if not _frame_times.is_empty():
		var total := 0.0
		var worst := 0.0
		for f in _frame_times:
			total += f
			worst = maxf(worst, f)
		var avg := total / _frame_times.size()
		print("FPS_AVG %.1f  FRAME_MS_AVG %.2f  FRAME_MS_WORST %.2f  FRAMES %d" % [1.0 / avg, avg * 1000.0, worst * 1000.0, _frame_times.size()])
	var vp := ($SubViewportContainer/SubViewport as SubViewport).get_viewport_rid()
	print("DRAW_CALLS ", RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"  OBJECTS ", RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"  PRIMITIVES ", RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	get_tree().quit()
