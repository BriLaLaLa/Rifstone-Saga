# File: res://scripts/battle/InventoryPopup.gd
# Popup inventario sliding con animazione per la BattleTab

extends Control
class_name InventoryPopup

# const LOG removed - using GameLogger

# Animation settings
const SLIDE_DURATION := 0.3
const OVERLAY_ALPHA := 0.6

# References
@onready var overlay: ColorRect = $Overlay
@onready var popup_panel: Panel = $PopupPanel
@onready var close_button: Button = $PopupPanel/CloseButton
@onready var inventory_container: Control = $PopupPanel/MarginContainer/InventoryContainer

# Inventory grid (riusa InventoryTab logic)
var inventory_grid: Control = null

# State
var is_open: bool = false
var tween: Tween = null

func _ready() -> void:
	# Inizialmente nascosto
	visible = false
	
	# Setup overlay
	if overlay:
		overlay.color = Color(0, 0, 0, 0)  # Inizia trasparente
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		overlay.gui_input.connect(_on_overlay_input)
	
	# Setup close button
	if close_button:
		close_button.pressed.connect(close_popup)
	
	# Setup popup panel position (fuori schermo a sinistra)
	if popup_panel:
		popup_panel.position.x = -popup_panel.size.x
	
	# Carica l'inventory grid
	_load_inventory_grid()
	
	if GameLogger.ENABLED:
		print("[InventoryPopup] Ready")

func _load_inventory_grid() -> void:
	"""Carica una copia dell'InventoryTab per il popup"""
	if not inventory_container:
		push_error("[InventoryPopup] InventoryContainer non trovato!")
		return
	
	# Prova a caricare la scena InventoryTab
	var inv_scene_path = "res://scripts/ui/InventoryTab.tscn"
	
	if not ResourceLoader.exists(inv_scene_path):
		push_error("[InventoryPopup] InventoryTab scene non trovata: %s" % inv_scene_path)
		_create_placeholder()
		return
	
	var inv_scene: PackedScene = load(inv_scene_path)
	if inv_scene:
		inventory_grid = inv_scene.instantiate()
		inventory_container.add_child(inventory_grid)

		# Wait for the node to be ready
		await inventory_grid.ready

		# Force refresh to load current items FIRST
		if inventory_grid.has_method("_refresh_from_gamestate"):
			inventory_grid._refresh_from_gamestate()
			if GameLogger.ENABLED:
				print("[InventoryPopup] Refreshed inventory from GameState")

		# THEN make inventory READ-ONLY (after items are loaded)
		# Use call_deferred to ensure all items are fully initialized
		_make_inventory_readonly.call_deferred(inventory_grid)

		if GameLogger.ENABLED:
			print("[InventoryPopup] InventoryTab caricato nel popup (READ-ONLY)")
	else:
		_create_placeholder()

func _make_inventory_readonly(inv_tab: Control) -> void:
	"""Rende l'inventory READ-ONLY (nessun drag & drop, nessuna interazione)"""
	# Nascondi HighlightLayer (l'highlight blu)
	var highlight_layer = inv_tab.get_node_or_null("InvSplit/Left/HighlightLayer")
	if highlight_layer:
		highlight_layer.visible = false
		if GameLogger.ENABLED:
			print("[InventoryPopup] HighlightLayer hidden")

	# Disabilita mouse filter su tutti i layer interattivi E il drag sugli items
	var items_layer = inv_tab.get_node_or_null("InvSplit/Left/ItemsLayer")
	if items_layer:
		items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Disabilita drag su tutti gli items
		for item in items_layer.get_children():
			if item is Control:
				# Set a flag to disable dragging
				item.set_meta("is_draggable", false)
				# But keep mouse_filter PASS for tooltip
				item.mouse_filter = Control.MOUSE_FILTER_PASS

	# Disabilita tutti gli slot (no drag & drop)
	var holder = inv_tab.get_node_or_null("InvSplit/Left/Holder")
	if holder:
		for slot in holder.get_children():
			if slot is Control:
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Disabilita il cestino se presente
	var trash_bin = inv_tab.get_node_or_null("InvSplit/Left/TrashBin")
	if trash_bin:
		trash_bin.visible = false  # Nascondi cestino (non serve in view-only)

	# Disabilita il bottone "Drop Random Item"
	var bottone = inv_tab.get_node_or_null("InvSplit/Left/Bottone")
	if bottone:
		bottone.visible = false  # Nascondi bottone

	# Disabilita equipment slots drag & drop ma mantieni visualizzazione
	var equipment_panel = inv_tab.get_node_or_null("InvSplit/Right/EquipmentPanel")
	if equipment_panel:
		var equipment_slots = equipment_panel.get_node_or_null("EquipmentSlots")
		if equipment_slots:
			for slot in equipment_slots.get_children():
				if slot is Control:
					# Disabilita drag & drop ma permetti visualizzazione
					if slot.has_method("set_readonly"):
						slot.set_readonly(true)
					else:
						# Se non ha metodo set_readonly, disabilita solo drag events
						slot.mouse_filter = Control.MOUSE_FILTER_PASS  # Permetti hover per tooltip

					# IMPORTANT: Ensure equipped items inside slots remain visible and non-draggable
					for child in slot.get_children():
						if child is Control and child.get_class() in ["TextureRect", "Control"]:
							# Disable dragging but keep visible
							if child.has_meta("item_id") or "Item" in str(child.get_script()):
								child.set_meta("is_draggable", false)
								child.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow tooltip

	if GameLogger.ENABLED:
		print("[InventoryPopup] Inventory set to READ-ONLY mode")

func _create_placeholder() -> void:
	"""Crea un placeholder se InventoryTab non è disponibile"""
	var label = Label.new()
	label.text = "📦 INVENTORY GRID\n\n(Placeholder)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	inventory_container.add_child(label)
	print("[InventoryPopup] Placeholder creato")

func open_popup() -> void:
	"""Apre il popup con animazione slide-in"""
	if is_open:
		return

	if GameLogger.ENABLED:
		print("[InventoryPopup] Opening popup...")

	# Refresh inventory before showing
	if inventory_grid and inventory_grid.has_method("_refresh_from_gamestate"):
		inventory_grid._refresh_from_gamestate()
		if GameLogger.ENABLED:
			print("[InventoryPopup] Refreshed inventory data")

		# IMPORTANT: Re-apply readonly after refresh (items are re-instantiated!)
		_make_inventory_readonly.call_deferred(inventory_grid)

	visible = true
	is_open = true

	# Kill tween esistente se presente
	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.set_parallel(true)  # Animazioni in parallelo
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Slide-in panel da sinistra
	if popup_panel:
		var target_x = 20.0  # Offset dal bordo
		tween.tween_property(popup_panel, "position:x", target_x, SLIDE_DURATION)

	# Fade-in overlay
	if overlay:
		tween.tween_property(overlay, "color:a", OVERLAY_ALPHA, SLIDE_DURATION)

	await tween.finished

	if GameLogger.ENABLED:
		print("[InventoryPopup] Popup opened")

func close_popup() -> void:
	"""Chiude il popup con animazione slide-out"""
	if not is_open:
		return
	
	if GameLogger.ENABLED:
		print("[InventoryPopup] Closing popup...")
	
	is_open = false
	
	# Kill tween esistente se presente
	if tween and tween.is_running():
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Slide-out panel verso sinistra (fuori schermo)
	if popup_panel:
		var target_x = -popup_panel.size.x
		tween.tween_property(popup_panel, "position:x", target_x, SLIDE_DURATION)
	
	# Fade-out overlay
	if overlay:
		tween.tween_property(overlay, "color:a", 0.0, SLIDE_DURATION)
	
	await tween.finished
	visible = false
	
	if GameLogger.ENABLED:
		print("[InventoryPopup] Popup closed")

func toggle_popup() -> void:
	"""Toggle apertura/chiusura popup"""
	if is_open:
		close_popup()
	else:
		open_popup()

func _on_overlay_input(event: InputEvent) -> void:
	"""Chiudi se clicchi sull'overlay"""
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_popup()

func get_inventory_grid() -> Control:
	"""Restituisce il riferimento all'inventory grid"""
	return inventory_grid

# ==================== INPUT HANDLING ====================

func _input(event: InputEvent) -> void:
	"""Gestisci input globali (es. ESC per chiudere)"""
	if not is_open:
		return
	
	if event.is_action_pressed("ui_cancel"):  # ESC key
		close_popup()
		get_viewport().set_input_as_handled()
