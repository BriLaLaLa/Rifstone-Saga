# File: res://scripts/battle/InventoryPopup.gd
# Popup inventario sliding con animazione per la BattleTab

extends Control
class_name InventoryPopup

const LOG := true

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
	
	if LOG:
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
		
		# Configura per il popup (dimensioni ridotte opzionali)
		# IMPORTANTE: Usa set() invece di accesso diretto per evitare errori
		if inventory_grid.has_method("set"):
			# Prova a settare cols e rows se esistono come proprietà
			if "cols" in inventory_grid:
				inventory_grid.set("cols", 8)  # Mantieni 8 colonne
			if "rows" in inventory_grid:
				inventory_grid.set("rows", 5)  # Mantieni 5 righe
		
		inventory_container.add_child(inventory_grid)
		
		if LOG:
			print("[InventoryPopup] InventoryTab caricato nel popup")
	else:
		_create_placeholder()

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
	
	if LOG:
		print("[InventoryPopup] Opening popup...")
	
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
	
	if LOG:
		print("[InventoryPopup] Popup opened")

func close_popup() -> void:
	"""Chiude il popup con animazione slide-out"""
	if not is_open:
		return
	
	if LOG:
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
	
	if LOG:
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
