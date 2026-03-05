extends Node

# Debug script per vedere esattamente cosa è equipaggiato
# Press F11 per mostrare il breakdown completo dell'equipment

func _ready():
	await get_tree().create_timer(1.0).timeout
	print("\n[DebugEquipment] Ready! Press F11 to see equipment breakdown")

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_print_equipment_breakdown()

func _print_equipment_breakdown():
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		print("[DebugEquipment] ERROR: GameState or character_stats not found!")
		return

	print("\n" + "=".repeat(70))
	print("🎽 EQUIPMENT BREAKDOWN - DEBUG")
	print("=".repeat(70))

	# Check equipment
	var has_equipment = false
	var total_strength_from_equip = 0
	var total_phys_dmg_from_equip = 0

	print("\n📦 EQUIPPED ITEMS:")
	for slot in gs.equipped_items.keys():
		var item = gs.equipped_items[slot]
		if item != null:
			has_equipment = true
			var item_name = item.get("name", "Unknown Item")
			var item_id = item.get("id", "unknown_id")

			print("\n  [%s]" % slot.to_upper())
			print("    Name: %s" % item_name)
			print("    ID: %s" % item_id)

			if item.has("stats"):
				print("    Stats:")
				for stat_name in item.stats.keys():
					var value = item.stats[stat_name]
					print("      +%s: %s" % [stat_name, value])

					# Track strength and phys_dmg
					if stat_name == "strength":
						total_strength_from_equip += value
					elif stat_name == "physical_damage":
						total_phys_dmg_from_equip += value
			else:
				print("    (No stats on this item)")

			# Check for bonuses
			if item.has("bonuses") and item.bonuses.size() > 0:
				print("    Bonuses:")
				for bonus in item.bonuses:
					print("      - %s" % bonus)

	if not has_equipment:
		print("  (No items equipped)")

	print("\n" + "-".repeat(70))

	# Character stats breakdown
	var stats = gs.character_stats

	print("\n💪 STRENGTH BREAKDOWN:")
	print("  Base Strength:      %d" % stats.base_stats["strength"])
	print("  Equipment Bonus:    +%d" % stats.equipment_bonuses["strength"])
	print("  Total Strength:     %d" % stats.get_stat("strength"))
	print("")
	print("  Expected from items: +%d" % total_strength_from_equip)

	if stats.equipment_bonuses["strength"] != total_strength_from_equip:
		print("  ⚠️ MISMATCH! Equipment bonus doesn't match item stats!")
		print("     Bonus in character_stats: %d" % stats.equipment_bonuses["strength"])
		print("     Sum from equipped items:  %d" % total_strength_from_equip)
		print("     Difference: %d" % (stats.equipment_bonuses["strength"] - total_strength_from_equip))

	print("\n🗡️ PHYSICAL DAMAGE BREAKDOWN:")
	print("  Base Physical Damage:  %d" % stats.base_stats["physical_damage"])
	print("  Equipment Bonus:       +%d" % stats.equipment_bonuses["physical_damage"])
	print("  Total Physical Damage: %d" % stats.get_stat("physical_damage"))
	print("")
	print("  Expected from items:   +%d" % total_phys_dmg_from_equip)

	if stats.equipment_bonuses["physical_damage"] != total_phys_dmg_from_equip:
		print("  ⚠️ MISMATCH! Equipment bonus doesn't match item stats!")

	print("\n⚔️ TOTAL ATTACK CALCULATION:")
	var total_attack = gs.get_total_attack()
	var phys = stats.get_stat("physical_damage")
	var strength = stats.get_stat("strength")
	print("  Formula: physical_damage + (strength × 0.5)")
	print("  Calc:    %d + (%d × 0.5)" % [phys, strength])
	print("  Calc:    %d + %.1f" % [phys, strength * 0.5])
	print("  Result:  %.1f" % total_attack)

	print("\n" + "=".repeat(70))
	print("🔍 DIAGNOSTIC:")

	# Level check
	if gs.has("level"):
		print("  Player Level: %d" % gs.level)
	else:
		print("  Player Level: NOT FOUND (no level system?)")

	# Check for save file
	var save_path = gs.SAVE_PATH if gs.has("SAVE_PATH") else "user://save.dat"
	if FileAccess.file_exists(save_path):
		print("  Save File: EXISTS at %s" % save_path)
		print("  ⚠️ Stats are loaded from this save!")
	else:
		print("  Save File: DOES NOT EXIST")

	# Check if stats match base
	if stats.base_stats["strength"] != 10:
		print("  ⚠️ WARNING: Base strength is %d, not 10!" % stats.base_stats["strength"])
		print("     This means base_stats was modified!")

	if stats.base_stats["physical_damage"] != 5:
		print("  ⚠️ WARNING: Base physical_damage is %d, not 5!" % stats.base_stats["physical_damage"])
		print("     This means base_stats was modified!")

	print("\n" + "=".repeat(70))
	print("Press F11 to refresh | Press F12 to reset equipment bonuses")
	print("=".repeat(70) + "\n")

func _input_reset(event):
	"""Additional input handler for reset"""
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_reset_equipment_bonuses()

func _reset_equipment_bonuses():
	"""Emergency reset - recalculates equipment bonuses from scratch"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		print("[DebugEquipment] ERROR: Can't reset!")
		return

	print("\n[DebugEquipment] 🔄 RESETTING EQUIPMENT BONUSES...")

	var stats = gs.character_stats

	# Clear all equipment bonuses
	for stat in stats.equipment_bonuses.keys():
		stats.equipment_bonuses[stat] = 0 if typeof(stats.base_stats[stat]) == TYPE_INT else 0.0

	print("  ✓ Cleared all equipment bonuses")

	# Re-apply from equipped items
	var reapplied = 0
	for slot in gs.equipped_items.keys():
		var item = gs.equipped_items[slot]
		if item != null and item.has("stats"):
			stats.apply_equipment_stats(item.stats)
			reapplied += 1
			print("  ✓ Re-applied stats from: %s" % item.get("name", slot))

	print("  ✓ Re-applied %d items" % reapplied)
	print("\n[DebugEquipment] ✅ RESET COMPLETE!")
	print("New Strength: %d (base: %d + equip: %d)" % [
		stats.get_stat("strength"),
		stats.base_stats["strength"],
		stats.equipment_bonuses["strength"]
	])
	print("New Attack: %.1f" % gs.get_total_attack())

	# Show breakdown again
	await get_tree().create_timer(0.5).timeout
	_print_equipment_breakdown()
