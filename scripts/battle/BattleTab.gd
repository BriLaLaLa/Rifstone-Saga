# File: res://scripts/battle/BattleTab.gd
# Controller principale della Battle Scene

extends Control
class_name BattleTab

const LOG := true

# Scene references
@onready var character_display: CharacterDisplay = $HSplit/LeftPanel/CharacterDisplay
@onready var inventory_button: Button = $HSplit/LeftPanel/InventoryButton
@onready var battle_area: BattleArea = $HSplit/RightPanel/BattleArea
@onready var action_bar: Control = $HSplit/RightPanel/ActionBar
@onready var start_battle_button: Button = $HSplit/RightPanel/BattleArea/StartBattleButton

# Inventory popup reference
var inventory_popup: InventoryPopup = null

# PackedScene per il popup
const INVENTORY_POPUP_SCENE := "res://scenes/battle/InventoryPopup.tscn"

# Battle state
var is_battle_active: bool = false
var current_area_id: String = "forest_1"  # Default area

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_create_inventory_popup()
	
	if LOG:
		print("[BattleTab] Ready")

func _setup_ui() -> void:
	"""Configura l'interfaccia iniziale"""
	
	# Setup inventory button
	if inventory_button:
		inventory_button.text = "📦 Open Inventory"
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Setup start battle button
	if start_battle_button:
		start_battle_button.pressed.connect(_on_start_battle_pressed)
		start_battle_button.disabled = false
	else:
		push_error("[BattleTab] StartBattleButton not found!")
	
	# Setup battle area
	if battle_area:
		battle_area.enemy_targeted.connect(_on_enemy_targeted)
		battle_area.enemy_killed.connect(_on_enemy_killed)
		battle_area.all_enemies_dead.connect(_on_all_enemies_dead)
	
	if LOG:
		print("[BattleTab] UI setup complete")

func _connect_signals() -> void:
	"""Connetti ai signal del GameState"""
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			# Ascolta eventi di combattimento
			if gs.has_signal("on_combat_event"):
				if not gs.on_combat_event.is_connected(_on_combat_event):
					gs.on_combat_event.connect(_on_combat_event)
			
			# Ascolta tick per aggiornare combattimento
			if gs.has_signal("on_tick"):
				if not gs.on_tick.is_connected(_on_tick):
					gs.on_tick.connect(_on_tick)

func _create_inventory_popup() -> void:
	"""Crea dinamicamente l'InventoryPopup"""
	if LOG:
		print("[BattleTab] Tentativo di creare InventoryPopup...")
	
	if not ResourceLoader.exists(INVENTORY_POPUP_SCENE):
		push_error("[BattleTab] InventoryPopup scene non trovata: %s" % INVENTORY_POPUP_SCENE)
		return
	
	var popup_scene: PackedScene = load(INVENTORY_POPUP_SCENE)
	if popup_scene:
		inventory_popup = popup_scene.instantiate()
		
		if inventory_popup:
			add_child(inventory_popup)
			inventory_popup.visible = false
			
			# IMPORTANTE: z_index alto per stare sopra tutto (inclusi enemy slots con z_index=10)
			inventory_popup.z_index = 1000
			
			if LOG:
				print("[BattleTab] ✅ InventoryPopup creato con successo!")
		else:
			push_error("[BattleTab] Instantiate ha restituito null")
	else:
		push_error("[BattleTab] Impossibile caricare InventoryPopup scene")

# ==================== BUTTON CALLBACKS ====================

func _on_inventory_button_pressed() -> void:
	"""Apri/chiudi il popup inventario"""
	if LOG:
		print("[BattleTab] Inventory button pressed")
	
	if inventory_popup == null:
		push_error("[BattleTab] InventoryPopup non trovato!")
		return
	
	inventory_popup.toggle_popup()

func _on_start_battle_pressed() -> void:
	"""INIZIO BATTAGLIA - Il layout è garantito essere pronto!"""
	if LOG:
		print("[BattleTab] ⚔️ START BATTLE pressed!")
		print("[BattleTab] BattleArea global_position: %s" % battle_area.global_position)
		print("[BattleTab] BattleArea size: %s" % battle_area.size)
	
	if is_battle_active:
		if LOG:
			print("[BattleTab] Battle already active, ignoring")
		return
	
	# Disabilita il bottone durante la battaglia
	start_battle_button.disabled = true
	start_battle_button.text = "⚔️ Battle in Progress..."
	
	# INIZIALIZZA gli slot SOLO ADESSO (layout pronto al 100%)
	if not battle_area.slots_created:
		await battle_area._initialize_slots()
	
	# Avvia la battaglia
	start_battle(current_area_id)
	
	# Spawna nemici
	battle_area.spawn_test_wave()

# ==================== COMBAT EVENTS ====================

func _on_combat_event(msg: String) -> void:
	"""Gestisci eventi di combattimento dal GameState"""
	if LOG:
		print("[BattleTab] Combat event: %s" % msg)

func _on_tick(delta: float) -> void:
	"""Aggiorna la battaglia ogni tick"""
	if not is_battle_active:
		return
	
	# TODO: Aggiornare enemy HP bars, cooldowns, ecc.
	pass

# ==================== API PUBBLICA ====================

func start_battle(area_id: String) -> void:
	"""Inizia una battaglia nell'area specificata"""
	if LOG:
		print("[BattleTab] Starting battle in area: %s" % area_id)
	
	is_battle_active = true
	current_area_id = area_id
	
	# Attiva il combattimento nel GameState
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			gs.set_area(area_id)
			gs.toggle_combat(true)

func stop_battle() -> void:
	"""Ferma la battaglia corrente"""
	if LOG:
		print("[BattleTab] Stopping battle")
	
	is_battle_active = false
	
	# Disattiva il combattimento nel GameState
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		if gs:
			gs.toggle_combat(false)
	
	# Riabilita il bottone start
	if start_battle_button:
		start_battle_button.disabled = false
		start_battle_button.text = "⚔️ Start Battle"
	
	# Clear enemy slots
	if battle_area:
		battle_area.clear_all_slots()

func get_character_display() -> CharacterDisplay:
	"""Ottieni il CharacterDisplay per accesso esterno"""
	return character_display

func get_battle_area() -> BattleArea:
	"""Ottieni il BattleArea per accesso esterno"""
	return battle_area

# ==================== BATTLE AREA CALLBACKS ====================

func _on_enemy_targeted(slot: EnemySlot) -> void:
	"""Callback quando un nemico viene targetato"""
	if LOG:
		print("[BattleTab] Enemy targeted: %s" % slot.get_enemy_name())

func _on_enemy_killed(slot: EnemySlot) -> void:
	"""Callback quando un nemico muore"""
	if LOG:
		print("[BattleTab] Enemy killed: %s" % slot.get_enemy_name())
	
	# TODO: Handle loot drop

func _on_all_enemies_dead() -> void:
	"""Callback quando tutti i nemici sono morti"""
	if LOG:
		print("[BattleTab] 🎉 Victory! All enemies defeated!")
	
	# Ferma la battaglia
	stop_battle()
	
	# TODO: Show victory screen, loot, etc.
	# Dopo 2 secondi riabilita il bottone per next wave
	await get_tree().create_timer(2.0).timeout
	
	if start_battle_button:
		start_battle_button.text = "⚔️ Next Wave"
		start_battle_button.disabled = false
