class_name Level
extends Node3D
## Plays one delivery level: builds the diorama from a level JSON file, turns
## taps and drags into courier paths and mechanism moves, and animates what
## LevelState reports as the rules play out.
##
## Drag to orbit, pinch or scroll to zoom, tap a spot to walk there. Drag a
## slider along its axis; tap a crank to turn its rotator. A white ripple
## marks the destination; a red ripple and a puzzled tilt mean there is no
## way. A double tap on empty space resets the view. Input waits while
## mechanisms move.

signal moves_changed(moves: int)
signal level_completed(moves: int, stars: int)

@export_file("*.json") var level_path: String = "res://levels/world_1/level_1.json"
## Degrees per second of idle orbit; 0 keeps the camera still.
@export var idle_orbit_speed: float = 0.0

var data: LevelData
var state: LevelState
var grid: Grid
var pathfinder: Pathfinder
var camera: OrbitCamera
var courier: Courier

var _stage: StageLighting
## Parcels on the floor by their current cell; carried ones in pickup order.
var _packages: Dictionary = {}
var _carried: Array[Package] = []
var _pads: Dictionary = {}
var _exit: ExitFlag
## id -> MechanismNode.
var _mechanism_nodes: Dictionary = {}
## Mechanism animations in progress; input waits for them.
var _busy: int = 0
## Where the courier stood before its current step (a step from a belt is a ride).
var _last_cell: Vector3i
## The slider being dragged: id, start, range, axis_px, press, riders.
var _grab: Dictionary = {}


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

	state = LevelState.new(data)
	grid = state.build_grid()
	pathfinder = Pathfinder.new(grid)
	_add_mesh("Blocks", BlockMesher.build(data.cells))
	_add_mesh("Stairs", PropFactory.build_stairs(grid))
	_add_mesh("Props", PropFactory.build_props(data.props))
	for mechanism: Mechanism in data.mechanisms:
		_add_mechanism(mechanism)

	for cell: Vector3i in state.waiting:
		var package := Package.create(state.waiting[cell])
		_place(package, cell)
		_packages[cell] = package
	for cell: Vector3i in state.pads:
		var pad := Pad.create(state.pads[cell])
		_place(pad, cell)
		_pads[cell] = pad
	_exit = ExitFlag.new()
	_exit.name = "Exit"
	_place(_exit, data.exit)
	_exit.set_open(state.all_delivered(), false)

	courier = preload("res://entities/Courier.tscn").instantiate()
	courier.pathfinder = pathfinder
	add_child(courier)
	courier.place(state.courier)
	courier.step_finished.connect(_on_courier_step)
	courier.arrived.connect(_on_courier_arrived)
	_last_cell = state.courier

	camera = OrbitCamera.new()
	camera.name = "Camera"
	camera.attributes = _stage.camera_attributes
	camera.idle_orbit_speed = idle_orbit_speed
	camera.grab_filter = _try_grab
	add_child(camera)
	camera.make_current()
	var bounds: AABB = _view_bounds()
	camera.distance_changed.connect(func(distance: float) -> void: _stage.fit_to_bounds(bounds, distance))
	camera.tapped.connect(_on_tapped)
	camera.double_tapped.connect(_on_double_tapped)
	camera.grab_moved.connect(_on_grab_moved)
	camera.grab_released.connect(_on_grab_released)
	camera.frame_bounds(bounds)


## Block under a screen position (see [method Grid.raycast]).
func pick(screen_position: Vector2) -> Dictionary:
	return grid.raycast(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


## Whether input is waiting for something to finish.
func is_busy() -> bool:
	return _busy > 0


func _on_tapped(screen_position: Vector2) -> void:
	if state.completed or _busy > 0:
		return
	var hit: Dictionary = pick(screen_position)
	if hit.is_empty():
		return
	var block: Vector3i = hit["cell"]
	for mechanism: Mechanism in data.mechanisms:
		if mechanism.kind == Mechanism.Kind.ROTATOR and mechanism.handle == block:
			_turn(mechanism.id)
			return
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


## Turns a rotator a quarter (one move), once the courier has stopped.
func _turn(id: String) -> void:
	if courier.is_moving():
		courier.stop()
		await courier.arrived
	var events: Array[Dictionary] = state.rotate(id)
	if events.is_empty():
		var handle: Vector3i = (state.mechanisms[id] as Mechanism).handle
		TapRipple.spawn(self, Vector3(handle) + Vector3(0.5, 0.75, 0.5), Vector3.UP, false)
		courier.puzzled()
		return
	moves_changed.emit(state.moves)
	await _play(events)


func _on_courier_step(cell: Vector3i) -> void:
	var ride: bool = pathfinder.is_belt(_last_cell)
	_last_cell = cell
	var events: Array[Dictionary] = state.enter(cell, ride)
	# Moving parts change the ground; let the player re-plan from here.
	if events.any(func(event: Dictionary) -> bool: return event["event"] == LevelState.Event.MECHANISM):
		courier.stop()
	moves_changed.emit(state.moves)
	_play(events)


func _on_courier_arrived(_cell: Vector3i) -> void:
	_continue_ride()


## A courier left standing on a running belt is carried on.
func _continue_ride() -> void:
	if _busy > 0 or state.completed or courier.is_moving():
		return
	var ride: Array[Vector3i] = pathfinder.ride_from(courier.cell)
	if not ride.is_empty():
		courier.walk(ride)


## Animates [param events] from LevelState, in order; mechanisms that move
## carry their riders along, and input waits until they settle.
func _play(events: Array[Dictionary]) -> void:
	_busy += 1
	var movers: Array[Dictionary] = []
	var relocated: Dictionary = {}
	var longest: float = 0.0
	var load_changed: bool = false
	for event: Dictionary in events:
		match event["event"]:
			LevelState.Event.PICKUP:
				var package: Package = _packages[event["cell"]]
				_packages.erase(event["cell"])
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
			LevelState.Event.MECHANISM:
				var mechanism: Mechanism = state.mechanisms[event["id"]]
				if mechanism.moves_blocks():
					movers.append({"id": event["id"], "from": event["from"], "to": event["to"], "riders": []})
				else:
					longest = maxf(longest, (_mechanism_nodes[event["id"]] as MechanismNode).show_value(event["to"]))
			LevelState.Event.CARRIED:
				_mover(movers, event["id"])["riders"].append({"node": courier, "to": event["to"]})
			LevelState.Event.PARCEL_MOVED:
				var package: Package = _packages[event["from"]]
				_packages.erase(event["from"])
				relocated[event["to"]] = package
				var mover: Dictionary = _mover(movers, event["id"])
				if mover.is_empty():
					longest = maxf(longest, package.slide_to(pathfinder.floor_position(event["to"])))
				else:
					mover["riders"].append({"node": package, "to": event["to"]})
	_packages.merge(relocated, true)
	if load_changed:
		courier.set_carried(state.carried)

	for mover: Dictionary in movers:
		var node: MechanismBlocks = _mechanism_nodes[mover["id"]]
		for rider: Dictionary in mover["riders"]:
			(rider["node"] as Node3D).reparent(node)
		longest = maxf(longest, node.show_value(mover["to"]))
	if longest > 0.0:
		await get_tree().create_timer(longest + 0.02).timeout
	for mover: Dictionary in movers:
		var mechanism: Mechanism = state.mechanisms[mover["id"]]
		for rider: Dictionary in mover["riders"]:
			_set_down(rider["node"], rider["to"], mechanism, mover["to"] - mover["from"])

	_refresh_grid()
	_last_cell = state.courier
	_busy -= 1
	_continue_ride()


## Puts a rider back in the level at [param cell] after a ride.
func _set_down(rider: Node3D, cell: Vector3i, mechanism: Mechanism, turned: int) -> void:
	rider.reparent(self)
	if rider == courier:
		var facing: Vector3i = courier.facing()
		if mechanism.kind == Mechanism.Kind.ROTATOR:
			facing = Mechanism.turn(facing, turned)
		courier.place(cell, facing)
	else:
		rider.rotation = Vector3.ZERO
		rider.position = pathfinder.floor_position(cell)


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


## Starts dragging a slider when a drag begins on one (see OrbitCamera.grab_filter).
func _try_grab(screen_position: Vector2) -> bool:
	if state.completed or _busy > 0 or courier.is_moving():
		return false
	var hit: Dictionary = pick(screen_position)
	if hit.is_empty():
		return false
	var id: String = _slider_at(hit["cell"])
	if id.is_empty():
		return false
	var mechanism: Mechanism = state.mechanisms[id]
	var node: MechanismBlocks = _mechanism_nodes[id]
	var centre: Vector3 = _centre(mechanism.cells_at(state.values[id]))
	var axis_px: Vector2 = camera.unproject_position(centre + Vector3(mechanism.axis)) - camera.unproject_position(centre)
	if axis_px.length() < 8.0:
		return false
	var riders: Array[Node3D] = []
	if mechanism.cells_at(state.values[id]).has(state.courier - Vector3i.UP):
		riders.append(courier)
	for cell: Vector3i in _packages:
		if mechanism.cells_at(state.values[id]).has(cell - Vector3i.UP):
			riders.append(_packages[cell])
	for rider: Node3D in riders:
		rider.reparent(node)
	_busy += 1
	_grab = {
		"id": id, "start": state.values[id], "range": state.slide_range(id),
		"axis_px": axis_px, "press": screen_position, "riders": riders,
	}
	return true


func _on_grab_moved(screen_position: Vector2) -> void:
	if _grab.is_empty():
		return
	var axis_px: Vector2 = _grab["axis_px"]
	var cells: float = (screen_position - (_grab["press"] as Vector2)).dot(axis_px) / axis_px.length_squared()
	var reach: Vector2i = _grab["range"]
	(_mechanism_nodes[_grab["id"]] as MechanismBlocks).set_pose(clampf(_grab["start"] + cells, reach.x, reach.y))


func _on_grab_released(_screen_position: Vector2) -> void:
	if _grab.is_empty():
		return
	var grab: Dictionary = _grab
	_grab = {}
	var node: MechanismBlocks = _mechanism_nodes[grab["id"]]
	var reach: Vector2i = grab["range"]
	var target: int = clampi(roundi(node.pose), reach.x, reach.y)
	for rider: Node3D in grab["riders"]:
		rider.reparent(self)
	var events: Array[Dictionary] = state.slide(grab["id"], target)
	if events.is_empty():
		# Not moved after all: ease back, riders and all.
		for rider: Node3D in grab["riders"]:
			rider.reparent(node)
		await get_tree().create_timer(node.show_value(grab["start"]) + 0.02).timeout
		var mechanism: Mechanism = state.mechanisms[grab["id"]]
		for rider: Node3D in grab["riders"]:
			var cell: Vector3i = state.courier if rider == courier else _cell_of(rider)
			_set_down(rider, cell, mechanism, 0)
		_busy -= 1
		return
	moves_changed.emit(state.moves)
	_busy -= 1
	await _play(events)


func _slider_at(cell: Vector3i) -> String:
	for mechanism: Mechanism in data.mechanisms:
		if mechanism.kind == Mechanism.Kind.SLIDER and mechanism.cells_at(state.values[mechanism.id]).has(cell):
			return mechanism.id
	return ""


func _cell_of(package: Node3D) -> Vector3i:
	for cell: Vector3i in _packages:
		if _packages[cell] == package:
			return cell
	return Vector3i.ZERO


static func _mover(movers: Array[Dictionary], id: String) -> Dictionary:
	for mover: Dictionary in movers:
		if mover["id"] == id:
			return mover
	return {}


static func _centre(cells: Array[Vector3i]) -> Vector3:
	var sum := Vector3.ZERO
	for cell: Vector3i in cells:
		sum += Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	return sum / cells.size()


func _refresh_grid() -> void:
	grid = state.build_grid()
	pathfinder.set_grid(grid)


func _add_mechanism(mechanism: Mechanism) -> void:
	var node: MechanismNode
	match mechanism.kind:
		Mechanism.Kind.CONVEYOR:
			node = MechanismConveyor.new(mechanism)
		Mechanism.Kind.BUTTON:
			node = MechanismButton.new(mechanism)
		Mechanism.Kind.GATE:
			node = MechanismGate.new(mechanism)
		_:
			node = MechanismBlocks.new(mechanism)
	node.value = state.values[mechanism.id]
	add_child(node)
	if mechanism.kind == Mechanism.Kind.ROTATOR:
		add_child((node as MechanismBlocks).make_crank())
	_mechanism_nodes[mechanism.id] = node


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


## Everything that can ever be on screen: blocks, mechanisms in every state,
## props and the exit post.
func _view_bounds() -> AABB:
	var bounds: AABB = grid.bounds
	for mechanism: Mechanism in data.mechanisms:
		var states: Array[int] = []
		match mechanism.kind:
			Mechanism.Kind.SLIDER:
				states.assign(range(mechanism.min_value, mechanism.max_value + 1))
			Mechanism.Kind.ELEVATOR:
				states.assign([0, 1])
			Mechanism.Kind.ROTATOR:
				states.assign([0, 1, 2, 3])
			_:
				states.assign([0])
		for value: int in states:
			for cell: Vector3i in mechanism.cells_at(value):
				bounds = bounds.merge(AABB(Vector3(cell), Vector3.ONE))
	for prop: Dictionary in data.props:
		bounds = bounds.merge(AABB(Vector3(prop["cell"]), Vector3(1.0, 1.1, 1.0)))
	return bounds.merge(AABB(Vector3(data.exit), Vector3(1.0, ExitFlag.POST_HEIGHT, 1.0)))
