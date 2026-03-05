# File: res://scripts/battle/GoldOrbManager.gd
# Manages gold orb spawning and collection

extends Node

# Scene reference
var gold_orb_scene: PackedScene = preload("res://scenes/battle/GoldOrb.tscn")

# References
var battle_tab: Node = null
var gold_panel: Control = null

# Tracking
var active_orbs: Array = []
var pending_gold: int = 0  # Gold waiting to be added

# Config
const MIN_ORBS = 2  # Minimum orbs to spawn
const MAX_ORBS = 6  # Maximum orbs to spawn
const GOLD_PER_ORB_MIN = 3  # Minimum gold per orb

func spawn_gold_orbs(total_gold: int, spawn_pos: Vector2) -> void:
	"""Spawn multiple gold orbs that split the total gold"""
	if total_gold <= 0:
		return

	# Find battle_tab and gold_panel if not cached
	if not battle_tab or not gold_panel:
		_find_references()

	if not gold_panel:
		# Fallback: add gold directly without visual
		if GameLogger.ENABLED:
			print("[GoldOrbManager] ⚠️ GoldPanel not found, using fallback")
		_add_gold_directly(total_gold)
		return

	# Calculate number of orbs (more gold = more orbs, but capped)
	var orb_count = clampi(int(total_gold / 15.0), MIN_ORBS, MAX_ORBS)
	var gold_per_orb = int(total_gold / orb_count)

	# Get target position (GoldPanel center)
	var target_pos = _get_gold_panel_position()

	# Spawn orbs in a spread pattern
	for i in range(orb_count):
		var orb = gold_orb_scene.instantiate()

		# Add to battle_tab
		battle_tab.add_child(orb)

		# Offset spawn positions slightly for visual variety
		var offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var orb_spawn_pos = spawn_pos + offset

		# Setup orb
		var orb_gold = gold_per_orb
		# Last orb gets remainder
		if i == orb_count - 1:
			orb_gold = total_gold - (gold_per_orb * (orb_count - 1))

		orb.setup(orb_gold, orb_spawn_pos, target_pos)

		# Connect collection signal
		orb.orb_collected.connect(_on_gold_orb_collected)

		# Track active orb
		active_orbs.append(orb)

		# Stagger spawns slightly
		await get_tree().create_timer(0.05).timeout

	if GameLogger.ENABLED:
		print("[GoldOrbManager] 💰 Spawned %d gold orbs (total: %d gold)" % [orb_count, total_gold])

func _find_references() -> void:
	"""Find BattleTab and GoldPanel in scene tree"""
	if battle_tab:
		return

	# Navigate: Main > Margin > VBox > TopBar > GoldPanel
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		var tabs = main.get_node_or_null("Margin/VBox/Tabs")
		if tabs:
			battle_tab = tabs.get_node_or_null("Combat")

		# Get GoldPanel from TopBar
		gold_panel = main.get_node_or_null("Margin/VBox/TopBar/GoldPanel")

	if not gold_panel and GameLogger.ENABLED:
		print("[GoldOrbManager] ⚠️ GoldPanel not found!")

func _get_gold_panel_position() -> Vector2:
	"""Get global center position of GoldPanel"""
	if gold_panel:
		return gold_panel.global_position + gold_panel.size / 2
	else:
		# Fallback: top right of screen
		var viewport_size = get_viewport().get_visible_rect().size
		return Vector2(viewport_size.x - 100, 30)

func _on_gold_orb_collected(gold_amount: int) -> void:
	"""Handle gold orb collection - add gold to GameState"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("add_gold"):
		gs.add_gold(gold_amount)

		if GameLogger.ENABLED:
			print("[GoldOrbManager] 💰 Collected %d gold" % gold_amount)

	# Remove from active tracking
	# (orb already queue_free'd itself)

func _add_gold_directly(gold_amount: int) -> void:
	"""Fallback: add gold without visual orbs"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("add_gold"):
		gs.add_gold(gold_amount)
		if GameLogger.ENABLED:
			print("[GoldOrbManager] ⚠️ Added gold directly (no visual): %d" % gold_amount)
