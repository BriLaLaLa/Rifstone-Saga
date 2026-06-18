# File: res://scenes/Main.gd
# Gestisce il montaggio di tutte le tab: Villaggio, Inventory, Combat, ecc.

extends Control

const VILLAGE_MAP_SCENE = preload("res://scenes/ui/VillageMap.tscn")
const VILLAGE_OV_SCENE       = preload("res://scenes/ui/VillageOverlay.tscn")

# Percorso alla BattleTab scene
const BATTLE_TAB_SCENE_PATH := "res://scenes/battle/BattleTab.tscn"

@onready var tabs: TabContainer = $Margin/VBox/Tabs
@onready var gold_label: Label = $Margin/VBox/TopBar/GoldPanel/HBox/GoldLabel

var last_gold_value: int = -1  # Track gold to update only on change

func _ready() -> void:
	# Stretch canvas_items + expand applicato via codice (più affidabile di project.godot in embedded mode)
	var win := get_viewport().get_window()
	print("[Main] BEFORE stretch — window size: ", win.size, " | mode: ", win.content_scale_mode, " | aspect: ", win.content_scale_aspect, " | scale_size: ", win.content_scale_size)
	win.content_scale_mode   = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size   = Vector2i(1280, 720)
	print("[Main] AFTER  stretch — window size: ", win.size, " | mode: ", win.content_scale_mode, " | aspect: ", win.content_scale_aspect, " | scale_size: ", win.content_scale_size)
	print("[Main] viewport size: ", get_viewport().get_visible_rect().size)
	# Log deferred: dopo che il layout è stato calcolato
	call_deferred("_log_window_state")
	_update_gold_display()
	print("[Main] mount tabs on existing scene")
	_mount_village_tab()
	_setup_inventory_tab()
	_mount_battle_tab()  # ← NUOVA FUNZIONE
	_connect_skills_to_battle()  # Connect SkillsTab to BattleTab
	_set_current_tab_by_name("Villaggio")

func _set_current_tab_by_name(tab_name: String) -> void:
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == tab_name or tabs.get_tab_control(i).name == tab_name:
			tabs.current_tab = i
			return

func _mount_village_tab() -> void:
	var vill_container := tabs.get_node_or_null("Villaggio") as Control
	if vill_container == null:
		push_warning("[Main] Tab 'Villaggio' non trovata")
		return
	for c in vill_container.get_children(): 
		c.queue_free()

	var map: Control = VILLAGE_MAP_SCENE.instantiate()
	map.name = "VillageMap"
	vill_container.add_child(map)
	print("[Main] VillageMap added")

	var overlay: Control = VILLAGE_OV_SCENE.instantiate()
	var map_root: Node = map.call("get_map_root")
	map_root.add_child(overlay)
	overlay.call("attach_to", map_root)
	print("[Main] VillageOverlay attached")

	if map.has_signal("npc_clicked"):
		map.connect("npc_clicked", Callable(overlay, "open_for_npc"))
	if overlay.has_signal("item_purchased"):
		overlay.connect("item_purchased", Callable(self, "_on_item_purchased"))

func _setup_inventory_tab() -> void:
	print("[Main] Setup inventory tab...")
	
	# Aspetta un frame per essere sicuri che tutto sia inizializzato
	await get_tree().process_frame
	
	# Trova il tab inventory
	var inv_tab = null
	for i in range(tabs.get_tab_count()):
		var tab = tabs.get_tab_control(i)
		var tab_name = tabs.get_tab_title(i)
		if tab_name == "Inventory" or tab.name == "Inventory":
			inv_tab = tab
			print("[Main] Trovato tab inventory: ", tab)
			break
	
	if inv_tab == null:
		print("[Main] Tab Inventory non trovato!")
		return
		
	print("[Main] InventoryTab configurato")

func _mount_battle_tab() -> void:
	"""Monta la BattleTab nella tab Combat"""
	var battle_container := tabs.get_node_or_null("Combat") as Control
	if battle_container == null:
		push_warning("[Main] Tab 'Combat' non trovata")
		return
	
	# Pulisci eventuali nodi esistenti
	for c in battle_container.get_children():
		c.queue_free()
	
	# Carica e instanzia la BattleTab scene
	var battle_scene: PackedScene = null
	
	# Prova a caricare la scena
	if ResourceLoader.exists(BATTLE_TAB_SCENE_PATH):
		battle_scene = load(BATTLE_TAB_SCENE_PATH)
	else:
		push_error("[Main] BattleTab scene non trovata: %s" % BATTLE_TAB_SCENE_PATH)
		# Crea un placeholder se la scena non esiste ancora
		_create_battle_placeholder(battle_container)
		return
	
	# Instanzia la BattleTab
	if battle_scene:
		var battle_tab = battle_scene.instantiate()
		battle_container.add_child(battle_tab)
		print("[Main] BattleTab montata con successo")
	else:
		push_error("[Main] Impossibile instanziare BattleTab")
		_create_battle_placeholder(battle_container)

func _create_battle_placeholder(container: Control) -> void:
	"""Crea un placeholder se BattleTab non è ancora disponibile"""
	var label = Label.new()
	label.text = "⚔️ BATTLE SYSTEM\n\n(BattleTab non trovata)\n\nCrea i file:\n- res://scenes/battle/BattleTab.tscn\n- res://scripts/battle/BattleTab.gd"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 20)
	container.add_child(label)
	print("[Main] BattleTab placeholder creato")

func _connect_skills_to_battle() -> void:
	"""Connect SkillsTab to BattleTab for real-time sync"""
	await get_tree().process_frame  # Wait for tabs to be ready

	print("[Main] 🔍 Starting SkillsTab <-> BattleTab connection...")

	# Find SkillsTab
	var skills_tab = null
	for i in range(tabs.get_tab_count()):
		var tab = tabs.get_tab_control(i)
		if tab.name == "Skills" or tabs.get_tab_title(i) == "Skills":
			skills_tab = tab
			print("[Main] ✅ Found SkillsTab: %s" % tab)
			break

	# Find BattleTab
	var battle_tab = null
	for i in range(tabs.get_tab_count()):
		var tab = tabs.get_tab_control(i)
		if tab.name == "Combat" or tabs.get_tab_title(i) == "Combat":
			# BattleTab is child of Combat container
			if tab.get_child_count() > 0:
				battle_tab = tab.get_child(0)
				print("[Main] ✅ Found BattleTab: %s" % battle_tab)
			break

	if skills_tab and battle_tab:
		# Connect loadout_changed signal
		if skills_tab.has_signal("loadout_changed"):
			skills_tab.loadout_changed.connect(battle_tab._on_skills_loadout_changed)
			print("[Main] ✅ Connected loadout_changed signal")

		# Store references for battle overlay control
		battle_tab.set_meta("skills_tab", skills_tab)

		# WAIT for SkillsTab to emit ready_for_sync signal
		print("[Main] ⏳ Waiting for SkillsTab ready_for_sync signal...")
		if skills_tab.has_signal("ready_for_sync"):
			await skills_tab.ready_for_sync
			print("[Main] ✅ SkillsTab is ready!")

		# Now perform initial sync
		if skills_tab.has_method("_sync_with_battle_tab"):
			print("[Main] 🔄 Performing initial loadout sync...")
			skills_tab._sync_with_battle_tab()
			print("[Main] ✅ Initial loadout sync completed")

		print("[Main] ✅✅ SkillsTab <-> BattleTab connection complete!")
	else:
		print("[Main] ⚠️ Could not find SkillsTab or BattleTab for connection")

func _on_item_purchased(item_id: String, qty: int) -> void:
	print("[Main] item_purchased:", item_id, "x", qty)
	if Engine.has_singleton("GameState"):
		var gs := Engine.get_singleton("GameState")
		if gs:
			var inv: Dictionary = {}
			if gs.has("inventory"):
				var v: Variant = gs.get("inventory")
				if typeof(v) == TYPE_DICTIONARY: 
					inv = v
			inv[item_id] = int(inv.get(item_id, 0)) + qty
			gs.set("inventory", inv)
			if gs.has_signal("inventory_changed"):
				gs.inventory_changed.emit()
			elif gs.has_signal("on_inventory_changed"):
				gs.on_inventory_changed.emit()
			if gs.has_method("save"): 
				gs.save()

func _on_save_pressed() -> void:
	print("[Main] Save pressed")
	if Engine.has_singleton("GameState"):
		var gs := Engine.get_singleton("GameState")
		if gs and gs.has_method("save"): 
			gs.save()

func _on_reset_pressed() -> void:
	print("[Main] Reset pressed")
	if Engine.has_singleton("GameState"):
		var gs := Engine.get_singleton("GameState")
		if gs and gs.has_method("reset"):
			gs.reset()

func _process(_delta: float) -> void:
	"""Update gold display when value changes"""
	_update_gold_display()

func _update_gold_display() -> void:
	"""Update gold label from GameState"""
	var gs = get_node_or_null("/root/GameState")
	if not gs or not gold_label:
		return

	# Get current gold value
	var current_gold = 0
	if "resources" in gs and gs.resources is Dictionary:
		current_gold = int(gs.resources.get("gold", 0))

	# Only update if changed
	if current_gold != last_gold_value:
		last_gold_value = current_gold
		gold_label.text = _format_number(current_gold)

func _log_window_state() -> void:
	var win := get_viewport().get_window()
	print("[Main] DEFERRED — window size: ", win.size)
	print("[Main] DEFERRED — content_scale_mode: ", win.content_scale_mode, " (expected ", Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, ")")
	print("[Main] DEFERRED — content_scale_aspect: ", win.content_scale_aspect, " (expected ", Window.CONTENT_SCALE_ASPECT_EXPAND, ")")
	print("[Main] DEFERRED — content_scale_size: ", win.content_scale_size, " (expected 1280x720)")
	print("[Main] DEFERRED — viewport visible rect: ", get_viewport().get_visible_rect())
	print("[Main] DEFERRED — Main node size: ", size)
	print("[Main] DEFERRED — Margin node size: ", $Margin.size)
	print("[Main] DEFERRED — Tabs node size: ", $Margin/VBox/Tabs.size)

func _format_number(value: int) -> String:
	"""Format number with thousand separators (1234 -> 1,234)"""
	var text = str(value)
	var result = ""
	var count = 0

	# Process from right to left
	for i in range(text.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = text[i] + result
		count += 1

	return result
