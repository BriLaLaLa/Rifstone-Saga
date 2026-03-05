extends Control
class_name WorldMapController

# World Map View Controller
# Displays main kingdom map with clickable regions
# NOTE: Clickable areas are now created directly in the scene for proper scaling

signal kingdom_clicked(kingdom_id: String)

# UI References
@onready var map_image: TextureRect = $MapImage
@onready var clickable_areas: Control = $ClickableAreas

# Data
var kingdoms_data: Array = []

func _ready() -> void:
	if GameLogger.ENABLED:
		print("[WorldMapController] Initializing world map...")

	# Load kingdoms data
	_load_kingdoms_data()

	# Setup map image
	_setup_map_image()

	# Connect existing clickable areas (created in scene)
	_connect_clickable_areas()

	# Update unlock states based on player level
	refresh_unlock_states()

	if GameLogger.ENABLED:
		print("[WorldMapController] World map ready with %d kingdoms" % kingdoms_data.size())

func _load_kingdoms_data() -> void:
	"""Load kingdom data from zones.json"""
	var file_path = "res://data/zones.json"

	if not FileAccess.file_exists(file_path):
		push_error("[WorldMapController] zones.json not found at: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_text)

		if error == OK:
			var data = json.get_data()
			if data is Dictionary and data.has("kingdoms"):
				kingdoms_data = data["kingdoms"]
				if GameLogger.ENABLED:
					print("[WorldMapController] Loaded %d kingdoms" % kingdoms_data.size())
			else:
				push_error("[WorldMapController] Invalid zones.json structure")
		else:
			push_error("[WorldMapController] JSON parse error: %s" % json.get_error_message())

		file.close()
	else:
		push_error("[WorldMapController] Failed to open zones.json")

func _setup_map_image() -> void:
	"""Setup the main kingdom map image"""
	if not map_image:
		push_error("[WorldMapController] MapImage node not found!")
		return

	# Load map texture
	var map_texture_path = "res://Icons/maps/regno principale.png"

	if ResourceLoader.exists(map_texture_path):
		map_image.texture = load(map_texture_path)
		map_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		map_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		if GameLogger.ENABLED:
			print("[WorldMapController] Loaded map image: %s" % map_texture_path)
	else:
		push_error("[WorldMapController] Map image not found: %s" % map_texture_path)

func _connect_clickable_areas() -> void:
	"""Connect signals from clickable areas created in the scene"""
	if not clickable_areas:
		push_error("[WorldMapController] ClickableAreas node not found!")
		return

	# Connect each child area's signal
	for child in clickable_areas.get_children():
		if child is MapClickableArea:
			# Connect click signal with kingdom_id from the area's name
			var kingdom_id = child.name  # Area name should match kingdom_id
			child.clicked.connect(_on_kingdom_area_clicked.bind(kingdom_id))

			if GameLogger.ENABLED:
				print("[WorldMapController] Connected area: %s" % kingdom_id)

	if GameLogger.ENABLED:
		print("[WorldMapController] Connected %d clickable areas" % clickable_areas.get_child_count())

func _on_kingdom_area_clicked(kingdom_id: String) -> void:
	"""Handle kingdom area click"""
	if GameLogger.ENABLED:
		print("[WorldMapController] Kingdom clicked: %s" % kingdom_id)

	# Emit signal for BattleTab to handle navigation
	kingdom_clicked.emit(kingdom_id)

func refresh_unlock_states() -> void:
	"""Refresh unlock states for all kingdoms (call when player levels up)"""
	if not clickable_areas:
		return

	if not has_node("/root/GameState"):
		return

	var gs = get_node("/root/GameState")
	var player_level = 1

	# Get player level
	if "character_stats" in gs and gs.character_stats != null:
		if "level" in gs.character_stats:
			player_level = gs.character_stats.level

	# Update each area's unlock status
	for area in clickable_areas.get_children():
		if area is MapClickableArea:
			# Find kingdom data by matching area name with kingdom_id
			for kingdom in kingdoms_data:
				if kingdom["id"] == area.name:
					var unlock_req = kingdom.get("unlock_requirement", 1)

					if player_level >= unlock_req:
						area.unlock()
					else:
						area.lock()
					break

	if GameLogger.ENABLED:
		print("[WorldMapController] Refreshed unlock states for level %d" % player_level)

func get_kingdom_data(kingdom_id: String) -> Dictionary:
	"""Get kingdom data by ID"""
	for kingdom in kingdoms_data:
		if kingdom["id"] == kingdom_id:
			return kingdom
	return {}

