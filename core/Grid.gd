class_name Grid
extends RefCounted
## The level's block grid: which block type occupies each cell.
##
## Cell (x, y, z) spans [x, x+1] x [y, y+1] x [z, z+1], so its centre is
## cell + (0.5, 0.5, 0.5).

## Vector3i -> block type (StringName).
var cells: Dictionary
## Vector3i -> Vector3i: the horizontal direction an oriented block faces.
## Stairs climb towards their facing.
var facing: Dictionary
## Cells the courier cannot enter although no block fills them (solid props,
## closed gates).
var obstacles: Dictionary = {}
## Running conveyor blocks: Vector3i -> Vector3i direction they carry.
var belts: Dictionary = {}
## Bounding box of all blocks, in world units.
var bounds: AABB


func _init(p_cells: Dictionary = {}, p_facing: Dictionary = {}) -> void:
	cells = p_cells
	facing = p_facing
	bounds = _compute_bounds()


## Stairs types are "stairs" or "stairs_<material>".
static func is_stairs(block_type: StringName) -> bool:
	return String(block_type).begins_with("stairs")


## Whether the courier can stand on top of a block of this type.
static func has_walkable_top(block_type: StringName) -> bool:
	return block_type != &"water" and block_type != &"crank" and not is_stairs(block_type)


## Whether this type is a whole cube (meshed by BlockMesher and hiding the
## faces it touches); stairs and cranks have their own meshes.
static func is_full_block(block_type: StringName) -> bool:
	return block_type != &"crank" and not is_stairs(block_type)


func get_block(cell: Vector3i) -> StringName:
	return cells.get(cell, &"")


func has_block(cell: Vector3i) -> bool:
	return cells.has(cell)


func is_stairs_at(cell: Vector3i) -> bool:
	return is_stairs(get_block(cell))


## Casts a ray against the block cells with a voxel traversal (no physics
## bodies needed). Returns an empty Dictionary on a miss, otherwise
## "cell" (Vector3i), "normal" (Vector3i, outward normal of the face that was
## hit; zero if the ray starts inside a block), "position" (Vector3) and
## "distance" (float).
func raycast(origin: Vector3, direction: Vector3, max_distance: float = 500.0) -> Dictionary:
	var dir: Vector3 = direction.normalized()
	if cells.is_empty() or dir.is_zero_approx():
		return {}

	# Clip the ray to the bounds so the traversal starts at the first cell.
	var t_enter: float = 0.0
	var t_exit: float = max_distance
	var enter_axis: int = -1
	for axis in 3:
		if absf(dir[axis]) < 1e-9:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]:
				return {}
			continue
		var t0: float = (bounds.position[axis] - origin[axis]) / dir[axis]
		var t1: float = (bounds.end[axis] - origin[axis]) / dir[axis]
		if t0 > t1:
			var swap: float = t0
			t0 = t1
			t1 = swap
		if t0 > t_enter:
			t_enter = t0
			enter_axis = axis
		t_exit = minf(t_exit, t1)
		if t_enter > t_exit:
			return {}

	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var cell := Vector3i((origin + dir * t_enter).floor())
	var normal := Vector3i.ZERO
	if enter_axis >= 0:
		# The entry point lies exactly on a bounds face; pick the cell inside.
		var low: int = int(bounds.position[enter_axis])
		cell[enter_axis] = low if step[enter_axis] > 0 else int(bounds.end[enter_axis]) - 1
		normal[enter_axis] = -step[enter_axis]

	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if step[axis] != 0:
			var boundary: float = cell[axis] + (1 if step[axis] > 0 else 0)
			t_max[axis] = (boundary - origin[axis]) / dir[axis]
			t_delta[axis] = absf(1.0 / dir[axis])

	var t: float = t_enter
	while t <= t_exit:
		if cells.has(cell):
			return {"cell": cell, "normal": normal, "position": origin + dir * t, "distance": t}
		var axis: int = 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		t = t_max[axis]
		t_max[axis] += t_delta[axis]
		cell[axis] += step[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}


func _compute_bounds() -> AABB:
	if cells.is_empty():
		return AABB()
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	for cell: Vector3i in cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))
