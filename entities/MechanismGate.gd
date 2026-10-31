class_name MechanismGate
extends MechanismNode
## Bars standing in the gate's cells. When the gate opens they sink into the
## floor; when it closes they rise again.

const SUNK: float = -0.95

var _bars: MeshInstance3D
var _tween: Tween


func _ready() -> void:
	_bars = MeshInstance3D.new()
	_bars.name = "Bars"
	_bars.mesh = PropFactory.gate_bars(mechanism.cells, build_delays)
	add_child(_bars)
	show_value(value, false)


func build_meshes() -> Array[GeometryInstance3D]:
	return [_bars]


func show_value(new_value: int, animate: bool = true) -> float:
	value = new_value
	var height: float = SUNK if new_value == 1 else 0.0
	if _tween:
		_tween.kill()
	if not animate:
		_bars.position.y = height
		_bars.visible = new_value == 0
		return 0.0
	_bars.visible = true
	_tween = create_tween()
	_tween.tween_property(_bars, "position:y", height, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if new_value == 1:
		_tween.tween_callback(func() -> void: _bars.visible = false)
	return 0.5
