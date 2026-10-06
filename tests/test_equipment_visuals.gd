extends GutTest
## Test del sistema skin 3D: catalogo (EquipmentVisuals), montaggio sul warrior (WarriorVisual),
## collegamento agli item e regole degli slot dei 3 stili (GameState.can_equip_in_slot).

var _warrior: WarriorVisual = null


func before_each() -> void:
	EquipmentVisuals.reload()
	var world := Node3D.new()
	add_child_autofree(world)
	_warrior = WarriorVisual.new()
	world.add_child(_warrior)
	await get_tree().process_frame


# ==================== CATALOGO ====================

func test_defaults_exist_for_every_slot() -> void:
	for slot in WarriorVisual.SLOTS:
		var id := EquipmentVisuals.default_for(slot)
		assert_true(EquipmentVisuals.has_visual(id), "Lo slot %s deve avere una skin base valida" % slot)


func test_inheritance_keeps_base_and_adds_colors() -> void:
	var v := EquipmentVisuals.get_visual("sword_disciple")
	assert_eq(str(v.get("node")), "Eq_Sword", "La variante eredita il modello dalla skin base")
	assert_eq(str(v.get("slot")), "weapon", "La variante eredita lo slot")
	assert_true(v["colors"].has("M_Blade"), "La variante ha i suoi colori")
	assert_almost_eq(float(v.get("scale", 1.0)), 1.08, 0.001, "La variante può cambiare la scala")


func test_every_item_visual_exists() -> void:
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for it in items:
		if it.has("visual"):
			assert_true(EquipmentVisuals.has_visual(str(it["visual"])), "La skin '%s' dell'item %s deve esistere" % [it["visual"], it["id"]])


func test_visual_for_item_fallbacks() -> void:
	assert_eq(EquipmentVisuals.visual_for_item({"slot": "weapon", "visual": "sword_iron"}, "weapon"), "sword_iron", "Usa la skin dell'item")
	assert_eq(EquipmentVisuals.visual_for_item({"slot": "helmet"}, "helmet"), EquipmentVisuals.default_for("helmet"), "Senza skin usa quella base dello slot")
	assert_eq(EquipmentVisuals.visual_for_item({"slot": "boots", "visual": "non_esiste"}, "boots"), EquipmentVisuals.default_for("boots"), "Skin inesistente → skin base")


func test_offhand_piece_keeps_weapon_colors() -> void:
	var piece := EquipmentVisuals.piece_for("sword_iron", "shield")
	assert_eq(str(piece.get("offhand")), "weapon", "Una spada nello slot sinistro è un'arma, non uno scudo")
	assert_eq(str(piece.get("bone")), "hand.L", "La seconda spada va sulla mano sinistra")
	assert_eq(piece["colors"].get("M_Blade"), EquipmentVisuals.get_visual("sword_iron")["colors"]["M_Blade"], "Tiene i colori della spada di ferro")


# ==================== WARRIOR ====================

func test_defaults_equipped_and_body_parts_hidden() -> void:
	assert_true(_warrior.is_slot_equipped("helmet"), "Con equip_defaults l'elmo è montato")
	assert_false(_warrior.is_body_part_visible("Body_Head"), "L'elmo nasconde la testa del corpo base")
	assert_false(_warrior.is_body_part_visible("Body_Torso"), "La corazza nasconde il busto")
	assert_true(_warrior.is_body_part_visible("Body"), "Il corpo base resta visibile")


func test_unequip_shows_body_part_again() -> void:
	_warrior.unequip("helmet")
	assert_false(_warrior.is_slot_equipped("helmet"), "Slot vuoto dopo unequip")
	assert_true(_warrior.is_body_part_visible("Body_Head"), "Senza elmo la testa torna visibile")
	_warrior.unequip("boots")
	assert_true(_warrior.is_body_part_visible("Body_Feet"), "Senza stivali tornano i piedi")


func test_equip_variant_replaces_piece() -> void:
	assert_true(_warrior.equip_visual("weapon", "sword_disciple"), "La variante si monta")
	assert_eq(_warrior.get_slot_visual("weapon"), "sword_disciple", "Lo slot usa la nuova skin")
	assert_not_null(_warrior.get_slot_mesh("weapon"), "C'è una mesh per l'arma")


func test_unknown_visual_is_rejected() -> void:
	assert_false(_warrior.equip_visual("weapon", "skin_che_non_esiste"), "Una skin sconosciuta non si monta")
	# l'avviso "skin sconosciuta" è voluto: lo segno come previsto
	for e in get_errors():
		e.handled = true
	assert_eq(_warrior.get_slot_visual("weapon"), EquipmentVisuals.default_for("weapon"), "E resta quella di prima")


func test_style_follows_weapons() -> void:
	assert_eq(_warrior.style, WarriorVisual.STYLE_SWORD_SHIELD, "Spada + scudo")
	_warrior.equip_visual("shield", "sword_iron")
	assert_eq(_warrior.style, WarriorVisual.STYLE_DUAL, "Seconda spada nella mano sinistra = due spade")
	_warrior.equip_visual("shield", "shield_basic")
	assert_eq(_warrior.style, WarriorVisual.STYLE_SWORD_SHIELD, "Rimesso lo scudo torna spada + scudo")


func test_greatsword_style_and_left_hand_blocked() -> void:
	if not _warrior.equip_visual("weapon", "greatsword_basic"):
		pending("Eq_Greatsword non ancora nel modello")
		return
	assert_eq(_warrior.style, WarriorVisual.STYLE_GREATSWORD, "Spadone = stile spadone")
	assert_false(_warrior.is_slot_equipped("shield"), "Montare lo spadone toglie lo scudo")
	assert_false(_warrior.equip_visual("shield", "shield_basic"), "Con lo spadone la mano sinistra è bloccata")
	assert_eq(_warrior.styled_animation("attack1"), "gs_attack1", "Usa le animazioni dello spadone")
	_warrior.equip_visual("weapon", "sword_basic")
	assert_eq(_warrior.style, WarriorVisual.STYLE_SWORD_SHIELD, "Tornando alla spada si torna allo stile base")


func test_styled_animation_falls_back_to_base() -> void:
	_warrior.equip_visual("shield", "sword_iron")
	var anim := _warrior.styled_animation("attack1")
	assert_true(anim == "attack1" or anim == "dual_attack1", "Usa dual_attack1 se esiste, altrimenti attack1")
	assert_true(_warrior.has_animation(anim), "L'animazione scelta esiste")


func test_enhancement_glow_on_slot() -> void:
	_warrior.set_enhancement("weapon", 9)
	assert_eq(_warrior.get_enhancement("weapon"), 9, "Livello salvato per lo slot")
	assert_not_null(_warrior.get_slot_mesh("weapon").material_overlay, "+9 aggiunge il bagliore all'arma")
	_warrior.equip_visual("weapon", "sword_iron")
	assert_not_null(_warrior.get_slot_mesh("weapon").material_overlay, "Cambiando skin il bagliore resta")


# ==================== REGOLE SLOT (GameState) ====================

func test_slot_rules() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState non disponibile")
		return
	var saved_weapon = gs.equipped_items.get("weapon")
	var sword := {"slot": "weapon", "weapon_type": "one_hand"}
	var greatsword := {"slot": "weapon", "weapon_type": "two_hand"}
	var shield := {"slot": "shield"}
	gs.equipped_items["weapon"] = null
	assert_true(gs.can_equip_in_slot(sword, "weapon"), "Spada nello slot arma")
	assert_true(gs.can_equip_in_slot(sword, "shield"), "Spada a una mano anche nella mano sinistra")
	assert_false(gs.can_equip_in_slot(greatsword, "shield"), "Lo spadone non va nella mano sinistra")
	assert_true(gs.can_equip_in_slot(shield, "shield"), "Scudo nello slot scudo")
	assert_false(gs.can_equip_in_slot(shield, "weapon"), "Scudo non nello slot arma")
	gs.equipped_items["weapon"] = greatsword
	assert_false(gs.can_equip_in_slot(shield, "shield"), "Con lo spadone la mano sinistra è bloccata")
	gs.equipped_items["weapon"] = saved_weapon


# ==================== COLLEGAMENTO A GAMESTATE ====================

func test_player_follows_game_state_equipment() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState non disponibile")
		return
	var saved: Dictionary = gs.equipped_items.duplicate(true)
	for slot in gs.equipped_items:
		gs.equipped_items[slot] = null
	var player := PlayerCharacter3D.new()
	_warrior.get_parent().add_child(player)
	await get_tree().process_frame
	var w := player.visual
	assert_false(w.is_slot_equipped("helmet"), "Senza equip nel gioco il warrior non ha l'elmo")
	assert_true(w.is_body_part_visible("Body_Head"), "e si vede la testa")

	var helmet := {"id": "leather_helmet", "slot": "helmet", "visual": "helmet_leather", "enhancement_level": 8}
	gs.equipped_items["helmet"] = helmet
	gs.on_item_equipped.emit("helmet", helmet)
	assert_eq(w.get_slot_visual("helmet"), "helmet_leather", "Equipaggiare nel gioco monta la skin dell'item")
	assert_eq(w.get_enhancement("helmet"), 8, "con il suo livello di potenziamento")

	var sword := {"id": "iron_sword", "slot": "weapon", "visual": "sword_iron", "weapon_type": "one_hand"}
	gs.equipped_items["shield"] = sword
	gs.on_item_equipped.emit("shield", sword)
	assert_eq(w.style, WarriorVisual.STYLE_DUAL, "Una spada nella mano sinistra attiva lo stile due spade")

	gs.equipped_items["helmet"] = null
	gs.on_item_unequipped.emit("helmet", helmet)
	assert_false(w.is_slot_equipped("helmet"), "Togliere l'oggetto nel gioco lo toglie anche al warrior")

	for slot in saved:
		gs.equipped_items[slot] = saved[slot]
	player.queue_free()


# ==================== GIOIELLI ====================

func test_jewelry_slots_exist_and_are_not_visual() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState non disponibile")
		return
	var saved: Dictionary = gs.equipped_items.duplicate(true)
	gs.equipped_items.erase("necklace")  # come un salvataggio fatto prima dei gioielli
	gs._ensure_equipment_slots()
	for slot in ["earrings", "necklace", "bracelet"]:
		assert_true(gs.equipped_items.has(slot), "Lo slot %s esiste (anche con salvataggi vecchi)" % slot)
		assert_true(gs.can_equip_in_slot({"slot": slot}, slot), "Un gioiello va nel suo slot")
		assert_false(slot in WarriorVisual.SLOTS, "I gioielli non si vedono sul personaggio 3D")
	assert_false(gs.can_equip_in_slot({"slot": "necklace"}, "earrings"), "Una collana non va negli orecchini")
	assert_false(gs.can_equip_in_slot({"slot": "weapon", "weapon_type": "one_hand"}, "bracelet"), "Un'arma non va nel bracciale")
	for slot in saved:
		gs.equipped_items[slot] = saved[slot]
