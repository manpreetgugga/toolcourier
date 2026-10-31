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
## its direction, so paths over belts are one-way. Stepping onto ice slides
## the courier on in the same direction until the next cell is not open
## ground at the same level (it stops on the ice) or it slides off onto
## ground (it stops there), so the graph links the cell before the ice
## straight to where the slide ends. Call [method set_grid] whenever the
## grid changes.

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
## Point id -> point id -> the ice cells slid over between them.
var _slides: Dictionary = {}


func _init(grid: Grid) -> void:
	set_grid(grid)


func set_grid(grid: Grid) -> void:
	_grid = grid
	rebuild()


func rebuild() -> void:
	_astar.clear()
	_cells_by_id.clear()
	_slides.clear()
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

	# Each cell links to where its own steps lead (a belt only onward), so
	# links are one-way and a step onto ice leads to the end of the slide.
	for id: int in _cells_by_id:
		var cell: Vector3i = _cells_by_id[id]
		if _grid.is_stairs_at(cell):
			continue
		var dirs: Array[Vector3i] = HORIZONTAL
		if is_belt(cell):
			_astar.set_point_weight_scale(id, BELT_COST)
			dirs = [belt_direction(cell)]
		for dir: Vector3i in dirs:
			var next: Vector3i = cell + dir
			if is_walkable(next) and not _grid.is_stairs_at(next):
				_link(cell, glide(next, dir))

	for cell: Vector3i in stairs:
		var climb: Vector3i = _grid.facing.get(cell, Vector3i(1, 0, 0))
		var foot: Vector3i = cell - climb
		if is_walkable(foot) and not _grid.is_stairs_at(foot):
			_link(cell, glide(foot, -climb))
			_astar.connect_points(_id(foot), _id(cell), false)
		# The top leads onto flat ground or straight onto more stairs going
		# the same way.
		var top: Vector3i = cell + climb + Vector3i.UP
		if is_walkable(top):
			if not _grid.is_stairs_at(top) or _grid.facing.get(top) == climb:
				_link(cell, glide(top, climb))
				_astar.connect_points(_id(top), _id(cell), false)


func is_walkable(cell: Vector3i) -> bool:
	return _astar.has_point(_id(cell))


## Cells the courier can step into from [param cell] (only onward on a belt).
func neighbors(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if is_walkable(cell):
		for id: int in _astar.get_point_connections(_id(cell)):
			result.append(_cells_by_id[id])
	return result


## Whether standing in [param cell] means standing on ice.
func is_ice(cell: Vector3i) -> bool:
	return _grid.get_block(cell - Vector3i.UP) == Grid.ICE and not _grid.is_stairs_at(cell)


## The cells the courier passes through moving into [param cell] heading
## [param dir]: that cell, and on ice every cell it slides on to, until the
## next one is not open ground at the same level or it has slid off the
## ice. The last cell is where it stops.
func glide(cell: Vector3i, dir: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = [cell]
	while dir != Vector3i.ZERO and is_ice(cells[-1]):
		var onward: Vector3i = cells[-1] + dir
		if not is_walkable(onward) or _grid.is_stairs_at(onward):
			break
		cells.append(onward)
	return cells


## Whether the step from [param from] to [param to] is free: carried by a
## belt, or sliding on over ice the way the courier came onto it
## ([param came], its heading into [param from]). The step that starts a
## slide is a move, and so is one onto stairs, where a slide stops.
func is_ride_step(from: Vector3i, to: Vector3i, came: Vector3i) -> bool:
	if is_belt(from):
		return true
	return came != Vector3i.ZERO and is_ice(from) and heading(from, to) == came and not _grid.is_stairs_at(to)


## Whether the step into [param path] [param i] is free (see
## [method is_ride_step]).
func is_ride(path: Array[Vector3i], i: int) -> bool:
	var came: Vector3i = heading(path[i - 2], path[i - 1]) if i >= 2 else Vector3i.ZERO
	return is_ride_step(path[i - 1], path[i], came)


## The horizontal direction of a step from [param from] to [param to].
static func heading(from: Vector3i, to: Vector3i) -> Vector3i:
	return Vector3i(to.x - from.x, 0, to.z - from.z)


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
		var cells: Array[Vector3i] = glide(onward, belt_direction(cell))
		ride.append_array(cells)
		for passed: Vector3i in cells:
			seen[passed] = true
		cell = cells[-1]
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
	var previous: int = -1
	for id: int in _astar.get_id_path(_id(from), _id(to)):
		if previous >= 0 and _slides.has(previous):
			path.append_array(_slides[previous].get(id, []))
		path.append(_cells_by_id[id])
		previous = id
	return path


## Links [param from] one way to the end of [param cells] (from
## [method glide]), keeping the ice slid over on the way.
func _link(from: Vector3i, cells: Array[Vector3i]) -> void:
	var end: Vector3i = cells[-1]
	if end == from:
		return
	_astar.connect_points(_id(from), _id(end), false)
	if cells.size() > 1:
		if not _slides.has(_id(from)):
			_slides[_id(from)] = {}
		_slides[_id(from)][_id(end)] = cells.slice(0, -1)


func _add_node(cell: Vector3i) -> void:
	var id: int = _id(cell)
	_astar.add_point(id, floor_position(cell))
	_cells_by_id[id] = cell


## Packs a cell into a non-negative point id (11 bits per axis, ±1024).
static func _id(cell: Vector3i) -> int:
	return ((cell.x + 1024) << 22) | ((cell.y + 1024) << 11) | (cell.z + 1024)
