class_name DryBoards
extends Node3D
## The level's dry boards (autumn): a plank deck on beams for each dry board
## block, crossed the way its neighbours lead. Once the courier steps off
## one it shakes, tips and drops away in a puff of dust. Level drives it
## from LevelState's FELL events and shows the fallen set after undo.

const SHAKE_TIME: float = 0.2
const FALL_TIME: float = 0.65
const DROP: float = 3.0
## How far below its block cell a board's underside hangs.
const UNDERSIDE: float = 0.75

## Block cell -> MeshInstance3D.
var _boards: Dictionary = {}
## Block cell -> its dust burst.
var _dust: Dictionary = {}
## Block cell -> the fall in progress.
var _falls: Dictionary = {}
## Block cell -> how far it drops: DROP, or onto the first block below.
var _drops: Dictionary = {}


## Boards for every dry board block in [param cells] (LevelData cells).
func _init(cells: Dictionary) -> void:
	name = "DryBoards"
	for cell: Vector3i in cells:
		if cells[cell] != Grid.BOARDS:
			continue
		var board := MeshInstance3D.new()
		board.name = "Board_%d_%d_%d" % [cell.x, cell.y, cell.z]
		board.mesh = PropFactory.board(_crossing(cells, cell), cell)
		add_child(board)
		_boards[cell] = board
		var dust: CPUParticles3D = Effects.dust(Vector3(1.0, 0.1, 1.0))
		dust.position = _home(cell) + Vector3(0.0, 0.85, 0.0)
		add_child(dust)
		_dust[cell] = dust
		_drops[cell] = DROP
		for depth in range(1, ceili(DROP) + 1):
			if cells.has(cell - Vector3i(0, depth, 0)):
				_drops[cell] = minf(DROP, depth - 1 + UNDERSIDE)
				break
	set_fallen({})


## Drops the board at [param cell] with a shake and a puff of dust.
func fall(cell: Vector3i) -> void:
	var board: MeshInstance3D = _boards[cell]
	_stop(cell)
	var home: Vector3 = _home(cell)
	var tip: float = 0.5 if (cell.x + cell.z) % 2 == 0 else -0.5
	var tween: Tween = create_tween()
	for i in 4:
		var shake := Vector3(0.035 if i % 2 == 0 else -0.035, -0.015 * i, 0.0)
		tween.tween_property(board, "position", home + shake, SHAKE_TIME / 4.0)
	tween.tween_callback((_dust[cell] as CPUParticles3D).restart)
	tween.set_parallel()
	tween.tween_property(board, "position:y", home.y - (_drops[cell] as float), FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(board, "rotation:z", tip, FALL_TIME).set_trans(Tween.TRANS_SINE)
	tween.tween_property(board, "scale", Vector3.ONE * 0.6, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(board.hide)
	_falls[cell] = tween


## Shows boards in [param fallen] (block cell -> true) as gone and the rest
## in place, at once.
func set_fallen(fallen: Dictionary) -> void:
	for cell: Vector3i in _boards:
		_stop(cell)
		var board: MeshInstance3D = _boards[cell]
		board.position = _home(cell)
		board.rotation = Vector3.ZERO
		board.scale = Vector3.ONE
		board.visible = not fallen.has(cell)


func _stop(cell: Vector3i) -> void:
	if _falls.has(cell):
		(_falls[cell] as Tween).kill()
		_falls.erase(cell)


static func _home(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.0, 0.5)


## The way across the board at [param cell]: along X unless more of its
## neighbours at its level lie along Z.
static func _crossing(cells: Dictionary, cell: Vector3i) -> Vector3i:
	var along_x: int = int(cells.has(cell + Vector3i(1, 0, 0))) + int(cells.has(cell + Vector3i(-1, 0, 0)))
	var along_z: int = int(cells.has(cell + Vector3i(0, 0, 1))) + int(cells.has(cell + Vector3i(0, 0, -1)))
	return Vector3i(0, 0, 1) if along_z > along_x else Vector3i(1, 0, 0)
