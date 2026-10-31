extends Node3D
## Test scene: a hardcoded 5x5 floating diorama under the shared stage
## lighting, meshed by BlockMesher and viewed through the OrbitCamera, with
## the courier walking on it.
##
## Drag to orbit, pinch or scroll to zoom. Tap a spot to walk there: a white
## ripple marks the destination, a red ripple and a puzzled tilt mean there is
## no way through. Stairs lead up to the wooden walkway. A double tap on
## empty space resets the view.

const START_CELL := Vector3i(1, 1, 2)

## Degrees per second of idle orbit; 0 keeps the camera still (deterministic
## screenshots).
@export var idle_orbit_speed: float = 0.0

var grid: Grid
var camera: OrbitCamera
var pathfinder: Pathfinder
var courier: Courier

var _stage: StageLighting


func _ready() -> void:
	_stage = StageLighting.new()
	_stage.name = "Stage"
	add_child(_stage)

	var facing: Dictionary = {}
	grid = Grid.new(_test_layout(facing), facing)
	var blocks := MeshInstance3D.new()
	blocks.name = "Blocks"
	blocks.mesh = BlockMesher.build(grid.cells)
	add_child(blocks)
	_build_stairs()

	pathfinder = Pathfinder.new(grid)
	courier = preload("res://entities/Courier.tscn").instantiate()
	courier.pathfinder = pathfinder
	add_child(courier)
	courier.place(START_CELL)

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
	var block: Vector3i = hit["cell"]
	var target: Vector3i = pathfinder.target_for_block(block)
	var path: Array[Vector3i] = pathfinder.find_path(courier.path_origin(), target)
	if path.is_empty():
		var normal: Vector3i = hit["normal"]
		var center: Vector3 = Vector3(block) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.5
		if grid.get_block(block) == BlockMesher.WATER and normal == Vector3i.UP:
			center.y -= 1.0 - BlockMesher.WATER_LEVEL
		TapRipple.spawn(self, center, Vector3(normal), false)
		courier.puzzled()
		return
	TapRipple.spawn(self, pathfinder.floor_position(target), Vector3.UP)
	path.remove_at(0)
	courier.walk(path)


func _on_double_tapped(screen_position: Vector2) -> void:
	if pick(screen_position).is_empty():
		camera.reset_view()


func _build_stairs() -> void:
	for cell: Vector3i in grid.cells:
		if not grid.is_stairs_at(cell):
			continue
		var climb: Vector3i = grid.facing.get(cell, Vector3i(1, 0, 0))
		var stairs := MeshInstance3D.new()
		stairs.name = "Stairs"
		stairs.mesh = ClayShapes.stairs()
		stairs.material_override = ClayShapes.material(Palette.block_color(&"stone"))
		# The mesh climbs towards +X; turn it to climb along the facing.
		stairs.rotation.y = atan2(-float(climb.z), float(climb.x))
		stairs.position = Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		add_child(stairs)


## Hardcoded test layout: Vector3i -> block type. Fills [param facing] for
## oriented blocks.
func _test_layout(facing: Dictionary) -> Dictionary:
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
	# Wooden walkway hanging off the tower, with stairs up to it.
	cells[Vector3i(2, 1, 4)] = &"wood"
	cells[Vector3i(3, 1, 4)] = &"wood"
	cells[Vector3i(2, 1, 3)] = &"stairs"
	facing[Vector3i(2, 1, 3)] = Vector3i(0, 0, 1)
	# Little brick house.
	for c: Vector3i in [Vector3i(4, 1, 2), Vector3i(4, 1, 3), Vector3i(3, 1, 2), Vector3i(4, 2, 3)]:
		cells[c] = &"brick"
	# One interactive (accent) block.
	cells[Vector3i(2, 1, 1)] = &"accent"
	return cells
