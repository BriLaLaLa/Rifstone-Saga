# File: res://scripts/battle/CombatStateManager.gd
# Manages exploration -> encounter -> combat -> transition cycle
# State machine for combat flow

extends Node
class_name CombatStateManager

# const LOG removed - using GameLogger

# ==================== STATE MACHINE ====================

enum State {
	IDLE,             # Not in any zone
	EXPLORATION,      # Walking/searching for encounter
	ENCOUNTER_GEN,    # Generating encounter type
	COMBAT,           # Fighting enemies
	TRANSITION,       # Post-battle rewards/cooldown
	ZONE_COMPLETE     # Zone completed (optional)
}

var current_state: State = State.IDLE

# ==================== TIMERS ====================

# Exploration phase: 2-5 seconds
const EXPLORATION_MIN: float = 2.0
const EXPLORATION_MAX: float = 5.0
var exploration_duration: float = 0.0
var exploration_timer: float = 0.0

# Transition phase: 1-3 seconds
const TRANSITION_MIN: float = 1.0
const TRANSITION_MAX: float = 3.0
var transition_duration: float = 0.0
var transition_timer: float = 0.0

# Enemy attack timer: REMOVED - now handled per-enemy in EnemySlot
# Old global system removed in favor of individual enemy timers

# ==================== ENCOUNTER DATA ====================

var current_encounter: Dictionary = {}
var encounter_count: int = 0
var last_rewards: Dictionary = {}

# ==================== REFERENCES ====================

var encounter_generator: EncounterGenerator = null
var pity_system: PitySystem = null

# ==================== SIGNALS ====================

signal state_changed(new_state: State)
signal exploration_started()
signal exploration_completed()
signal exploration_progress(progress: float)
signal encounter_generated(encounter: Dictionary)
signal combat_started(encounter: Dictionary)
signal combat_ended()
signal transition_started(rewards: Dictionary)
signal transition_completed()
signal zone_exited()
# enemy_attack_incoming signal REMOVED - now each enemy has its own timer

# ==================== INITIALIZATION ====================

func _ready() -> void:
	set_process(false)  # Will be enabled when zone starts

	if GameLogger.ENABLED:
		print("[CombatStateManager] Initialized")

func setup(generator: EncounterGenerator, pity: PitySystem) -> void:
	"""Setup with generator and pity system"""
	encounter_generator = generator
	pity_system = pity

	if GameLogger.ENABLED:
		print("[CombatStateManager] Setup complete with generator and pity system")

# ==================== STATE MACHINE ====================

func _process(delta: float) -> void:
	"""Update current state"""

	match current_state:
		State.EXPLORATION:
			_update_exploration(delta)
		State.TRANSITION:
			_update_transition(delta)
		# State.COMBAT removed - enemy attacks now handled per-enemy in EnemySlot

func _change_state(new_state: State) -> void:
	"""Change to new state"""
	if current_state == new_state:
		return

	var old_state = current_state
	current_state = new_state

	if GameLogger.ENABLED:
		print("[CombatStateManager] State: %s -> %s" % [_state_to_string(old_state), _state_to_string(new_state)])

	state_changed.emit(new_state)

	# Handle state entry
	_on_state_entered(new_state)

func _on_state_entered(state: State) -> void:
	"""Handle state entry logic"""

	match state:
		State.EXPLORATION:
			_start_exploration_timer()
		State.ENCOUNTER_GEN:
			_generate_encounter()
		State.COMBAT:
			_start_combat()
		State.TRANSITION:
			_start_transition_timer()

# ==================== EXPLORATION PHASE ====================

func start_exploration() -> void:
	"""Start exploration phase"""
	if current_state != State.IDLE and current_state != State.TRANSITION:
		if GameLogger.ENABLED:
			print("[CombatStateManager] Cannot start exploration from state: %s" % _state_to_string(current_state))
		return

	set_process(true)
	_change_state(State.EXPLORATION)

func _start_exploration_timer() -> void:
	"""Start exploration timer with random duration"""
	exploration_duration = randf_range(EXPLORATION_MIN, EXPLORATION_MAX)
	exploration_timer = 0.0

	if GameLogger.ENABLED:
		print("[CombatStateManager] 🚶 Exploration started (duration: %.1fs)" % exploration_duration)

	exploration_started.emit()

func _update_exploration(delta: float) -> void:
	"""Update exploration phase"""
	exploration_timer += delta

	# Emit progress
	var progress = min(exploration_timer / exploration_duration, 1.0)
	exploration_progress.emit(progress)

	# Check if exploration complete
	if exploration_timer >= exploration_duration:
		_complete_exploration()

func _complete_exploration() -> void:
	"""Complete exploration and move to encounter generation"""
	if GameLogger.ENABLED:
		print("[CombatStateManager] ✅ Exploration complete")

	exploration_completed.emit()
	_change_state(State.ENCOUNTER_GEN)

func get_exploration_duration() -> float:
	"""Get current exploration duration"""
	return exploration_duration

func get_exploration_progress() -> float:
	"""Get exploration progress (0.0 - 1.0)"""
	if exploration_duration == 0.0:
		return 0.0
	return min(exploration_timer / exploration_duration, 1.0)

# ==================== ENCOUNTER GENERATION ====================

func _generate_encounter() -> void:
	"""Generate encounter using encounter generator"""
	if not encounter_generator:
		push_error("[CombatStateManager] No encounter generator set!")
		_change_state(State.IDLE)
		return

	# Generate encounter with pity system
	current_encounter = encounter_generator.generate_with_pity()
	encounter_count += 1

	if GameLogger.ENABLED:
		print("[CombatStateManager] 🎲 Encounter #%d generated: %s" % [encounter_count, current_encounter["type"]])

	encounter_generated.emit(current_encounter)

	# Move to combat
	_change_state(State.COMBAT)

func get_current_encounter() -> Dictionary:
	"""Get current encounter data"""
	return current_encounter

func get_encounter_count() -> int:
	"""Get total encounters in this zone session"""
	return encounter_count

# ==================== COMBAT PHASE ====================

func _start_combat() -> void:
	"""Start combat with current encounter"""
	if GameLogger.ENABLED:
		print("[CombatStateManager] ⚔️ Combat started")

	combat_started.emit(current_encounter)

	# Combat is managed by BattleTab/BattleArea
	# Enemy attacks are now handled per-enemy in EnemySlot
	# This state manager waits for combat_ended signal

# OLD ENEMY ATTACK SYSTEM REMOVED - now handled per-enemy in EnemySlot.gd
# _start_enemy_attack_timer(), _update_combat(), _trigger_enemy_attack(),
# _reset_enemy_attack_timer(), _stop_enemy_attacks() all removed

func on_combat_ended() -> void:
	"""Called when combat ends (victory)"""
	if current_state != State.COMBAT:
		if GameLogger.ENABLED:
			print("[CombatStateManager] WARNING: combat_ended called but not in COMBAT state")
		return

	if GameLogger.ENABLED:
		print("[CombatStateManager] ✅ Combat ended")

	combat_ended.emit()
	_change_state(State.TRANSITION)

func set_combat_rewards(rewards: Dictionary) -> void:
	"""Set rewards from combat (called by BattleArea)"""
	last_rewards = rewards

# ==================== TRANSITION PHASE ====================

func _start_transition_timer() -> void:
	"""Start transition timer with random duration"""
	transition_duration = randf_range(TRANSITION_MIN, TRANSITION_MAX)
	transition_timer = 0.0

	if GameLogger.ENABLED:
		print("[CombatStateManager] 💰 Transition started (duration: %.1fs)" % transition_duration)
		if not last_rewards.is_empty():
			print("[CombatStateManager] Rewards: %s" % str(last_rewards))

	transition_started.emit(last_rewards)

func _update_transition(delta: float) -> void:
	"""Update transition phase"""
	transition_timer += delta

	# Check if transition complete
	if transition_timer >= transition_duration:
		_complete_transition()

func _complete_transition() -> void:
	"""Complete transition and return to exploration"""
	if GameLogger.ENABLED:
		print("[CombatStateManager] ✅ Transition complete - returning to exploration")

	transition_completed.emit()

	# Loop back to exploration
	_change_state(State.EXPLORATION)

func skip_transition() -> void:
	"""Skip transition phase immediately"""
	if current_state != State.TRANSITION:
		return

	if GameLogger.ENABLED:
		print("[CombatStateManager] ⏩ Transition skipped")

	transition_completed.emit()
	_change_state(State.EXPLORATION)

func get_transition_duration() -> float:
	"""Get current transition duration"""
	return transition_duration

func get_last_rewards() -> Dictionary:
	"""Get rewards from last combat"""
	return last_rewards

# ==================== ZONE CONTROL ====================

func exit_zone() -> void:
	"""Exit current zone and stop cycle"""
	if GameLogger.ENABLED:
		print("[CombatStateManager] 🚪 Exiting zone")

	set_process(false)
	_change_state(State.IDLE)

	# Reset counters
	encounter_count = 0
	current_encounter = {}
	last_rewards = {}

	zone_exited.emit()

func is_in_zone() -> bool:
	"""Check if currently in a zone"""
	return current_state != State.IDLE

# ==================== PERSISTENCE ====================

func save_state() -> Dictionary:
	"""Save current state"""
	return {
		"current_state": current_state,
		"encounter_count": encounter_count,
		"current_encounter": current_encounter,
		"last_rewards": last_rewards
	}

func load_state(state: Dictionary) -> void:
	"""Load saved state"""
	current_state = state.get("current_state", State.IDLE)
	encounter_count = state.get("encounter_count", 0)
	current_encounter = state.get("current_encounter", {})
	last_rewards = state.get("last_rewards", {})

	if GameLogger.ENABLED:
		print("[CombatStateManager] State loaded: %s, encounters=%d" %
			[_state_to_string(current_state), encounter_count])

# ==================== GETTERS ====================

func get_current_state() -> State:
	"""Get current state"""
	return current_state

func is_in_combat() -> bool:
	"""Check if currently in combat"""
	return current_state == State.COMBAT

func is_exploring() -> bool:
	"""Check if currently exploring"""
	return current_state == State.EXPLORATION

# ==================== UTILITY ====================

func _state_to_string(state: State) -> String:
	"""Convert state enum to string"""
	match state:
		State.IDLE:
			return "IDLE"
		State.EXPLORATION:
			return "EXPLORATION"
		State.ENCOUNTER_GEN:
			return "ENCOUNTER_GEN"
		State.COMBAT:
			return "COMBAT"
		State.TRANSITION:
			return "TRANSITION"
		State.ZONE_COMPLETE:
			return "ZONE_COMPLETE"
		_:
			return "UNKNOWN"

func get_debug_info() -> String:
	"""Get formatted debug info"""
	return """[CombatStateManager Debug]
Current State: %s
Encounter Count: %d
Current Encounter Type: %s
Last Rewards: %s
Exploration Progress: %.1f%%
""" % [
		_state_to_string(current_state),
		encounter_count,
		current_encounter.get("type", "none"),
		str(last_rewards),
		get_exploration_progress() * 100.0
	]

