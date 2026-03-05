extends Node

# Debug script per mostrare come viene calcolato l'attacco
# Aggiungi questo nodo alla scena Main per vedere il breakdown

func _ready():
	await get_tree().create_timer(1.0).timeout
	_print_attack_breakdown()

func _input(event):
	# Press F10 per vedere il breakdown
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_print_attack_breakdown()

func _print_attack_breakdown():
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gs.character_stats:
		print("[DebugAttack] ERROR: GameState or character_stats not found!")
		return

	var stats = gs.character_stats

	print("\n" + "=".repeat(60))
	print("🗡️ ATTACK DAMAGE BREAKDOWN")
	print("=".repeat(60))

	# Physical Damage
	var base_phys_dmg = stats.base_stats.get("physical_damage", 0)
	var bonus_phys_dmg = stats.equipment_bonuses.get("physical_damage", 0)
	var total_phys_dmg = stats.get_stat("physical_damage")

	print("\n1️⃣ PHYSICAL DAMAGE:")
	print("   Base:      %d" % base_phys_dmg)
	print("   Equipment: +%d" % bonus_phys_dmg)
	print("   Total:     %d" % total_phys_dmg)

	# Strength
	var base_str = stats.base_stats.get("strength", 0)
	var bonus_str = stats.equipment_bonuses.get("strength", 0)
	var total_str = stats.get_stat("strength")

	print("\n2️⃣ STRENGTH:")
	print("   Base:      %d" % base_str)
	print("   Equipment: +%d" % bonus_str)
	print("   Total:     %d" % total_str)
	print("   × 0.5 =    %.1f" % (total_str * 0.5))

	# Total Attack
	var total_attack = gs.get_total_attack()

	print("\n⚔️ TOTAL ATTACK:")
	print("   Formula:   physical_damage + (strength × 0.5)")
	print("   Calc:      %d + (%.1f)" % [total_phys_dmg, total_str * 0.5])
	print("   Result:    %.1f" % total_attack)

	# Equipment breakdown
	print("\n🎽 EQUIPPED ITEMS:")
	var has_equipment = false
	for slot in gs.equipped_items.keys():
		var item = gs.equipped_items[slot]
		if item != null:
			has_equipment = true
			var item_name = item.get("name", "Unknown")
			print("\n   [%s]: %s" % [slot.to_upper(), item_name])

			if item.has("stats"):
				for stat in item.stats.keys():
					if stat in ["physical_damage", "strength", "attack_speed"]:
						print("      +%s: %s" % [stat, item.stats[stat]])

	if not has_equipment:
		print("   (No items equipped)")

	print("\n" + "=".repeat(60))
	print("Press F10 to refresh this breakdown")
	print("=".repeat(60) + "\n")
