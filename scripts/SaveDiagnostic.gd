extends Node

# Diagnostic script to track all save operations
# Add this as an autoload BEFORE GameState to intercept saves

func _ready():
	print("[SaveDiagnostic] ⚙️ Monitoring save operations...")

	# Monitor file access
	var save_path = OS.get_user_data_dir() + "/save.json"
	print("[SaveDiagnostic] Save location: %s" % save_path)

	# Check if file exists and size
	if FileAccess.file_exists(save_path):
		var f = FileAccess.open(save_path, FileAccess.READ)
		if f:
			var content = f.get_as_text()
			f.close()
			print("[SaveDiagnostic] Existing save file size: %d bytes" % content.length())
		else:
			print("[SaveDiagnostic] ⚠️ Cannot read existing save file!")
	else:
		print("[SaveDiagnostic] No existing save file")

func verify_save_after_write():
	var save_path = OS.get_user_data_dir() + "/save.json"

	# Wait a moment for file to be written
	await get_tree().create_timer(0.1).timeout

	if FileAccess.file_exists(save_path):
		var f = FileAccess.open(save_path, FileAccess.READ)
		if f:
			var content = f.get_as_text()
			f.close()

			var parsed = JSON.parse_string(content)
			if parsed:
				var inv_count = parsed.get("inventory_items", []).size()
				print("[SaveDiagnostic] ✅ VERIFIED: File on disk has %d inventory items" % inv_count)
				print("[SaveDiagnostic] → File size: %d bytes" % content.length())
				return inv_count
			else:
				print("[SaveDiagnostic] ❌ FAILED: Cannot parse JSON from file!")
		else:
			print("[SaveDiagnostic] ❌ FAILED: Cannot open save file for verification!")
	else:
		print("[SaveDiagnostic] ❌ FAILED: Save file does not exist!")

	return -1
