extends Node3D
## Step 1 test scene: a hardcoded 5x5 floating diorama under the shared stage
## lighting. Blocks are plain boxes here; the procedural BlockMesher (bevels,
## culling, baked AO) replaces them in step 2.
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
	var root := Node3D.new()
	root.name = "Blocks"
	add_child(root)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var materials: Dictionary = {}
	for cell: Vector3i in cells:
		var block_type: StringName = cells[cell]
		if not materials.has(block_type):
			materials[block_type] = _make_material(block_type)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = materials[block_type]
		mi.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		root.add_child(mi)


func _make_material(block_type: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	mat.metallic_specular = 0.2
	if block_type == &"accent":
		mat.albedo_color = Palette.ACCENT
		mat.emission_enabled = true
		mat.emission = Palette.ACCENT
		mat.emission_energy_multiplier = 0.25
	else:
		mat.albedo_color = Palette.block_color(block_type)
	return mat


func _compute_bounds(cells: Dictionary) -> AABB:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for cell: Vector3i in cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))


func _fit_camera() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# FOV applies to the shorter screen axis so the fit works in any orientation.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if vp_size.x < vp_size.y else Camera3D.KEEP_HEIGHT
	var radius: float = _bounds.size.length() * 0.5
	_distance = radius / (FILL_FRACTION * tan(deg_to_rad(CAMERA_FOV) * 0.5))
	_place_camera()
	_stage.fit_to_bounds(_bounds, _distance)


func _place_camera() -> void:
	var target: Vector3 = _bounds.get_center()
	var yaw: float = deg_to_rad(_yaw_deg)
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _distance
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)
