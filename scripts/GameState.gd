extends Node

signal on_tick(delta: float)
signal on_skill_level_up(skill_id: String, new_level: int)
signal on_inventory_changed()
signal on_craft_updated()
signal on_combat_event(msg: String)

# NUOVI segnali per la tab Skills (actions & promo)
signal on_action_started(action_id: String)
signal on_action_progress(action_id: String, t_left: float, t_total: float)
signal on_action_finished(action_id: String)
signal on_promotion_result(skill_id: String, success: bool, msg: String)

# ============================================
# NUOVO: CHARACTER STATS SYSTEM
# ============================================
var character_stats: CharacterStats = null

# ============================================
# GATHERING SKILLS SYSTEM
# ============================================
var gathering_skills: GatheringSkillsManager = null

# Equipment slots
var equipped_items := {
	"helmet": null,
	"weapon": null,
	"chest": null,
	"shield": null,
	"belt": null,
	"boots": null,
}

# Nuovi segnali per stats
signal on_stats_changed()
signal on_item_equipped(slot: String, item_data: Dictionary)
signal on_item_unequipped(slot: String, item_data: Dictionary)

# ============================================
# VARIABILI ESISTENTI
# ============================================

var skills := {}         # skill_id -> Skill (Resource)
var resources := {"gold": 0}
var inventory := {}      # item_id -> count

# NEW: Inventory item positions and stack info
# Format: [ {"item_id": "...", "pos": Vector2i(x,y), "stack_count": N}, ... ]
var inventory_items := []

# NEW: Equipped bags in bag slots
# Format: [{\"item_id\": \"...\", \"bag_slots\": N}, null, null, ...] (5 slots total)
var equipped_bags := []

# NEW: Passive skill tree (LEGACY - keep for backwards compatibility)
var passive_points: int = 0  # Available points to spend (CHANGED: was 5, now 0 - earned by leveling)
var activated_passives: Array = []  # List of activated passive IDs

# NEW: Passive skill tree by category
# Points now earned through leveling:
# - "main": +1 point per combat level
# - "mining/herbalism/fishing": +1 point per gathering skill level
var passive_points_by_category: Dictionary = {
	"main": 0,
	"mining": 0,
	"herbalism": 0,
	"fishing": 0
}

# User preferences
var auto_continue_battles: bool = true  # Auto-continue to next battle after victory
var activated_passives_by_category: Dictionary = {
	"main": [],
	"mining": [],
	"herbalism": [],
	"fishing": []
}

var data := {
	"items": {},
	"recipes": {},
	"mobs": {},
	"areas": {},
	"loot_tables": {},
	"actions": {},
	"promotions": [],
	"npcs": {},
	"skills": {}
}

# crafting (come prima)
var craft_queue := []
var max_queue := 3

# combat (come prima, con bonus applicati)
var combat_active := false
var current_area := ""
var current_mob := ""
var enemy_hp := 0.0
var kills := 0

# player/global bonuses (per es. da promozioni/azioni)
var bonus_dps_add := 0.0
var bonus_dps_mult := 0.0

# base combat
var base_dps := 5.0

# ACTION SYSTEM (skill tab)
var current_action_id: String = ""
var action_time_left: float = 0.0
var action_time_total: float = 0.0

var _tick_accum := 0.0
var _tick_rate := 1.0
var current_slot: int = 1
var play_time: float = 0.0
var SAVE_PATH: String = "user://save_slot_1.dat"  # Updated by set_active_slot()

# CRITICAL: Prevent concurrent saves
var _is_saving := false

var rng := RandomNumberGenerator.new()

# Autosave system
var autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL: float = 5.0  # Autosave every 5 seconds

func _ready() -> void:
	rng.randomize()
	_migrate_old_save()
	SAVE_PATH = get_save_path(current_slot)
	_load_default_data()

	# NUOVO: Inizializza character stats
	character_stats = CharacterStats.new()
	character_stats.stats_changed.connect(_on_character_stat_changed)
	character_stats.hp_changed.connect(_on_hp_changed)
	character_stats.mana_changed.connect(_on_mana_changed)
	character_stats.level_up.connect(_on_combat_level_up)
	print("[GameState] Character stats initialized")

	# NUOVO: Inizializza gathering skills
	gathering_skills = GatheringSkillsManager.new()
	gathering_skills.skill_level_up.connect(_on_gathering_skill_level_up)
	print("[GameState] Gathering skills initialized")

	load_game()
	set_process(true)
	print("[GameState] Autosave enabled - saving every %d seconds" % AUTOSAVE_INTERVAL)

func _notification(what: int) -> void:
	"""Save game when closing"""
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("[GameState] 💾 Saving before closing...")
		save_game()
		print("[GameState] ✅ Game saved")

func _process(delta: float) -> void:
	play_time += delta
	_tick_accum += delta
	if _tick_accum >= _tick_rate:
		_tick_accum = 0.0
		_tick()

	# NUOVO: Aggiorna stats temporanee
	if character_stats:
		character_stats.update_temporary_modifiers(delta)

	# Autosave timer
	autosave_timer += delta
	if autosave_timer >= AUTOSAVE_INTERVAL:
		autosave_timer = 0.0
		save_game()
		print("[GameState] ✅ Autosaved")

func _tick() -> void:
	_tick_skills_legacy()   # mantiene vecchio training se lo usi
	_tick_crafting()
	_tick_combat()
	_tick_action()
	on_tick.emit(_tick_rate)

# -------- ACTION LOOP --------
func start_action(action_id: String) -> bool:
	if not data.actions.has(action_id): return false
	var a = data.actions[action_id]
	var s: Skill = skills.get(a.skill_id, null)
	if s == null: return false
	# requisiti livello
	var req_level = int(a.req.get("level", 1))
	if s.level < req_level: return false
	# costi iniziali
	if a.has("costs"):
		for k in a.costs.keys():
			if inventory.get(k, 0) < int(a.costs[k]):
				return false
		for k in a.costs.keys():
			_remove_item(k, int(a.costs[k]))
	current_action_id = action_id
	action_time_total = float(a.time)
	action_time_left = action_time_total
	on_action_started.emit(action_id)
	return true

func cancel_action() -> void:
	current_action_id = ""
	action_time_left = 0.0
	action_time_total = 0.0
	

func _tick_action() -> void:
	if current_action_id == "": return
	action_time_left -= _tick_rate
	on_action_progress.emit(current_action_id, action_time_left, action_time_total)
	if action_time_left <= 0.0:
		var a = data.actions[current_action_id]
		# ricompense
		if a.rewards.has("items"):
			for k in a.rewards.items.keys():
				_add_item(k, int(a.rewards.items[k]))
		var xp_gain = float(a.rewards.get("xp", 0))
		if xp_gain > 0.0:
			_gain_skill_xp(a.skill_id, xp_gain)
		# bonuses opzionali
		if a.rewards.has("bonuses"):
			for b in a.rewards.bonuses:
				_apply_bonus(b)
		on_action_finished.emit(current_action_id)
		# azione continua (idle) → riparte automaticamente
		action_time_left = action_time_total

func _gain_skill_xp(skill_id: String, amount: float) -> void:
	var s: Skill = skills[skill_id]
	s.xp += amount
	# curva xp semplificata
	var need := _xp_required(s.xp_curve, s.level, s.grade)
	while s.xp >= need:
		s.xp -= need
		s.level += 1
		on_skill_level_up.emit(skill_id, s.level)
		need = _xp_required(s.xp_curve, s.level, s.grade)

func _xp_required(curve: String, level: int, grade: String) -> float:
	var g_mult := 1.0
	match grade:
		"A": g_mult = 1.2
		"M": g_mult = 1.5
		"G": g_mult = 1.8
		_ : g_mult = 1.0
	match curve:
		"linear_easy":
			return g_mult * (20.0 + 5.0 * level)
		"craft_slow":
			return g_mult * (30.0 + 8.0 * level)
		"combat_std":
			return g_mult * (25.0 + 6.0 * level)
		_:
			return g_mult * (20.0 + 5.0 * level)

func try_promotion(skill_id: String) -> void:
	var s: Skill = skills.get(skill_id, null)
	if s == null:
		return

	var next_map = {"N":"A","A":"M","M":"G"}
	if not next_map.has(s.grade):
		on_promotion_result.emit(skill_id, false, "Grado massimo.")
		return

	var target = next_map[s.grade]

	# trova la promozione compatibile
	for p in data.promotions:
		if p.skill_id == skill_id and p.from == s.grade and p.to == target:
			# requisiti di livello
			var lvl_req = int(p.req.get("level", 1))
			if s.level < lvl_req:
				on_promotion_result.emit(skill_id, false, "Livello insufficiente.")
				return

			# requisiti oggetti
			var consumed := {}
			if p.req.has("items"):
				for k in p.req.items.keys():
					var need := int(p.req.items[k])
					if inventory.get(k, 0) < need:
						on_promotion_result.emit(skill_id, false, "Oggetti mancanti.")
						return
				# consuma prima del roll (ma teniamo traccia per eventuale rimborso)
				for k in p.req.items.keys():
					var need := int(p.req.items[k])
					consumed[k] = need
					_remove_item(k, need)

			# roll della promozione
			var chance = float(p.get("chance", 1.0))
			var ok = rng.randf() <= chance

			if ok:
				s.grade = target
				if p.has("on_success") and p.on_success.has("bonuses"):
					for b in p.on_success.bonuses:
						_apply_bonus(b)
				on_promotion_result.emit(skill_id, true, "Promosso a %s!" % target)
			else:
				# Rimborso materiali se indicato (consume=false)
				if p.req.has("items") and p.has("on_fail") and not bool(p.on_fail.get("consume", false)):
					for k in consumed.keys():
						_add_item(k, int(consumed[k]))
				on_promotion_result.emit(skill_id, false, "Promozione fallita.")
			return

	on_promotion_result.emit(skill_id, false, "Nessuna promozione disponibile.")


func _apply_bonus(b: Dictionary) -> void:
	match String(b.get("type","")):
		"dps_add":
			bonus_dps_add += float(b.get("value",0.0))
		"dps_mult":
			bonus_dps_mult += float(b.get("value",0.0))
		_:
			pass

# -------- LEGACY SKILLS (compatibilità col vecchio training, opzionale) --------
func _tick_skills_legacy() -> void:
	for s in skills.values():
		if s.is_training and s.rate > 0.0:
			s.progress += s.rate
			if s.progress >= s.threshold:
				s.progress = 0.0
				s.level += 1
				resources.gold += s.reward_gold
				for item_id in s.yields.keys():
					_add_item(item_id, int(s.yields[item_id]))

# -------- Crafting / Combat (come prima, con bonus dps) --------
func _tick_crafting() -> void:
	if craft_queue.is_empty(): return
	var entry = craft_queue[0]
	entry.time_left -= _tick_rate
	if entry.time_left <= 0.0:
		var r = data.recipes[entry.recipe_id]
		for k in r.outputs.keys():
			_add_item(k, int(r.outputs[k]))
		craft_queue.pop_front()
		on_craft_updated.emit()

func start_craft(recipe_id: String) -> bool:
	if not data.recipes.has(recipe_id):
		return false
	if craft_queue.size() >= int(max_queue):
		return false

	var r = data.recipes[recipe_id]
	if r.has("inputs"):
		for k in r.inputs.keys():
			if inventory.get(k, 0) < int(r.inputs[k]):
				return false
		for k in r.inputs.keys():
			_remove_item(k, int(r.inputs[k]))

	craft_queue.append({ "recipe_id": recipe_id, "time_left": float(r.time) })
	on_craft_updated.emit()
	return true

func _tick_combat() -> void:
	if not combat_active or current_mob == "": return
	var combat_level := 1
	if skills.has("swordsmanship"):
		combat_level = skills["swordsmanship"].level
	var player_dps = (base_dps + 0.5 * combat_level + bonus_dps_add) * (1.0 + bonus_dps_mult)
	enemy_hp -= player_dps
	if enemy_hp <= 0.0:
		_handle_kill(data.mobs[current_mob])
		_spawn_enemy()

func _handle_kill(mob: Dictionary) -> void:
	kills += 1
	var table = data.loot_tables[mob.loot_table_id]
	for drop in table.drops:
		if rng.randf() <= float(drop.chance):
			var qty = rng.randi_range(int(drop.min), int(drop.max))
			_add_item(drop.item_id, qty)
	on_combat_event.emit("Defeated %s (total kills: %d)" % [mob.name, kills])

func set_area(area_id: String) -> void:
	if not data.areas.has(area_id): return
	current_area = area_id
	var arr = data.areas[area_id].mobs
	if arr.size() > 0: set_mob(arr[0])

func set_mob(mob_id: String) -> void:
	if not data.mobs.has(mob_id): return
	current_mob = mob_id
	if combat_active: _spawn_enemy()

func toggle_combat(active: bool) -> void:
	combat_active = active
	if active: _spawn_enemy()

func _spawn_enemy() -> void:
	if current_mob == "": return
	enemy_hp = float(data.mobs[current_mob].hp)

# -------- Inventory helpers --------
func _add_item(item_id: String, amount: int) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + amount
	on_inventory_changed.emit()

func _remove_item(item_id: String, amount: int) -> void:
	var have := int(inventory.get(item_id, 0))
	var left := have - int(amount)
	if left <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = left
	on_inventory_changed.emit()

func add_gold(amount: int) -> void:
	"""Add gold to player resources"""
	if amount <= 0:
		return
	resources["gold"] = int(resources.get("gold", 0)) + amount
	if GameLogger.ENABLED:
		print("[GameState] 💰 Added %d gold (total: %d)" % [amount, resources["gold"]])

func remove_gold(amount: int) -> bool:
	"""Remove gold from player resources. Returns true if successful."""
	var current = int(resources.get("gold", 0))
	if current < amount:
		if GameLogger.ENABLED:
			print("[GameState] ⚠️ Not enough gold! Have: %d, Need: %d" % [current, amount])
		return false
	resources["gold"] = current - amount
	if GameLogger.ENABLED:
		print("[GameState] 💸 Removed %d gold (remaining: %d)" % [amount, resources["gold"]])
	return true

func get_gold() -> int:
	"""Get current gold amount"""
	return int(resources.get("gold", 0))

# ============================================
# NUOVO: EQUIPMENT MANAGEMENT
# ============================================

func equip_item_to_slot(item_id: String, slot: String) -> bool:
	"""Equipaggia un item da inventory a equipment slot"""
	if not data.items.has(item_id):
		print("[GameState] Item non trovato: ", item_id)
		return false

	# Get BASE item data from database
	var item_data = data.items[item_id].duplicate(true)

	# CRITICAL: Search for this item in inventory_items to get bonuses and upgrade_level
	for inv_item in inventory_items:
		if inv_item.get("item_id") == item_id:
			print("[GameState] 📦 Found item in inventory_items with upgrades/bonuses")

			# Apply bonuses from inventory
			if inv_item.has("bonuses"):
				item_data["bonuses"] = inv_item.bonuses
				print("[GameState] → Applied %d bonuses" % inv_item.bonuses.size())

			# CRITICAL: Apply enhancement_level (for particle effects)
			if inv_item.has("enhancement_level"):
				item_data["enhancement_level"] = inv_item.enhancement_level
				print("[GameState] → Item has enhancement level +%d (for visual effects)" % inv_item.enhancement_level)

			# Apply upgrade_level and RECALCULATE stats
			if inv_item.has("upgrade_level"):
				var upgrade_level = inv_item.upgrade_level
				item_data["upgrade_level"] = upgrade_level
				print("[GameState] → Item is at upgrade level +%d" % upgrade_level)

				# RECALCULATE stats with upgrade bonus (same formula as ForgeUI/InventoryTab)
				if item_data.has("stats") and upgrade_level > 0:
					const STAT_BOOST_PER_LEVEL = 0.05  # 5% boost per upgrade level

					# Save original stats
					if not item_data.has("base_stats"):
						item_data["base_stats"] = item_data["stats"].duplicate(true)

					var base_stats = item_data["base_stats"]
					var multiplier = 1.0 + (upgrade_level * STAT_BOOST_PER_LEVEL)

					# Recalculate stats
					var boosted_stats = {}
					for stat_key in base_stats.keys():
						boosted_stats[stat_key] = int(base_stats[stat_key] * multiplier)

					item_data["stats"] = boosted_stats
					print("[GameState] → Stats boosted by %d%%" % (int(multiplier * 100) - 100))

			break  # Found the item, stop searching

	# Apply bonuses from gems to stats (if any)
	if item_data.has("bonuses") and item_data.bonuses.size() > 0:
		print("[GameState] 💎 Applying %d gem bonuses to stats" % item_data.bonuses.size())

		const ItemBonus = preload("res://scripts/crafting/ItemBonus.gd")

		for bonus_dict in item_data.bonuses:
			var bonus = ItemBonus.new()
			bonus.from_dict(bonus_dict)

			# Apply bonus based on type
			match bonus.bonus_stat:
				ItemBonus.BonusStat.PHYSICAL_DAMAGE:
					if item_data["stats"].has("physical_damage"):
						var current = item_data["stats"]["physical_damage"]
						item_data["stats"]["physical_damage"] = int(current * (1.0 + bonus.value1 / 100.0))
						print("[GameState] → Physical Damage: %d → %d (+%.1f%%)" % [current, item_data["stats"]["physical_damage"], bonus.value1])

				ItemBonus.BonusStat.ATTACK_SPEED:
					# Attack speed is usually stored differently, but if it exists:
					if item_data["stats"].has("attack_speed"):
						var current = item_data["stats"]["attack_speed"]
						item_data["stats"]["attack_speed"] = current * (1.0 + bonus.value1 / 100.0)
						print("[GameState] → Attack Speed: %.1f → %.1f (+%.1f%%)" % [current, item_data["stats"]["attack_speed"], bonus.value1])

				ItemBonus.BonusStat.HP_REGEN:
					# HP Regen bonus (usually a new stat)
					if not item_data["stats"].has("hp_regen"):
						item_data["stats"]["hp_regen"] = 0
					item_data["stats"]["hp_regen"] += bonus.value1
					print("[GameState] → HP Regen: +%.1f" % bonus.value1)

				ItemBonus.BonusStat.AUTO_HEAL_ON_DAMAGE:
					# Special bonus (stored separately, not in stats)
					if not item_data.has("special_effects"):
						item_data["special_effects"] = []
					item_data["special_effects"].append({
						"type": "auto_heal",
						"chance": bonus.value1,
						"heal": bonus.value2
					})
					print("[GameState] → Auto Heal: %.1f%% chance to heal %.1f HP" % [bonus.value1, bonus.value2])

	# Verifica che l'item possa essere equipaggiato in questo slot
	var item_slot = item_data.get("slot", "none")
	if item_slot != slot and item_slot != "any":
		print("[GameState] Item non compatibile con slot: ", item_id, " -> ", slot)
		return false

	# Se c'è già qualcosa equipaggiato, unequip prima
	if equipped_items[slot] != null:
		unequip_item_from_slot(slot)

	# Equipaggia
	equipped_items[slot] = item_data

	# Applica stats (now with upgrades and bonuses!)
	if item_data.has("stats"):
		character_stats.apply_equipment_stats(item_data.stats)
	
	# Rimuovi dall'inventario
	_remove_item(item_id, 1)
	
	on_item_equipped.emit(slot, item_data)
	on_stats_changed.emit()

	print("[GameState] Equipped: ", item_data.get("name", item_id), " in ", slot)
	return true

func _add_item_to_visual_inventory(item_id: String, item_data: Dictionary) -> bool:
	"""Add an item to visual inventory system (inventory_items array with position)
	Used by ExplorationCombatController to add drops after combat.

	Args:
		item_id: The item ID from database
		item_data: Full item data including bonuses, upgrade_level, etc.

	Returns:
		true if item was added successfully, false if inventory is full
	"""
	print("[GameState] 📦 _add_item_to_visual_inventory called: %s" % item_id)

	# Get base item data from database if not provided
	var full_item_data = item_data.duplicate(true) if not item_data.is_empty() else {}

	# Merge with database data (item_data overrides database for bonuses/upgrades)
	if data.items.has(item_id):
		var db_data = data.items[item_id].duplicate(true)
		# Merge database properties first, then override with item_data
		for key in db_data.keys():
			if not full_item_data.has(key):
				full_item_data[key] = db_data[key]
	else:
		push_error("[GameState] Item not found in database: %s" % item_id)
		return false

	# Get item size
	var item_size = Vector2i(1, 1)
	if full_item_data.has("size") and full_item_data.size is Array and full_item_data.size.size() >= 2:
		item_size = Vector2i(full_item_data.size[0], full_item_data.size[1])

	# Check if item is stackable
	var is_stackable = full_item_data.get("stackable", false)
	var max_stack = full_item_data.get("max_stack", 99)
	var amount = 1  # Always add 1 item at a time from drops

	# OLD FORMAT: Update count (for compatibility)
	if not inventory.has(item_id):
		inventory[item_id] = 0
	inventory[item_id] += amount

	# NEW FORMAT: Add to inventory_items with position
	var items_were_stacked = false  # Track if we modified existing stacks
	if is_stackable:
		# Try to stack with existing items first
		var stacked_amount = 0
		for inv_item in inventory_items:
			if inv_item.get("item_id") == item_id:
				var current_stack = inv_item.get("stack_count", 1)
				if current_stack < max_stack:
					var can_add = min(amount - stacked_amount, max_stack - current_stack)
					inv_item["stack_count"] = current_stack + can_add
					stacked_amount += can_add
					items_were_stacked = true
					print("[GameState] 📦 Stacked +%d %s (now %d)" % [can_add, item_id, inv_item["stack_count"]])

					if stacked_amount >= amount:
						break  # All items stacked

		amount = amount - stacked_amount  # Remaining items to add as new stacks

	# If items were stacked and no new items need to be added, emit signal now
	if items_were_stacked and amount <= 0:
		print("[GameState] 📢 Emitting on_inventory_changed signal (after stacking)...")
		on_inventory_changed.emit()
		print("[GameState] 📢 Signal emitted. Connected listeners: %d" % on_inventory_changed.get_connections().size())
		return true

	# Add remaining items as new entries
	while amount > 0:
		var stack_size = min(amount, max_stack) if is_stackable else 1

		# Find first empty position in inventory
		var pos = _find_empty_inventory_position(item_size)
		if pos != Vector2i(-1, -1):
			# Add to inventory_items
			var new_item = {
				"item_id": item_id,
				"pos": {"x": pos.x, "y": pos.y},  # Dictionary format for JSON compatibility
				"stack_count": stack_size
			}

			# Include bonuses if present (for crafted/upgraded items)
			if full_item_data.has("bonuses") and full_item_data.bonuses.size() > 0:
				new_item["bonuses"] = full_item_data.bonuses

			# Include upgrade_level if present (for upgraded items)
			if full_item_data.has("upgrade_level") and full_item_data.upgrade_level > 0:
				new_item["upgrade_level"] = full_item_data.upgrade_level

			inventory_items.append(new_item)
			print("[GameState] ✅ Added %s x%d at position %s" % [item_id, stack_size, pos])

			# Emit signal to refresh inventory UI
			print("[GameState] 📢 Emitting on_inventory_changed signal...")
			on_inventory_changed.emit()
			print("[GameState] 📢 Signal emitted. Connected listeners: %d" % on_inventory_changed.get_connections().size())

			amount -= stack_size
			return true
		else:
			push_error("[GameState] ❌ No space in inventory for %s! Lost %d items" % [item_id, amount])
			return false

	return true

func _find_empty_inventory_position(item_size: Vector2i) -> Vector2i:
	"""Find first available position in inventory grid for an item of given size

	Args:
		item_size: Size of item in grid cells (e.g. Vector2i(1, 2) for a 1x2 sword)

	Returns:
		Vector2i position of first available slot, or Vector2i(-1, -1) if no space
	"""
	# Get inventory grid dimensions
	# Base: 6x5 (30 slots)
	# + bags (each bag adds rows)
	var cols = 6
	var base_rows = 5

	# Calculate total rows based on equipped bags
	var total_slots = base_rows * cols  # Start with base
	for bag_data in equipped_bags:
		if bag_data != null and bag_data.has("bag_slots"):
			total_slots += bag_data.bag_slots

	var rows = ceili(float(total_slots) / float(cols))

	# Build occupancy grid from existing inventory_items
	var grid_occupied = []
	for y in range(rows):
		var row = []
		for x in range(cols):
			row.append(false)
		grid_occupied.append(row)

	# Mark occupied cells
	for inv_item in inventory_items:
		var pos = inv_item.get("pos")
		var inv_item_id = inv_item.get("item_id", "")

		# Convert Dictionary to Vector2i if needed
		var pos_vec: Vector2i
		if pos is Dictionary:
			pos_vec = Vector2i(pos.get("x", 0), pos.get("y", 0))
		else:
			pos_vec = pos

		# Get item size from database
		var inv_item_data = data.items.get(inv_item_id, {})
		var inv_item_size = Vector2i(1, 1)
		if inv_item_data.has("size") and inv_item_data.size is Array and inv_item_data.size.size() >= 2:
			inv_item_size = Vector2i(inv_item_data.size[0], inv_item_data.size[1])

		# Mark all cells occupied by this item
		for y in range(pos_vec.y, min(pos_vec.y + inv_item_size.y, rows)):
			for x in range(pos_vec.x, min(pos_vec.x + inv_item_size.x, cols)):
				if y < rows and x < cols:
					grid_occupied[y][x] = true

	# Find first empty position that fits the item
	for y in range(rows):
		for x in range(cols):
			# Check if item fits at this position
			if x + item_size.x > cols or y + item_size.y > rows:
				continue  # Doesn't fit

			# Check if all required cells are free
			var can_place = true
			for dy in range(item_size.y):
				for dx in range(item_size.x):
					if grid_occupied[y + dy][x + dx]:
						can_place = false
						break
				if not can_place:
					break

			if can_place:
				return Vector2i(x, y)

	# No space found
	return Vector2i(-1, -1)

func unequip_item_from_slot(slot: String) -> bool:
	"""Rimuove un item da un equipment slot"""
	if not equipped_items.has(slot) or equipped_items[slot] == null:
		return false
	
	var item_data = equipped_items[slot]
	var item_id = item_data.get("id", "unknown")
	
	# Rimuovi stats
	if item_data.has("stats"):
		character_stats.remove_equipment_stats(item_data.stats)
	
	# Rimetti in inventory
	_add_item(item_id, 1)
	
	# Clear slot
	equipped_items[slot] = null
	
	on_item_unequipped.emit(slot, item_data)
	on_stats_changed.emit()
	
	print("[GameState] Unequipped: ", item_data.get("name", item_id), " from ", slot)
	return true

func get_equipped_item(slot: String) -> Dictionary:
	"""Ottiene l'item equipaggiato in uno slot"""
	return equipped_items.get(slot, {}) if equipped_items.get(slot) != null else {}

func get_total_attack() -> float:
	"""Calcola attacco totale (per compatibilità col combat esistente)"""
	return character_stats.get_stat("physical_damage") + character_stats.get_stat("strength") * 0.5

func get_total_defense() -> float:
	"""Calcola difesa totale (per compatibilità)"""
	return character_stats.get_stat("physical_defense") + character_stats.get_stat("vitality") * 0.3

# -------- CALLBACKS STATS --------

func _on_character_stat_changed(stat_name: String, old_value, new_value):
	on_stats_changed.emit()

func _on_hp_changed(current: float, maximum: float):
	if current <= 0:
		_on_character_death()

func _on_mana_changed(current: float, maximum: float):
	pass

func _on_character_death():
	print("[GameState] Character died!")
	combat_active = false

# -------- LEVEL UP CALLBACKS --------

func _on_combat_level_up(new_level: int):
	"""Called when player levels up (combat)"""
	print("[GameState] 🎉 LEVEL UP! New level: %d" % new_level)

	# Award +1 passive point for "main" category
	passive_points_by_category["main"] += 1
	print("[GameState] +1 passive point for 'main' category (total: %d)" % passive_points_by_category["main"])

	# Update legacy passive_points too
	passive_points += 1

func _on_gathering_skill_level_up(skill_name: String, new_level: int):
	"""Called when a gathering skill levels up"""
	print("[GameState] 🎉 %s LEVEL UP! New level: %d" % [skill_name.capitalize(), new_level])

	# Award +1 passive point for the skill's category
	if passive_points_by_category.has(skill_name):
		passive_points_by_category[skill_name] += 1
		print("[GameState] +1 passive point for '%s' category (total: %d)" %
			[skill_name, passive_points_by_category[skill_name]])

# -------- Data loading --------
func _read_json_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	return parsed if typeof(parsed) == TYPE_ARRAY else []

func _read_json_dict(path: String, key: String) -> Dictionary:
	var arr: Array = _read_json_array(path)
	var d := {}
	for it in arr: d[it[key]] = it
	return d

func _load_default_data() -> void:
	data.items = _read_json_dict("res://data/items.json", "id")
	data.recipes = _read_json_dict("res://data/recipes.json", "id")
	data.mobs = _read_json_dict("res://data/mobs.json", "id")
	data.areas = _read_json_dict("res://data/areas.json", "id")
	data.loot_tables = _read_json_dict("res://data/loot_tables.json", "id")
	data.actions = _read_json_dict("res://data/actions.json", "id")
	data.npcs = _read_json_dict("res://data/npcs.json", "id")
	data.promotions = _read_json_array("res://data/promotions.json")
	# Skills
	var skills_arr = _read_json_array("res://data/skills.json")
	for d in skills_arr:
		var s = Skill.new()
		s.id = d.id; s.name = d.name; s.category = d.category
		s.grade = d.grade; s.level = d.level; s.xp = float(d.xp)
		s.xp_curve = d.xp_curve; s.actions = d.actions; s.bonuses = d.bonuses
		s.icon = d.get("icon","")
		skills[s.id] = s

		# Also store in data.skills for Skills Tab UI
		data.skills[s.id] = {
			"id": d.id,
			"name": d.name,
			"category": d.category,
			"grade": d.grade,
			"level": d.level,
			"xp": float(d.xp),
			"xp_curve": d.xp_curve,
			"actions": d.actions,
			"bonuses": d.bonuses,
			"icon": d.get("icon", ""),
			"skill_data": d.get("skill_data", {})
		}

# -------- Save/Load --------
func save_game() -> void:
	# CRITICAL: Prevent concurrent saves
	if _is_saving:
		print("[GameState] ⚠️ Save already in progress, skipping...")
		return

	_is_saving = true
	print("[GameState] 💾 Saving game with store_var()...")

	# Prepare skills dict
	var skills_data = {}
	for k in skills.keys():
		var s: Skill = skills[k]
		skills_data[k] = {"level": s.level, "xp": s.xp, "grade": s.grade}

	# Get quest data from QuestSystem
	var quest_data = {}
	if has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		quest_data = quest_system.to_dict()

	# Single dictionary with ALL game state
	var save_data = {
		"version": 1,  # Save format version
		"save_time": int(Time.get_unix_time_from_system()),
		"play_time": play_time,
		"resources": resources,
		"inventory": inventory,
		"inventory_items": inventory_items,  # NATIVE support for Array/Dict/Vector2i!
		"equipped_items": equipped_items,    # NATIVE support - bonuses included automatically!
		"equipped_bags": equipped_bags,
		"passive_points": passive_points,
		"activated_passives": activated_passives,
		"passive_points_by_category": passive_points_by_category,
		"activated_passives_by_category": activated_passives_by_category,
		"skills": skills_data,
		"craft_queue": craft_queue,
		"current_area": current_area,
		"current_mob": current_mob,
		"enemy_hp": enemy_hp,
		"kills": kills,
		"combat_active": combat_active,
		"current_action_id": current_action_id,
		"action_time_left": action_time_left,
		"action_time_total": action_time_total,
		"bonus_dps_add": bonus_dps_add,
		"bonus_dps_mult": bonus_dps_mult,
		"character_stats": character_stats.to_dict() if character_stats else {},
		"gathering_skills": gathering_skills.to_dict() if gathering_skills else {},
		"quests": quest_data
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("[GameState] ❌ Failed to open save file: %s" % SAVE_PATH)
		_is_saving = false
		return

	# MAGIC: store_var() handles EVERYTHING automatically!
	# Vector2i, Arrays, Dictionaries, nested structures - all native!
	file.store_var(save_data)
	file.close()

	# Count only non-null equipped items
	var equipped_count = 0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			equipped_count += 1

	print("[GameState] ✅ Game saved successfully!")
	print("  → %d inventory items" % inventory_items.size())
	print("  → %d equipped items" % equipped_count)

	# DEBUG: Print equipped items details
	if equipped_count > 0:
		print("[GameState] 🔍 DEBUG - Equipped items:")
		for slot in equipped_items.keys():
			if equipped_items[slot] != null:
				var item = equipped_items[slot]
				print("  → %s: %s (id: %s)" % [slot, item.get("name", "?"), item.get("id", "?")])

	# DEBUG: Check if equipped items are ALSO in inventory_items (using instance_id)
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			var equipped_instance_id = equipped_items[slot].get("instance_id", "")
			var equipped_id = equipped_items[slot].get("id")

			# Only check if we have an instance_id (new system)
			if equipped_instance_id != "":
				for inv_item in inventory_items:
					var inv_instance_id = inv_item.get("instance_id", "")
					# Compare by instance_id - if the SAME instance is in both places, warn
					if inv_instance_id != "" and inv_instance_id == equipped_instance_id:
						var pos_str = "unknown"
						if inv_item.has("pos"):
							var pos_dict = inv_item["pos"]
							var pos = Vector2i(pos_dict.get("x", -1), pos_dict.get("y", -1))
							pos_str = str(pos)
						print("[GameState] ⚠️ WARNING: Same item instance '%s' (instance_id: %s) is BOTH equipped in slot '%s' AND in inventory at %s!" % [equipped_id, equipped_instance_id, slot, pos_str])

	_is_saving = false

func load_game() -> void:
	print("[GameState] 📂 Loading game with get_var()...")

	if not FileAccess.file_exists(SAVE_PATH):
		print("[GameState] ⚠️ No save file found, starting fresh")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[GameState] ❌ Failed to open save file!")
		return

	# MAGIC: get_var() loads EVERYTHING with native types restored!
	var save_data = file.get_var()
	file.close()

	if typeof(save_data) != TYPE_DICTIONARY:
		push_error("[GameState] ❌ Invalid save data!")
		return

	# Direct assignment - no conversion needed!
	resources = save_data.get("resources", resources)
	inventory = save_data.get("inventory", inventory)
	inventory_items = save_data.get("inventory_items", [])  # Vector2i positions restored automatically!
	equipped_items = save_data.get("equipped_items", {})    # Bonuses included automatically!
	equipped_bags = save_data.get("equipped_bags", [])
	passive_points = save_data.get("passive_points", 0)
	activated_passives = save_data.get("activated_passives", [])
	passive_points_by_category = save_data.get("passive_points_by_category", {
		"main": 0,
		"mining": 0,
		"herbalism": 0,
		"fishing": 0
	})
	activated_passives_by_category = save_data.get("activated_passives_by_category", {
		"main": [],
		"mining": [],
		"herbalism": [],
		"fishing": []
	})
	craft_queue = save_data.get("craft_queue", [])
	current_area = save_data.get("current_area", current_area)
	current_mob = save_data.get("current_mob", current_mob)
	enemy_hp = save_data.get("enemy_hp", 0.0)
	kills = save_data.get("kills", 0)
	combat_active = save_data.get("combat_active", false)
	current_action_id = save_data.get("current_action_id", "")
	action_time_left = save_data.get("action_time_left", 0.0)
	action_time_total = save_data.get("action_time_total", 0.0)
	bonus_dps_add = save_data.get("bonus_dps_add", 0.0)
	bonus_dps_mult = save_data.get("bonus_dps_mult", 0.0)
	play_time = save_data.get("play_time", 0.0)

	# Load character stats
	if save_data.has("character_stats") and character_stats:
		character_stats.from_dict(save_data.character_stats)

		# CRITICAL FIX: Clear equipment bonuses to prevent double-apply bug
		# The save file contains equipment_bonuses from when it was saved,
		# but we need to recalculate them from currently equipped items
		for stat in character_stats.equipment_bonuses.keys():
			character_stats.equipment_bonuses[stat] = 0 if typeof(character_stats.base_stats[stat]) == TYPE_INT else 0.0

		if GameLogger.ENABLED:
			print("[GameState] Cleared equipment bonuses (will be recalculated)")

	# Load gathering skills
	if save_data.has("gathering_skills") and gathering_skills:
		gathering_skills.from_dict(save_data.gathering_skills)

	# Load quests
	if save_data.has("quests") and has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		quest_system.from_dict(save_data.quests)

	# Load skills
	var saved_skills = save_data.get("skills", {})
	for k in saved_skills.keys():
		if skills.has(k):
			var s: Skill = skills[k]
			var d = saved_skills[k]
			s.level = d.get("level", s.level)
			s.xp = d.get("xp", s.xp)
			s.grade = d.get("grade", s.grade)

	# Re-apply equipment stats from currently equipped items
	var equipment_count = 0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null and equipped_items[slot].has("stats"):
			character_stats.apply_equipment_stats(equipped_items[slot].stats)
			equipment_count += 1
			if GameLogger.ENABLED:
				print("[GameState] Re-applied stats from %s: %s" % [slot, equipped_items[slot].get("name", "Unknown")])

	if GameLogger.ENABLED:
		print("[GameState] Re-applied %d equipped items" % equipment_count)

	# Count only non-null equipped items
	var equipped_count = 0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			equipped_count += 1

	print("[GameState] ✅ Game loaded successfully!")
	print("  → %d inventory items" % inventory_items.size())
	print("  → %d equipped items" % equipped_count)

	# DEBUG: Print loaded equipped items
	if equipped_count > 0:
		print("[GameState] 🔍 DEBUG - Loaded equipped items:")
		for slot in equipped_items.keys():
			if equipped_items[slot] != null:
				var item = equipped_items[slot]
				print("  → %s: %s (id: %s)" % [slot, item.get("name", "?"), item.get("id", "?")])

	# DEBUG: Check if equipped items are ALSO in loaded inventory_items
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			var equipped_id = equipped_items[slot].get("id")
			for inv_item in inventory_items:
				if inv_item.get("item_id") == equipped_id or inv_item.get("id") == equipped_id:
					print("[GameState] ⚠️ WARNING: Loaded equipped item '%s' is ALSO in inventory_items!" % equipped_id)
					print("[GameState]   This means the item was NOT removed from inventory when equipped!")

	# IMPORTANT: Don't emit signals here - UI isn't ready yet!
	# CharacterDisplay will call refresh_equipped_items() when it connects

func refresh_equipped_items() -> void:
	"""Emit on_item_equipped signals for all equipped items
	Called by CharacterDisplay when it connects to signals after load"""
	print("[GameState] 🔄 Refreshing equipped items UI...")

	var signals_emitted = 0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			print("[GameState] 📢 Emitting on_item_equipped for %s: %s" % [slot, equipped_items[slot].get("name", "Unknown")])
			on_item_equipped.emit(slot, equipped_items[slot])
			signals_emitted += 1

	print("[GameState] ✅ Refreshed %d equipped items" % signals_emitted)

func fix_equipment_bonuses() -> void:
	"""Emergency fix: Recalculate equipment bonuses from scratch"""
	if not character_stats:
		return

	print("\n[GameState] 🔧 FIXING EQUIPMENT BONUSES...")

	# Clear all bonuses
	for stat in character_stats.equipment_bonuses.keys():
		character_stats.equipment_bonuses[stat] = 0 if typeof(character_stats.base_stats[stat]) == TYPE_INT else 0.0

	print("  ✓ Cleared all equipment bonuses")

	# Re-apply from equipped items
	var count = 0
	for slot in equipped_items.keys():
		if equipped_items[slot] != null and equipped_items[slot].has("stats"):
			character_stats.apply_equipment_stats(equipped_items[slot].stats)
			count += 1
			print("  ✓ Re-applied: %s (%s)" % [slot, equipped_items[slot].get("name", "Unknown")])

	print("  ✓ Total items re-applied: %d" % count)
	print("\n[GameState] ✅ FIX COMPLETE!")
	print("  New Attack: %.1f" % get_total_attack())
	print("  New Defense: %.1f" % get_total_defense())
	print("  Strength: %d (base: %d + equip: %d)" % [
		character_stats.get_stat("strength"),
		character_stats.base_stats["strength"],
		character_stats.equipment_bonuses["strength"]
	])

	# Emit signal to update UI
	on_stats_changed.emit()

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var err := DirAccess.remove_absolute(SAVE_PATH)
		if err != OK:
			push_warning("Impossibile rimuovere il salvataggio: %s (err %d)" % [SAVE_PATH, err])

	_reset_memory()
	_load_default_data()

	on_inventory_changed.emit()
	on_craft_updated.emit()
	on_stats_changed.emit()

	print("[GameState] Reset eseguito. Skills caricate:", skills.keys())

# ============================================
# SAVE SLOT SYSTEM
# ============================================

func get_save_path(slot: int) -> String:
	return "user://save_slot_%d.dat" % slot

func set_active_slot(slot: int) -> void:
	current_slot = slot
	SAVE_PATH = get_save_path(slot)

func start_new_game_slot(slot: int) -> void:
	"""Avvia una nuova partita nello slot indicato. Chiamato da MainMenu prima del cambio scena."""
	set_active_slot(slot)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_reset_memory()
	_load_default_data()
	print("[GameState] ✅ New game started in slot %d" % slot)

func load_game_slot(slot: int) -> void:
	"""Carica il gioco dallo slot indicato. Chiamato da MainMenu prima del cambio scena."""
	set_active_slot(slot)
	_reset_memory()
	_load_default_data()
	load_game()
	print("[GameState] ✅ Loaded game from slot %d" % slot)

func read_slot_info(slot: int) -> Dictionary:
	"""Legge le statistiche di un slot senza modificare lo stato corrente. Usato da MainMenu."""
	var path = get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var slot_data = file.get_var()
	file.close()

	if typeof(slot_data) != TYPE_DICTIONARY:
		return {}

	var char_stats = slot_data.get("character_stats", {})
	var level_sys = char_stats.get("level_system", {})

	return {
		"exists": true,
		"save_time": slot_data.get("save_time", 0),
		"play_time": slot_data.get("play_time", 0.0),
		"gold": slot_data.get("resources", {}).get("gold", 0),
		"kills": slot_data.get("kills", 0),
		"level": level_sys.get("current_level", 1),
		"inventory_count": slot_data.get("inventory_items", []).size(),
	}

func _reset_memory() -> void:
	"""Azzera tutto lo stato in-memoria. Chiamato da reset_save, start_new_game_slot e load_game_slot."""
	inventory.clear()
	inventory_items.clear()
	resources = {"gold": 0}
	equipped_bags.clear()
	for slot in equipped_items.keys():
		equipped_items[slot] = null
	passive_points = 0
	passive_points_by_category = {"main": 0, "mining": 0, "herbalism": 0, "fishing": 0}
	activated_passives.clear()
	activated_passives_by_category = {"main": [], "mining": [], "herbalism": [], "fishing": []}
	kills = 0
	enemy_hp = 0.0
	combat_active = false
	current_area = ""
	current_mob = ""
	bonus_dps_add = 0.0
	bonus_dps_mult = 0.0
	current_action_id = ""
	action_time_left = 0.0
	action_time_total = 0.0
	craft_queue.clear()
	play_time = 0.0

	if character_stats:
		character_stats = CharacterStats.new()
		character_stats.stats_changed.connect(_on_character_stat_changed)
		character_stats.hp_changed.connect(_on_hp_changed)
		character_stats.mana_changed.connect(_on_mana_changed)
		character_stats.level_up.connect(_on_combat_level_up)

	if gathering_skills:
		gathering_skills = GatheringSkillsManager.new()
		gathering_skills.skill_level_up.connect(_on_gathering_skill_level_up)

func _migrate_old_save() -> void:
	"""Migra il vecchio save.dat al nuovo formato slot (save_slot_1.dat)."""
	var old_path = "user://save.dat"
	var new_path = get_save_path(1)
	if FileAccess.file_exists(old_path) and not FileAccess.file_exists(new_path):
		var dir = DirAccess.open("user://")
		if dir:
			var err = dir.rename("save.dat", "save_slot_1.dat")
			if err == OK:
				print("[GameState] ✅ Migrated save.dat → save_slot_1.dat")
			else:
				push_warning("[GameState] Could not migrate old save (err %d)" % err)
