class_name MechanismNode
extends Node3D
## The visible side of a mechanism: shows a state (see Mechanism), animated or
## at once. Level drives it from LevelState events and owns everything else
## (riders, the grid, input).

var mechanism: Mechanism
## The state being shown (or animated towards).
var value: int = 0
## When each cell starts building up (see Assembly); set before adding.
var build_delays: Dictionary = {}


func _init(source: Mechanism) -> void:
	mechanism = source
	name = "Mechanism_%s" % source.id
	value = source.initial


## Meshes that build up through their anchors (see Assembly); other
## mechanisms pop in as a whole.
func build_meshes() -> Array[GeometryInstance3D]:
	return []


## Shows state [param new_value]. Returns how long the animation lasts
## (0 when [param animate] is false).
func show_value(new_value: int, _animate: bool = true) -> float:
	value = new_value
	return 0.0
