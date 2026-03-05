@tool
extends Control
class_name SpawnPointDebugger

## Debug tool to visualize spawn points over backgrounds
## Attach this to BattleArea in the editor to see spawn point positions
## Path: res://scripts/battle/SpawnPointDebugger.gd

# ==================== EXPORTED VARIABLES ====================
@export_group("Debug Settings")
@export var show_spawn_points: bool = true
@export var background_to_test: String = "m1_z1_1"
@export var show_boss_differently: bool = true
@export_color_no_alpha var normal_point_color: Color = Color.GREEN
@export_color_no_alpha var boss_point_color: Color = Color.RED
@export var point_radius: float = 8.0
@export var show_labels: bool = true
@export var label_font_size: int = 12

const BackgroundManager = preload("res://scripts/battle/BackgroundManager.gd")

var background_manager: BackgroundManager = null
var spawn_positions: Array = []

func _ready() -> void:
	if Engine.is_editor_hint():
		# Initialize in editor
		background_manager = BackgroundManager.new()
		add_child(background_manager)
		_load_spawn_points()

	# Always update visual
	queue_redraw()

func _load_spawn_points() -> void:
	if not background_manager:
		return

	var bg_config = background_manager.get_background_by_key(background_to_test)
	if bg_config.is_empty():
		push_warning("[SpawnPointDebugger] Failed to load background: %s" % background_to_test)
		return

	spawn_positions = background_manager.get_all_spawn_points()
	queue_redraw()

func _draw() -> void:
	if not show_spawn_points or spawn_positions.is_empty():
		return

	for i in range(spawn_positions.size()):
		var pos = spawn_positions[i]
		var is_boss = (i == 0)

		# Draw circle
		var color = boss_point_color if (is_boss and show_boss_differently) else normal_point_color
		draw_circle(pos, point_radius, color)

		# Draw outline
		draw_arc(pos, point_radius + 1, 0, TAU, 32, Color.BLACK, 2.0)

		# Draw label
		if show_labels:
			var label_text = "BOSS" if is_boss else str(i)
			var label_pos = pos + Vector2(-10, -point_radius - 5)

			# Draw text shadow
			draw_string(ThemeDB.fallback_font, label_pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, Color.BLACK)
			# Draw text
			draw_string(ThemeDB.fallback_font, label_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, color)

		# Draw cross at center
		var cross_size = 3
		draw_line(pos - Vector2(cross_size, 0), pos + Vector2(cross_size, 0), Color.WHITE, 1.0)
		draw_line(pos - Vector2(0, cross_size), pos + Vector2(0, cross_size), Color.WHITE, 1.0)

# Editor property changed
func _get_property_list():
	return []

func _set(property, value):
	if Engine.is_editor_hint():
		if property == "background_to_test" and background_to_test != value:
			background_to_test = value
			_load_spawn_points()
			return true
		elif property in ["show_spawn_points", "show_boss_differently", "normal_point_color", "boss_point_color", "point_radius", "show_labels", "label_font_size"]:
			queue_redraw()
			return true
	return false
