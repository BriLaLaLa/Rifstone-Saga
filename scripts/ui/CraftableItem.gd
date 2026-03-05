# File: res://scripts/ui/CraftableItem.gd
# Estensione di Item che supporta crafting con gemme

extends Item
class_name CraftableItem

# Scene references
const CUSTOM_TOOLTIP_SCENE = preload("res://scenes/ui/CustomTooltip.tscn")

# Dati dinamici dell'item (include bonuses)
var item_data: Dictionary = {}

# Custom tooltip instance (now using CustomTooltip.tscn instead of Panel.new())
var custom_tooltip: CustomTooltip = null

# Track last slot that triggered tooltip to prevent duplicate triggers
var _last_tooltip_slot: Vector2i = Vector2i(-1, -1)

# Override setup_item per supportare i bonus
func setup_item(id: String, data: Dictionary) -> void:
	"""Configura l'item con supporto per bonus"""
	item_id = id
	item_data = data.duplicate(true)  # Deep copy to preserve bonuses

	# CRITICAL: Store item_data in metadata for _sync_to_gamestate() to access
	set_meta("item_data", item_data)

	if data.has("size") and data.size is Array and data.size.size() >= 2:
		item_size = Vector2i(data.size[0], data.size[1])

	if data.has("icon") and data.icon != "":
		var tex = load(data.icon)
		if tex:
			texture = tex

	# Crea il tooltip con bonus
	_update_tooltip()

	# NOTE: Upgrade level is now shown in tooltip name only (Metin2 style)
	# We don't create a visual label anymore

	custom_minimum_size = Vector2(item_size.x * cell_px, item_size.y * cell_px)
	size = custom_minimum_size

	# IMPORTANTE: Assicurati che riceva eventi drop PRIMA dello slot sottostante
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_STOP  # Ferma eventi al parent

func _update_tooltip() -> void:
	"""Clear native tooltip (we use custom tooltip via CustomTooltip.tscn)"""
	# CONVERSION: Removed ~50 lines of duplicate tooltip formatting
	# Tooltip is now generated on-demand by CustomTooltip.setup_item() when mouse enters
	tooltip_text = ""  # Clear native tooltip (doesn't support BBCode)

func _get_rarity_color() -> Color:
	"""Restituisce il colore della rarità dell'item"""
	if not item_data.has("bonuses"):
		return Color.WHITE

	var count = item_data.bonuses.size()

	if count == 0:
		return Color.WHITE
	elif count <= 2:
		return Color(0.3, 0.6, 1.0)  # Blu
	elif count <= 4:
		return Color(1.0, 0.9, 0.2)  # Giallo
	else:
		return Color(1.0, 0.6, 0.0)  # Oro

func _update_visual_rarity() -> void:
	"""Aggiorna il colore del bordo in base alla rarità"""
	var rarity_color = _get_rarity_color()

	# Modula il colore dell'item per mostrare rarità
	if rarity_color != Color.WHITE:
		modulate = rarity_color.lerp(Color.WHITE, 0.5)  # Mix con bianco per non saturare
	else:
		modulate = Color.WHITE

func get_bonus_count() -> int:
	"""Restituisce il numero di bonus sull'item"""
	if not item_data.has("bonuses"):
		return 0
	return item_data.bonuses.size()

func is_weapon() -> bool:
	"""Controlla se l'item è un'arma"""
	return item_data.get("type", "") == "Weapon"

func is_gem() -> bool:
	"""Controlla se l'item è una gemma"""
	return item_data.get("type", "") == "Gem"

func can_accept_drop() -> bool:
	"""Determina se questo item può accettare un drop (solo weapon per ora)"""
	return is_weapon()

# Override _get_drag_data per includere item_data
func _get_drag_data(at_position: Vector2) -> Variant:
	var data = super._get_drag_data(at_position)
	if typeof(data) == TYPE_DICTIONARY:
		data["item_data"] = item_data
	return data

# ==================== GEM CRAFTING SUPPORT ====================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Controlla se puoi droppare una gemma su quest'arma"""
	if typeof(data) != TYPE_DICTIONARY:
		return false

	# Accetta solo gemme
	var dragged_item_data = data.get("item_data", {})
	if dragged_item_data.get("type", "") != "Gem":
		return false

	# Accetta solo su armi
	if not is_weapon():
		return false

	print("[CraftableItem] Can accept gem on weapon %s" % item_id)
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	"""Applica una gemma all'arma"""
	# IMPORTANTE: Verifica che sia una gemma prima di procedere
	if typeof(data) != TYPE_DICTIONARY:
		return

	var dragged_item_data = data.get("item_data", {})
	if dragged_item_data.get("type", "") != "Gem":
		# Non è una gemma, lascia che l'evento si propaghi al parent (slot)
		return

	# È una gemma! Procedi con l'applicazione
	var gem_item = data.get("item", null)
	var gem_id = data.get("item_id", "")

	if gem_item == null or gem_id == "":
		return

	print("[CraftableItem] Applying gem %s to weapon %s" % [gem_id, item_id])

	# Cerca il GemCrafting system
	var gem_crafting = get_node_or_null("/root/GemCrafting")
	if not gem_crafting:
		push_error("[CraftableItem] GemCrafting system not found!")
		return

	# Applica la gemma
	var result = gem_crafting.apply_gem_to_item(item_data, gem_id)

	# Aggiorna i dati locali
	item_data = result.item

	# CRITICAL: Aggiorna metadata con i nuovi bonuses!
	set_meta("item_data", item_data)
	print("[CraftableItem] ✅ Updated item_data metadata with new bonuses: %d" % item_data.bonuses.size())

	# IMPORTANTE: Aggiorna anche GameState.inventory_items con i nuovi bonus!
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("update_inventory_item_bonuses"):
		# Trova la posizione dell'item nell'inventario
		var inv_tab = _find_inventory_tab()
		if inv_tab and inv_tab.has_method("get_item_position"):
			var item_pos = inv_tab.get_item_position(self)
			if item_pos != Vector2i(-1, -1):
				gs.update_inventory_item_bonuses(item_id, item_pos, item_data.get("bonuses", []))
				print("[CraftableItem] 💾 Updated bonuses in GameState.inventory_items")

	# Aggiorna tooltip per mostrare nuovi bonus
	_update_tooltip()

	# Aggiorna visivamente il bordo se necessario (colore rarità)
	_update_visual_rarity()

	# Se il tooltip è visibile, aggiornalo in tempo reale
	if custom_tooltip:
		_refresh_custom_tooltip()

	# Se la gemma è stata consumata, rimuovila dall'inventario
	if result.gem_consumed:
		print("[CraftableItem] Gem consumed! New bonuses: %d" % item_data.bonuses.size())

		# CRITICAL: Restore mouse filter on all items BEFORE deleting the gem!
		# The gem's drag set all other items to IGNORE, we need to restore them to PASS
		if gem_item.has_method("_restore_mouse_filter"):
			print("[CraftableItem] 🔧 Restoring mouse filter on all items before deleting gem")
			gem_item._restore_mouse_filter()

		# CRITICAL: Rimuovi la gemma da ENTRAMBI inventory E inventory_items!
		if gs:
			# 1. Rimuovi dall'inventory dictionary (quantità)
			if "inventory" in gs:
				var inv = gs.get("inventory")
				if inv.has(gem_id):
					inv[gem_id] = max(0, inv[gem_id] - 1)
					if inv[gem_id] == 0:
						inv.erase(gem_id)

			# 2. CRITICAL: Rimuovi da inventory_items (posizioni)
			var inv_tab = _find_inventory_tab()
			if inv_tab and inv_tab.has_method("get_item_position"):
				var gem_pos = inv_tab.get_item_position(gem_item)
				if gem_pos != Vector2i(-1, -1):
					# Trova e rimuovi l'item da inventory_items
					for i in range(gs.inventory_items.size() - 1, -1, -1):
						var inv_item = gs.inventory_items[i]
						var inv_pos = inv_item.get("pos")
						# Convert Dictionary to Vector2i if needed
						var pos_vec: Vector2i
						if inv_pos is Dictionary:
							pos_vec = Vector2i(inv_pos.get("x", 0), inv_pos.get("y", 0))
						else:
							pos_vec = inv_pos

						if inv_item.get("item_id") == gem_id and pos_vec == gem_pos:
							gs.inventory_items.remove_at(i)
							print("[CraftableItem] 🗑️ Removed gem from inventory_items at pos %s" % gem_pos)
							break

		# 3. CRITICAL: Gestisci stack - rimuovi solo 1 gemma dallo stack
		var inv_tab = _find_inventory_tab()
		if gem_item.has_method("get") and "stack_count" in gem_item:
			var current_stack = gem_item.stack_count
			print("[CraftableItem] Stack detected: %d gems in stack" % current_stack)

			if current_stack > 1:
				# Diminuisci lo stack di 1
				gem_item.stack_count = current_stack - 1
				if gem_item.has_method("_update_stack_label"):
					gem_item._update_stack_label()
				print("[CraftableItem] ✅ Reduced stack from %d to %d" % [current_stack, current_stack - 1])
			else:
				# Era l'ultima gemma nello stack, rimuovila completamente
				print("[CraftableItem] Last gem in stack, removing completely")
				if inv_tab and inv_tab.has_method("_remove_item_if_exists"):
					inv_tab._remove_item_if_exists(gem_item)
					print("[CraftableItem] 🧹 Removed gem from InventoryTab tracking")
				gem_item.queue_free()
				print("[CraftableItem] ✅ Gem visual node queued for deletion")
		else:
			# Non è uno stack, rimuovi normalmente
			if inv_tab and inv_tab.has_method("_remove_item_if_exists"):
				inv_tab._remove_item_if_exists(gem_item)
				print("[CraftableItem] 🧹 Removed gem from InventoryTab tracking")
			gem_item.queue_free()
			print("[CraftableItem] ✅ Gem visual node queued for deletion")
	else:
		print("[CraftableItem] Gem NOT consumed (already at max), returning to inventory")

# ==================== CUSTOM TOOLTIP ====================

func _ready() -> void:
	super._ready()

	# CRITICAL: Restore MOUSE_FILTER_STOP after super._ready() sets it to PASS
	# We need STOP to receive _can_drop_data() and _drop_data() events for gems!
	mouse_filter = Control.MOUSE_FILTER_STOP

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	"""Show custom tooltip with BBCode support"""
	_show_custom_tooltip()

func _on_mouse_exited() -> void:
	"""Hide custom tooltip"""
	_hide_custom_tooltip()

func _show_custom_tooltip() -> void:
	"""Create and show a RichTextLabel tooltip"""
	if custom_tooltip:
		print("[CraftableItem] 💡 Tooltip already showing for %s, skipping duplicate" % item_id)
		return  # Already showing

	print("[CraftableItem] 💡 Showing tooltip for %s" % item_id)

	# CONVERSION: Use CustomTooltip.tscn instead of creating Panel.new()
	# This replaces ~50 lines of manual tooltip creation with scene instantiation
	custom_tooltip = CUSTOM_TOOLTIP_SCENE.instantiate()

	# Add to scene tree (must be done before setup to ensure nodes are ready)
	get_tree().root.add_child(custom_tooltip)

	# Setup tooltip with item data (CustomTooltip handles all formatting)
	custom_tooltip.setup_item(item_data)

	# Show tooltip near mouse (CustomTooltip handles positioning)
	custom_tooltip.show_at_mouse()

func _hide_custom_tooltip() -> void:
	"""Hide and cleanup custom tooltip"""
	if custom_tooltip:
		print("[CraftableItem] 💡 Hiding tooltip for %s" % item_id)
		custom_tooltip.hide_tooltip()  # Use CustomTooltip's hide method
		custom_tooltip.queue_free()
		custom_tooltip = null
	_last_tooltip_slot = Vector2i(-1, -1)  # Reset slot tracking

func _refresh_custom_tooltip() -> void:
	"""Refresh tooltip content without hiding/showing"""
	if not custom_tooltip:
		return

	# CONVERSION: Simply call setup_item again - CustomTooltip handles all formatting
	# This replaces ~60 lines of duplicated tooltip formatting code
	custom_tooltip.setup_item(item_data)

# ==================== HELPER FUNCTIONS ====================

func _find_inventory_tab():
	"""Trova il nodo InventoryTab risalendo la gerarchia"""
	var current = get_parent()
	while current != null:
		if current.get_script() and current.get_script().resource_path.ends_with("InventoryTab.gd"):
			return current
		if current.name == "InventoryTab" or current.name == "Inventory":
			return current
		current = current.get_parent()
	return null
