# File: res://scripts/battle/LootOrbManager.gd
# Autoload manager for spawning and collecting loot orbs

extends Node

const LOOT_ORB_SCENE = preload("res://scenes/battle/LootOrb.tscn")

# Rarity configuration
const RARITY_CONFIG = {
	"common": {
		"color": Color.WHITE,
		"particle_count": 15,
		"particle_speed": 50.0,
		"glow_scale": 1.0,
		"sound": "res://audio/loot/loot_common.wav"
	},
	"rare": {
		"color": Color.BLUE,
		"particle_count": 30,
		"particle_speed": 70.0,
		"glow_scale": 1.4,
		"sound": "res://audio/loot/loot_rare.wav"
	},
	"epic": {
		"color": Color.PURPLE,
		"particle_count": 45,
		"particle_speed": 90.0,
		"glow_scale": 1.7,
		"sound": "res://audio/loot/loot_epic.wav"
	},
	"legendary": {
		"color": Color.ORANGE,
		"particle_count": 60,
		"particle_speed": 120.0,
		"glow_scale": 2.0,
		"sound": "res://audio/loot/loot_legendary.wav"
	}
}

# Audio
var orb_audio_player: AudioStreamPlayer = null
var preloaded_sounds: Dictionary = {}

# References
var battle_tab: Node = null
var active_orbs: Array = []  # Array of LootOrb instances

func _ready() -> void:
	_setup_audio()
	# Battle tab will be found when first needed (may not exist at autoload time)

func _setup_audio() -> void:
	"""Setup audio player and preload sounds"""
	orb_audio_player = AudioStreamPlayer.new()
	orb_audio_player.name = "OrbAudioPlayer"
	orb_audio_player.bus = "Master"  # Change to "SFX" if that bus exists
	add_child(orb_audio_player)

	# Preload sounds (only if files exist)
	for rarity in RARITY_CONFIG.keys():
		var path = RARITY_CONFIG[rarity].sound
		if ResourceLoader.exists(path):
			preloaded_sounds[rarity] = load(path)
		else:
			if GameLogger.ENABLED:
				print("[LootOrbManager] Sound not found: %s" % path)

func _find_battle_tab() -> Node:
	"""Find BattleTab in scene tree for orb spawning"""
	if battle_tab:
		return battle_tab

	# Navigate: Main > Margin > VBox > Tabs > Battle
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		var tabs = main.get_node_or_null("Margin/VBox/Tabs")
		if tabs:
			battle_tab = tabs.get_node_or_null("Battle")

	if not battle_tab:
		if GameLogger.ENABLED:
			print("[LootOrbManager] ⚠️ BattleTab not found!")

	return battle_tab

func spawn_orb(item_data: Dictionary, spawn_pos: Vector2, rarity: String) -> void:
	"""Spawn a loot orb at the given position"""
	print("[DEBUG] 🌟 LootOrbManager.spawn_orb called - item: %s, pos: %s, rarity: %s" % [item_data.get("name", "Unknown"), spawn_pos, rarity])

	_find_battle_tab()

	if not battle_tab:
		# Fallback: add directly to inventory
		print("[DEBUG] ⚠️ BattleTab NOT FOUND - using fallback")
		if GameLogger.ENABLED:
			print("[LootOrbManager] ⚠️ BattleTab not found - adding item directly")
		_add_to_inventory_directly(item_data)
		return

	print("[DEBUG] ✅ BattleTab found: %s" % battle_tab)

	# Instantiate orb
	var orb = LOOT_ORB_SCENE.instantiate()
	print("[DEBUG] 📦 Orb instantiated: %s" % orb)

	battle_tab.add_child(orb)
	print("[DEBUG] ✅ Orb added to BattleTab")

	# Setup orb
	var target_pos = _get_player_target_position()
	print("[DEBUG] 🎯 Target position: %s" % target_pos)

	orb.setup(item_data, rarity, spawn_pos, target_pos)
	print("[DEBUG] ✅ Orb.setup() called")

	orb.orb_collected.connect(_on_orb_collected)

	active_orbs.append(orb)

	print("[DEBUG] 🎉 Orb fully configured! Active orbs: %d" % active_orbs.size())

	if GameLogger.ENABLED:
		print("[LootOrbManager] 🌟 Spawned %s orb at %s for item: %s" % [rarity, spawn_pos, item_data.get("name", "Unknown")])

func _on_orb_collected(item_data: Dictionary) -> void:
	"""Handle orb collection - add to inventory, play sound, show notification"""
	# Add to inventory
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("_add_item_to_visual_inventory"):
		var item_id = item_data.get("id", "")
		if not item_id.is_empty():
			gs._add_item_to_visual_inventory(item_id, item_data)
			if GameLogger.ENABLED:
				print("[LootOrbManager] ✅ Added to inventory: %s" % item_data.get("name", item_id))

	# Determine rarity for sound
	var rarity = _get_item_rarity_from_data(item_data)
	play_collection_sound(rarity)

	# Show notification
	if GameLogger.ENABLED:
		print("[LootOrbManager] 📬 Showing notification for: %s" % item_data.get("name", "Unknown"))
		print("[LootOrbManager] 🖼️ Item data icon: '%s'" % item_data.get("icon", "MISSING"))

	var notif_manager = get_node_or_null("/root/LootNotificationManager")
	if notif_manager and notif_manager.has_method("show_notification"):
		notif_manager.show_notification(item_data)

func play_collection_sound(rarity: String) -> void:
	"""Play collection sound based on rarity"""
	if not preloaded_sounds.has(rarity):
		if GameLogger.ENABLED:
			print("[LootOrbManager] No sound for rarity: %s" % rarity)
		return

	if orb_audio_player:
		orb_audio_player.stream = preloaded_sounds[rarity]
		orb_audio_player.volume_db = -8.0
		orb_audio_player.play()

func _get_player_target_position() -> Vector2:
	"""Get the position where orbs should fly to (player's CharacterDisplay center)"""
	if not battle_tab:
		return Vector2(175, 225)

	# Try to find CharacterDisplay
	var char_display = battle_tab.get_node_or_null("HSplit/LeftPanel/CharacterDisplay")
	if char_display:
		# Return center of CharacterDisplay, slightly offset upward
		return char_display.global_position + char_display.size / 2 - Vector2(0, 50)

	# Fallback position
	return Vector2(175, 225)

func _get_item_rarity_from_data(item_data: Dictionary) -> String:
	"""Determine rarity from item bonuses (matches ExplorationCombatController logic)"""
	if not item_data.has("bonuses"):
		return "common"

	var bonus_count = item_data.bonuses.size()

	# Map bonus count to rarity
	if bonus_count == 0:
		return "common"
	elif bonus_count <= 2:
		return "rare"
	elif bonus_count <= 4:
		return "epic"
	else:
		return "legendary"

func _add_to_inventory_directly(item_data: Dictionary) -> void:
	"""Fallback: add item directly to inventory if orb system fails"""
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("_add_item_to_visual_inventory"):
		var item_id = item_data.get("id", "")
		if not item_id.is_empty():
			gs._add_item_to_visual_inventory(item_id, item_data)
