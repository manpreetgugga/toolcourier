class_name LevelState
extends RefCounted
## The delivery rules, with no visuals: which parcels still lie where, what
## the courier carries, which pads are filled, and how many moves were made.
## Shared by the Level scene, the solver and undo.
##
## Each time the courier enters a cell, [method enter] applies the rules in
## order and reports what happened: a parcel matching an empty pad is
## dropped there, a parcel lying in the cell is picked up if there is room,
## and reaching the exit with every pad filled completes the level.

enum Event { PICKUP, DROP, EXIT_OPENED, COMPLETED }

var carry_limit: int
var exit: Vector3i
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


func _init(data: LevelData) -> void:
	carry_limit = data.carry_limit
	exit = data.exit
	for item: Dictionary in data.packages:
		waiting[item["cell"]] = item["color"]
	for item: Dictionary in data.pads:
		pads[item["cell"]] = item["color"]


func all_delivered() -> bool:
	return filled.size() == pads.size()


## Counts a move into [param cell] and applies the rules. Returns events as
## {"event": Event, "cell": Vector3i, "color": StringName}.
func enter(cell: Vector3i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if completed:
		return events
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
	if cell == exit and all_delivered():
		completed = true
		events.append({"event": Event.COMPLETED, "cell": cell, "color": &""})
	return events


## Everything needed to restore this state later (for undo).
func snapshot() -> Dictionary:
	return {
		"moves": moves, "waiting": waiting.duplicate(), "filled": filled.duplicate(),
		"carried": carried.duplicate(), "completed": completed,
	}


func restore(saved: Dictionary) -> void:
	moves = saved["moves"]
	waiting = saved["waiting"].duplicate()
	filled = saved["filled"].duplicate()
	carried.assign(saved["carried"])
	completed = saved["completed"]
