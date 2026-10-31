class_name MechanismBlocks
extends MechanismNode
## Accent blocks that slide, lift or turn (slider, elevator, rotator). The
## mesh is built in level coordinates at state 0 and this node's transform
## carries it to the current pose; moves ease out with a small overshoot and
## end in a puff of dust. Rotators also get a crank, a separate static node
## that spins while they turn.

const BASE_TIME: float = 0.3
## Extra time per cell (or quarter turn) travelled.
const TIME_PER_STEP: float = 0.12

## Current pose: a state, fractional while dragged or animating.
var pose: float = 0.0

var _blocks: MeshInstance3D
var _dust: CPUParticles3D
var _wheel: Node3D
var _tween: Tween


func _ready() -> void:
	var cells: Dictionary = {}
	var bounds := AABB(Vector3(mechanism.cells[0]), Vector3.ONE)
	for cell: Vector3i in mechanism.cells:
		cells[cell] = BlockMaterials.ACCENT
		bounds = bounds.merge(AABB(Vector3(cell), Vector3.ONE))
	_blocks = MeshInstance3D.new()
	_blocks.name = "Blocks"
	_blocks.mesh = BlockMesher.build(cells, build_delays)
	add_child(_blocks)
	_dust = Effects.dust(Vector3(bounds.size.x + 0.2, 0.1, bounds.size.z + 0.2))
	_dust.position = Vector3(bounds.get_center().x, bounds.position.y + 0.05, bounds.get_center().z)
	add_child(_dust)
	set_pose(value)


func build_meshes() -> Array[GeometryInstance3D]:
	return [_blocks]


## The blocks' mesh in state 0, in level coordinates (see
## [method Mechanism.transform_for]).
func blocks_mesh() -> Mesh:
	return _blocks.mesh


## A crank to tap for turning a rotator, standing in its handle cell. Add it
## to the level separately; it does not move with the blocks.
func make_crank() -> Node3D:
	var crank := Node3D.new()
	crank.name = "Crank_%s" % mechanism.id
	crank.position = Vector3(mechanism.handle) + Vector3(0.5, 0.0, 0.5)
	var dark: ShaderMaterial = ClayShapes.material(PropFactory.POST)
	var base := MeshInstance3D.new()
	base.mesh = ClayShapes.rounded_box(Vector3(0.34, 0.1, 0.34), 0.04)
	base.material_override = dark
	base.position.y = 0.05
	crank.add_child(base)
	var post := MeshInstance3D.new()
	post.mesh = ClayShapes.rounded_box(Vector3(0.1, 0.5, 0.1), 0.03)
	post.material_override = dark
	post.position.y = 0.33
	crank.add_child(post)
	_wheel = Node3D.new()
	_wheel.position.y = 0.55
	crank.add_child(_wheel)
	var wheel := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2
	disc.bottom_radius = 0.2
	disc.height = 0.07
	disc.radial_segments = 20
	disc.rings = 1
	wheel.mesh = disc
	wheel.material_override = ClayShapes.accent_material()
	_wheel.add_child(wheel)
	var knob := MeshInstance3D.new()
	knob.mesh = ClayShapes.rounded_box(Vector3(0.07, 0.16, 0.07), 0.03)
	knob.material_override = dark
	knob.position = Vector3(0.13, 0.1, 0.0)
	_wheel.add_child(knob)
	return crank


func show_value(new_value: int, animate: bool = true) -> float:
	value = new_value
	if _tween:
		_tween.kill()
	if not animate:
		set_pose(new_value)
		return 0.0
	var target: float = float(new_value)
	# Rotators always turn forwards, so 3 -> 0 goes on to 4.
	if mechanism.kind == Mechanism.Kind.ROTATOR and target < pose - 0.5:
		target += 4.0
	var distance: float = absf(target - pose)
	if mechanism.kind == Mechanism.Kind.ELEVATOR:
		distance *= mechanism.travel
	var duration: float = BASE_TIME + TIME_PER_STEP * distance
	_tween = create_tween()
	_tween.tween_method(set_pose, pose, target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_settle.bind(new_value))
	if _wheel:
		var spin: Tween = create_tween()
		spin.tween_property(_wheel, "rotation:y", _wheel.rotation.y + TAU, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return duration


func set_pose(new_pose: float) -> void:
	pose = new_pose
	transform = mechanism.transform_for(pose)


func _settle(final_value: int) -> void:
	set_pose(final_value)
	_dust.restart()
