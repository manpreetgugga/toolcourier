class_name Level
extends Node3D
## Plays one delivery level: builds the diorama from a level JSON file, turns
## taps into courier paths, and applies the delivery rules (LevelState) as
## the courier steps, animating pickups, drops, the exit opening and the
## finish.
##
## Drag to orbit, pinch or scroll to zoom, tap a spot to walk there. A white
## ripple marks the destination; a red ripple and a puzzled tilt mean there
## is no way. A double tap on empty space resets the view.

signal moves_changed(moves: int)
signal level_completed(moves: int, stars: int)

@export_file("*.json") var level_path: String = "res://levels/world_1/level_1.json"
## Degrees per second of idle orbit; 0 keeps the camera still.
@export var idle_orbit_speed: float = 0.0

var data: LevelData
var grid: Grid
var pathfinder: Pathfinder
var state: LevelState
var camera: OrbitCamera
var courier: Courier

var _stage: StageLighting
## Parcels by the cell they started in; carried ones in pickup order.
var _packages: Dictionary = {}
var _carried: Array[Package] = []
var _pads: Dictionary = {}
var _exit: ExitFlag


func _ready() -> void:
	data = LevelLoader.load_file(level_path)
	if not data.is_valid():
		for problem: String in data.errors:
			push_error("%s: %s" % [level_path, problem])
		return

	_stage = StageLighting.new()
	_stage.name = "Stage"
	_stage.theme_name = data.palette
	add_child(_stage)

	grid = data.make_grid()
	_add_mesh("Blocks", BlockMesher.build(grid.cells))
	_add_mesh("Stairs", PropFactory.build_stairs(grid))
	_add_mesh("Props", PropFactory.build_props(data.props))
	pathfinder = Pathfinder.new(grid)
	state = LevelState.new(data)

	for item: Dictionary in data.packages:
		var package := Package.create(item["color"])
		_place(package, item["cell"])
		_packages[item["cell"]] = package
	for item: Dictionary in data.pads:
		var pad := Pad.create(item["color"])
		_place(pad, item["cell"])
		_pads[item["cell"]] = pad
	_exit = ExitFlag.new()
	_exit.name = "Exit"
	_place(_exit, data.exit)
	_exit.set_open(state.all_delivered(), false)

	courier = preload("res://entities/Courier.tscn").instantiate()
	courier.pathfinder = pathfinder
	add_child(courier)
	courier.place(data.start)
	courier.step_finished.connect(_on_courier_step)

	camera = OrbitCamera.new()
	camera.name = "Camera"
	camera.attributes = _stage.camera_attributes
	camera.idle_orbit_speed = idle_orbit_speed
	add_child(camera)
	camera.make_current()
	var bounds: AABB = _view_bounds()
	camera.distance_changed.connect(func(distance: float) -> void: _stage.fit_to_bounds(bounds, distance))
	camera.tapped.connect(_on_tapped)
	camera.double_tapped.connect(_on_double_tapped)
	camera.frame_bounds(bounds)


## Block under a screen position (see [method Grid.raycast]).
func pick(screen_position: Vector2) -> Dictionary:
	return grid.raycast(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _on_tapped(screen_position: Vector2) -> void:
	if state.completed:
		return
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


func _on_courier_step(cell: Vector3i) -> void:
	var load_changed: bool = false
	for event: Dictionary in state.enter(cell):
		match event["event"]:
			LevelState.Event.PICKUP:
				var package: Package = _packages[event["cell"]]
				_carried.append(package)
				courier.flap_door()
				package.fly_into(courier.door_anchor)
				load_changed = true
			LevelState.Event.DROP:
				_drop(event["color"], event["cell"])
				load_changed = true
			LevelState.Event.EXIT_OPENED:
				_exit.set_open(true)
			LevelState.Event.COMPLETED:
				courier.stop()
				courier.celebrate()
				level_completed.emit(state.moves, data.stars_for(state.moves))
	if load_changed:
		courier.set_carried(state.carried)
	moves_changed.emit(state.moves)


func _drop(color: StringName, pad_cell: Vector3i) -> void:
	var package: Package
	for carried: Package in _carried:
		if carried.color == color:
			package = carried
			break
	_carried.erase(package)
	var pad: Pad = _pads[pad_cell]
	courier.flap_door()
	package.drop_onto(courier.door_anchor(), pad.global_position + Pad.PARCEL_SPOT, Pad.PARCEL_SIZE)
	get_tree().create_timer(Package.DROP_TIME).timeout.connect(pad.set_filled.bind(true))


func _place(node: Node3D, cell: Vector3i) -> void:
	add_child(node)
	node.position = pathfinder.floor_position(cell)


func _add_mesh(node_name: String, mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)


## Blocks plus anything that stands above them (props, the exit post).
func _view_bounds() -> AABB:
	var bounds: AABB = grid.bounds
	for prop: Dictionary in data.props:
		bounds = bounds.merge(AABB(Vector3(prop["cell"]), Vector3(1.0, 1.1, 1.0)))
	return bounds.merge(AABB(Vector3(data.exit), Vector3(1.0, ExitFlag.POST_HEIGHT, 1.0)))
