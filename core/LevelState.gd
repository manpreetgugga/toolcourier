class_name LevelState
extends RefCounted
## The whole puzzle state of a level, with no visuals: where the courier is,
## which parcels lie where, what it carries, which pads are filled, the state
## of every mechanism and how many moves were made. Shared by the Level
## scene, the solver and undo.
##
## The courier acts in two ways. [method enter] moves it into a cell (the
## caller has checked the step is allowed) and applies the rules there, in
## order: a parcel matching an empty pad is dropped, a parcel lying there is
## picked up if there is room, a button is toggled, an elevator underfoot
## sets off, and reaching the open exit completes the level. [method slide]
## and [method rotate] are the player working a mechanism. Every change is
## reported as events, in order, for the scene to animate:
## {"event": Event, "cell": Vector3i, "color": StringName} for parcels and
## the exit, {"event": Event, "id": String, "from": ..., "to": ...} for
## mechanisms and what they carry.

enum Event { PICKUP, DROP, EXIT_OPENED, COMPLETED, MECHANISM, CARRIED, PARCEL_MOVED }

const CONVEYOR_BLOCK: StringName = &"conveyor"

var data: LevelData
var carry_limit: int
var exit: Vector3i
var courier: Vector3i
var moves: int = 0
## Parcels still on the floor: Vector3i -> color.
var waiting: Dictionary = {}
## Pads: Vector3i -> color.
var pads: Dictionary = {}
## Filled pads: Vector3i -> true.
var filled: Dictionary = {}
## Colours carried, in pickup order.
var carried: Array[StringName] = []
var completed: bool = false
## id -> Mechanism, and id -> its state (see Mechanism).
var mechanisms: Dictionary = {}
var values: Dictionary = {}


func _init(level: LevelData) -> void:
	data = level
	carry_limit = level.carry_limit
	exit = level.exit
	courier = level.start
	for item: Dictionary in level.packages:
		waiting[item["cell"]] = item["color"]
	for item: Dictionary in level.pads:
		pads[item["cell"]] = item["color"]
	for mechanism: Mechanism in level.mechanisms:
		mechanisms[mechanism.id] = mechanism
		values[mechanism.id] = mechanism.initial
	_update_gates()
	for mechanism: Mechanism in level.mechanisms:
		if mechanism.kind == Mechanism.Kind.CONVEYOR and values[mechanism.id] == 1:
			_settle_belt(mechanism)


func all_delivered() -> bool:
	return filled.size() == pads.size()


## The grid as it stands now: level blocks plus mechanism blocks where they
## are, solid props and closed gates as obstacles, running belts.
func build_grid() -> Grid:
	var cells: Dictionary = data.cells.duplicate()
	for mechanism: Mechanism in mechanisms.values():
		if mechanism.has_blocks():
			var block_type: StringName = CONVEYOR_BLOCK if mechanism.kind == Mechanism.Kind.CONVEYOR else BlockMaterials.ACCENT
			for cell: Vector3i in mechanism.cells_at(values[mechanism.id]):
				cells[cell] = block_type
	var grid := Grid.new(cells, data.facing)
	for prop: Dictionary in data.props:
		if prop["solid"]:
			grid.obstacles[prop["cell"]] = true
	for mechanism: Mechanism in mechanisms.values():
		if mechanism.kind == Mechanism.Kind.GATE and values[mechanism.id] == 0:
			for cell: Vector3i in mechanism.cells:
				grid.obstacles[cell] = true
		elif mechanism.kind == Mechanism.Kind.CONVEYOR and values[mechanism.id] == 1:
			for cell: Vector3i in mechanism.cells:
				grid.belts[cell] = mechanism.axis
	return grid


## The courier moves into [param cell]: a walked step counts as a move, a
## [param ride] on a belt does not. Returns the events it caused.
func enter(cell: Vector3i, ride: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if completed:
		return events
	courier = cell
	if not ride:
		moves += 1
	if pads.has(cell) and not filled.has(cell):
		var index: int = carried.find(pads[cell])
		if index >= 0:
			carried.remove_at(index)
			filled[cell] = true
			events.append({"event": Event.DROP, "cell": cell, "color": pads[cell]})
			if all_delivered():
				events.append({"event": Event.EXIT_OPENED, "cell": exit, "color": &""})
	if waiting.has(cell) and carried.size() < carry_limit:
		carried.append(waiting[cell])
		events.append({"event": Event.PICKUP, "cell": cell, "color": waiting[cell]})
		waiting.erase(cell)
	for mechanism: Mechanism in mechanisms.values():
		if mechanism.kind == Mechanism.Kind.BUTTON and mechanism.cells[0] == cell:
			events.append_array(_press(mechanism))
	for mechanism: Mechanism in mechanisms.values():
		if mechanism.kind == Mechanism.Kind.ELEVATOR and _stands_on(mechanism, values[mechanism.id], courier):
			events.append_array(move_mechanism(mechanism.id, 1 - values[mechanism.id]))
			break
	if cell == exit and all_delivered():
		completed = true
		events.append({"event": Event.COMPLETED, "cell": cell, "color": &""})
	return events


## The player drags slider [param id] to offset [param to] (one move).
func slide(id: String, to: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = move_mechanism(id, to)
	if not events.is_empty():
		moves += 1
	return events


## The player turns rotator [param id] a quarter turn (one move).
func rotate(id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = move_mechanism(id, (values[id] + 1) % 4)
	if not events.is_empty():
		moves += 1
	return events


## Offsets a slider can reach from where it is, as (lowest, highest).
func slide_range(id: String) -> Vector2i:
	var mechanism: Mechanism = mechanisms[id]
	var low: int = values[id]
	var high: int = low
	while low - 1 >= mechanism.min_value and can_move(id, low - 1):
		low -= 1
	while high + 1 <= mechanism.max_value and can_move(id, high + 1):
		high += 1
	return Vector2i(low, high)


## Moves a slider, elevator or rotator to state [param to] if nothing is in
## the way, carrying the courier and parcels standing on it.
func move_mechanism(id: String, to: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var mechanism: Mechanism = mechanisms[id]
	var from: int = values[id]
	if from == to or not can_move(id, to):
		return events
	events.append({"event": Event.MECHANISM, "id": id, "from": from, "to": to})
	var rides: bool = _stands_on(mechanism, from, courier)
	var parcels: Array[Vector3i] = _parcels_on(mechanism, from)
	values[id] = to
	if rides:
		var landing: Vector3i = mechanism.carry(courier, from, to)
		events.append({"event": Event.CARRIED, "id": id, "from": courier, "to": landing})
		courier = landing
	_move_parcels(parcels, func(cell: Vector3i) -> Vector3i: return mechanism.carry(cell, from, to), id, events)
	return events


## Whether a moving mechanism can go to state [param to]: its blocks may not
## pass through blocks, obstacles, fixtures (pads, the exit, buttons) or
## anyone not riding it, and whatever rides it must stay in open cells.
func can_move(id: String, to: int) -> bool:
	var mechanism: Mechanism = mechanisms[id]
	var from: int = values[id]
	if not mechanism.moves_blocks():
		return false
	var blocked: Dictionary = _blocked_cells(id)
	for cell: Vector3i in pads:
		blocked[cell] = true
	blocked[exit] = true
	for other: Mechanism in mechanisms.values():
		if other.kind == Mechanism.Kind.BUTTON:
			blocked[other.cells[0]] = true
	var riders: Array[Vector3i] = _parcels_on(mechanism, from)
	if _stands_on(mechanism, from, courier):
		riders.append(courier)
	else:
		blocked[courier] = true
	for cell: Vector3i in waiting:
		if not riders.has(cell):
			blocked[cell] = true

	var start: Array[Vector3i] = mechanism.cells_at(from)
	var poses: Array = []
	if mechanism.kind == Mechanism.Kind.ROTATOR:
		var turned: Array[Vector3i] = []
		for rider: Vector3i in riders:
			turned.append(mechanism.carry(rider, from, to))
		poses.append([mechanism.cells_at(to), turned])
	else:
		for offset: Vector3i in mechanism.steps(from, to):
			var shifted: Array[Vector3i] = []
			for cell: Vector3i in start:
				shifted.append(cell + offset)
			var carried_riders: Array[Vector3i] = []
			for rider: Vector3i in riders:
				carried_riders.append(rider + offset)
			poses.append([shifted, carried_riders])
	for pose: Array in poses:
		for cell: Vector3i in pose[0]:
			if blocked.has(cell):
				return false
		for rider: Vector3i in pose[1]:
			if blocked.has(rider) or (pose[0] as Array).has(rider):
				return false
	return true


## Everything needed to restore this state later (for undo and the solver).
func snapshot() -> Dictionary:
	return {
		"courier": courier, "moves": moves, "waiting": waiting.duplicate(), "filled": filled.duplicate(),
		"carried": carried.duplicate(), "completed": completed, "values": values.duplicate(),
	}


func restore(saved: Dictionary) -> void:
	courier = saved["courier"]
	moves = saved["moves"]
	waiting = saved["waiting"].duplicate()
	filled = saved["filled"].duplicate()
	carried.assign(saved["carried"])
	completed = saved["completed"]
	values = saved["values"].duplicate()


func _press(button: Mechanism) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var was: int = values[button.id]
	values[button.id] = 1 - was
	events.append({"event": Event.MECHANISM, "id": button.id, "from": was, "to": 1 - was})
	for target: String in button.links:
		var mechanism: Mechanism = mechanisms[target]
		var value: int = values[target]
		match mechanism.kind:
			Mechanism.Kind.ELEVATOR:
				events.append_array(move_mechanism(target, 1 - value))
			Mechanism.Kind.ROTATOR:
				events.append_array(move_mechanism(target, (value + 1) % 4))
			Mechanism.Kind.SLIDER:
				# Off to the far end, or as far as it can get.
				var reach: Vector2i = slide_range(target)
				events.append_array(move_mechanism(target, reach.x if value == mechanism.max_value else reach.y))
			Mechanism.Kind.CONVEYOR:
				values[target] = 1 - value
				events.append({"event": Event.MECHANISM, "id": target, "from": value, "to": 1 - value})
				if values[target] == 1:
					events.append_array(_settle_belt(mechanism))
	events.append_array(_update_gates())
	return events


## Gates open when all their buttons are on, and close again otherwise
## unless the courier or a parcel is standing in them.
func _update_gates() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for gate: Mechanism in mechanisms.values():
		if gate.kind != Mechanism.Kind.GATE:
			continue
		var open: int = 1
		for button: String in gate.links:
			if values[button] == 0:
				open = 0
		if open == values[gate.id]:
			continue
		if open == 0 and (gate.cells.has(courier) or gate.cells.any(func(cell: Vector3i) -> bool: return waiting.has(cell))):
			continue
		events.append({"event": Event.MECHANISM, "id": gate.id, "from": values[gate.id], "to": open})
		values[gate.id] = open
	return events


## A running belt pushes the parcels on it to its far end (they stop there,
## or behind another parcel or the courier).
func _settle_belt(belt: Mechanism) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var tops: Dictionary = {}
	for cell: Vector3i in belt.cells:
		tops[cell + Vector3i.UP] = true
	var on_belt: Array[Vector3i] = []
	for cell: Vector3i in waiting:
		if tops.has(cell):
			on_belt.append(cell)
	# Downstream parcels first, so the ones behind queue up against them.
	var axis: Vector3i = belt.axis
	on_belt.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x * axis.x + a.z * axis.z > b.x * axis.x + b.z * axis.z)
	for cell: Vector3i in on_belt:
		var stop: Vector3i = cell
		while tops.has(stop + axis) and not waiting.has(stop + axis) and stop + axis != courier:
			stop += axis
		if stop != cell:
			waiting[stop] = waiting[cell]
			waiting.erase(cell)
			events.append({"event": Event.PARCEL_MOVED, "id": belt.id, "from": cell, "to": stop})
	return events


func _move_parcels(parcels: Array[Vector3i], carry: Callable, id: String, events: Array[Dictionary]) -> void:
	var moved: Dictionary = {}
	for cell: Vector3i in parcels:
		var landing: Vector3i = carry.call(cell)
		moved[landing] = waiting[cell]
		events.append({"event": Event.PARCEL_MOVED, "id": id, "from": cell, "to": landing})
	for cell: Vector3i in parcels:
		waiting.erase(cell)
	waiting.merge(moved, true)


## Level blocks, other mechanisms' blocks, solid props and closed gates.
func _blocked_cells(except_id: String) -> Dictionary:
	var blocked: Dictionary = {}
	for cell: Vector3i in data.cells:
		blocked[cell] = true
	for mechanism: Mechanism in mechanisms.values():
		if mechanism.id == except_id:
			continue
		if mechanism.has_blocks():
			for cell: Vector3i in mechanism.cells_at(values[mechanism.id]):
				blocked[cell] = true
		elif mechanism.kind == Mechanism.Kind.GATE and values[mechanism.id] == 0:
			for cell: Vector3i in mechanism.cells:
				blocked[cell] = true
	for prop: Dictionary in data.props:
		if prop["solid"]:
			blocked[prop["cell"]] = true
	return blocked


func _parcels_on(mechanism: Mechanism, value: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector3i in waiting:
		if _stands_on(mechanism, value, cell):
			result.append(cell)
	return result


static func _stands_on(mechanism: Mechanism, value: int, cell: Vector3i) -> bool:
	return mechanism.moves_blocks() and mechanism.cells_at(value).has(cell - Vector3i.UP)
