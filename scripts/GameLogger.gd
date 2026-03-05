# File: res://scripts/GameLogger.gd
# Sistema centralizzato di logging con toggle ON/OFF
# Usare GameLogger.log(tag, message) invece di print() per log controllati

extends Node

# ============================================
# CONFIGURAZIONE LOGGING
# ============================================

# TOGGLE GLOBALE: true = mostra log, false = nasconde log
var ENABLED: bool = false  # ← DISABLED per ridurre noise durante test gathering

# DEBUG MODE: Set to false to disable ALL non-essential logs
const DEBUG_MODE: bool = false

func _ready() -> void:
	if DEBUG_MODE:
		print("[GameLogger] ✅ GameLogger autoload initialized - ENABLED: %s" % ENABLED)

# Toggle per categorie specifiche (opzionale, per controllo fine)
var category_filters := {
	"inventory": true,
	"battle": true,
	"skills": true,
	"crafting": true,
	"ui": true,
	"system": true,
	"stats": true,
}

# ============================================
# FUNZIONI DI LOGGING
# ============================================

func log(tag: String, message: String) -> void:
	"""Log standard con tag"""
	if not ENABLED:
		return

	print("[%s] %s" % [tag, message])

func log_category(category: String, tag: String, message: String) -> void:
	"""Log con categoria (es: inventory, battle, etc.)"""
	if not ENABLED:
		return

	if category_filters.has(category) and not category_filters[category]:
		return

	print("[%s][%s] %s" % [category.to_upper(), tag, message])

func warn(tag: String, message: String) -> void:
	"""Warning (sempre mostrato anche se ENABLED = false)"""
	push_warning("[%s] ⚠️ %s" % [tag, message])

func error(tag: String, message: String) -> void:
	"""Error (sempre mostrato anche se ENABLED = false)"""
	push_error("[%s] ❌ %s" % [tag, message])

# ============================================
# UTILITY
# ============================================

func is_enabled() -> bool:
	"""Check se il logging è abilitato"""
	return ENABLED

func enable() -> void:
	"""Abilita il logging"""
	ENABLED = true
	print("[GameLogger] ✅ Logging ENABLED")

func disable() -> void:
	"""Disabilita il logging"""
	print("[GameLogger] 🔇 Logging DISABLED")
	ENABLED = false

func toggle() -> void:
	"""Toggle ON/OFF"""
	ENABLED = not ENABLED
	if ENABLED:
		print("[GameLogger] ✅ Logging ENABLED")
	else:
		print("[GameLogger] 🔇 Logging DISABLED")

func set_category(category: String, enabled: bool) -> void:
	"""Abilita/disabilita logging per una categoria specifica"""
	if category_filters.has(category):
		category_filters[category] = enabled
		print("[GameLogger] Category '%s': %s" % [category, "ENABLED" if enabled else "DISABLED"])
