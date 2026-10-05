@tool
class_name EquipmentVisuals
extends RefCounted
## Catalogo delle skin 3D degli equip (data/equipment_visuals.json).
## Risolve l'ereditarietà ("base"), i colori e sceglie la skin giusta per un item del gioco.
## Per aggiungere una skin: un nodo nuovo in un .glb + una riga nel JSON (+ "visual" sull'item).

const DATA_PATH := "res://data/equipment_visuals.json"
const SLOTS := ["weapon", "shield", "helmet", "chest", "boots", "belt"]

static var _raw: Dictionary = {}
static var _defaults: Dictionary = {}
static var _resolved: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[EquipmentVisuals] %s non leggibile" % DATA_PATH)
		return
	_raw = data.get("visuals", {})
	_defaults = data.get("defaults", {})


## Ricarica il JSON (es. dopo averlo modificato mentre il gioco gira)
static func reload() -> void:
	_loaded = false
	_resolved.clear()
	_ensure_loaded()


static func has_visual(id: String) -> bool:
	_ensure_loaded()
	return _raw.has(id)


## Skin completa con i campi ereditati; "colors" già convertiti in Color. {} se non esiste.
static func get_visual(id: String) -> Dictionary:
	_ensure_loaded()
	if _resolved.has(id):
		return _resolved[id]
	if not _raw.has(id):
		return {}
	var v: Dictionary = _merge_chain(id, 0)
	v["id"] = id
	var colors := {}
	for mat_name in v.get("colors", {}):
		colors[mat_name] = Color.html(str(v["colors"][mat_name]))
	v["colors"] = colors
	if v.has("tint") and v["tint"] is String:
		v["tint"] = Color.html(v["tint"])
	_resolved[id] = v
	return v


static func _merge_chain(id: String, depth: int) -> Dictionary:
	var own: Dictionary = _raw.get(id, {})
	if depth > 8 or not own.has("base"):
		return own.duplicate(true)
	var merged := _merge_chain(str(own["base"]), depth + 1)
	for k in own:
		if k == "colors":
			var c: Dictionary = merged.get("colors", {}).duplicate()
			c.merge(own["colors"], true)
			merged["colors"] = c
		elif k != "base":
			merged[k] = own[k]
	return merged


static func default_for(slot: String) -> String:
	_ensure_loaded()
	return str(_defaults.get(slot, ""))


## Skin da mostrare per un item equipaggiato (item senza "visual" valido → skin base dello slot;
## un'arma nello slot "shield" senza skin → spada base).
static func visual_for_item(item_data: Dictionary, slot: String) -> String:
	_ensure_loaded()
	var id := str(item_data.get("visual", ""))
	if has_visual(id):
		return id
	if slot == "shield" and str(item_data.get("slot", "")) == "weapon":
		return default_for("weapon")
	return default_for(slot)


## Pezzo finale da montare in uno slot. Un'arma a una mano nello slot "shield" (stile due spade)
## prende modello e osso della sua versione per la mano sinistra, ma tiene colori e scala propri.
static func piece_for(id: String, slot: String) -> Dictionary:
	var v := get_visual(id)
	if v.is_empty():
		return {}
	if slot == "shield" and str(v.get("slot", "")) == "weapon":
		var oh := get_visual(str(v.get("offhand_visual", default_for("offhand_weapon"))))
		if oh.is_empty():
			return {}
		var piece := oh.duplicate(true)
		var colors: Dictionary = oh.get("colors", {}).duplicate()
		colors.merge(v.get("colors", {}), true)
		piece["colors"] = colors
		piece["scale"] = v.get("scale", oh.get("scale", 1.0))
		if v.has("tint"):
			piece["tint"] = v["tint"]
		piece["id"] = id + "@offhand"
		piece["offhand"] = "weapon"
		return piece
	return v


## Tutte le skin di uno slot (per anteprime e prove)
static func ids_for_slot(slot: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for id in _raw:
		if str(get_visual(id).get("slot", "")) == slot:
			out.append(id)
	return out
