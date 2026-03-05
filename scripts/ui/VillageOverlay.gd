# File: res://scripts/ui/VillageOverlay.gd
# Overlay full-map (shop Grocer incluso). Emette item_purchased(item_id, qty).
class_name VillageOverlay
extends Control

signal item_purchased(item_id: String, qty: int)

const ITEMS_JSON: String = "res://data/items.json"
const FORGE_UI_SCRIPT = preload("res://scripts/ui/ForgeUI.gd")

var _host: Control                    # map_root
var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _items_catalog: Array = []
var _forge_ui: Control = null  # ForgeUI instance

func _ready() -> void:
	_load_catalog()

func attach_to(host: Control) -> void:
	_host = host
	_build()

func open_for_npc(npc_id: String) -> void:
	if _host == null:
		return
	var npcs: Array = _load_json_array("res://data/npcs.json")
	var npc: Dictionary = {}
	for n in npcs:
		if typeof(n) == TYPE_DICTIONARY and str((n as Dictionary).get("id","")) == npc_id:
			npc = n
			break
	if npc.is_empty():
		return

	# Check for quests FIRST (highest priority)
	if has_node("/root/QuestSystem"):
		var quest_system = get_node("/root/QuestSystem")
		var npc_quests = quest_system.get_quests_for_npc(npc_id)
		if not npc_quests.is_empty():
			_show_quest_dialog(npc, npc_quests)
			visible = true
			return

	# Check if it's the forge
	if _is_forge(npc):
		_open_forge(npc)
		return

	if _is_grocer(npc):
		_show_grocer_shop(npc)
	else:
		_show_generic(npc)
	visible = true

# ----- Build -----
func _build() -> void:
	for c in get_children():
		c.queue_free()

	name = "NpcOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_host.add_child(self)

	var dim := ColorRect.new()
	dim.color = Color(0,0,0,0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(top)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 22)
	_title.text = "NPC"
	top.add_child(_title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): visible = false)
	top.add_child(close_btn)

	v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

# ----- Screens -----
func _show_generic(npc: Dictionary) -> void:
	_clear(_body)
	_title.text = str(npc.get("name","NPC"))
	var lbl := Label.new()
	lbl.text = "Parla con %s" % str(npc.get("name","NPC"))
	_body.add_child(lbl)

func _show_grocer_shop(npc: Dictionary) -> void:
	_clear(_body)
	_title.text = "%s – Shop" % str(npc.get("name","Grocer"))

	var gold_row := HBoxContainer.new()
	gold_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(gold_row)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % _get_gold()
	gold_lbl.add_theme_font_size_override("font_size", 18)
	gold_row.add_child(gold_lbl)

	_body.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for it in _items_catalog:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = str(it.get("name", it.get("id","Item")))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var price: int = int(it.get("price", 1))
		var price_lbl := Label.new()
		price_lbl.text = "%d g" % price
		price_lbl.custom_minimum_size = Vector2(64, 0)
		row.add_child(price_lbl)

		var qty := SpinBox.new()
		qty.min_value = 1
		qty.max_value = 999
		qty.step = 1
		qty.custom_minimum_size = Vector2(72, 0)
		row.add_child(qty)

		var buy := Button.new()
		buy.text = "Buy"
		buy.focus_mode = Control.FOCUS_NONE
		buy.pressed.connect(func():
			var count: int = int(qty.value)
			var cost: int = price * count
			if _get_gold() < cost:
				_toast("Not enough gold.")
				return
			_set_gold(_get_gold() - cost)
			gold_lbl.text = "Gold: %d" % _get_gold()
			item_purchased.emit(str(it.get("id","item")), count)
			_toast("Bought %dx %s" % [count, name_lbl.text])
		)
		row.add_child(buy)

func _show_quest_dialog(npc: Dictionary, quests: Array[Quest]) -> void:
	_clear(_body)
	_title.text = str(npc.get("name", "NPC"))

	for quest in quests:
		var quest_panel = PanelContainer.new()
		quest_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(quest_panel)

		var quest_margin = MarginContainer.new()
		quest_margin.add_theme_constant_override("margin_left", 8)
		quest_margin.add_theme_constant_override("margin_top", 8)
		quest_margin.add_theme_constant_override("margin_right", 8)
		quest_margin.add_theme_constant_override("margin_bottom", 8)
		quest_panel.add_child(quest_margin)

		var quest_vbox = VBoxContainer.new()
		quest_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quest_margin.add_child(quest_vbox)

		# Quest title
		var title_lbl = Label.new()
		title_lbl.text = quest.title
		title_lbl.add_theme_font_size_override("font_size", 20)
		quest_vbox.add_child(title_lbl)

		quest_vbox.add_child(HSeparator.new())

		# Quest description
		var desc_lbl = Label.new()
		desc_lbl.text = quest.description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_vbox.add_child(desc_lbl)

		quest_vbox.add_child(HSeparator.new())

		# Quest objectives
		var objectives_lbl = Label.new()
		objectives_lbl.text = "Objectives:\n" + quest.get_objectives_text()
		objectives_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_vbox.add_child(objectives_lbl)

		# Rewards
		var rewards_lbl = Label.new()
		rewards_lbl.text = "Rewards: " + quest.get_rewards_text()
		rewards_lbl.modulate = Color(1.0, 0.9, 0.3)
		quest_vbox.add_child(rewards_lbl)

		quest_vbox.add_child(HSeparator.new())

		# Action buttons
		var button_hbox = HBoxContainer.new()
		button_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_hbox.alignment = BoxContainer.ALIGNMENT_END
		quest_vbox.add_child(button_hbox)

		match quest.status:
			Quest.QuestStatus.AVAILABLE:
				# Show Accept button
				var accept_btn = Button.new()
				accept_btn.text = "Accept Quest"
				accept_btn.focus_mode = Control.FOCUS_NONE
				accept_btn.pressed.connect(func():
					if has_node("/root/QuestSystem"):
						var quest_system = get_node("/root/QuestSystem")
						quest_system.accept_quest(quest)
						_toast("Quest accepted: %s" % quest.title)
						# Refresh dialog
						await get_tree().process_frame
						var npc_quests = quest_system.get_quests_for_npc(npc.get("id", ""))
						if npc_quests.is_empty():
							visible = false
						else:
							_show_quest_dialog(npc, npc_quests)
				)
				button_hbox.add_child(accept_btn)

			Quest.QuestStatus.ACTIVE:
				# Show progress status
				var status_lbl = Label.new()
				status_lbl.text = "In Progress..."
				status_lbl.modulate = Color(0.8, 0.8, 0.8)
				button_hbox.add_child(status_lbl)

			Quest.QuestStatus.READY_TO_TURN_IN:
				# Show Turn In button
				var turnin_btn = Button.new()
				turnin_btn.text = "Turn In Quest"
				turnin_btn.focus_mode = Control.FOCUS_NONE
				turnin_btn.modulate = Color(1.0, 1.0, 0.5)
				turnin_btn.pressed.connect(func():
					if has_node("/root/QuestSystem"):
						var quest_system = get_node("/root/QuestSystem")
						quest_system.turn_in_quest(quest)
						_toast("Quest completed: %s" % quest.title)
						# Close dialog after turn-in
						await get_tree().process_frame
						visible = false
				)
				button_hbox.add_child(turnin_btn)

		_body.add_child(VSeparator.new())

# ----- Helpers -----
func _is_grocer(npc: Dictionary) -> bool:
	var id: String = str(npc.get("id","")).to_lower()
	var role: String = str(npc.get("role","")).to_lower()
	var name: String = str(npc.get("name","")).to_lower()
	return id.contains("grocer") or role.contains("grocer") or name.contains("grocer")

func _is_forge(npc: Dictionary) -> bool:
	var id: String = str(npc.get("id","")).to_lower()
	return id == "forge" or id.contains("fabbro")

func _open_forge(npc: Dictionary) -> void:
	# Hide standard overlay
	visible = false

	# Create ForgeUI if not exists
	if _forge_ui == null:
		_forge_ui = FORGE_UI_SCRIPT.new()
		_forge_ui.attach_to(_host)

	# Open forge
	_forge_ui.open_forge()
	print("[VillageOverlay] Opened Forge UI")

func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

func _toast(msg: String, secs: float = 1.5) -> void:
	var note := Label.new()
	note.text = msg
	note.modulate = Color(1,1,1,0.0)
	note.anchor_left = 1.0
	note.anchor_top = 0.0
	note.anchor_right = 1.0
	note.anchor_bottom = 0.0
	note.offset_left = -12
	note.offset_top = 12
	add_child(note)
	var tw := create_tween()
	tw.tween_property(note, "modulate:a", 1.0, 0.15)
	tw.tween_interval(secs)
	tw.tween_property(note, "modulate:a", 0.0, 0.25)
	tw.finished.connect(func():
		if is_instance_valid(note): note.queue_free()
	)

# ----- Gold & catalog -----
func _get_gold() -> int:
	if has_node("/root/GameState"):
		var gs: Object = get_node("/root/GameState")
		if gs:
			var res: Variant = gs.get("resources")
			if typeof(res) == TYPE_DICTIONARY and (res as Dictionary).has("gold"):
				return int((res as Dictionary)["gold"])
	return 0

func _set_gold(v: int) -> void:
	if has_node("/root/GameState"):
		var gs: Object = get_node("/root/GameState")
		if gs:
			var res: Variant = gs.get("resources")
			if typeof(res) == TYPE_DICTIONARY:
				var d: Dictionary = res
				d["gold"] = v
				gs.set("resources", d)
				if gs.has_signal("resources_changed"):
					gs.resources_changed.emit()
				if gs.has_method("save"):
					gs.save()

func _load_catalog() -> void:
	if ResourceLoader.exists(ITEMS_JSON):
		var arr: Array = _load_json_array(ITEMS_JSON)
		if arr.size() > 0:
			_items_catalog = arr
	if _items_catalog.is_empty():
		_items_catalog = [
			{"id":"potion","name":"Potion","price":5},
			{"id":"log","name":"Log","price":1},
			{"id":"fish","name":"Fish","price":2}
		]

func _load_json_array(path: String) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return (data as Array) if typeof(data) == TYPE_ARRAY else []
