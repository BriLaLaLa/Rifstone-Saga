extends TextureButton
class_name PassiveNode

## Passive Node - A single node in the passive skill tree
## Click to activate if any connected node is already activated

signal node_activated(node_id: String)
signal node_hovered(node_id: String, is_hovered: bool)

# ==================== EXPORTED VARIABLES ====================
@export var passive_id: String = "passive_1"
@export var passive_name: String = "Passive Skill"
@export var passive_description: String = "Increases a stat."
@export var connected_nodes: Array[String] = []  # IDs of connected nodes
@export var is_start_node: bool = false  # Start node is pre-activated

# ==================== STATE ====================
var is_activated: bool = false
var is_unlocked: bool = false  # Can be clicked (adjacent to activated node)

# ==================== NODE REFERENCES ====================
@onready var icon: TextureRect = $Icon
@onready var glow: ColorRect = $Glow
@onready var lock_overlay: ColorRect = $LockOverlay

# ==================== READY ====================
func _ready() -> void:
	# Connect signals
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Set default icon if none provided
	if icon and icon.texture == null:
		icon.texture = preload("res://icon.svg")
	
	# Start node is pre-activated
	if is_start_node:
		activate()
	else:
		_update_visual_state()

# ==================== PUBLIC API ====================
func activate() -> void:
	"""Activate this passive node"""
	if is_activated:
		return
	
	is_activated = true
	is_unlocked = true
	_update_visual_state()
	node_activated.emit(passive_id)
	print("[PassiveNode] ✅ Activated: %s" % passive_id)

func set_unlocked(unlocked: bool) -> void:
	"""Set whether this node can be clicked"""
	is_unlocked = unlocked
	_update_visual_state()

func get_center_position() -> Vector2:
	"""Get center position for drawing connection lines"""
	return global_position + size / 2

# ==================== VISUAL STATE ====================
func _update_visual_state() -> void:
	"""Update visual appearance based on state"""
	if is_activated:
		# Activated: show glow, no lock overlay
		if glow:
			glow.visible = true
		if lock_overlay:
			lock_overlay.visible = false
		modulate = Color.WHITE
	elif is_unlocked:
		# Unlocked but not activated: no glow, no lock
		if glow:
			glow.visible = false
		if lock_overlay:
			lock_overlay.visible = false
		modulate = Color.WHITE
	else:
		# Locked: gray out with lock overlay
		if glow:
			glow.visible = false
		if lock_overlay:
			lock_overlay.visible = true
		modulate = Color(0.6, 0.6, 0.6, 1.0)

# ==================== EVENT HANDLERS ====================
func _on_pressed() -> void:
	"""Handle click on node"""
	if is_activated:
		print("[PassiveNode] Already activated: %s" % passive_id)
		return
	
	if not is_unlocked:
		print("[PassiveNode] ❌ Cannot activate %s - not unlocked" % passive_id)
		return
	
	# Check if player has enough points (handled by parent)
	activate()

func _on_mouse_entered() -> void:
	"""Show tooltip on hover"""
	node_hovered.emit(passive_id, true)
	
	# Visual feedback on hover
	if not is_activated and is_unlocked:
		modulate = Color(1.2, 1.2, 1.2, 1.0)

func _on_mouse_exited() -> void:
	"""Hide tooltip"""
	node_hovered.emit(passive_id, false)
	
	# Reset visual
	_update_visual_state()

# ==================== TOOLTIP ====================
func _get_passive_tooltip_text() -> String:
	"""Get tooltip text for this passive"""
	var status = ""
	if is_activated:
		status = "[ACTIVATED]"
	elif is_unlocked:
		status = "[Click to Activate]"
	else:
		status = "[LOCKED]"
	
	return "%s\n%s\n\n%s" % [passive_name.to_upper(), status, passive_description]
