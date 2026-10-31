class_name Solver
extends RefCounted
## Finds the fewest moves that finish a level from a given state: a
## breadth-first search over LevelState in which walked steps, slider drags
## and crank turns cost a move and belt rides cost nothing (0-1 BFS). The
## plan it returns drives hints; the level checker reuses it.
##
## A plan is a list of actions, each a Dictionary:
##   {"action": Action.STEP, "cell": Vector3i, "ride": bool}
##   {"action": Action.SLIDE, "id": String, "to": int}
##   {"action": Action.TURN, "id": String}
## plus, describing what it did, "events" (it changed more than where the
## courier stands), "key" and "moves" (the state after it).

enum Action { STEP, SLIDE, TURN }

## Gives up past this many states, so a hint never hangs.
const MAX_STATES: int = 150000

var data: LevelData
## States looked at by the last search, and whether it stopped at
## MAX_STATES without an answer.
var explored: int = 0
var gave_up: bool = false

var _state: LevelState
## Mechanism values key -> Pathfinder for the grid in that configuration.
var _paths: Dictionary = {}
var _sliders: Array[String] = []
var _rotators: Array[String] = []


func _init(level: LevelData) -> void:
	data = level
	_state = LevelState.new(level)
	for mechanism: Mechanism in level.mechanisms:
		if mechanism.kind == Mechanism.Kind.SLIDER:
			_sliders.append(mechanism.id)
		elif mechanism.kind == Mechanism.Kind.ROTATOR:
			_rotators.append(mechanism.id)


## The shortest plan from [param start] (a LevelState snapshot) to the end of
## the level. Empty when the level is already complete, cannot be finished
## from there, or the search [member gave_up].
func solve(start: Dictionary) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	explored = 0
	_state.restore(start)
	if _state.completed:
		return plan
	var start_key: String = key_of(_state)
	var cost: Dictionary = {start_key: 0}
	var snapshots: Dictionary = {start_key: start}
	## key -> [previous key, action]
	var came_from: Dictionary = {}
	var layer: Array[String] = [start_key]
	var depth: int = 0
	var goal: String = ""
	gave_up = false
	while not layer.is_empty() and goal.is_empty():
		var next_layer: Array[String] = []
		var i: int = 0
		# Free actions (rides) append to the layer being read.
		while i < layer.size():
			var key: String = layer[i]
			i += 1
			if cost[key] != depth:
				continue
			if snapshots[key]["completed"]:
				goal = key
				break
			explored += 1
			if explored > MAX_STATES:
				gave_up = true
				return plan
			for action: Dictionary in _actions(snapshots[key]):
				_state.restore(snapshots[key])
				action["events"] = not apply_to(_state, action, true).is_empty()
				var next_key: String = key_of(_state)
				var next_cost: int = depth + _state.moves - (snapshots[key]["moves"] as int)
				if cost.has(next_key) and cost[next_key] <= next_cost:
					continue
				cost[next_key] = next_cost
				snapshots[next_key] = _state.snapshot()
				action["key"] = next_key
				action["moves"] = _state.moves
				came_from[next_key] = [key, action]
				if next_cost == depth:
					layer.append(next_key)
				else:
					next_layer.append(next_key)
		layer = next_layer
		depth += 1
	var at: String = goal
	while not at.is_empty() and at != start_key:
		var link: Array = came_from[at]
		plan.push_front(link[1])
		at = link[0]
	return plan


## Applies [param action] to [param state] (as the Level does for the
## player) and returns its events. [param checked]: the action was just
## found possible in this state, so slides and turns skip checking again.
static func apply_to(state: LevelState, action: Dictionary, checked: bool = false) -> Array[Dictionary]:
	match action["action"]:
		Action.SLIDE:
			return state.slide(action["id"], action["to"], checked)
		Action.TURN:
			return state.rotate(action["id"], checked)
	return state.enter(action["cell"], action["ride"])


## A string naming everything about [param state] except the move count.
static func key_of(state: LevelState) -> String:
	var parts := PackedStringArray()
	parts.append(_cell_text(state.courier))
	var cells := PackedStringArray()
	for cell: Vector3i in state.waiting:
		cells.append(_cell_text(cell) + String(state.waiting[cell]))
	cells.sort()
	parts.append(",".join(cells))
	var colors := PackedStringArray()
	for color: StringName in state.carried:
		colors.append(String(color))
	colors.sort()
	parts.append(",".join(colors))
	cells = PackedStringArray()
	for cell: Vector3i in state.filled:
		cells.append(_cell_text(cell))
	cells.sort()
	parts.append(",".join(cells))
	for mechanism: Mechanism in state.data.mechanisms:
		parts.append(str(state.values[mechanism.id]))
	parts.append("1" if state.completed else "0")
	return "|".join(parts)


## The Pathfinder for the grid as [param state] stands (cached per
## mechanism configuration).
func paths_for(state: LevelState) -> Pathfinder:
	var key := PackedStringArray()
	for mechanism: Mechanism in data.mechanisms:
		key.append(str(state.values[mechanism.id]))
	var joined: String = ",".join(key)
	if not _paths.has(joined):
		_paths[joined] = Pathfinder.new(state.build_grid())
	return _paths[joined]


func _actions(snapshot: Dictionary) -> Array[Dictionary]:
	_state.restore(snapshot)
	var actions: Array[Dictionary] = []
	var paths: Pathfinder = paths_for(_state)
	var here: Vector3i = _state.courier
	var riding: bool = paths.is_belt(here)
	for next: Vector3i in paths.neighbors(here):
		actions.append({"action": Action.STEP, "cell": next, "ride": riding})
	# A belt carries the courier on; nothing else happens until it is off.
	if riding:
		return actions
	for id: String in _sliders:
		var reach: Vector2i = _state.slide_range(id)
		for to: int in range(reach.x, reach.y + 1):
			if to != _state.values[id]:
				actions.append({"action": Action.SLIDE, "id": id, "to": to})
	for id: String in _rotators:
		if _state.can_move(id, (_state.values[id] + 1) % 4):
			actions.append({"action": Action.TURN, "id": id})
	return actions


static func _cell_text(cell: Vector3i) -> String:
	return "%d %d %d" % [cell.x, cell.y, cell.z]
