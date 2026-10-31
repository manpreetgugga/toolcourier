extends Node3D
## Test scene: a hardcoded 5x5 floating diorama under the shared stage
## lighting, meshed by BlockMesher (bevels, culling, baked AO).
##
## Cell convention used everywhere in the project: cell (x, y, z) occupies
## [x, x+1] x [y, y+1] x [z, z+1], so its centre is cell + (0.5, 0.5, 0.5).

const CAMERA_FOV: float = 30.0
const CAMERA_YAW_DEG: float = 40.0
const CAMERA_PITCH_DEG: float = 32.0
## Fraction of the shorter screen axis the diorama should fill.
const FILL_FRACTION: float = 0.75

## Degrees per second; 0 keeps the camera still (deterministic screenshots).
@export var auto_rotate_speed_deg: float = 0.0

var _stage: StageLighting
var _camera: Camera3D
var _bounds: AABB
var _yaw_deg: float = CAMERA_YAW_DEG
var _distance: float = 20.0


func _ready() -> void:
	_stage = StageLighting.new()
	_stage.name = "Stage"
	add_child(_stage)

	var cells: Dictionary = _test_layout()
	_bounds = _compute_bounds(cells)
	_build_blocks(cells)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = CAMERA_FOV
	_camera.attributes = _stage.camera_attributes
	add_child(_camera)
	_camera.make_current()

	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()


func _process(delta: float) -> void:
	if auto_rotate_speed_deg != 0.0:
		_yaw_deg = fposmod(_yaw_deg + auto_rotate_speed_deg * delta, 360.0)
		_place_camera()


## Hardcoded test layout: Vector3i -> block type.
func _test_layout() -> Dictionary:
	var cells: Dictionary = {}
	# Floating rock underside, tapering to a point.
	cells[Vector3i(2, -2, 2)] = &"dark_stone"
	for x in range(1, 4):
		for z in range(1, 4):
			cells[Vector3i(x, -1, z)] = &"dark_stone"
	cells[Vector3i(3, -1, 0)] = &"dark_stone"
	cells[Vector3i(4, -1, 0)] = &"dark_stone"
	cells[Vector3i(4, -1, 1)] = &"dark_stone"
	# Ground layer.
	for x in 5:
		for z in 5:
			cells[Vector3i(x, 0, z)] = &"grass"
	for c: Vector3i in [Vector3i(3, 0, 0), Vector3i(4, 0, 0), Vector3i(4, 0, 1)]:
		cells[c] = &"water"
	for c: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		cells[c] = &"sand"
	# Stone tower in the back corner with a terracotta cap.
	for c: Vector3i in [Vector3i(0, 1, 4), Vector3i(1, 1, 4), Vector3i(0, 1, 3), Vector3i(0, 2, 4), Vector3i(0, 3, 4)]:
		cells[c] = &"stone"
	cells[Vector3i(0, 4, 4)] = &"brick"
	# Wooden walkway hanging off the tower.
	cells[Vector3i(2, 1, 4)] = &"wood"
	cells[Vector3i(3, 1, 4)] = &"wood"
	# Little brick house.
	for c: Vector3i in [Vector3i(4, 1, 2), Vector3i(4, 1, 3), Vector3i(3, 1, 2), Vector3i(4, 2, 3)]:
		cells[c] = &"brick"
	# One interactive (accent) block.
	cells[Vector3i(2, 1, 1)] = &"accent"
	return cells


func _build_blocks(cells: Dictionary) -> void:
	var blocks := MeshInstance3D.new()
	blocks.name = "Blocks"
	blocks.mesh = BlockMesher.build(cells)
	add_child(blocks)


func _compute_bounds(cells: Dictionary) -> AABB:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for cell: Vector3i in cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))


func _fit_camera() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vp_size.x < vp_size.y
	# FOV applies to the shorter screen axis so the fit works in any orientation.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	var aspect: float = maxf(vp_size.x, vp_size.y) / minf(vp_size.x, vp_size.y)
	var tan_short: float = tan(deg_to_rad(CAMERA_FOV) * 0.5) * FILL_FRACTION
	var tan_x: float = tan_short if portrait else tan_short * aspect
	var tan_y: float = tan_short * aspect if portrait else tan_short
	# Back off until every bounds corner fits inside the fill frame.
	var view: Basis = _view_basis()
	var center: Vector3 = _bounds.get_center()
	_distance = 0.0
	for i in 8:
		var offset: Vector3 = _bounds.get_endpoint(i) - center
		var needed: float = maxf(absf(offset.dot(view.x)) / tan_x, absf(offset.dot(view.y)) / tan_y)
		_distance = maxf(_distance, needed + offset.dot(view.z))
	_place_camera()
	_stage.fit_to_bounds(_bounds, _distance)


## Camera basis for the current yaw/pitch; z points from the target to the camera.
func _view_basis() -> Basis:
	var yaw: float = deg_to_rad(_yaw_deg)
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var right: Vector3 = Vector3.UP.cross(back).normalized()
	return Basis(right, back.cross(right), back)


func _place_camera() -> void:
	var target: Vector3 = _bounds.get_center()
	_camera.position = target + _view_basis().z * _distance
	_camera.look_at(target, Vector3.UP)
