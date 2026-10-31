class_name Mechanism
extends RefCounted
## One moving part of a level as defined in its JSON, with the geometry of
## each of its states. The state itself is a single int kept in LevelState:
##
##   slider    offset along its axis in cells, min..max
##   elevator  0 at the bottom stop, 1 at the top stop
##   rotator   quarter turns about +Y (counter-clockwise seen from above), 0..3
##   conveyor  1 running, 0 stopped
##   button    1 pressed (on), 0 off
##   gate      1 open, 0 closed (follows its buttons)

enum Kind { SLIDER, ELEVATOR, ROTATOR, CONVEYOR, BUTTON, GATE }

const KINDS: Dictionary = {
	"slider": Kind.SLIDER, "elevator": Kind.ELEVATOR, "rotator": Kind.ROTATOR,
	"conveyor": Kind.CONVEYOR, "button": Kind.BUTTON, "gate": Kind.GATE,
}

var id: String = ""
var kind: Kind = Kind.SLIDER
## Block cells in state 0 (slider, elevator, rotator, conveyor), the cells
## the bars block (gate), or the plate's standing cell (button).
var cells: Array[Vector3i] = []
## Slider axis or conveyor direction.
var axis := Vector3i.ZERO
var min_value: int = 0
var max_value: int = 0
## Elevator height between its stops.
var travel: int = 0
## Rotator centre cell, and the cell of the crank that turns it.
var pivot := Vector3i.ZERO
var handle := Vector3i.ZERO
## Button targets, or a gate's buttons.
var links: Array[String] = []
var initial: int = 0


## Whether this mechanism is made of blocks the courier can stand on.
func has_blocks() -> bool:
	return kind in [Kind.SLIDER, Kind.ELEVATOR, Kind.ROTATOR, Kind.CONVEYOR]


## Whether its blocks move (and carry whatever stands on them).
func moves_blocks() -> bool:
	return kind in [Kind.SLIDER, Kind.ELEVATOR, Kind.ROTATOR]


## Block cells in state [param value].
func cells_at(value: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector3i in cells:
		result.append(carry(cell, 0, value) if moves_blocks() else cell)
	return result


## Where a cell riding the mechanism ends up when it goes from state
## [param from] to state [param to].
func carry(cell: Vector3i, from: int, to: int) -> Vector3i:
	match kind:
		Kind.SLIDER:
			return cell + axis * (to - from)
		Kind.ELEVATOR:
			return cell + Vector3i.UP * travel * (to - from)
		Kind.ROTATOR:
			return turn(cell - pivot, to - from) + pivot
	return cell


## Turns a horizontal offset by [param quarters] quarter turns about +Y.
static func turn(offset: Vector3i, quarters: int) -> Vector3i:
	for i in posmod(quarters, 4):
		offset = Vector3i(offset.z, offset.y, -offset.x)
	return offset


## Transform taking the state-0 geometry to [param pose], a state that may be
## fractional while a slider is dragged or anything is animating.
func transform_for(pose: float) -> Transform3D:
	match kind:
		Kind.SLIDER:
			return Transform3D(Basis.IDENTITY, Vector3(axis) * pose)
		Kind.ELEVATOR:
			return Transform3D(Basis.IDENTITY, Vector3.UP * travel * pose)
		Kind.ROTATOR:
			var centre: Vector3 = Vector3(pivot) + Vector3(0.5, 0.0, 0.5)
			var spin := Basis(Vector3.UP, pose * PI * 0.5)
			return Transform3D(spin, centre - spin * centre)
	return Transform3D.IDENTITY


## Translations, relative to state [param from], that a slider or elevator
## passes through cell by cell on its way to [param to], ending with the
## destination. Empty for rotators, which only check where they land.
func steps(from: int, to: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if kind == Kind.ROTATOR:
		return result
	var total: Vector3i = carry(Vector3i.ZERO, from, to)
	var length: int = absi(total.x) + absi(total.y) + absi(total.z)
	for i in range(1, length + 1):
		result.append(total / length * i)
	return result
