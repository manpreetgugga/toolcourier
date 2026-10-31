extends Node3D
## Test scene: a hardcoded 5x5 floating diorama under the shared stage
## lighting, meshed by BlockMesher and viewed through the OrbitCamera.
##
## Drag to orbit, pinch or scroll to zoom. A tap ripples on the block face
## under the finger (white on open tops, red elsewhere); a double tap on empty
## space resets the view.

## Degrees per second of idle orbit; 0 keeps the camera still (deterministic
## screenshots).
@export var idle_orbit_speed: float = 0.0

var grid: Grid
var camera: OrbitCamera

var _stage: StageLighting


func _ready() -> void:
	_stage = StageLighting.new()
	_stage.name = "Stage"
	add_child(_stage)

	grid = Grid.new(_test_layout())
	var blocks := MeshInstance3D.new()
	blocks.name = "Blocks"
	blocks.mesh = BlockMesher.build(grid.cells)
	add_child(blocks)

	camera = OrbitCamera.new()
	camera.name = "Camera"
	camera.attributes = _stage.camera_attributes
	camera.idle_orbit_speed = idle_orbit_speed
	add_child(camera)
	camera.make_current()
	camera.distance_changed.connect(func(distance: float) -> void: _stage.fit_to_bounds(grid.bounds, distance))
	camera.tapped.connect(_on_tapped)
	camera.double_tapped.connect(_on_double_tapped)
	camera.frame_bounds(grid.bounds)


## Block under a screen position (see [method Grid.raycast]).
func pick(screen_position: Vector2) -> Dictionary:
	return grid.raycast(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _on_tapped(screen_position: Vector2) -> void:
	var hit: Dictionary = pick(screen_position)
	if hit.is_empty():
		return
	var cell: Vector3i = hit["cell"]
	var normal: Vector3i = hit["normal"]
	var center: Vector3 = Vector3(cell) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.5
	var water: bool = grid.get_block(cell) == BlockMesher.WATER
	if water and normal == Vector3i.UP:
		center.y -= 1.0 - BlockMesher.WATER_LEVEL
	# Until pathfinding exists, open land tops stand in for reachable targets.
	TapRipple.spawn(self, center, Vector3(normal), normal == Vector3i.UP and not water)


func _on_double_tapped(screen_position: Vector2) -> void:
	if pick(screen_position).is_empty():
		camera.reset_view()


## Hardcoded test layout: Vector3i -> block type.
func _test_layout() -> Dictionary:
	var cells: Dictionary = {}
	# Floating rock underside, tapering to a point.
	cells[Vector3i(2, -2, 2)] = &"dark_stone"
	for x in range(1, 4):
		for z in range(1, 4):
			cells[Vector3i(x, -1, z)] = &"dark_stone"
	cells[Vector3i(3, -1, 0)] = &"dark_stone"
	cells[Vector3i(4, -1, 0)] = &"dark_stone"
	cells[Vector3i(4, -1, 1)] = &"dark_stone"
	# Ground layer.
	for x in 5:
		for z in 5:
			cells[Vector3i(x, 0, z)] = &"grass"
	for c: Vector3i in [Vector3i(3, 0, 0), Vector3i(4, 0, 0), Vector3i(4, 0, 1)]:
		cells[c] = &"water"
	for c: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		cells[c] = &"sand"
	# Stone tower in the back corner with a terracotta cap.
	for c: Vector3i in [Vector3i(0, 1, 4), Vector3i(1, 1, 4), Vector3i(0, 1, 3), Vector3i(0, 2, 4), Vector3i(0, 3, 4)]:
		cells[c] = &"stone"
	cells[Vector3i(0, 4, 4)] = &"brick"
	# Wooden walkway hanging off the tower.
	cells[Vector3i(2, 1, 4)] = &"wood"
	cells[Vector3i(3, 1, 4)] = &"wood"
	# Little brick house.
	for c: Vector3i in [Vector3i(4, 1, 2), Vector3i(4, 1, 3), Vector3i(3, 1, 2), Vector3i(4, 2, 3)]:
		cells[c] = &"brick"
	# One interactive (accent) block.
	cells[Vector3i(2, 1, 1)] = &"accent"
	return cells
