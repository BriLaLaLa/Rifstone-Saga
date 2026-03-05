# File: res://scripts/gathering/GatheringDatabase.gd
# Database for gathering nodes and tools
# Singleton autoload for global access

extends Node

# Data caches
var nodes: Dictionary = {}
var tools: Dictionary = {}
var spawn_rates: Dictionary = {}

# ==================== INITIALIZATION ====================

func _ready() -> void:
	_load_nodes_data()
	_load_tools_data()

func _load_nodes_data() -> void:
	"""Load gathering nodes data from JSON file"""
	var file_path = "res://data/gathering_nodes.json"

	if not FileAccess.file_exists(file_path):
		push_error("[GatheringDatabase] gathering_nodes.json not found at: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[GatheringDatabase] Failed to open gathering_nodes.json")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error("[GatheringDatabase] Failed to parse gathering_nodes.json: %s" % json.get_error_message())
		return

	var data = json.get_data()

	if data.has("nodes"):
		nodes = data["nodes"]

	if data.has("spawn_rates"):
		spawn_rates = data["spawn_rates"]

	if GameLogger.ENABLED:
		print("[GatheringDatabase] ✅ Loaded %d node types" % nodes.size())
		for node_id in nodes.keys():
			print("[GatheringDatabase]   - %s" % node_id)

func _load_tools_data() -> void:
	"""Load gathering tools data from JSON file"""
	var file_path = "res://data/gathering_tools.json"

	if not FileAccess.file_exists(file_path):
		push_error("[GatheringDatabase] gathering_tools.json not found at: %s" % file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[GatheringDatabase] Failed to open gathering_tools.json")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error("[GatheringDatabase] Failed to parse gathering_tools.json: %s" % json.get_error_message())
		return

	var data = json.get_data()

	if data.has("tools"):
		tools = data["tools"]

	if GameLogger.ENABLED:
		print("[GatheringDatabase] ✅ Loaded %d tool types" % tools.size())

# ==================== NODE DATA RETRIEVAL ====================

func get_node_data(node_id: String) -> Dictionary:
	"""Get full data for a gathering node type"""
	if not nodes.has(node_id):
		push_warning("[GatheringDatabase] Unknown node type: %s" % node_id)
		return {}

	return nodes[node_id].duplicate(true)

func get_random_node_type() -> String:
	"""Get random node type based on weights"""
	if spawn_rates.is_empty() or not spawn_rates.has("type_weights"):
		return ["mining_node", "gathering_node", "fishing_pond"].pick_random()

	var weights = spawn_rates["type_weights"]
	var total_weight = 0

	for type_name in weights.keys():
		total_weight += weights[type_name]

	var roll = randf() * total_weight
	var cumulative = 0.0

	for type_name in weights.keys():
		cumulative += weights[type_name]
		if roll <= cumulative:
			return type_name + "_node" if type_name != "fishing" else "fishing_pond"

	return "mining_node"

func should_spawn_node() -> bool:
	"""Check if a gathering node should spawn (30-40% chance)"""
	var base_chance = spawn_rates.get("base_chance", 0.35)
	return randf() < base_chance

# ==================== TOOL DATA RETRIEVAL ====================

func get_tool_data(tool_id: String) -> Dictionary:
	"""Get full data for a gathering tool"""
	if not tools.has(tool_id):
		push_warning("[GatheringDatabase] Unknown tool: %s" % tool_id)
		return {}

	return tools[tool_id].duplicate(true)

func get_tools_by_type(tool_type: String) -> Array:
	"""Get all tools of a specific type (mining, gathering, fishing)"""
	var filtered_tools = []

	for tool_id in tools.keys():
		var tool_data = tools[tool_id]
		if tool_data.get("type") == tool_type:
			filtered_tools.append(tool_id)

	return filtered_tools

# ==================== DROP CALCULATION ====================

func calculate_node_drops(node_id: String, tool_stats: Dictionary) -> Array:
	"""Calculate what items this node should drop"""
	var node_data = get_node_data(node_id)
	if node_data.is_empty():
		return []

	var drops = []
	var attempts = int(node_data.get("base_attempts", 5))
	var possible_drops = node_data.get("possible_drops", [])

	if possible_drops.is_empty():
		return []

	# Calculate total weight
	var total_weight = 0
	for drop in possible_drops:
		total_weight += drop.get("weight", 1)

	# Roll for each attempt
	for i in range(attempts):
		# Check critical hit (bonus item)
		var critical_chance = float(tool_stats.get("critical_chance", 0.05))
		var is_critical = randf() < critical_chance

		# Roll for item
		var roll = randf() * total_weight
		var cumulative = 0.0

		for drop in possible_drops:
			cumulative += drop.get("weight", 1)
			if roll <= cumulative:
				var item_id = drop.get("item_id")
				var min_amount = int(drop.get("min_amount", 1))
				var max_amount = int(drop.get("max_amount", 1))

				# Add yield bonus from tool
				var yield_bonus = int(tool_stats.get("yield_bonus", 0))
				max_amount += yield_bonus

				# Critical doubles the amount
				if is_critical:
					min_amount *= 2
					max_amount *= 2

				var amount = randi_range(min_amount, max_amount)

				drops.append({
					"item_id": item_id,
					"amount": amount,
					"critical": is_critical
				})
				break

	if GameLogger.ENABLED:
		print("[GatheringDatabase] Calculated %d drops from %s" % [drops.size(), node_id])

	return drops

# ==================== UTILITY ====================

func get_all_node_ids() -> Array:
	"""Get list of all node IDs"""
	return nodes.keys()

func get_all_tool_ids() -> Array:
	"""Get list of all tool IDs"""
	return tools.keys()

func node_exists(node_id: String) -> bool:
	"""Check if node type exists"""
	return nodes.has(node_id)

func tool_exists(tool_id: String) -> bool:
	"""Check if tool exists"""
	return tools.has(tool_id)
