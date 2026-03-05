# File: res://scripts/battle/XpOrbManager.gd
# Manages XP orb spawning and collection

extends Node

# Scene reference
var xp_orb_scene: PackedScene = preload("res://scenes/battle/XpOrb.tscn")

# References
var battle_tab: Node = null
var character_display: Node = null
var exp_bar: ProgressBar = null

# Tracking
var active_orbs: Array = []
var pending_xp: int = 0  # XP waiting to be added

# Config
const MIN_ORBS = 3  # Minimum orbs to spawn
const MAX_ORBS = 8  # Maximum orbs to spawn
const XP_PER_ORB_MIN = 5  # Minimum XP per orb

func spawn_xp_orbs(total_xp: int, spawn_pos: Vector2) -> void:
	"""Spawn multiple XP orbs that split the total XP"""
	if total_xp <= 0:
		return

	# Find battle_tab and exp_bar if not cached
	if not battle_tab or not exp_bar:
		_find_references()

	if not exp_bar:
		# Fallback: add XP directly without visual
		if GameLogger.ENABLED:
			print("[XpOrbManager] ⚠️ ExpBar not found, using fallback")
		_add_xp_directly(total_xp)
		return

	# Calculate number of orbs (more XP = more orbs, but capped)
	var orb_count = clampi(int(total_xp / 20.0), MIN_ORBS, MAX_ORBS)
	var xp_per_orb = int(total_xp / orb_count)

	# Get target position (ExpBar center)
	var target_pos = _get_exp_bar_position()

	# Spawn orbs in a spread pattern
	for i in range(orb_count):
		var orb = xp_orb_scene.instantiate()

		# Add to battle_tab
		battle_tab.add_child(orb)

		# Offset spawn positions slightly for visual variety
		var offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var orb_spawn_pos = spawn_pos + offset

		# Setup orb
		var orb_xp = xp_per_orb
		# Last orb gets remainder
		if i == orb_count - 1:
			orb_xp = total_xp - (xp_per_orb * (orb_count - 1))

		orb.setup(orb_xp, orb_spawn_pos, target_pos)

		# Connect collection signal
		orb.orb_collected.connect(_on_xp_orb_collected)

		# Track active orb
		active_orbs.append(orb)

		# Stagger spawns slightly
		await get_tree().create_timer(0.05).timeout

	if GameLogger.ENABLED:
		print("[XpOrbManager] ✨ Spawned %d XP orbs (total: %d XP)" % [orb_count, total_xp])

func _find_references() -> void:
	"""Find BattleTab and ExpBar in scene tree"""
	if battle_tab:
		return

	# Navigate: Main > Margin > VBox > Tabs > Combat > BattleTab > HSplit > LeftPanel > CharacterDisplay
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		var tabs = main.get_node_or_null("Margin/VBox/Tabs")
		if tabs:
			battle_tab = tabs.get_node_or_null("Combat")

	if battle_tab:
		# Find CharacterDisplay and ExpBar
		character_display = battle_tab.get_node_or_null("BattleTab/HSplit/LeftPanel/CharacterDisplay")
		if character_display:
			exp_bar = character_display.get_node_or_null("StatsPanel/LevelPanel/VBox/ExpBar")

	if not exp_bar and GameLogger.ENABLED:
		print("[XpOrbManager] ⚠️ ExpBar not found!")

func _get_exp_bar_position() -> Vector2:
	"""Get global center position of ExpBar"""
	if exp_bar:
		return exp_bar.global_position + exp_bar.size / 2
	else:
		# Fallback: center of screen
		return get_viewport().get_visible_rect().size / 2

func _on_xp_orb_collected(xp_amount: int) -> void:
	"""Handle XP orb collection - add XP to GameState"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.character_stats and gs.character_stats.level_system:
		gs.character_stats.level_system.add_exp(xp_amount)

		if GameLogger.ENABLED:
			print("[XpOrbManager] 💚 Collected %d XP" % xp_amount)

	# Remove from active tracking
	# (orb already queue_free'd itself)

func _add_xp_directly(xp_amount: int) -> void:
	"""Fallback: add XP without visual orbs"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.character_stats and gs.character_stats.level_system:
		gs.character_stats.level_system.add_exp(xp_amount)
		if GameLogger.ENABLED:
			print("[XpOrbManager] ⚠️ Added XP directly (no visual): %d" % xp_amount)
