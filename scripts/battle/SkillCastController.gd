# File: res://scripts/battle/SkillCastController.gd
# Skill Auto-Cast System Controller
# Manages skill priority, cooldowns, casting, and effects

class_name SkillCastController
extends Node

const WarriorSkill = preload("res://scripts/battle/WarriorSkill.gd")
const SkillDatabase = preload("res://scripts/battle/SkillDatabase.gd")

# const LOG removed - using GameLogger

# ==================== REFERENCES ====================

var skill_db: SkillDatabase = null
var battle_area = null  # Reference to BattleArea
var slot_manager = null  # Reference to SlotManager (used for enemy targeting)
var player = null  # Reference to CharacterStats

# ==================== STATE ====================

# Skill loadout (6 slots, ordered by priority)
var loadout: Array[WarriorSkill] = [null, null, null, null, null, null]

# Currently casting
var is_currently_casting: bool = false
var current_cast_skill: WarriorSkill = null
var cast_time_remaining: float = 0.0

# Active buffs/debuffs on player
var active_buffs: Dictionary = {}  # buff_id -> {skill, end_time, values}

# Combat state
var combat_active: bool = false
var cast_check_interval: float = 2.5  # Check for cast every 2.5s
var cast_check_timer: float = 0.0

# Cast history for testing
var cast_history: Array = []

## Combattimento 3D: chi esegue gli eventi delle animazioni (PlayerCharacter3D, gruppo "skill_event_driver").
## Con un esecutore, danni / stordimento / buff / cure partono negli eventi dell'animazione dello stile attivo
## (hit, hit1-3, on) invece che a fine cast. Senza esecutore (combat 2D) tutto resta come prima.
const EVENT_DRIVER_GROUP := "skill_event_driver"
var event_driver = null
var _event_targets = null  # bersagli scelti all'inizio del cast in modalità eventi (null = modalità 2D)

# Signals
signal skill_cast_started(skill: WarriorSkill)
signal skill_cast_completed(skill: WarriorSkill)
signal skill_effect_applied(skill: WarriorSkill, targets: Array)
signal buff_applied(buff_name: String, duration: float)
signal buff_expired(buff_name: String)
signal heal_applied(amount: float)

# ==================== INITIALIZATION ====================

func _init():
	skill_db = SkillDatabase.new()

func _ready() -> void:
	set_process(false)  # Will be enabled when combat starts

	if GameLogger.ENABLED:
		print("[SkillCastController] Initialized")

func _process(delta: float) -> void:
	if not combat_active:
		return

	# Regenerate mana
	_regenerate_mana(delta)

	# Update cooldowns
	_update_cooldowns(delta)

	# Update buffs
	_update_buffs(delta)

	# Update casting
	if is_currently_casting:
		_update_casting(delta)
	else:
		# Check if we should cast something
		cast_check_timer += delta
		if cast_check_timer >= get_cast_interval():
			cast_check_timer = 0.0
			_check_and_cast_next_skill()

# ==================== COMBAT CONTROL ====================

func start_combat() -> void:
	"""Start the auto-cast combat loop"""
	if combat_active:
		if GameLogger.ENABLED:
			print("[SkillCastController] WARNING: Combat already active!")
		return

	# Reset all skill cooldowns so they don't persist from previous battle
	for i in range(6):
		if loadout[i] != null:
			loadout[i].current_cooldown = 0.0

	combat_active = true
	set_process(true)
	cast_check_timer = 0.0

	if GameLogger.ENABLED:
		print("[SkillCastController] Combat started - combat_active: %s, process: %s" % [combat_active, is_processing()])
		if player:
			print("[SkillCastController] Player mana at combat start: %d/%d" % [player.current_mana, player.get_stat("max_mana")])
		print("[SkillCastController] Loadout (6 slots):")
		for i in range(6):
			var skill_name = loadout[i].name if loadout[i] else "empty"
			print("  Slot %d: %s" % [i, skill_name])

func stop_combat() -> void:
	"""Stop the auto-cast combat loop"""
	combat_active = false
	set_process(false)
	is_currently_casting = false
	current_cast_skill = null

	if GameLogger.ENABLED:
		print("[SkillCastController] Combat stopped")

# ==================== LOADOUT MANAGEMENT ====================

func equip_skill_to_slot(slot_index: int, skill_id: String) -> bool:
	"""Equip a skill to a specific loadout slot (0-5)"""
	if slot_index < 0 or slot_index >= 6:
		push_error("[SkillCastController] Invalid slot index: %d" % slot_index)
		return false

	skill_id = SkillDatabase.canonical_id(skill_id)  # loadout vecchi: guard / battle_cry
	if not skill_db.has_skill(skill_id):
		push_error("[SkillCastController] Skill not found: %s" % skill_id)
		return false

	var skill = skill_db.get_skill(skill_id)
	loadout[slot_index] = skill

	if GameLogger.ENABLED:
		print("[SkillCastController] Equipped %s to slot %d" % [skill.name, slot_index])

	return true

func unequip_skill(slot_index: int) -> void:
	"""Remove skill from a loadout slot"""
	if slot_index < 0 or slot_index >= 4:
		return

	loadout[slot_index] = null

	if GameLogger.ENABLED:
		print("[SkillCastController] Unequipped slot %d" % slot_index)

func clear_loadout() -> void:
	"""Clear all loadout slots"""
	for i in range(6):
		loadout[i] = null

	if GameLogger.ENABLED:
		print("[SkillCastController] Loadout cleared")

func get_loadout() -> Array[WarriorSkill]:
	"""Get current loadout"""
	return loadout.duplicate()

# ==================== AUTO-CAST LOGIC ====================

func _check_and_cast_next_skill() -> void:
	"""Check loadout in priority order and cast first available skill"""
	if not player:
		if GameLogger.ENABLED:
			print("[SkillCastController] WARNING: No player set!")
		return

	if not slot_manager and not battle_area:
		if GameLogger.ENABLED:
			print("[SkillCastController] WARNING: No slot_manager or battle_area set!")
		return

	# Check each loadout slot in order (priority).
	# L'attacco base NON viene castato qui: è il ripiego (sotto). Altrimenti, essendo
	# sempre disponibile (no cooldown/mana), vincerebbe la priorità e le vere skill
	# negli slot inferiori non partirebbero mai.
	for i in range(6):
		var skill = loadout[i]
		if skill == null:
			continue
		if skill.id == "basic_attack":
			continue

		# Can we cast this skill?
		if _can_cast_skill(skill):
			_start_casting(skill)
			return

	# Nessuna skill pronta - usa l'attacco base come ripiego
	var basic_attack = skill_db.get_skill("basic_attack")
	if basic_attack and _can_cast_skill(basic_attack):
		if GameLogger.ENABLED:
			print("[SkillCastController] No skills available - using Basic Attack")
		_start_casting(basic_attack)
	elif GameLogger.ENABLED:
		print("[SkillCastController] Cannot cast any skill or basic attack")

func _can_cast_skill(skill: WarriorSkill) -> bool:
	"""Check if a skill can be cast right now"""
	# Already casting
	if is_currently_casting:
		return false

	# On cooldown
	if skill.is_on_cooldown():
		return false

	# Check if buff is already active (for self-buff skills)
	if skill.skill_type == "self" and skill.duration > 0:
		# This is a buff skill - check if its buff is already active
		var buff_id = skill.id  # e.g., "berserk", "sword_aura"
		if has_buff(buff_id):
			if GameLogger.ENABLED:
				print("[SkillCastController] Buff %s already active (%.1fs remaining)" %
					[buff_id, get_buff_remaining_time(buff_id)])
			return false

	# Not enough mana
	if player.current_mana < skill.mana_cost:
		return false

	# No valid targets (except self buffs)
	if skill.skill_type != "self":
		# Use slot_manager if available, fallback to battle_area
		var enemy_count = 0
		if slot_manager:
			enemy_count = slot_manager.get_alive_enemy_count()
		elif battle_area:
			enemy_count = battle_area.get_alive_enemy_count()

		if enemy_count == 0:
			return false

	return true

func can_cast_skill(skill_id: String) -> bool:
	"""Public method to check if a skill can be cast"""
	var skill = skill_db.get_skill(skill_id)
	if not skill:
		return false
	return _can_cast_skill(skill)

func force_check_cast() -> void:
	"""Force an immediate cast check (for testing)"""
	_check_and_cast_next_skill()

# ==================== CASTING ====================

func _start_casting(skill: WarriorSkill) -> void:
	"""Begin casting a skill"""
	is_currently_casting = true
	current_cast_skill = skill
	cast_time_remaining = skill.cast_time
	_event_targets = null

	if GameLogger.ENABLED:
		print("[SkillCastController] Started casting: %s" % skill.name)

	# Combattimento 3D: i bersagli si scelgono subito (lo scatto di Sibilare parte prima di fine cast)
	# e gli effetti li applica l'esecutore negli eventi dell'animazione
	var driver = get_event_driver()
	if driver:
		var targets := _get_skill_targets(skill)
		_event_targets = targets
		driver.queue_skill_events(skill.id, targets, func(event_name: String, index: int) -> Dictionary:
			return apply_skill_event(skill, targets, event_name, index))

	skill_cast_started.emit(skill)

func _update_casting(delta: float) -> void:
	"""Update cast time"""
	cast_time_remaining -= delta

	if cast_time_remaining <= 0.0:
		_complete_casting()

func _complete_casting() -> void:
	"""Complete the cast and apply skill effects"""
	if not current_cast_skill:
		return

	var skill = current_cast_skill

	# Consume mana
	if player:
		player.consume_mana(skill.mana_cost)

	# Apply skill effects (in modalità eventi li applica l'esecutore 3D al momento giusto)
	var targets: Array
	if _event_targets != null:
		targets = _event_targets
		_event_targets = null
	else:
		targets = _get_skill_targets(skill)
		_apply_skill_effects(skill, targets)

	# Start cooldown
	skill.start_cooldown()

	# Record cast
	cast_history.append({
		"skill_id": skill.id,
		"time": Time.get_ticks_msec() / 1000.0
	})

	if GameLogger.ENABLED:
		print("[SkillCastController] Completed casting: %s on %d targets" % [skill.name, targets.size()])

	skill_cast_completed.emit(skill)
	skill_effect_applied.emit(skill, targets)

	# Reset casting state
	is_currently_casting = false
	current_cast_skill = null
	cast_time_remaining = 0.0

# ==================== TARGETING ====================

func _get_skill_targets(skill: WarriorSkill) -> Array:
	"""Get targets for a skill based on its type"""
	var targets: Array = []

	# Check if we have targeting capability
	if not slot_manager and not battle_area:
		if GameLogger.ENABLED:
			print("[SkillCastController] WARNING: No slot_manager or battle_area set!")
		return targets

	match skill.skill_type:
		"self":
			# Self-target (for buffs)
			if player:
				targets.append(player)

		"single":
			# Random single enemy
			var enemy = null
			if slot_manager:
				enemy = slot_manager.get_random_alive_enemy()
			elif battle_area:
				enemy = battle_area.get_random_alive_enemy()

			if enemy:
				targets.append(enemy)
			elif GameLogger.ENABLED:
				print("[SkillCastController] WARNING: No alive enemies for single target")

		"aoe":
			# All alive enemies
			if slot_manager:
				targets = slot_manager.get_all_alive_enemies()
			elif battle_area:
				targets = battle_area.get_all_alive_enemies()

			if GameLogger.ENABLED and targets.is_empty():
				print("[SkillCastController] WARNING: No alive enemies for AOE")

		"multi":
			# Multiple random enemies (up to max_targets)
			var alive_enemies = []
			if slot_manager:
				alive_enemies = slot_manager.get_all_alive_enemies()
			elif battle_area:
				alive_enemies = battle_area.get_all_alive_enemies()

			var count = min(skill.max_targets, alive_enemies.size())

			# Shuffle and take first N
			alive_enemies.shuffle()
			for i in range(count):
				targets.append(alive_enemies[i])

			if GameLogger.ENABLED and targets.is_empty():
				print("[SkillCastController] WARNING: No alive enemies for multi target")

		"cone":
			# Colpo frontale ad area: nel 3D il cono lo sceglie l'esecutore al momento del colpo,
			# nel 2D (niente direzione) fino a max_targets nemici a caso
			var alive_list = []
			if slot_manager:
				alive_list = slot_manager.get_all_alive_enemies()
			elif battle_area:
				alive_list = battle_area.get_all_alive_enemies()
			if get_event_driver() != null:
				targets = alive_list
			else:
				alive_list.shuffle()
				for i in range(min(skill.max_targets, alive_list.size())):
					targets.append(alive_list[i])

	if GameLogger.ENABLED:
		print("[SkillCastController] Found %d targets for %s (type: %s)" % [targets.size(), skill.name, skill.skill_type])

	return targets

# ==================== SKILL EFFECTS ====================

func _apply_skill_effects(skill: WarriorSkill, targets: Array) -> void:
	"""Apply skill effects to targets"""

	# SWORD VORTEX: play visual, damage fires mid-animation via callback
	if skill.id == "sword_vortex":
		_play_sword_vortex_visual(skill, targets)
		# Stun/buffs still fall through below if ever added to vortex in future
		return

	# HISS (SIBILARE): dash + slash visual, damage+stun fire on impact via callback
	if skill.id == "hiss":
		_play_sibilare_visual(skill, targets)
		return

	# DAMAGE EFFECTS
	var dealt := 0
	if skill.damage_max > 0:
		dealt = _apply_damage(skill, targets)

	# LIFESTEAL (Volontà di Vivere): cura una parte del danno inflitto
	if skill.has_effect("lifesteal"):
		_apply_lifesteal(skill, dealt)

	# STUN EFFECT
	if skill.has_effect("stun"):
		_apply_stun(skill, targets)

	# BUFF EFFECTS (Estasi da Combattimento, ex Grido di Battaglia)
	if skill.has_effect("buff_attack") or skill.has_effect("debuff_defense"):
		_apply_berserk_buff(skill)

	# AURA DELLA SPADA: danno extra fisso a ogni colpo
	if skill.has_effect("aura_damage"):
		_apply_aura_buff(skill)

func _apply_damage(skill: WarriorSkill, targets: Array, damage_scale: float = 1.0) -> int:
	"""Apply damage to targets. damage_scale: quota del danno (colpi divisi). Restituisce il danno totale."""
	var ignore_defense = skill.has_effect("defense_pierce")
	var total := 0

	for target in targets:
		# Target may have been freed between delayed hits (e.g. sword vortex 3-hit)
		if not is_instance_valid(target):
			continue
		if target.has_method("is_alive") and not target.is_alive():
			continue

		var damage = skill.roll_damage()
		if damage_scale != 1.0:
			damage = maxi(1, int(round(damage * damage_scale)))

		# Apply player attack bonus
		if player:
			var attack_bonus = player.get_stat("physical_damage")
			damage += int(attack_bonus)

			# Apply Estasi da Combattimento (ex Grido di Battaglia) if active
			if has_buff("berserk"):
				var berserk_data = active_buffs["berserk"]
				var attack_percent = berserk_data.values.get("attack_percent", 0.0)
				damage = int(damage * (1.0 + attack_percent / 100.0))

		# Aura della Spada: danno extra fisso a ogni colpo (anche attacco base e altre skill)
		damage += get_aura_bonus_damage()

		# Apply damage
		if target.has_method("take_damage"):
			target.take_damage(damage)
		elif battle_area and battle_area.has_method("damage_enemy"):
			battle_area.damage_enemy(target, damage)

		total += damage
		if GameLogger.ENABLED:
			print("[SkillCastController] %s dealt %d damage to %s" %
				[skill.name, damage, target.get_enemy_name() if target.has_method("get_enemy_name") else "target"])

	return total

func _apply_stun(skill: WarriorSkill, targets: Array) -> void:
	"""Apply stun to targets"""
	var stun_duration = skill.get_effect_value("stun_duration", 1.5)

	for target in targets:
		if not is_instance_valid(target):
			continue
		if target.has_method("stun"):
			target.stun(stun_duration)

			if GameLogger.ENABLED:
				print("[SkillCastController] Stunned target for %.1fs" % stun_duration)

func _apply_berserk_buff(skill: WarriorSkill) -> void:
	"""Estasi da Combattimento (ex Grido di Battaglia): +attacco, -difesa, +velocità"""
	if not player:
		return

	var attack_percent = skill.get_effect_value("attack_percent", 40.0)
	var defense_percent = skill.get_effect_value("defense_percent", -30.0)

	# Apply temporary modifiers to player stats (rilanciata: sostituisce quella vecchia)
	if player.has_method("remove_temporary_modifier"):
		player.remove_temporary_modifier("berserk")
	var modifier = {
		"id": "berserk",
		"type": "percent",
		"physical_damage": attack_percent,
		"physical_defense": defense_percent,
		"duration": skill.duration
	}
	player.add_temporary_modifier(modifier, skill.duration)

	# Track buff for UI
	var end_time = (Time.get_ticks_msec() / 1000.0) + skill.duration
	active_buffs["berserk"] = {
		"skill": skill,
		"end_time": end_time,
		"values": skill.effect_values
	}

	buff_applied.emit("berserk", skill.duration)

	if GameLogger.ENABLED:
		print("[SkillCastController] Estasi: +%.0f%% ATK, %.0f%% DEF, +%.0f%% velocità for %.1fs" %
			[attack_percent, defense_percent, skill.get_effect_value("attack_speed_percent", 0.0), skill.duration])

func _apply_aura_buff(skill: WarriorSkill) -> void:
	"""Aura della Spada: ogni colpo aggiunge un danno extra fisso finché è attiva"""
	var end_time = (Time.get_ticks_msec() / 1000.0) + skill.duration
	active_buffs["sword_aura"] = {
		"skill": skill,
		"end_time": end_time,
		"values": {"bonus_damage": skill.get_effect_value("bonus_damage", 8.0)}
	}

	buff_applied.emit("sword_aura", skill.duration)

	if GameLogger.ENABLED:
		print("[SkillCastController] Aura della Spada: +%d danni per colpo for %.1fs" %
			[get_aura_bonus_damage(), skill.duration])

func _apply_lifesteal(skill: WarriorSkill, damage_dealt: int) -> float:
	"""Volontà di Vivere: cura il warrior di una parte del danno inflitto. Restituisce la cura."""
	var amount: float = round(damage_dealt * skill.get_effect_value("heal_percent", 30.0) / 100.0)
	if amount <= 0.0:
		return 0.0
	if player and player.has_method("heal"):
		player.heal(amount)
	heal_applied.emit(amount)
	if GameLogger.ENABLED:
		print("[SkillCastController] Volontà di Vivere: cura %d (danno %d)" % [amount, damage_dealt])
	return amount

func get_aura_bonus_damage() -> int:
	"""Danno extra per colpo dell'Aura della Spada (0 se non attiva)"""
	if not has_buff("sword_aura"):
		return 0
	return int(active_buffs["sword_aura"].values.get("bonus_damage", 0.0))

func get_cast_interval() -> float:
	"""Intervallo tra i lanci: più breve con Estasi da Combattimento (+velocità d'attacco)"""
	if has_buff("berserk"):
		var pct: float = active_buffs["berserk"].values.get("attack_speed_percent", 0.0)
		return cast_check_interval / (1.0 + pct / 100.0)
	return cast_check_interval

# ==================== EVENTI DELLE ANIMAZIONI (combattimento 3D) ====================

func set_event_driver(driver) -> void:
	"""Imposta l'esecutore degli eventi (altrimenti viene cercato nel gruppo skill_event_driver)"""
	event_driver = driver

func get_event_driver():
	"""Esecutore 3D attivo (visibile e pronto), o null nel combat 2D"""
	if event_driver != null and is_instance_valid(event_driver) and event_driver.accepts_skill_events():
		return event_driver
	if not is_inside_tree():
		return null
	for d in get_tree().get_nodes_in_group(EVENT_DRIVER_GROUP):
		if is_instance_valid(d) and d.has_method("accepts_skill_events") and d.accepts_skill_events():
			return d
	return null

func apply_skill_event(skill: WarriorSkill, targets: Array, event_name: String, index: int = 0) -> Dictionary:
	"""Applica la parte di gameplay di un evento dell'animazione (combattimento 3D).
	Restituisce {targets, damage, heal} per gli effetti visivi."""
	var result := {"targets": [], "heal": 0.0, "damage": 0}
	match skill.id:
		"sword_aura":
			if event_name == "on":
				_apply_aura_buff(skill)
		"berserk":
			if event_name == "on":
				_apply_berserk_buff(skill)
		"three_way_slash":
			if not event_name.begins_with("hit"):
				return result
			var alive := _alive_only(targets)
			if alive.is_empty():
				alive = _alive_only(_get_skill_targets(skill))
			if alive.is_empty():
				return result
			# ogni fendente colpisce uno dei bersagli (o lo stesso, se è solo): il danno di un bersaglio
			# si divide tra i fendenti che riceve, così il totale resta quello di prima
			var n := clampi(int(event_name.substr(3)) - 1, 0, 2)
			var k := alive.size()
			var hits_on_target := 0
			for i in 3:
				if i % k == n % k:
					hits_on_target += 1
			var t = alive[n % k]
			result.damage = _apply_damage(skill, [t], 1.0 / hits_on_target)
			result.targets = [t]
		"sword_vortex":
			if event_name != "hit":
				return result
			# tre colpi durante il giro (come i tre giri del 2D), sui nemici vicini in quel momento
			var near := _alive_only(_get_skill_targets(skill))
			result.damage = _apply_damage(skill, near)
			result.targets = near
		"life_force":
			if event_name != "hit":
				return result
			# nemici vicini al momento del colpo, poi il cono frontale lo sceglie l'esecutore
			var cands := _alive_only(_get_skill_targets(skill))
			var driver = get_event_driver()
			if driver and driver.has_method("filter_cone_targets"):
				cands = driver.filter_cone_targets(cands, skill.get_effect_value("cone_range", 3.0),
					skill.get_effect_value("cone_angle", 100.0), skill.max_targets)
			result.damage = _apply_damage(skill, cands)
			result.targets = cands
			result.heal = _apply_lifesteal(skill, result.damage)
		_:
			# attacco base, Sibilare e skill a colpo singolo
			if event_name != "hit":
				return result
			var alive := _alive_only(targets)
			result.damage = _apply_damage(skill, alive)
			result.targets = alive
			if skill.has_effect("stun"):
				_apply_stun(skill, alive)
	return result

func _alive_only(list: Array) -> Array:
	var out: Array = []
	for t in list:
		if is_instance_valid(t) and (not t.has_method("is_alive") or t.is_alive()):
			out.append(t)
	return out

# ==================== BUFF MANAGEMENT ====================

func _update_buffs(delta: float) -> void:
	"""Update and expire buffs"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var expired_buffs: Array[String] = []

	for buff_name in active_buffs.keys():
		var buff_data = active_buffs[buff_name]
		if current_time >= buff_data.end_time:
			expired_buffs.append(buff_name)

	# Remove expired buffs
	for buff_name in expired_buffs:
		active_buffs.erase(buff_name)
		buff_expired.emit(buff_name)

		if GameLogger.ENABLED:
			print("[SkillCastController] Buff expired: %s" % buff_name)

func has_buff(buff_name: String) -> bool:
	"""Check if a buff is active"""
	return active_buffs.has(buff_name)

func get_buff_remaining_time(buff_name: String) -> float:
	"""Get remaining time for a buff"""
	if not active_buffs.has(buff_name):
		return 0.0

	var buff_data = active_buffs[buff_name]
	var current_time = Time.get_ticks_msec() / 1000.0
	return max(0.0, buff_data.end_time - current_time)

func apply_damage_reduction(incoming_damage: float) -> float:
	"""Riduzione del danno di Guardia (skill tolta: resta per compatibilità, senza buff "guard" non riduce)"""
	if not has_buff("guard"):
		return incoming_damage

	var guard_data = active_buffs["guard"]
	var reduction_percent = guard_data.values.get("damage_reduction_percent", 50.0)
	var reduction_multiplier = 1.0 - (reduction_percent / 100.0)

	return incoming_damage * reduction_multiplier

# ==================== MANA REGENERATION ====================

func _regenerate_mana(delta: float) -> void:
	"""Regenerate mana based on player's mana_regen stat"""
	if not player:
		return

	var mana_regen = player.get_stat("mana_regen")
	var amount = mana_regen * delta

	player.restore_mana(amount)

# ==================== COOLDOWN MANAGEMENT ====================

func _update_cooldowns(delta: float) -> void:
	"""Update all cooldowns"""
	for skill in loadout:
		if skill != null:
			skill.update_cooldown(delta)

func get_skill_cooldown(skill_id: String) -> float:
	"""Get cooldown remaining for a specific skill"""
	for skill in loadout:
		if skill and skill.id == skill_id:
			return skill.get_cooldown_remaining()
	return 0.0

func set_skill_on_cooldown(skill_id: String, cooldown: float) -> void:
	"""Manually set a skill on cooldown (for testing)"""
	for skill in loadout:
		if skill and skill.id == skill_id:
			skill.current_cooldown = cooldown
			return

# ==================== SWORD VORTEX VISUAL ====================

func _play_sword_vortex_visual(skill: WarriorSkill, targets: Array) -> void:
	"""Spawn the spinning sword vortex effect; damage fires mid-animation."""
	var parent_node = battle_area
	if not parent_node:
		# No visual parent – apply damage immediately as fallback
		_apply_damage(skill, targets)
		return

	# Load effect script
	var effect_script = load("res://scripts/battle/effects/SwordVortexEffect.gd")
	if not effect_script:
		_apply_damage(skill, targets)
		return

	# Load sword texture
	const SWORD_TEX_PATH := "res://Item_Texture/Skills/Vortice della spada/ChatGPT Image 8 mar 2026, 12_12_10.png"
	var tex: Texture2D = null
	if ResourceLoader.exists(SWORD_TEX_PATH):
		tex = ResourceLoader.load(SWORD_TEX_PATH)

	# Create effect node and add to battle_area
	var effect := Node2D.new()
	effect.set_script(effect_script)
	parent_node.add_child(effect)

	# Position at center of battle area (Control uses global_position + size/2)
	if parent_node is Control:
		effect.global_position = parent_node.global_position + parent_node.size * 0.5
	else:
		effect.global_position = parent_node.global_position

	# Capture skill + targets for the callback closure
	var captured_skill := skill
	var captured_targets := targets.duplicate()

	effect.initialize(
		tex,
		# Called once per completed rotation (3 hits total = 3× full AOE damage)
		func(): _apply_damage(captured_skill, captured_targets),
		Callable()
	)

	if GameLogger.ENABLED:
		print("[SkillCastController] Sword Vortex spawned — 3 rotations, 3 damage hits")

# ==================== SIBILARE (HISS) VISUAL ====================

func _play_sibilare_visual(skill: WarriorSkill, targets: Array) -> void:
	"""Spawn the dash-slash Sibilare effect; damage and stun fire on impact."""
	var parent_node = battle_area
	if not parent_node or targets.is_empty():
		# Fallback: apply immediately without visual
		_apply_damage(skill, targets)
		_apply_stun(skill, targets)
		return

	var effect_script = load("res://scripts/battle/effects/SibilareEffect.gd")
	if not effect_script:
		_apply_damage(skill, targets)
		_apply_stun(skill, targets)
		return

	# Determine target position in battle_area local space
	var target = targets[0]
	var target_global: Vector2
	if target.has_method("get_center_position"):
		target_global = target.get_center_position()
	elif target is Node2D:
		target_global = target.global_position
	elif target is Control:
		target_global = target.global_position + target.size * 0.5
	else:
		target_global = parent_node.global_position + parent_node.size * 0.5

	# Convert to battle_area local space
	var target_local: Vector2
	if parent_node is Control:
		target_local = target_global - parent_node.global_position
	else:
		target_local = parent_node.to_local(target_global)

	# Start position: left edge of battle_area at the target's Y height, with margin
	var start_local: Vector2
	if parent_node is Control:
		start_local = Vector2(40.0, target_local.y)
	else:
		start_local = Vector2(40.0, target_local.y)

	# Spawn effect as child of battle_area
	var effect := Node2D.new()
	effect.set_script(effect_script)
	parent_node.add_child(effect)

	var captured_skill    := skill
	var captured_targets  := targets.duplicate()

	effect.initialize(
		start_local,
		target_local,
		func(): _apply_damage(captured_skill, captured_targets),
		func(): _apply_stun(captured_skill, captured_targets)
	)

	if GameLogger.ENABLED:
		print("[SkillCastController] Sibilare spawned — dash from %s to %s" % [start_local, target_local])

# ==================== SETTERS ====================

func set_battle_area(area) -> void:
	"""Set reference to battle area"""
	battle_area = area

func set_slot_manager(manager) -> void:
	"""Set reference to slot manager (for enemy targeting)"""
	slot_manager = manager

func set_player(p) -> void:
	"""Set reference to player stats"""
	player = p

# ==================== GETTERS (for testing) ====================

func is_casting() -> bool:
	return is_currently_casting

func get_cast_history() -> Array:
	return cast_history

func get_active_buffs() -> Dictionary:
	return active_buffs.duplicate()
