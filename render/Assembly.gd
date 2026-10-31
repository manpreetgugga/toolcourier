class_name Assembly
extends Node
## The build-up a level opens with and the tear-down it closes with. Blocks,
## stairs and props pop up from below into place one after another, lowest
## layer first and each layer from the middle outwards; then the courier,
## parcels, pads and the exit pop in where they stand. Leaving plays the
## same thing backwards, a little faster.
##
## Meshes from BlockMesher and PropFactory carry their anchors in CUSTOM0
## and are driven through the build_time instance uniform (see
## shaders/build_up.gdshaderinc); whole nodes are scaled and lowered here.

signal finished

## Seconds between one part and the next...
const STAGGER: float = 0.015
## ...but the whole wave takes no longer than this, however big the level.
const MAX_SPREAD: float = 1.1
## As BUILD_POP and BUILD_DROP in shaders/build_up.gdshaderinc.
const POP: float = 0.42
const DROP: float = 1.4
## Leaving plays this much faster.
const OUT_SPEED: float = 1.7
## build_time that leaves every part in place.
const AT_REST: float = 1000.0

var _meshes: Array[GeometryInstance3D] = []
## {"node": Node3D, "delay": float, "position": Vector3, "scale": Vector3}
var _nodes: Array[Dictionary] = []
var _time: float = AT_REST
var _speed: float = 0.0
var _length: float = POP


## When each of [param cells] starts building up (seconds from the start):
## lowest layer first, each layer from its middle outwards, a little shuffled.
static func delays(cells: Array[Vector3i]) -> Dictionary:
	var unique: Dictionary = {}
	var centre := Vector2.ZERO
	for cell: Vector3i in cells:
		if not unique.has(cell):
			unique[cell] = true
			centre += Vector2(cell.x, cell.z)
	centre /= maxf(unique.size(), 1.0)
	var order: Array = unique.keys()
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _order(a, centre) < _order(b, centre))
	var stagger: float = minf(STAGGER, MAX_SPREAD / maxf(order.size(), 1.0))
	var result: Dictionary = {}
	for i in order.size():
		result[order[i]] = i * stagger
	return result


static func _order(cell: Vector3i, centre: Vector2) -> float:
	var shuffle: float = float(hash(cell) % 1000) / 1000.0
	return cell.y * 1000.0 + Vector2(cell.x, cell.z).distance_to(centre) + shuffle * 0.8


func _ready() -> void:
	# Godot turns processing on for any script with _process; it only runs
	# while a build-up or take-down plays.
	set_process(_speed != 0.0)


## Drives [param instance]'s build_time (its mesh must carry anchors).
func add_mesh(instance: GeometryInstance3D) -> void:
	_meshes.append(instance)
	_length = maxf(_length, POP)


## Pops [param node] in as a whole, [param delay] seconds into the build-up
## (only nodes that are showing).
func add_node(node: Node3D, delay: float) -> void:
	_nodes.append({"node": node, "delay": delay, "position": node.position, "scale": node.scale})
	_length = maxf(_length, delay + POP)


## Sets how long the wave of anchored meshes runs (their latest delay).
func cover(latest_delay: float) -> void:
	_length = maxf(_length, latest_delay + POP)


## Seconds the build-up takes.
func length() -> float:
	return _length


func is_playing() -> bool:
	return is_processing()


## Hides everything, ready to build up (see [method play_in]).
func hold() -> void:
	_snapshot()
	_time = 0.0
	_speed = 0.0
	set_process(false)
	_apply()


## Starts from nothing and builds everything up.
func play_in() -> void:
	_snapshot()
	_time = 0.0
	_speed = 1.0
	_apply()
	set_process(true)


## Takes everything down, last part first (from wherever the build-up has
## got to, if it is still running).
func play_out() -> void:
	if _speed < 0.0 and is_processing():
		return
	_snapshot()
	_time = minf(_time, _length)
	_speed = -OUT_SPEED
	_apply()
	set_process(true)


## Notes where the nodes stand, while they stand in place (nodes move
## during play: the courier walks, parcels are carried off).
func _snapshot() -> void:
	if _time < _length:
		return
	for entry: Dictionary in _nodes:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			entry["position"] = node.position
			entry["scale"] = node.scale


func _process(delta: float) -> void:
	_time = clampf(_time + delta * _speed, 0.0, _length)
	var done: bool = _time >= _length if _speed > 0.0 else _time <= 0.0
	if done and _speed > 0.0:
		_time = AT_REST
	_apply()
	if done:
		set_process(false)
		finished.emit()


func _apply() -> void:
	for instance: GeometryInstance3D in _meshes:
		if is_instance_valid(instance):
			instance.set_instance_shader_parameter(&"build_time", _time)
	for entry: Dictionary in _nodes:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue
		var t: float = clampf((_time - entry["delay"]) / POP, 0.0, 1.0)
		var u: float = t - 1.0
		var grow: float = 1.0 + 2.70158 * u * u * u + 1.70158 * u * u
		node.visible = t > 0.0
		node.scale = entry["scale"] * maxf(grow, 0.001)
		node.position = entry["position"] - Vector3(0.0, u * u * DROP, 0.0)
