class_name BlockMesher
extends RefCounted
## Builds the merged mesh for a set of blocks.
##
## Blocks are sculpted like clay: neighbouring blocks merge into one smooth
## surface (faces that touch another solid block are culled), and only the
## outside edges of the combined shape are rounded. Water merges with water.
##
## Each face is a vertex grid laid out on the unit cube and projected onto the
## rounded shape; the grid's outer ring lands on the 45° line of the bevel, so
## faces meet exactly and the surface stays watertight. Ambient occlusion, a
## top/bottom tint and a per-block colour jitter are baked into vertex colours.
##
## The result has one surface per block type, so a level costs one draw call
## per material.

## Radius of the rounded outside edges.
const DEFAULT_BEVEL: float = 0.17
## Segments per half bevel; a full rounded edge has twice as many.
const DEFAULT_STEPS: int = 2
## Brightness at full occlusion (AO 0); AO 3 maps to 1.0.
const AO_MIN: float = 0.55
const TOP_TINT: float = 1.06
const BOTTOM_TINT: float = 0.82
const JITTER: float = 0.03
## Height of an open water surface inside its cell.
const WATER_LEVEL: float = 0.88
## Scale applied to the shade stored in vertex colour (shaders undo it).
const SHADE_ENCODE: float = 0.5

const WATER: StringName = &"water"
const GRASS: StringName = &"grass"

## Face order: +x, -x, +y, -y, +z, -z (axis = face / 2).
const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Face tangents. V is vertical on side faces so wood planks run horizontally.
const TANGENT_U: Array[Vector3i] = [
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
]
const TANGENT_V: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
]
const FACE_UP: int = 2


class _Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()


## Per-block data shared by all of its faces.
class _Block:
	var cell: Vector3i
	var origin: Vector3
	var water: bool
	var grass: bool
	var exposed: Array[bool] = [false, false, false, false, false, false]
	## Inner box of the rounded cube; a side without bevel extends to 0.5.
	var lo: Vector3
	var hi: Vector3
	var jitter: float
	var lowered: bool
	var top_open: bool
	## Corner AO per (face * 8 + corner), -1 until computed.
	var ao_cache := PackedFloat32Array()


var _cells: Dictionary
var _bevel: float
var _inner: float
## Segments per half bevel (each face rounds its edge from 0° to 45°).
var _steps: int
## Grid coordinates along each face tangent, on the unit cube.
var _grid := PackedFloat32Array()
var _surfaces: Dictionary = {}


## [param cells] maps Vector3i -> block type (StringName). [param bevel] is
## the edge radius, [param steps] the segments per half bevel.
static func build(cells: Dictionary, bevel: float = DEFAULT_BEVEL, steps: int = DEFAULT_STEPS) -> ArrayMesh:
	return BlockMesher.new(cells, bevel, steps)._build()


func _init(cells: Dictionary, bevel: float, steps: int) -> void:
	_cells = cells
	_bevel = clampf(bevel, 0.005, 0.45)
	_inner = 0.5 - _bevel
	_steps = maxi(steps, 1)
	# Offsets at evenly spaced bevel angles from 45° on the -side to 45° on the +side.
	for k in range(_steps, -1, -1):
		_grid.append(-_bevel_offset(k))
	for k in range(0, _steps + 1):
		_grid.append(_bevel_offset(k))


## Position along a face tangent where the bevel has turned 45° * k / steps.
func _bevel_offset(k: int) -> float:
	return _inner + _bevel * tan(deg_to_rad(45.0 * k / _steps))


func _build() -> ArrayMesh:
	for cell: Vector3i in _cells:
		# Stairs have their own mesh (ClayShapes.stairs).
		if not Grid.is_stairs(_cells[cell]):
			_mesh_block(cell, _cells[cell])
	var mesh := ArrayMesh.new()
	for block_type: StringName in _surfaces:
		var s: _Surface = _surfaces[block_type]
		if s.indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.vertices
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_INDEX] = s.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var index: int = mesh.get_surface_count() - 1
		mesh.surface_set_name(index, block_type)
		mesh.surface_set_material(index, BlockMaterials.get_material(block_type))
	return mesh


func _mesh_block(cell: Vector3i, block_type: StringName) -> void:
	var b := _Block.new()
	b.cell = cell
	b.origin = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	b.water = block_type == WATER
	b.grass = block_type == GRASS
	b.jitter = 1.0 if b.water else 1.0 + JITTER * _hash_signed(cell)
	for face in 6:
		b.exposed[face] = not _occludes(cell + DIRS[face], b.water)
		# Round only where this side is open; a covered side runs flat into
		# the neighbour so the two merge.
		var bound: float = _inner if b.exposed[face] else 0.5
		var axis: int = face >> 1
		if face & 1 == 0:
			b.hi[axis] = bound
		else:
			b.lo[axis] = -bound
	b.top_open = b.exposed[FACE_UP]
	b.lowered = b.water and b.top_open
	b.ao_cache.resize(48)
	b.ao_cache.fill(-1.0)

	var s: _Surface = _surfaces.get(block_type)
	if s == null:
		s = _Surface.new()
		_surfaces[block_type] = s
	for face in 6:
		if b.exposed[face]:
			_mesh_face(s, b, face)


func _mesh_face(s: _Surface, b: _Block, face: int) -> void:
	var n := Vector3(DIRS[face])
	var u := Vector3(TANGENT_U[face])
	var v := Vector3(TANGENT_V[face])
	var size: int = _grid.size()
	var grid_index := PackedInt32Array()
	grid_index.resize(size * size)
	grid_index.fill(-1)
	for qj in size - 1:
		for qi in size - 1:
			_add_quad(s,
				_grid_vertex(s, b, n, u, v, grid_index, qi, qj),
				_grid_vertex(s, b, n, u, v, grid_index, qi + 1, qj),
				_grid_vertex(s, b, n, u, v, grid_index, qi + 1, qj + 1),
				_grid_vertex(s, b, n, u, v, grid_index, qi, qj + 1))


func _grid_vertex(s: _Surface, b: _Block, n: Vector3, u: Vector3, v: Vector3,
		grid_index: PackedInt32Array, i: int, j: int) -> int:
	var key: int = j * _grid.size() + i
	if grid_index[key] >= 0:
		return grid_index[key]

	# Point on the unit cube, projected onto the rounded cube around the inner box.
	var q: Vector3 = n * 0.5 + u * _grid[i] + v * _grid[j]
	var inner: Vector3 = q.clamp(b.lo, b.hi)
	var normal: Vector3 = (q - inner).normalized()
	var p: Vector3 = inner + normal * _bevel
	if b.lowered:
		p.y = -0.5 + (p.y + 0.5) * WATER_LEVEL

	var ao: float = _vertex_ao(b, q)
	var brightness: float = lerpf(AO_MIN, 1.0, ao) * b.jitter
	if normal.y >= 0.0:
		brightness *= lerpf(1.0, TOP_TINT, normal.y)
	else:
		brightness *= lerpf(1.0, BOTTOM_TINT, -normal.y)
	# Alpha carries per-type data: the grass cap flag, or the shore AO for water.
	var aux: float = 1.0
	if b.water:
		aux = ao
	elif b.grass:
		aux = 1.0 if b.top_open else 0.0

	var world: Vector3 = b.origin + p
	s.vertices.append(world)
	s.normals.append(normal)
	# Vertex colours are stored as 8-bit unorm, so the shade (which can exceed
	# 1.0 on lit tops) is halved here and doubled in the shaders.
	var shade: float = brightness * SHADE_ENCODE
	s.colors.append(Color(shade, shade, shade, aux))
	s.uvs.append(Vector2(world.dot(u), world.dot(v)))
	var index: int = s.vertices.size() - 1
	grid_index[key] = index
	return index


## Averages the voxel AO of every exposed face this vertex belongs to: one
## face on a flat area, two on an edge bevel, three on a corner.
func _vertex_ao(b: _Block, q: Vector3) -> float:
	var corner := Vector3i(int(signf(q.x)), int(signf(q.y)), int(signf(q.z)))
	var corner_index: int = int(q.x > 0.0) | (int(q.y > 0.0) << 1) | (int(q.z > 0.0) << 2)
	var total: float = 0.0
	var count: int = 0
	for axis in 3:
		if absf(q[axis]) > _inner + 0.0001:
			var face: int = axis * 2 + (0 if q[axis] > 0.0 else 1)
			if b.exposed[face]:
				var slot: int = face * 8 + corner_index
				if b.ao_cache[slot] < 0.0:
					b.ao_cache[slot] = _corner_ao(b, face, corner)
				total += b.ao_cache[slot]
				count += 1
	# Every meshed vertex lies on an exposed face, so count is at least 1.
	return total / maxi(count, 1)


## Classic voxel smooth lighting for one face corner, normalised to 0..1.
## Open water is sampled at its own level: its surface sits below the
## neighbouring tops, so walls there shade it (and drive the foam).
func _corner_ao(b: _Block, face: int, corner: Vector3i) -> float:
	var front: Vector3i = b.cell if (b.lowered and face == FACE_UP) else b.cell + DIRS[face]
	var du: Vector3i = corner * TANGENT_U[face]
	var dv: Vector3i = corner * TANGENT_V[face]
	var side1: bool = _shades(front + du)
	var side2: bool = _shades(front + dv)
	if side1 and side2:
		return 0.0
	var occluders: int = int(side1) + int(side2) + int(_shades(front + du + dv))
	return (3 - occluders) / 3.0


## Splits along the diagonal whose ends are most alike so AO gradients stay
## symmetric instead of streaking across the quad.
func _add_quad(s: _Surface, c0: int, c1: int, c2: int, c3: int) -> void:
	if absf(s.colors[c0].r - s.colors[c2].r) <= absf(s.colors[c1].r - s.colors[c3].r):
		_add_triangle(s, c0, c1, c2)
		_add_triangle(s, c0, c2, c3)
	else:
		_add_triangle(s, c0, c1, c3)
		_add_triangle(s, c1, c2, c3)


## Godot treats clockwise triangles as front-facing; fix the order from the
## vertex normals so face frames don't need a consistent handedness.
func _add_triangle(s: _Surface, i0: int, i1: int, i2: int) -> void:
	var p0: Vector3 = s.vertices[i0]
	var cross: Vector3 = (s.vertices[i1] - p0).cross(s.vertices[i2] - p0)
	if cross.length_squared() < 1e-12:
		return
	var facing: Vector3 = s.normals[i0] + s.normals[i1] + s.normals[i2]
	s.indices.append(i0)
	if cross.dot(facing) > 0.0:
		s.indices.append(i2)
		s.indices.append(i1)
	else:
		s.indices.append(i1)
		s.indices.append(i2)


## Whether the block at [param cell] hides a face of a neighbour. Water hides
## only water faces; stairs hide nothing (their profile is open); other
## solid blocks hide everything.
func _occludes(cell: Vector3i, water: bool) -> bool:
	var block_type: StringName = _cells.get(cell, &"")
	if block_type == &"" or Grid.is_stairs(block_type):
		return false
	return water or block_type != WATER


## Whether the block at [param cell] casts ambient occlusion (water does not).
func _shades(cell: Vector3i) -> bool:
	var block_type: StringName = _cells.get(cell, &"")
	return block_type != &"" and block_type != WATER


## Deterministic value in [-1, 1] per cell.
static func _hash_signed(cell: Vector3i) -> float:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return float(h & 0xFFFF) / 32767.5 - 1.0
