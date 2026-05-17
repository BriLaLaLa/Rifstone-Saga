extends Control
class_name RegionZoomController

# Region Zoom View Controller
# Displays zoomed region map with clickable zones
# NOTE: Zone areas are now created directly in the scene for proper scaling

signal zone_clicked(zone_data: ZoneData)
signal back_to_world_map()

# UI References
@onready var zoom_image: TextureRect = $ZoomImage
@onready var zone_areas: Control = $ZoneAreas
@onready var back_button: Button = $TopBar/BackButton
@onready var region_title: Label = $TopBar/RegionTitle

# State
var current_kingdom_id: String = ""
var current_kingdom_data: Dictionary = {}
var zones_data: Array = []

func _ready() -> void:
	# Connect back button
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)

	if GameLogger.ENABLED:
		print("[RegionZoomController] Ready")

func load_kingdom(kingdom_id: String) -> void:
	"""Load and display a specific kingdom's zoom map"""
	current_kingdom_id = kingdom_id

	if GameLogger.ENABLED:
		print("[RegionZoomController] Loading kingdom: %s" % kingdom_id)

	# Load kingdom data
	_load_kingdom_data()

	# Setup zoom image
	_setup_zoom_image()

	# Show/hide zones based on kingdom and connect signals
	_setup_zone_visibility()

	# Update title
	if region_title:
		region_title.text = current_kingdom_data.get("name", kingdom_id)

func _load_kingdom_data() -> void:
	"""Load kingdom data from zones.json"""
	var file_path = "res://data/zones.json"

	if not FileAccess.file_exists(file_path):
		push_error("[RegionZoomController] zones.json not found")
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_text)

		if error == OK:
			var data = json.get_data()
			if data is Dictionary and data.has("kingdoms"):
				var kingdoms = data["kingdoms"]

				# Find our kingdom
				for kingdom in kingdoms:
					if kingdom["id"] == current_kingdom_id:
						current_kingdom_data = kingdom
						zones_data = kingdom.get("zones", [])

						if GameLogger.ENABLED:
							print("[RegionZoomController] Found kingdom with %d zones" % zones_data.size())
						break

		file.close()

func _setup_zoom_image() -> void:
	"""Setup the zoomed region map image"""
	if not zoom_image:
		push_error("[RegionZoomController] ZoomImage node not found!")
		return

	# Get zoom map path from kingdom data
	var zoom_map_path = current_kingdom_data.get("zoom_map", "")

	if zoom_map_path.is_empty():
		push_error("[RegionZoomController] No zoom_map for kingdom: %s" % current_kingdom_id)
		return

	if ResourceLoader.exists(zoom_map_path):
		zoom_image.texture = load(zoom_map_path)
		zoom_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		zoom_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

		if GameLogger.ENABLED:
			print("[RegionZoomController] Loaded zoom image: %s" % zoom_map_path)
	else:
		push_error("[RegionZoomController] Zoom image not found: %s" % zoom_map_path)

func _setup_zone_visibility() -> void:
	"""Show/hide zones based on current kingdom and connect signals"""
	if not zone_areas:
		push_error("[RegionZoomController] ZoneAreas node not found!")
		return

	var visible_count = 0
	var gs = get_node("/root/GameState") if has_node("/root/GameState") else null
	var player_level = 1

	# Get player level
	if gs and "character_stats" in gs and gs.character_stats != null:
		if "level" in gs.character_stats:
			player_level = gs.character_stats.level

	# Process each zone area in the scene
	for child in zone_areas.get_children():
		if child is MapClickableArea:
			var zone_id = child.name  # Area name should match zone_id

			# Check if this zone belongs to current kingdom
			if zone_id.begins_with(current_kingdom_id):
				# This zone belongs to this kingdom - show it
				child.visible = true
				visible_count += 1

				# Find zone data from zones.json
				var zone_dict: Dictionary = {}
				for zone in zones_data:
					if zone["id"] == zone_id:
						zone_dict = zone
						break

				# Connect click signal with ZoneData
				if zone_dict.is_empty():
					push_error("[RegionZoomController] No data found for zone: %s" % zone_id)
					continue

				var zone_data = ZoneData.from_dict(zone_dict)

				# Disconnect any previous connections
				if child.clicked.is_connected(_on_zone_area_clicked):
					child.clicked.disconnect(_on_zone_area_clicked)

				# Connect with zone data
				child.clicked.connect(_on_zone_area_clicked.bind(zone_data))

				# Update unlock status
				var unlock_req = zone_dict.get("unlock_requirement", 1)
				if player_level >= unlock_req:
					child.unlock()
				else:
					child.lock()

				if GameLogger.ENABLED:
					print("[RegionZoomController] Showed zone: %s (Unlocked: %s)" %
						[zone_id, player_level >= unlock_req])
			else:
				# This zone belongs to a different kingdom - hide it
				child.visible = false

	if GameLogger.ENABLED:
		print("[RegionZoomController] Showing %d zones for kingdom: %s" % [visible_count, current_kingdom_id])

func _on_zone_area_clicked(zone_data: ZoneData) -> void:
	"""Handle zone area click"""
	if GameLogger.ENABLED:
		print("[RegionZoomController] Zone clicked: %s (Area: %s)" %
			[zone_data.name, zone_data.area_id])

	# Emit signal for BattleTab to start battle
	zone_clicked.emit(zone_data)

func _on_back_button_pressed() -> void:
	"""Handle back button click"""
	if GameLogger.ENABLED:
		print("[RegionZoomController] Back button pressed")

	# Emit signal to return to world map
	back_to_world_map.emit()

func refresh_zones() -> void:
	"""Refresh zone unlock states (call when player levels up)"""
	if not zone_areas:
		return

	var gs = get_node("/root/GameState") if has_node("/root/GameState") else null
	var player_level = 1

	# Get player level
	if gs and "character_stats" in gs and gs.character_stats != null:
		if "level" in gs.character_stats:
			player_level = gs.character_stats.level

	# Update each visible zone's unlock status
	for area in zone_areas.get_children():
		if area is MapClickableArea and area.visible:
			var zone_id = area.name

			# Find zone data
			for zone_dict in zones_data:
				if zone_dict["id"] == zone_id:
					var unlock_req = zone_dict.get("unlock_requirement", 1)

					if player_level >= unlock_req:
						area.unlock()
					else:
						area.lock()
					break

	if GameLogger.ENABLED:
		print("[RegionZoomController] Refreshed zone states for level %d" % player_level)
