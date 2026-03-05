# File: res://scripts/battle/GridLayoutManager.gd
# Responsive grid layout system for enemy positioning
# Supports multiple resolutions and grid configurations

extends RefCounted
class_name GridLayoutManager

# const LOG removed - using GameLogger

# Grid configuration
var rows: int = 2
var cols: int = 3
var cell_size: Vector2 = Vector2(120, 140)
var spacing: Vector2 = Vector2(40, 40)  # Spacing between enemies
var padding: Vector2 = Vector2(50, 50)  # Padding from edges

# Container dimensions
var container_size: Vector2 = Vector2.ZERO

# Calculated grid bounds
var grid_width: float = 0.0
var grid_height: float = 0.0
var grid_offset: Vector2 = Vector2.ZERO

# Base resolutions for reference
const BASE_RESOLUTIONS := {
	"fullhd": Vector2(1920, 1080),
	"hd": Vector2(1280, 720),
	"standard": Vector2(1024, 768)
}

func _init(p_rows: int = 2, p_cols: int = 3, p_cell_size: Vector2 = Vector2(120, 140)) -> void:
	rows = p_rows
	cols = p_cols
	cell_size = p_cell_size

	if GameLogger.ENABLED:
		print("[GridLayoutManager] Initialized: %dx%d grid, cell size: %s" % [rows, cols, cell_size])

## Sets the container size and recalculates grid layout
func set_container_size(size: Vector2) -> void:
	container_size = size
	_calculate_grid_layout()

	if GameLogger.ENABLED:
		print("[GridLayoutManager] Container size set to %s" % container_size)
		print("[GridLayoutManager] Grid bounds: %sx%s at offset %s" % [grid_width, grid_height, grid_offset])

## Sets custom spacing between cells
func set_spacing(p_spacing: Vector2) -> void:
	spacing = p_spacing
	if container_size != Vector2.ZERO:
		_calculate_grid_layout()

## Sets custom padding from container edges
func set_padding(p_padding: Vector2) -> void:
	padding = p_padding
	if container_size != Vector2.ZERO:
		_calculate_grid_layout()

## Calculate grid layout dimensions and centering offset
func _calculate_grid_layout() -> void:
	# Calculate total grid dimensions
	grid_width = (cols * cell_size.x) + ((cols - 1) * spacing.x)
	grid_height = (rows * cell_size.y) + ((rows - 1) * spacing.y)

	# Calculate offset to center grid in container
	var available_width = container_size.x - (padding.x * 2)
	var available_height = container_size.y - (padding.y * 2)

	grid_offset.x = padding.x + (available_width - grid_width) / 2.0
	grid_offset.y = padding.y + (available_height - grid_height) / 2.0

	# Ensure grid doesn't go negative
	grid_offset.x = max(padding.x, grid_offset.x)
	grid_offset.y = max(padding.y, grid_offset.y)

## Get position for a specific grid cell (0-indexed)
func get_cell_position(index: int) -> Vector2:
	if index < 0 or index >= (rows * cols):
		push_warning("[GridLayoutManager] Invalid cell index: %d (max: %d)" % [index, rows * cols - 1])
		return Vector2.ZERO

	var row = index / cols
	var col = index % cols

	var x = grid_offset.x + (col * (cell_size.x + spacing.x))
	var y = grid_offset.y + (row * (cell_size.y + spacing.y))

	return Vector2(x, y)

## Get position for row and column
func get_position_at(row: int, col: int) -> Vector2:
	if row < 0 or row >= rows or col < 0 or col >= cols:
		push_warning("[GridLayoutManager] Invalid row/col: %d, %d" % [row, col])
		return Vector2.ZERO

	var index = row * cols + col
	return get_cell_position(index)

## Get all cell positions as an array
func get_all_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var total_cells = rows * cols

	for i in range(total_cells):
		positions.append(get_cell_position(i))

	return positions

## Get total number of cells in grid
func get_cell_count() -> int:
	return rows * cols

## Get grid configuration info
func get_grid_info() -> Dictionary:
	return {
		"rows": rows,
		"cols": cols,
		"cell_size": cell_size,
		"spacing": spacing,
		"padding": padding,
		"container_size": container_size,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"grid_offset": grid_offset,
		"total_cells": rows * cols
	}

## Auto-adjust spacing to fit container better
func auto_adjust_spacing(min_spacing: Vector2 = Vector2(20, 20), max_spacing: Vector2 = Vector2(80, 80)) -> void:
	if container_size == Vector2.ZERO:
		return

	var available_width = container_size.x - (padding.x * 2)
	var available_height = container_size.y - (padding.y * 2)

	# Calculate spacing to fill available space
	var total_cell_width = cols * cell_size.x
	var total_cell_height = rows * cell_size.y

	var space_for_gaps_x = available_width - total_cell_width
	var space_for_gaps_y = available_height - total_cell_height

	if cols > 1:
		spacing.x = space_for_gaps_x / (cols - 1)
		spacing.x = clamp(spacing.x, min_spacing.x, max_spacing.x)

	if rows > 1:
		spacing.y = space_for_gaps_y / (rows - 1)
		spacing.y = clamp(spacing.y, min_spacing.y, max_spacing.y)

	_calculate_grid_layout()

	if GameLogger.ENABLED:
		print("[GridLayoutManager] Auto-adjusted spacing to: %s" % spacing)

## Check if grid fits in container
func fits_in_container() -> bool:
	if container_size == Vector2.ZERO:
		return false

	var required_width = grid_width + (padding.x * 2)
	var required_height = grid_height + (padding.y * 2)

	return required_width <= container_size.x and required_height <= container_size.y

## Get grid utilization percentage
func get_utilization() -> Dictionary:
	if container_size == Vector2.ZERO:
		return {"width": 0.0, "height": 0.0}

	var used_width = grid_width + (padding.x * 2)
	var used_height = grid_height + (padding.y * 2)

	return {
		"width": (used_width / container_size.x) * 100.0,
		"height": (used_height / container_size.y) * 100.0
	}

