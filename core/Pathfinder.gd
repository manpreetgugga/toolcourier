class_name Pathfinder
extends RefCounted
## Where the courier can stand and how it moves, as an AStar3D graph over a
## Grid.
##
## The courier stands in an empty cell on top of a block with a walkable top
## (anything but water, stairs and cranks) and moves one cell at a time to a
## horizontal neighbour at the same height. It never jumps gaps and never
## climbs a block on its own: stairs are nodes of their own that link the
## cell at their foot (same level) with the cell past their top (one level
## up). A running belt can be stepped onto from any side but only left along
## its direction, so paths over belts are one-way. Call [method set_grid]
## whenever the grid changes.

## Height of the middle tread above the bottom of a stairs cell.
const STAIRS_FLOOR: float = 2.0 / 3.0
## Riding a belt costs the courier nothing, so routes may prefer it.
const BELT_COST: float = 0.25
const HORIZONTAL: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var _grid: Grid
var _astar := AStar3D.new()
## Point id -> cell.
var _cells_by_id: Dictionary = {}


func _init(grid: Grid) -> void:
	set_grid(grid)


func set_grid(grid: Grid) -> void:
	_grid = grid
	rebuild()


func rebuild() -> void:
	_astar.clear()
	_cells_by_id.clear()
	var stairs: Array[Vector3i] = []
	for block: Vector3i in _grid.cells:
		var block_type: StringName = _grid.cells[block]
		if Grid.is_stairs(block_type):
			if not _grid.has_block(block + Vector3i.UP):
				_add_node(block)
				stairs.append(block)
		elif Grid.has_walkable_top(block_type) and not _grid.has_block(block + Vector3i.UP) \
				and not _grid.obstacles.has(block + Vector3i.UP):
			_add_node(block + Vector3i.UP)

	for id: int in _cells_by_id:
		var cell: Vector3i = _cells_by_id[id]
		if _grid.is_stairs_at(cell):
			continue
		if is_belt(cell):
			_astar.set_point_weight_scale(id, BELT_COST)
			var onward: Vector3i = cell + belt_direction(cell)
			if _astar.has_point(_id(onward)) and not _grid.is_stairs_at(onward):
				_astar.connect_points(id, _id(onward), false)
			continue
		for dir: Vector3i in HORIZONTAL:
			var next: Vector3i = cell + dir
			if _astar.has_point(_id(next)) and not _grid.is_stairs_at(next):
				# Stepping onto a belt is fine; walking off it is the belt's call.
				_astar.connect_points(id, _id(next), not is_belt(next))

	for cell: Vector3i in stairs:
		var climb: Vector3i = _grid.facing.get(cell, Vector3i(1, 0, 0))
		var foot: Vector3i = cell - climb
		if _astar.has_point(_id(foot)) and not _grid.is_stairs_at(foot):
			_astar.connect_points(_id(cell), _id(foot))
		# The top leads onto flat ground or straight onto more stairs going
		# the same way.
		var top: Vector3i = cell + climb + Vector3i.UP
		if _astar.has_point(_id(top)):
			if not _grid.is_stairs_at(top) or _grid.facing.get(top) == climb:
				_astar.connect_points(_id(cell), _id(top))


func is_walkable(cell: Vector3i) -> bool:
	return _astar.has_point(_id(cell))


## Cells the courier can step into from [param cell] (only onward on a belt).
func neighbors(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if is_walkable(cell):
		for id: int in _astar.get_point_connections(_id(cell)):
			result.append(_cells_by_id[id])
	return result


## Whether standing in [param cell] means riding a running belt.
func is_belt(cell: Vector3i) -> bool:
	return _grid.belts.has(cell - Vector3i.UP)


func belt_direction(cell: Vector3i) -> Vector3i:
	return _grid.belts.get(cell - Vector3i.UP, Vector3i.ZERO)


## The cells a belt carries the courier through from [param cell] until it
## steps off (or the belt ends against something). Empty off belts.
func ride_from(cell: Vector3i) -> Array[Vector3i]:
	var ride: Array[Vector3i] = []
	var seen: Dictionary = {cell: true}
	while is_belt(cell):
		var onward: Vector3i = cell + belt_direction(cell)
		if not is_walkable(onward) or _grid.is_stairs_at(onward) or seen.has(onward):
			break
		ride.append(onward)
		seen[onward] = true
		cell = onward
	return ride


## Number of cells the courier can stand in.
func node_count() -> int:
	return _cells_by_id.size()


## Where the courier's feet rest in [param cell].
func floor_position(cell: Vector3i) -> Vector3:
	var floor_height: float = STAIRS_FLOOR if _grid.is_stairs_at(cell) else 0.0
	return Vector3(cell) + Vector3(0.5, floor_height, 0.5)


## The cell to walk to when the player taps [param block]: the stairs
## themselves, or the cell on top of the block. Check [method is_walkable]
## on the result.
func target_for_block(block: Vector3i) -> Vector3i:
	return block if _grid.is_stairs_at(block) else block + Vector3i.UP


## Cells from [param from] to [param to], both included; empty when there is
## no way through.
func find_path(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if not is_walkable(from) or not is_walkable(to):
		return path
	for id: int in _astar.get_id_path(_id(from), _id(to)):
		path.append(_cells_by_id[id])
	return path


func _add_node(cell: Vector3i) -> void:
	var id: int = _id(cell)
	_astar.add_point(id, floor_position(cell))
	_cells_by_id[id] = cell


## Packs a cell into a non-negative point id (11 bits per axis, ±1024).
static func _id(cell: Vector3i) -> int:
	return ((cell.x + 1024) << 22) | ((cell.y + 1024) << 11) | (cell.z + 1024)
