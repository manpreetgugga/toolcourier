class_name MechanismNode
extends Node3D
## The visible side of a mechanism: shows a state (see Mechanism), animated or
## at once. Level drives it from LevelState events and owns everything else
## (riders, the grid, input).

var mechanism: Mechanism
## The state being shown (or animated towards).
var value: int = 0


func _init(source: Mechanism) -> void:
	mechanism = source
	name = "Mechanism_%s" % source.id
	value = source.initial


## Shows state [param new_value]. Returns how long the animation lasts
## (0 when [param animate] is false).
func show_value(new_value: int, _animate: bool = true) -> float:
	value = new_value
	return 0.0
