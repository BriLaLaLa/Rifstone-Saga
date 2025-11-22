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
# Format: [{"item_id": "...", "bag_slots": N}, null, null, ...] (5 slots total)
var equipped_bags := []

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
const SAVE_PATH := "user://save.json"

var rng := RandomNumberGenerator.new()

# Autosave system
var autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL: float = 5.0  # Autosave every 5 seconds

func _ready() -> void:
	rng.randomize()
	_load_default_data()

	# NUOVO: Inizializza character stats
	character_stats = CharacterStats.new()
	character_stats.stats_changed.connect(_on_character_stat_changed)
	character_stats.hp_changed.connect(_on_hp_changed)
	character_stats.mana_changed.connect(_on_mana_changed)
	print("[GameState] Character stats initialized")

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

# ============================================
# NUOVO: EQUIPMENT MANAGEMENT
# ============================================

func equip_item_to_slot(item_id: String, slot: String) -> bool:
	"""Equipaggia un item da inventory a equipment slot"""
	if not data.items.has(item_id):
		print("[GameState] Item non trovato: ", item_id)
		return false
	
	var item_data = data.items[item_id]
	
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
	
	# Applica stats
	if item_data.has("stats"):
		character_stats.apply_equipment_stats(item_data.stats)
	
	# Rimuovi dall'inventario
	_remove_item(item_id, 1)
	
	on_item_equipped.emit(slot, item_data)
	on_stats_changed.emit()
	
	print("[GameState] Equipped: ", item_data.get("name", item_id), " in ", slot)
	return true

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
	var data_save = {
		"resources": resources,
		"inventory": inventory,  # Old format (kept for compatibility)
		"inventory_items": inventory_items,  # NEW: Grid-based inventory
		"skills": {},
		"craft_queue": craft_queue,
		"combat": {
			"current_area": current_area,
			"current_mob": current_mob,
			"enemy_hp": enemy_hp,
			"kills": kills,
			"combat_active": combat_active
		},
		"action": {
			"id": current_action_id,
			"left": action_time_left,
			"total": action_time_total
		},
		"bonuses": {"dps_add": bonus_dps_add, "dps_mult": bonus_dps_mult},

		# NUOVO: Salva character stats
		"character_stats": character_stats.to_dict() if character_stats else {},
		"equipped_items": {},
		"equipped_bags": equipped_bags  # NEW: Save equipped bags
	}

	# NUOVO: Salva equipped items
	for slot in equipped_items.keys():
		if equipped_items[slot] != null:
			data_save.equipped_items[slot] = equipped_items[slot].get("id", "")
	
	for k in skills.keys():
		var s: Skill = skills[k]
		data_save.skills[k] = {
			"level": s.level, "xp": s.xp, "grade": s.grade
		}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data_save))
	file.flush()
	print("[GameState] Game saved with stats")

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var txt := file.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY: return
	
	resources = parsed.get("resources", resources)
	inventory = parsed.get("inventory", inventory)  # Old format

	# NEW: Load grid-based inventory
	if parsed.has("inventory_items"):
		inventory_items = parsed.get("inventory_items", [])
		print("[GameState] Loaded %d items from grid inventory" % inventory_items.size())

	# NEW: Load equipped bags
	if parsed.has("equipped_bags"):
		equipped_bags = parsed.get("equipped_bags", [])
		print("[GameState] Loaded %d equipped bags" % equipped_bags.size())

	var saved_skills = parsed.get("skills", {})
	for k in saved_skills.keys():
		if skills.has(k):
			var s: Skill = skills[k]
			var d = saved_skills[k]
			s.level = int(d.get("level", s.level))
			s.xp = float(d.get("xp", s.xp))
			s.grade = String(d.get("grade", s.grade))
	
	craft_queue = parsed.get("craft_queue", [])
	
	var c = parsed.get("combat", {})
	current_area = c.get("current_area", current_area)
	current_mob = c.get("current_mob", current_mob)
	enemy_hp = float(c.get("enemy_hp", 0.0))
	kills = int(c.get("kills", 0))
	combat_active = bool(c.get("combat_active", false))
	
	var a = parsed.get("action", {})
	current_action_id = String(a.get("id",""))
	action_time_left = float(a.get("left",0.0))
	action_time_total = float(a.get("total",0.0))
	
	var b = parsed.get("bonuses", {})
	bonus_dps_add = float(b.get("dps_add", 0.0))
	bonus_dps_mult = float(b.get("dps_mult", 0.0))
	
	# NUOVO: Carica character stats
	if parsed.has("character_stats") and character_stats:
		character_stats.from_dict(parsed.character_stats)
	
	# NUOVO: Carica equipped items
	if parsed.has("equipped_items"):
		for slot in parsed.equipped_items.keys():
			var item_id = parsed.equipped_items[slot]
			if item_id != "" and data.items.has(item_id):
				equipped_items[slot] = data.items[item_id]
				# Riapplica stats
				if equipped_items[slot].has("stats"):
					character_stats.apply_equipment_stats(equipped_items[slot].stats)
	
	print("[GameState] Game loaded with stats")

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var err := DirAccess.remove_absolute(SAVE_PATH)
		if err != OK:
			push_warning("Impossibile rimuovere il salvataggio: %s (err %d)" % [SAVE_PATH, err])

	_load_default_data()

	current_action_id = ""
	action_time_left = 0.0
	action_time_total = 0.0
	craft_queue.clear()
	
	# NUOVO: Reset stats
	if character_stats:
		character_stats = CharacterStats.new()
		character_stats.stats_changed.connect(_on_character_stat_changed)
		character_stats.hp_changed.connect(_on_hp_changed)
		character_stats.mana_changed.connect(_on_mana_changed)
	
	# Reset equipment
	for slot in equipped_items.keys():
		equipped_items[slot] = null
	
	on_inventory_changed.emit()
	on_craft_updated.emit()
	on_stats_changed.emit()

	print("[GameState] Reset eseguito. Skills caricate:", skills.keys())
