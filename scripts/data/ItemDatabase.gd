extends Node
class_name ItemDatabase

var items: Dictionary = {}

func _ready():
	load_items()

func load_items():
	var file = FileAccess.open("res://data/items.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		var parsed = JSON.parse_string(json_text)
		file.close()
		
		if parsed is Array:
			# Nuovo formato: array di oggetti
			items.clear()
			for item_data in parsed:
				if item_data is Dictionary and item_data.has("id"):
					items[item_data.id] = item_data
		elif parsed is Dictionary:
			# Vecchio formato: oggetto con chiavi
			items = parsed
		
		print("[ItemDatabase] Loaded %d items" % items.size())

func get_random_item() -> Dictionary:
	if items.is_empty():
		return {}
	var keys = items.keys()
	var rand_id = keys[randi() % keys.size()]
	return { "id": rand_id, "data": items[rand_id] }
