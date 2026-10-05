# scripts/combat/RouteManager.gd
# Gestisce le route di una zona: default (da ZoneData) + custom salvate su file.
# Ricorda l'ultima route scelta dal giocatore per zona.
# Persistenza: user://routes_{zone_id}.json → { "custom": [...], "selected": "route_id" }
# NB: niente class_name di proposito — viene preloadato dove serve (evita problemi
# di cache delle classi globali nei run headless GUT).

extends RefCounted

func _save_path(zone_id: String) -> String:
	return "user://routes_%s.json" % zone_id

# ---- Lettura ----

# Lista completa di route per la zona: default + custom (ognuna {id,name,loop,waypoints,is_custom})
func get_routes(zone_id: String, default_routes: Array) -> Array:
	var routes: Array = []
	for r in default_routes:
		routes.append(_normalize(r, false))
	for r in _load_file(zone_id).get("custom", []):
		routes.append(_normalize(r, true))
	return routes

func get_selected_route_id(zone_id: String) -> String:
	return str(_load_file(zone_id).get("selected", ""))

# ---- Scrittura ----

func set_selected_route_id(zone_id: String, route_id: String) -> void:
	var data := _load_file(zone_id)
	data["selected"] = route_id
	_write_file(zone_id, data)

func save_custom_route(zone_id: String, route: Dictionary) -> void:
	var data := _load_file(zone_id)
	var custom: Array = data.get("custom", [])
	# Sostituisci se esiste già un id uguale, altrimenti append
	var replaced := false
	for i in range(custom.size()):
		if str(custom[i].get("id", "")) == str(route.get("id", "")):
			custom[i] = route
			replaced = true
			break
	if not replaced:
		custom.append(route)
	data["custom"] = custom
	_write_file(zone_id, data)

# ---- Helpers ----

func _normalize(r: Dictionary, is_custom: bool) -> Dictionary:
	return {
		"id":        str(r.get("id", "route")),
		"name":      str(r.get("name", "Route")),
		"loop":      bool(r.get("loop", true)),
		"waypoints": r.get("waypoints", []),
		"is_custom": is_custom,
	}

func _load_file(zone_id: String) -> Dictionary:
	var path := _save_path(zone_id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _write_file(zone_id: String, data: Dictionary) -> void:
	var f := FileAccess.open(_save_path(zone_id), FileAccess.WRITE)
	if f == null:
		push_error("[RouteManager] Impossibile scrivere %s" % _save_path(zone_id))
		return
	f.store_string(JSON.stringify(data))
	f.close()
