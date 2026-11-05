class_name Level
extends Node3D
## Plays one delivery level: builds the diorama from a level JSON file, turns
## taps and drags into courier paths and mechanism moves, and animates what
## LevelState reports as the rules play out. Keeps the undo history, shows
## hints from the Solver, records finishes in Progress and saves a game in
## progress when the app is paused or closed.
##
## Drag to orbit, pinch or scroll to zoom, tap a spot to walk there (a slide
## over ice or a bounce off a spring runs to its end before the courier can
## turn). Drag a slider
## along its axis; tap a crank to turn its rotator. A white ripple
## marks the destination; a red ripple and a puzzled tilt mean there is no
## way. Tapping the courier while it stands still plays an emote. A double
## tap on empty space resets the view. Input waits while mechanisms move.
##
## With [member intro] the diorama builds itself up when it opens and takes
## itself down before it is left (see Assembly); input waits meanwhile. A
## playable level plays its world's music, starts the ads (from world 1's
## level 21 on) and tells them of each finish (see Ads); the back button
## pauses (see Hud).

signal moves_changed(moves: int)
signal level_completed(moves: int, stars: int)
## The build-up has finished and play can start.
signal assembled

## Undo steps kept (oldest are dropped).
const MAX_UNDO: int = 300
## The sound of each of the courier's emotes (see Courier.emote).
const EMOTE_SOUNDS: Dictionary = {&"wave": &"pickup", &"hop": &"whoosh", &"chatter": &"drop", &"wiggle": &"tap"}

@export_file("*.json") var level_path: String = "res://levels/world_1/level_1.json"
## Degrees per second of idle orbit; 0 keeps the camera still.
@export var idle_orbit_speed: float = 0.0
## Adds the HUD (moves, stars, undo, restart, hint and the finish card).
@export var show_hud: bool = true
## Builds up on opening and takes itself down on leaving (the game's flow
## turns it on; tests and tools start with the diorama standing).
@export var intro: bool = false
## Answers taps and drags; a menu backdrop turns it off.
@export var interactive: bool = true
## How much of the screen's short side the diorama fills.
@export_range(0.3, 1.0) var view_fill: float = 0.75
## Seconds the build-up waits (with nothing showing) before it starts.
@export var intro_delay: float = 0.0

var data: LevelData
var state: LevelState
var grid: Grid
var pathfinder: Pathfinder
var camera: OrbitCamera
var courier: Courier
## The 2D interface (null without [member show_hud]).
var hud: Hud
## Whether the last finish beat the saved best.
var finished_best: bool = false

var _stage: StageLighting
## Parcels on the floor by their current cell; carried ones in pickup order;
## delivered ones by pad cell.
var _packages: Dictionary = {}
var _carried: Array[Package] = []
var _delivered: Dictionary = {}
var _pads: Dictionary = {}
var _exit: ExitFlag
## id -> MechanismNode.
var _mechanism_nodes: Dictionary = {}
## Mechanism animations in progress; input waits for them.
var _busy: int = 0
## Where the courier stood before its current step (a step from a belt is a ride).
var _last_cell: Vector3i
## The way the courier came onto the ice or the spring it is on (zero off
## them or once it has stopped): carrying on that way is a ride.
var _glide: Vector3i
var _boards: DryBoards
var _springs: Springs
## The slider being dragged: id, start, range, the track it slides along (a
## point and the axis), where along it the press was, and its riders.
var _grab: Dictionary = {}
## The state at the start, and snapshots taken before each player action
## (a walk, a slider drag, a crank turn, a restart), oldest first.
var _initial: Dictionary
var _history: Array[Dictionary] = []
var _solver: Solver
## The solver's last plan and the state it started from.
var _plan: Array[Dictionary] = []
var _plan_from: Array = []
var _hint: HintMarker
## What the hint showing asks for (see [method hinted]).
var _hinted: Dictionary = {}
var _assembly: Assembly
## When each cell starts building up.
var _delays: Dictionary = {}
var _bounds: AABB
var _leaving: bool = false
## A slider let go of after a drag: its move makes no sliding sound.
var _dragged: String = ""
## Restarted since it opened (Replay too): a finish after that is never
## followed by a level break.
var _restarted: bool = false
## The go at the level under way, for the statistics (see Analytics): the
## seconds played in it (not paused), and its hints, undos and restarts.
## Not counting before it starts or once it has ended.
var _counting: bool = false
var _seconds: float = 0.0
var _hints: int = 0
var _undos: int = 0
var _restarts: int = 0


func _ready() -> void:
	set_process(false)
	data = LevelLoader.load_file(level_path)
	if not data.is_valid():
		for problem: String in data.errors:
			push_error("%s: %s" % [level_path, problem])
		return

	_stage = StageLighting.new()
	_stage.name = "Stage"
	_stage.theme_name = data.palette
	_stage.tilt_shift_enabled = Settings.tilt_shift
	add_child(_stage)
	Settings.events.changed.connect(_on_setting_changed)

	state = LevelState.new(data)
	_initial = state.snapshot()
	_solver = Solver.new(data)
	var saved: Dictionary = Progress.in_progress(_id(), data.fingerprint, state)
	if not saved.is_empty():
		_history = saved["history"]
		state.restore(saved["state"])
	grid = state.build_grid()
	pathfinder = Pathfinder.new(grid)
	_delays = Assembly.delays(_build_order())
	_assembly = Assembly.new()
	_assembly.name = "Assembly"
	add_child(_assembly)
	_add_mesh("Blocks", BlockMesher.build(data.cells, _delays))
	_add_mesh("Stairs", PropFactory.build_stairs(grid, _delays))
	_add_mesh("Props", PropFactory.build_props(data.props, Palette.season(data.palette), _delays))
	for mechanism: Mechanism in data.mechanisms:
		_add_mechanism(mechanism)
	_boards = DryBoards.new(data.cells)
	add_child(_boards)
	_boards.set_fallen(state.fallen)
	_springs = Springs.new(data.cells)
	add_child(_springs)

	for cell: Vector3i in state.pads:
		var pad := Pad.create(state.pads[cell])
		_place(pad, cell)
		_pads[cell] = pad
	_rebuild_parcels()
	_exit = ExitFlag.new()
	_exit.name = "Exit"
	_place(_exit, data.exit)
	_exit.set_open(state.all_delivered(), false)

	courier = preload("res://entities/Courier.tscn").instantiate()
	courier.pathfinder = pathfinder
	add_child(courier)
	courier.place(state.courier)
	if not state.carried.is_empty():
		courier.set_carried(state.carried)
	courier.step_finished.connect(_on_courier_step)
	courier.arrived.connect(_on_courier_arrived)
	_last_cell = state.courier

	camera = OrbitCamera.new()
	camera.name = "Camera"
	camera.attributes = _stage.camera_attributes
	camera.idle_orbit_speed = idle_orbit_speed
	camera.fill_fraction = view_fill
	camera.grab_filter = _try_grab
	add_child(camera)
	camera.make_current()
	camera.set_process_unhandled_input(interactive)
	_bounds = _view_bounds()
	var weather: CPUParticles3D = Weather.create(Palette.weather(data.palette), _bounds)
	if weather:
		add_child(weather)
	camera.distance_changed.connect(func(distance: float) -> void: _stage.fit_to_bounds(_bounds, distance))
	camera.tapped.connect(_on_tapped)
	camera.double_tapped.connect(_on_double_tapped)
	camera.grab_moved.connect(_on_grab_moved)
	camera.grab_released.connect(_on_grab_released)
	camera.frame_bounds(_bounds)

	if show_hud:
		hud = Hud.new()
		hud.name = "Hud"
		hud.level = self
		add_child(hud)
	_prepare_assembly()
	if interactive and show_hud:
		AudioManager.play_music(LevelCatalog.world_of(level_path))
		Ads.start_for(level_path)
		Analytics.start()
		Reminders.start()
		Analytics.screen("level")
		_begin_go(not saved.is_empty(), false)
	if intro:
		_build_up()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		keep_progress()
	# An ad on screen pauses the app too; the game carries on after it.
	if what == NOTIFICATION_APPLICATION_PAUSED and hud and not Ads.is_showing():
		hud.pause.call_deferred()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and interactive and not Game.is_swapping():
		go_back()


func _exit_tree() -> void:
	keep_progress()
	_end_go(false, 0)


func _process(delta: float) -> void:
	_seconds += delta


## Block under a screen position (see [method Grid.raycast]).
func pick(screen_position: Vector2) -> Dictionary:
	return grid.raycast(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


## Whether a tap at [param screen_position] lands on the courier, in front
## of any block there.
func taps_courier(screen_position: Vector2) -> bool:
	var along: float = courier.ray_distance(camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position))
	if along < 0.0:
		return false
	var hit: Dictionary = pick(screen_position)
	return hit.is_empty() or hit["distance"] > along - Courier.TAP_RADIUS


## Whether input is waiting for something to finish.
func is_busy() -> bool:
	return _busy > 0


## How many actions can be undone.
func undo_count() -> int:
	return _history.size()


func can_undo() -> bool:
	return not _history.is_empty() and _is_settled()


## Takes back the last action (a walk, even one still going, a slider drag,
## a crank turn or a restart), moves and all.
func undo() -> bool:
	if not can_undo():
		return false
	state.restore(_history.pop_back())
	_sync()
	_undos += 1
	return true


func can_restart() -> bool:
	return state.moves > 0 and _is_settled(true)


## Back to the start. Undo brings the game back, unless it was finished.
func restart() -> bool:
	if not can_restart():
		return false
	var replay: bool = state.completed
	if replay:
		_history.clear()
	else:
		_record()
	state.restore(_initial)
	_restarted = true
	_sync()
	if replay:
		_begin_go(false, true)
	else:
		_restarts += 1
	return true


func can_hint() -> bool:
	return _is_settled() and not courier.is_moving()


## Shows the first step of the shortest way to finish from here: where to
## walk, which slider to drag where, or which crank to turn. Returns what
## to tell the player, or "" if no hint can be shown now.
func show_hint() -> String:
	if not can_hint():
		return ""
	_clear_hint()
	var plan: Array[Dictionary] = _plan_from_here()
	if plan.is_empty():
		courier.puzzled()
		return "Too tricky to work out from here." if _solver.gave_up else "No way forward from here: undo or restart."
	_hints += 1
	var first: Dictionary = plan[0]
	_hinted = {"action": first["action"], "id": first.get("id", ""), "to": first.get("to", 0)}
	match first["action"]:
		Solver.Action.SLIDE:
			var mechanism: Mechanism = state.mechanisms[first["id"]]
			_hint = HintMarker.pointing_at(_centre(mechanism.cells_at(state.values[first["id"]])) + Vector3(0.0, 0.5, 0.0))
			_hint.add_ghost((_mechanism_nodes[first["id"]] as MechanismBlocks).blocks_mesh(), mechanism.transform_for(first["to"]))
			add_child(_hint)
			return "Drag the orange block to the outline."
		Solver.Action.TURN:
			var mechanism: Mechanism = state.mechanisms[first["id"]]
			_hint = HintMarker.pointing_at(Vector3(mechanism.handle) + Vector3(0.5, 0.65, 0.5))
			_hint.add_ghost((_mechanism_nodes[first["id"]] as MechanismBlocks).blocks_mesh(),
				mechanism.transform_for((state.values[first["id"]] + 1) % 4))
			add_child(_hint)
			return "Tap the crank to turn the bridge."
	var route: Array[Vector3i] = _hint_route(plan)
	_hinted["cell"] = route[-1]
	_hint = HintMarker.pointing_at(pathfinder.floor_position(route[-1]))
	var dots: Array[Vector3] = []
	for i in range(1, route.size() - 1):
		dots.append(pathfinder.floor_position(route[i]))
	_hint.add_trail(dots)
	add_child(_hint)
	return "Walk to the arrow."


## Whether a hint is showing.
func has_hint() -> bool:
	return _hint != null


## What the hint showing asks for: {"action": Solver.Action.STEP, "cell":
## where to walk}, {"action": SLIDE, "id", "to"} or {"action": TURN, "id"};
## empty when no hint shows.
func hinted() -> Dictionary:
	return _hinted


## The level after this one ("" when this is the last).
func next_level_path() -> String:
	return LevelCatalog.next_after(level_path)


## Replaces this level with the one at [param path] (taking this one down
## first and fading across, with [member intro]).
func go_to(path: String) -> void:
	if intro:
		leave(func() -> void: Game.open_level(path))
	else:
		_replace_with(path)


## Leaves for the menu's [param screen] ("main" or "levels", showing this
## level's world).
func go_home(screen: StringName = &"main") -> void:
	get_tree().paused = false
	leave(func() -> void: Game.open_menu(screen, LevelCatalog.world_of(level_path)))


## The back button (see [method Hud.go_back]).
func go_back() -> void:
	if hud:
		hud.go_back()


## Whether the build-up or the take-down is running.
func is_assembling() -> bool:
	return _assembly != null and _assembly.is_playing()


## Takes the diorama down (with [member intro]; at once otherwise), then
## calls [param then]. Input stops; the game in progress is kept.
func leave(then: Callable) -> void:
	if _leaving:
		return
	_leaving = true
	_busy += 1
	_clear_hint()
	keep_progress()
	if courier.is_moving():
		courier.stop()
	if hud:
		hud.fade_away()
	if intro:
		AudioManager.play(&"whoosh", -4.0)
		_assembly.play_out()
		await _assembly.finished
	then.call()


func _replace_with(path: String) -> void:
	var next: Level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	next.level_path = path
	next.idle_orbit_speed = idle_orbit_speed
	next.show_hud = show_hud
	next.intro = intro
	next.interactive = interactive
	var parent: Node = get_parent()
	var was_current: bool = get_tree().current_scene == self
	parent.remove_child(self)
	queue_free()
	parent.add_child(next)
	if was_current:
		get_tree().current_scene = next


## Saves the game in progress (or forgets it once finished or untouched).
func keep_progress() -> void:
	if state == null or not interactive:
		return
	if state.completed or state.moves == 0:
		Progress.drop_in_progress(_id())
	else:
		Progress.keep_in_progress(_id(), data.fingerprint, _history, state.snapshot())


func _id() -> String:
	return Progress.level_id(level_path)


## A go at the level starts (for the statistics): it was opened, [param
## resumed] when a game in progress was picked up, or played again after a
## finish ([param replay]).
func _begin_go(resumed: bool, replay: bool) -> void:
	_counting = true
	_seconds = 0.0
	_hints = 0
	_undos = 0
	_restarts = 0
	set_process(true)
	Analytics.level_started(level_path, resumed, replay)


## The go at the level ends: finished with [param stars], or left.
func _end_go(finished: bool, stars: int) -> void:
	if not _counting:
		return
	_counting = false
	set_process(false)
	Analytics.level_ended(level_path, {"success": finished, "moves": state.moves, "stars": stars,
		"seconds": roundi(_seconds), "hints": _hints, "undos": _undos, "restarts": _restarts})


func _on_tapped(screen_position: Vector2) -> void:
	if _busy > 0 or not interactive:
		return
	if not courier.is_moving() and taps_courier(screen_position):
		Haptics.tap()
		AudioManager.play(EMOTE_SOUNDS[courier.emote(camera.global_position)])
		return
	if state.completed:
		return
	var hit: Dictionary = pick(screen_position)
	if hit.is_empty():
		return
	Haptics.tap()
	var block: Vector3i = hit["cell"]
	for mechanism: Mechanism in data.mechanisms:
		if mechanism.kind == Mechanism.Kind.ROTATOR and mechanism.handle == block:
			_turn(mechanism.id)
			return
	var target: Vector3i = pathfinder.target_for_block(block)
	# A slide can't be steered: plan from where it ends.
	var lead: Array[Vector3i] = _slide_rest()
	var path: Array[Vector3i] = pathfinder.find_path(lead[-1] if not lead.is_empty() else courier.path_origin(), target)
	if path.is_empty():
		var normal: Vector3i = hit["normal"]
		var center: Vector3 = Vector3(block) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.5
		if grid.get_block(block) == BlockMesher.WATER and normal == Vector3i.UP:
			center.y -= 1.0 - BlockMesher.WATER_LEVEL
		TapRipple.spawn(self, center, Vector3(normal), false)
		courier.puzzled()
		AudioManager.play(&"error")
		return
	_clear_hint()
	# A new walk is one undo step; re-routing mid-walk belongs to the same one.
	if not courier.is_moving():
		_record()
	TapRipple.spawn(self, pathfinder.floor_position(target), Vector3.UP)
	AudioManager.play(&"tap")
	path.remove_at(0)
	courier.walk(lead + path)


func _on_double_tapped(screen_position: Vector2) -> void:
	if pick(screen_position).is_empty():
		camera.reset_view()


## Turns a rotator a quarter (one move), once the courier has stopped (at
## the end of a slide it is on).
func _turn(id: String) -> void:
	_clear_hint()
	if courier.is_moving():
		courier.walk(_slide_rest())
		_busy += 1
		await courier.arrived
		_busy -= 1
	_record()
	var events: Array[Dictionary] = state.rotate(id)
	if events.is_empty():
		_history.pop_back()
		var handle: Vector3i = (state.mechanisms[id] as Mechanism).handle
		TapRipple.spawn(self, Vector3(handle) + Vector3(0.5, 0.75, 0.5), Vector3.UP, false)
		courier.puzzled()
		AudioManager.play(&"error")
		_continue_ride()
		return
	moves_changed.emit(state.moves)
	await _play(events)


func _on_courier_step(cell: Vector3i) -> void:
	var heading: Vector3i = Pathfinder.heading(_last_cell, cell)
	var ride: bool = pathfinder.is_ride_step(_last_cell, cell, _glide)
	if pathfinder.is_ice(cell) and _glide != Vector3i.ZERO:
		AudioManager.play(&"glide")
	else:
		AudioManager.play(&"step")
	if grid.get_block(cell - Vector3i.UP) == Grid.BOARDS:
		AudioManager.play(&"creak")
	if pathfinder.is_spring(cell):
		var throws: bool = pathfinder.bounce(cell, heading) != cell
		_springs.press(cell - Vector3i.UP, throws)
		AudioManager.play(&"bounce", 0.0 if throws else -8.0)
	_glide = heading if pathfinder.is_ice(cell) or pathfinder.is_spring(cell) else Vector3i.ZERO
	_last_cell = cell
	var events: Array[Dictionary] = state.enter(cell, ride)
	# Moving parts change the ground; let the player re-plan from here.
	if events.any(func(event: Dictionary) -> bool: return event["event"] == LevelState.Event.MECHANISM):
		courier.stop()
	moves_changed.emit(state.moves)
	_play(events)


func _on_courier_arrived(_cell: Vector3i) -> void:
	_glide = Vector3i.ZERO
	_continue_ride()


## The cells the courier still has to slide or bounce through after the one
## it is stepping into (empty unless ice or a spring carries it on from there).
func _slide_rest() -> Array[Vector3i]:
	if not courier.is_moving():
		return []
	var origin: Vector3i = courier.path_origin()
	return pathfinder.glide(origin, Pathfinder.heading(courier.cell, origin)).slice(1)


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
				AudioManager.play(&"pickup")
				var package: Package = _packages[event["cell"]]
				_packages.erase(event["cell"])
				_carried.append(package)
				courier.flap_door()
				package.fly_into(courier.door_anchor)
				load_changed = true
			LevelState.Event.DROP:
				AudioManager.play(&"drop")
				_drop(event["color"], event["cell"])
				load_changed = true
			LevelState.Event.EXIT_OPENED:
				_exit.set_open(true)
			LevelState.Event.COMPLETED:
				courier.stop()
				courier.celebrate()
				_celebrate()
				var stars: int = data.stars_for(state.moves)
				finished_best = Progress.record(_id(), state.moves, stars)
				_end_go(true, stars)
				Ads.level_finished(level_path, stars > 0 and not _restarted)
				Reminders.level_finished()
				level_completed.emit(state.moves, stars)
			LevelState.Event.MECHANISM:
				var mechanism: Mechanism = state.mechanisms[event["id"]]
				_mechanism_sound(mechanism)
				if mechanism.moves_blocks():
					movers.append({"id": event["id"], "from": event["from"], "to": event["to"], "riders": []})
				else:
					longest = maxf(longest, (_mechanism_nodes[event["id"]] as MechanismNode).show_value(event["to"]))
			LevelState.Event.CARRIED:
				_mover(movers, event["id"])["riders"].append({"node": courier, "to": event["to"]})
			LevelState.Event.FELL:
				AudioManager.play(&"fall")
				_boards.fall(event["cell"])
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
	if not movers.is_empty():
		AudioManager.play(&"snap")
		Haptics.snap()
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
		_glide = Vector3i.ZERO
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
	_delivered[pad_cell] = package
	var pad: Pad = _pads[pad_cell]
	courier.flap_door()
	package.drop_onto(courier.door_anchor(), pad.global_position + Pad.PARCEL_SPOT, Pad.PARCEL_SIZE)
	get_tree().create_timer(Package.DROP_TIME).timeout.connect(_light_pad.bind(pad_cell))


## Lights a pad as its parcel lands, unless undo took the parcel back.
func _light_pad(pad_cell: Vector3i) -> void:
	var pad: Pad = _pads[pad_cell]
	if state.filled.has(pad_cell) and not pad.filled:
		pad.set_filled(true)
		AudioManager.play(&"pad_complete")


## Starts dragging a slider when a drag begins on one (see OrbitCamera.grab_filter).
func _try_grab(screen_position: Vector2) -> bool:
	if state.completed or _busy > 0 or courier.is_moving() or not interactive:
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
	_clear_hint()
	var riders: Array[Node3D] = []
	if mechanism.cells_at(state.values[id]).has(state.courier - Vector3i.UP):
		riders.append(courier)
	for cell: Vector3i in _packages:
		if mechanism.cells_at(state.values[id]).has(cell - Vector3i.UP):
			riders.append(_packages[cell])
	for rider: Node3D in riders:
		rider.reparent(node)
	_busy += 1
	Haptics.tap()
	AudioManager.play(&"slide", -6.0)
	# The slider follows the finger along its track, in perspective.
	var track: Vector3 = centre + Vector3.UP * 0.5
	_grab = {
		"id": id, "start": state.values[id], "range": state.slide_range(id), "track": track,
		"axis": Vector3(mechanism.axis), "press": _along_track(screen_position, track, Vector3(mechanism.axis)),
		"riders": riders,
	}
	return true


## How far along the line through [param origin] in direction [param axis]
## (a unit vector) the point under [param screen_position] lies.
func _along_track(screen_position: Vector2, origin: Vector3, axis: Vector3) -> float:
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var ray: Vector3 = camera.project_ray_normal(screen_position)
	var facing: float = axis.dot(ray)
	var offset: Vector3 = origin - from
	# Closest point between the track and the ray; _try_grab refuses tracks
	# seen nearly end-on, so the two are never parallel.
	return (facing * ray.dot(offset) - axis.dot(offset)) / maxf(1.0 - facing * facing, 0.0001)


func _on_grab_moved(screen_position: Vector2) -> void:
	if _grab.is_empty():
		return
	var cells: float = _along_track(screen_position, _grab["track"], _grab["axis"]) - (_grab["press"] as float)
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
	_record()
	var events: Array[Dictionary] = state.slide(grab["id"], target)
	if events.is_empty():
		_history.pop_back()
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
	_dragged = grab["id"]
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


## Nothing is moving or being dragged, so the state can be replaced (a walk
## may still be going; undo stops it). [param finished_ok] also allows a
## finished level.
func _is_settled(finished_ok: bool = false) -> bool:
	return _busy == 0 and _grab.is_empty() and (finished_ok or not state.completed)


func _record() -> void:
	_history.append(state.snapshot())
	if _history.size() > MAX_UNDO:
		_history.pop_front()


## Rebuilds everything shown from [member state] at once (after undo,
## restart or resuming).
func _sync() -> void:
	_clear_hint()
	_refresh_grid()
	courier.place(state.courier, courier.facing())
	courier.reset_pose()
	courier.set_carried(state.carried)
	_last_cell = state.courier
	_glide = Vector3i.ZERO
	_boards.set_fallen(state.fallen)
	_springs.settle()
	_rebuild_parcels()
	_exit.set_open(state.all_delivered(), false)
	for id: String in _mechanism_nodes:
		(_mechanism_nodes[id] as MechanismNode).show_value(state.values[id], false)
	moves_changed.emit(state.moves)


## Parcel nodes for [member state]: waiting on the floor, hidden in the
## mailbox, or resting on their pads.
func _rebuild_parcels() -> void:
	for package: Package in _packages.values() + _carried + _delivered.values():
		package.queue_free()
	_packages.clear()
	_carried.clear()
	_delivered.clear()
	for cell: Vector3i in state.waiting:
		var package := Package.create(state.waiting[cell])
		_place(package, cell)
		_packages[cell] = package
	for color: StringName in state.carried:
		var package := Package.create(color)
		_place(package, state.courier)
		package.hide()
		_carried.append(package)
	for cell: Vector3i in _pads:
		var pad: Pad = _pads[cell]
		pad.set_filled(state.filled.has(cell), false)
		if state.filled.has(cell):
			var package := Package.create(pad.color)
			add_child(package)
			package.rest_at(pad.position + Pad.PARCEL_SPOT, Pad.PARCEL_SIZE)
			_delivered[cell] = package


## The rest of the shortest plan from the current state, reusing the last
## one while the player follows it.
func _plan_from_here() -> Array[Dictionary]:
	var here: Array = [Solver.key_of(state), state.moves]
	var rest: Array[Dictionary] = []
	if _plan_from == here:
		rest.assign(_plan)
		return rest
	for i in _plan.size():
		if _plan[i]["key"] == here[0] and _plan[i]["moves"] == here[1]:
			rest.assign(_plan.slice(i + 1))
			return rest
	_plan = _solver.solve(state.snapshot())
	_plan_from = here
	rest.assign(_plan)
	return rest


## The cells a single tap walks through to follow [param plan] (which starts
## with steps) as far as possible: up to its first event, and only as far as
## the path a tap would take really does what the plan does.
func _hint_route(plan: Array[Dictionary]) -> Array[Vector3i]:
	var last: int = 0
	while last + 1 < plan.size() and plan[last + 1]["action"] == Solver.Action.STEP and not plan[last]["events"]:
		last += 1
	for stop in range(last, -1, -1):
		var path: Array[Vector3i] = pathfinder.find_path(state.courier, plan[stop]["cell"])
		if path.size() < 2:
			continue
		var trial := LevelState.new(data)
		trial.restore(state.snapshot())
		var on_the_way: bool = false
		for i in range(1, path.size()):
			var events: Array[Dictionary] = trial.enter(path[i], pathfinder.is_ride(path, i))
			# Boards dropping behind is no reason to stop.
			if events.any(Solver._not_fall) and i < path.size() - 1:
				on_the_way = true
				break
		if on_the_way:
			continue
		for cell: Vector3i in pathfinder.ride_from(path[-1]):
			trial.enter(cell, true)
		var key: String = Solver.key_of(trial)
		for k in range(stop, last + 1):
			if plan[k]["key"] == key and plan[k]["moves"] == trial.moves:
				return path
	var first: Array[Vector3i] = [state.courier, plan[0]["cell"]]
	return first


func _clear_hint() -> void:
	_hinted = {}
	if _hint:
		_hint.dismiss()
		_hint = null


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
	node.build_delays = _delays
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
	_assembly.add_mesh(instance)


## Every cell something stands in, for the build-up order: blocks,
## mechanisms, props, pads, parcels and the exit.
func _build_order() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	cells.assign(data.cells.keys())
	for mechanism: Mechanism in data.mechanisms:
		cells.append_array(mechanism.cells)
		if mechanism.kind == Mechanism.Kind.ROTATOR:
			cells.append(mechanism.handle)
	for prop: Dictionary in data.props:
		cells.append(prop["cell"])
	for cell: Vector3i in state.pads:
		cells.append(cell)
	for cell: Vector3i in state.waiting:
		cells.append(cell)
	cells.append(data.exit)
	return cells


## Hands the parts that are not anchored meshes to the build-up: whole
## nodes popping in where they stand, the courier last.
func _prepare_assembly() -> void:
	var latest: float = 0.0
	for delay: float in _delays.values():
		latest = maxf(latest, delay)
	_assembly.cover(latest)
	for id: String in _mechanism_nodes:
		var node: MechanismNode = _mechanism_nodes[id]
		var meshes: Array[GeometryInstance3D] = node.build_meshes()
		for mesh: GeometryInstance3D in meshes:
			_assembly.add_mesh(mesh)
		if meshes.is_empty():
			_assembly.add_node(node, _delays.get(node.mechanism.cells[0], 0.0))
		if node.mechanism.kind == Mechanism.Kind.ROTATOR:
			_assembly.add_node(get_node("Crank_%s" % id), _delays.get(node.mechanism.handle, 0.0))
	var boards: Dictionary = _boards.standing()
	for cell: Vector3i in boards:
		_assembly.add_node(boards[cell], _delays.get(cell, 0.0))
	var springs: Dictionary = _springs.all()
	for cell: Vector3i in springs:
		_assembly.add_node(springs[cell], _delays.get(cell, 0.0))
	for cell: Vector3i in _pads:
		_assembly.add_node(_pads[cell], _delays.get(cell, 0.0))
	for cell: Vector3i in _packages:
		_assembly.add_node(_packages[cell], _delays.get(cell, 0.0) + 0.05)
	for cell: Vector3i in _delivered:
		_assembly.add_node(_delivered[cell], _delays.get(cell, 0.0) + 0.05)
	_assembly.add_node(_exit, _delays.get(data.exit, 0.0))
	_assembly.add_node(courier, latest + 0.12)


func _build_up() -> void:
	_busy += 1
	if intro_delay > 0.0:
		_assembly.hold()
		await get_tree().create_timer(intro_delay, false).timeout
	AudioManager.play(&"whoosh")
	_assembly.play_in()
	await _assembly.finished
	_busy -= 1
	assembled.emit()


func _mechanism_sound(mechanism: Mechanism) -> void:
	if mechanism.id == _dragged:
		_dragged = ""
		return
	match mechanism.kind:
		Mechanism.Kind.SLIDER, Mechanism.Kind.ELEVATOR, Mechanism.Kind.GATE:
			AudioManager.play(&"slide")
		Mechanism.Kind.ROTATOR, Mechanism.Kind.CONVEYOR:
			AudioManager.play(&"rotate")
		Mechanism.Kind.BUTTON:
			AudioManager.play(&"snap", -4.0)
			Haptics.snap()


## The finish: the jingle (with the music dipped under it) and a shower of
## confetti over the courier.
func _celebrate() -> void:
	AudioManager.play(&"level_complete")
	AudioManager.duck()
	Haptics.snap()
	var confetti: CPUParticles3D = Effects.confetti()
	confetti.position = courier.position + Vector3(0.0, 0.9, 0.0)
	add_child(confetti)
	confetti.restart()
	get_tree().create_timer(confetti.lifetime + 0.5).timeout.connect(confetti.queue_free)


func _on_setting_changed(key: StringName) -> void:
	if key == &"tilt_shift" and camera:
		_stage.tilt_shift_enabled = Settings.tilt_shift
		_stage.fit_to_bounds(_bounds, camera.get_distance())


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
