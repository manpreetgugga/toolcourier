class_name Springs
extends Node3D
## The level's springs (summer): a box with a coil and a round pad on top for
## each spring block. A step onto one squashes it and it wobbles back; when
## it throws the courier on, the pad goes right down with the courier first.
## Level drives it from the courier's steps.

## Seconds the pad takes to go down, and to wobble back to rest.
const SQUASH_TIME: float = 0.08
const SETTLE_TIME: float = 0.6
## How far the coil and pad squash (as a scale) under a step it throws on,
## so the pad sinks as far as the courier does (see Courier.BOUNCE_DIP), and
## under one it does not.
const SQUASH: float = 1.0 - Courier.BOUNCE_DIP / (1.0 - PropFactory.SPRING_FOOT)
const SAG: float = 0.82

## Block cell -> the whole spring (MeshInstance3D).
var _springs: Dictionary = {}
## Block cell -> its coil and pad, which squash.
var _tops: Dictionary = {}
## Block cell -> the squash in progress.
var _squashes: Dictionary = {}


## Springs for every spring block in [param cells] (LevelData cells).
func _init(cells: Dictionary) -> void:
	name = "Springs"
	for cell: Vector3i in cells:
		if cells[cell] != Grid.SPRING:
			continue
		var spring := MeshInstance3D.new()
		spring.name = "Spring_%d_%d_%d" % [cell.x, cell.y, cell.z]
		spring.mesh = PropFactory.spring_box()
		spring.position = Vector3(cell) + Vector3(0.5, 0.0, 0.5)
		add_child(spring)
		var top := MeshInstance3D.new()
		top.name = "Top"
		top.mesh = PropFactory.spring_top()
		top.position.y = PropFactory.SPRING_FOOT
		spring.add_child(top)
		_springs[cell] = spring
		_tops[cell] = top


## Every spring, by block cell.
func all() -> Dictionary:
	return _springs


## The courier steps onto the spring at block cell [param cell]: it squashes
## and wobbles back, all the way down first when it [param throws] the
## courier on.
func press(cell: Vector3i, throws: bool) -> void:
	var top: Node3D = _tops.get(cell)
	if top == null:
		return
	if _squashes.has(cell):
		(_squashes[cell] as Tween).kill()
	var tween: Tween = create_tween()
	tween.tween_property(top, "scale:y", SQUASH if throws else SAG, SQUASH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(top, "scale:y", 1.0, SETTLE_TIME).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_squashes[cell] = tween


## Puts every spring at rest at once (after undo or restart).
func settle() -> void:
	for tween: Tween in _squashes.values():
		tween.kill()
	_squashes.clear()
	for top: Node3D in _tops.values():
		top.scale = Vector3.ONE
