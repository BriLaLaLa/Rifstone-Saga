# File: res://scripts/gathering/GatheringNode.gd
# Visual representation of a gathering node
# Appears during combat (small, in corner) and becomes active after victory

extends Control
class_name GatheringNode

# Node data
var node_id: String = ""
var node_name: String = ""
var node_type: String = ""  # mining, gathering, fishing
var attempts_remaining: int = 5
var attempt_duration: float = 3.0

# Visual state
var is_active: bool = false  # True when gathering can start
var is_gathering: bool = false  # True during an attempt

# Visual references
@onready var node_sprite: TextureRect = $NodeSprite
@onready var name_label: Label = $NameLabel
@onready var attempts_label: Label = $AttemptsLabel
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var background: Panel = $Background

# Gathering state
var current_attempt_time: float = 0.0
var collected_items: Array = []

# Signals
signal gathering_attempt_complete(items: Array)
signal all_attempts_complete(total_items: Array)

# ==================== INITIALIZATION ====================

func _ready() -> void:
	print("[GATHERING-NODE] 🟢 _ready() called")
	print("[GATHERING-NODE] 📍 Initial position: %s" % position)
	print("[GATHERING-NODE] 📍 Initial size: %s" % size)
	print("[GATHERING-NODE] 👁️ Initial visible: %s" % visible)

	visible = false
	is_active = false
	is_gathering = false

	# Hide progress bar initially
	if progress_bar:
		progress_bar.visible = false
		progress_bar.value = 0

	# Setup background style
	_setup_background()

	print("[GATHERING-NODE] ✅ _ready() complete - visible set to false")

	if GameLogger.ENABLED:
		print("[GatheringNode] Ready")

func _process(delta: float) -> void:
	"""Process gathering attempts"""
	if not is_active or not is_gathering:
		return

	# Update progress bar
	current_attempt_time += delta
	var progress = current_attempt_time / attempt_duration

	if progress_bar:
		progress_bar.value = progress * 100.0

	# Check if attempt complete
	if current_attempt_time >= attempt_duration:
		print("[GATHERING-NODE] Attempt timer complete! Calling _complete_attempt()")
		_complete_attempt()

# ==================== SETUP ====================

func setup_node(node_data: Dictionary) -> void:
	"""Initialize the node with data from GatheringDatabase"""
	node_id = node_data.get("id", "")
	node_name = node_data.get("name", "Unknown Node")
	node_type = node_data.get("type", "mining")
	attempts_remaining = int(node_data.get("base_attempts", 5))
	attempt_duration = float(node_data.get("attempt_duration", 3.0))

	# Setup visuals
	_setup_visuals(node_data)
	_update_attempts_label()

	if GameLogger.ENABLED:
		print("[GatheringNode] Setup %s - %d attempts" % [node_name, attempts_remaining])

func _setup_visuals(node_data: Dictionary) -> void:
	"""Setup sprite and labels"""
	# Load icon
	if node_sprite and node_data.has("icon"):
		var icon_path = node_data.get("icon")
		print("[GatheringNode] Trying to load icon: %s" % icon_path)
		print("[GatheringNode] ResourceLoader.exists: %s" % ResourceLoader.exists(icon_path))
		if ResourceLoader.exists(icon_path):
			node_sprite.texture = load(icon_path)
			print("[GatheringNode] ✅ Texture loaded successfully")
		else:
			print("[GatheringNode] ⚠️ Texture not found, creating placeholder")
			_create_placeholder_icon()
	else:
		print("[GatheringNode] ⚠️ No sprite or no icon in data")

	# Set name
	if name_label:
		name_label.text = node_name

	# Color based on type
	_setup_background()

func _create_placeholder_icon() -> void:
	"""Create placeholder colored rectangle as texture"""
	if not node_sprite:
		return

	# Create a simple colored texture
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)

	var fill_color: Color
	match node_type:
		"mining":
			fill_color = Color(0.6, 0.6, 0.7)  # Gray
		"gathering":
			fill_color = Color(0.3, 0.7, 0.3)  # Green
		"fishing":
			fill_color = Color(0.3, 0.5, 0.8)  # Blue
		_:
			fill_color = Color(0.5, 0.5, 0.5)

	img.fill(fill_color)
	node_sprite.texture = ImageTexture.create_from_image(img)
	print("[GatheringNode] ✅ Created placeholder texture with color: %s" % fill_color)

func _setup_background() -> void:
	"""Setup background panel style"""
	if not background:
		return

	var style = StyleBoxFlat.new()

	match node_type:
		"mining":
			style.bg_color = Color(0.3, 0.3, 0.35, 0.9)
			style.border_color = Color(0.6, 0.6, 0.7)
		"gathering":
			style.bg_color = Color(0.2, 0.35, 0.2, 0.9)
			style.border_color = Color(0.3, 0.7, 0.3)
		"fishing":
			style.bg_color = Color(0.2, 0.3, 0.4, 0.9)
			style.border_color = Color(0.3, 0.5, 0.8)
		_:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
			style.border_color = Color(0.5, 0.5, 0.5)

	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	background.add_theme_stylebox_override("panel", style)

# ==================== STATE MANAGEMENT ====================

func show_during_combat() -> void:
	"""Show node in small size during combat (corner position)"""
	visible = true
	is_active = false

	# Small size for combat
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.7  # Semi-transparent

	if GameLogger.ENABLED:
		print("[GatheringNode] Showing during combat (small)")

func activate_for_gathering() -> void:
	"""Activate node for gathering after combat victory"""
	print("[GATHERING-NODE] 🎯 activate_for_gathering() called")
	print("[GATHERING-NODE] 📍 Current position: %s" % position)
	print("[GATHERING-NODE] 📍 Current scale: %s" % scale)
	print("[GATHERING-NODE] 👁️ Current visible: %s" % visible)
	print("[GATHERING-NODE] 📍 Viewport size: %s" % get_viewport_rect().size)
	print("[GATHERING-NODE] 📍 Node size: %s" % size)

	is_active = true
	visible = true  # Make sure it's visible!

	# Calculate center position
	var center_pos = get_viewport_rect().size / 2 - size / 2
	print("[GATHERING-NODE] 📍 Target center position: %s" % center_pos)

	# Animate to center and full size
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	tween.tween_property(self, "position", center_pos, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	print("[GATHERING-NODE] ✅ Tween started - animating to center")

	if GameLogger.ENABLED:
		print("[GatheringNode] Activated for gathering")

func start_gathering() -> void:
	"""Start the gathering process"""
	print("[GATHERING-NODE] start_gathering() called - is_active=%s, attempts_remaining=%d" % [is_active, attempts_remaining])

	if not is_active or attempts_remaining <= 0:
		print("[GATHERING-NODE] ERROR: Cannot start - is_active=%s, attempts_remaining=%d" % [is_active, attempts_remaining])
		return

	is_gathering = true
	current_attempt_time = 0.0

	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = 0

	print("[GATHERING-NODE] ✅ Attempt started - is_gathering=true, timer=0")

# ==================== GATHERING LOGIC ====================

func _complete_attempt() -> void:
	"""Complete one gathering attempt"""
	print("[GATHERING-NODE] _complete_attempt() called")
	is_gathering = false
	current_attempt_time = 0.0
	attempts_remaining -= 1

	# Get tool stats from GameState
	var tool_stats = _get_tool_stats()

	# Calculate drops
	var drops = GatheringDatabase.calculate_node_drops(node_id, tool_stats)

	# Store collected items
	for drop in drops:
		collected_items.append(drop)

	# Emit signal
	gathering_attempt_complete.emit(drops)
	print("[GATHERING-NODE] Signal emitted - Got %d items" % drops.size())

	# Award gathering skill EXP based on node type
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.gathering_skills:
		match node_type:
			"mining":
				gs.gathering_skills.add_mining_exp(20)
				if GameLogger.ENABLED:
					print("[GatheringNode] 💫 Awarded 20 EXP to mining skill")
			"gathering":  # herbalism
				gs.gathering_skills.add_herbalism_exp(20)
				if GameLogger.ENABLED:
					print("[GatheringNode] 💫 Awarded 20 EXP to herbalism skill")
			"fishing":
				gs.gathering_skills.add_fishing_exp(20)
				if GameLogger.ENABLED:
					print("[GatheringNode] 💫 Awarded 20 EXP to fishing skill")
			_:
				if GameLogger.ENABLED:
					print("[GatheringNode] ⚠️ Unknown node type: %s - no EXP awarded!" % node_type)

	# Update UI
	_update_attempts_label()

	if progress_bar:
		progress_bar.visible = false

	print("[GATHERING-NODE] Attempts left: %d" % attempts_remaining)

	# Check if all attempts done
	if attempts_remaining <= 0:
		print("[GATHERING-NODE] All attempts done! Calling _finish_gathering()")
		_finish_gathering()
	else:
		# Schedule next attempt using timer (can't use await in non-async context)
		print("[GATHERING-NODE] Scheduling next attempt in 0.5s...")
		get_tree().create_timer(0.5).timeout.connect(_start_next_attempt, CONNECT_ONE_SHOT)

func _start_next_attempt() -> void:
	"""Start the next gathering attempt (called by timer)"""
	print("[GATHERING-NODE] Timer fired! Starting next attempt...")
	start_gathering()

func _finish_gathering() -> void:
	"""Finish all gathering attempts"""
	is_active = false
	is_gathering = false

	if GameLogger.ENABLED:
		print("[GatheringNode] Gathering complete - Total items: %d" % collected_items.size())

	# Emit signal with all collected items
	all_attempts_complete.emit(collected_items)

	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished

	queue_free()

func _get_tool_stats() -> Dictionary:
	"""Get equipped tool stats from GameState"""
	var stats = {
		"yield_bonus": 0,
		"speed_bonus": 0.0,
		"critical_chance": 0.05
	}

	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return stats

	# Get equipped gathering tool for this type
	var tool_slot = ""
	match node_type:
		"mining":
			tool_slot = "mining_tool"
		"gathering":
			tool_slot = "gathering_tool"
		"fishing":
			tool_slot = "fishing_tool"

	if "equipped_gathering_tools" in gs and gs.equipped_gathering_tools.has(tool_slot):
		var tool_id = gs.equipped_gathering_tools[tool_slot]
		if tool_id != "":
			var tool_data = GatheringDatabase.get_tool_data(tool_id)
			if tool_data.has("stats"):
				stats = tool_data["stats"].duplicate()

	return stats

func _update_attempts_label() -> void:
	"""Update attempts remaining label"""
	if attempts_label:
		attempts_label.text = "Attempts: %d" % attempts_remaining

# ==================== UTILITY ====================

func get_node_type() -> String:
	"""Get the type of this node"""
	return node_type

func is_gathering_complete() -> bool:
	"""Check if gathering is complete"""
	return attempts_remaining <= 0
