class_name EquipmentSync3D
extends Node
## Tiene il warrior 3D allineato all'equipaggiamento del gioco (GameState.equipped_items):
## mettere, togliere o potenziare un oggetto si vede subito addosso al personaggio.
## Si aggiunge come figlio di chi possiede il WarriorVisual (es. PlayerCharacter3D).

var warrior: WarriorVisual


func _init(p_warrior: WarriorVisual = null) -> void:
	warrior = p_warrior


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or warrior == null:
		return
	gs.on_item_equipped.connect(_on_equipment_changed)
	gs.on_item_unequipped.connect(_on_equipment_changed)
	var es = get_node_or_null("/root/EnhancementSystem")
	if es:
		es.enhancement_succeeded.connect(_on_enhanced)
	refresh()


func _on_equipment_changed(_slot: String, _item_data: Dictionary) -> void:
	refresh()


func _on_enhanced(_item_id: String, _new_level: int) -> void:
	refresh()


## Riallinea tutti gli slot: skin dell'item (o quella base dello slot) e livello di potenziamento
func refresh() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not is_instance_valid(warrior):
		return
	for slot in WarriorVisual.SLOTS:
		var item = gs.equipped_items.get(slot)
		if item == null or not (item is Dictionary) or item.is_empty():
			warrior.unequip(slot)
			continue
		var visual_id := EquipmentVisuals.visual_for_item(item, slot)
		var level := int(item.get("enhancement_level", 0))
		if warrior.get_slot_visual(slot) == visual_id:
			warrior.set_enhancement(slot, level)
		else:
			warrior.equip_visual(slot, visual_id, level)
