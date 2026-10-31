class_name PropFactory
extends RefCounted
## Procedural clay decor: trees, bushes, lamp posts, flags, crates, fences
## and rocks, plus the level's stairs and the parcel and pad meshes. Parts
## are merged into one mesh with a surface per colour, so a level's decor
## costs a handful of draw calls.
##
## Props stand on the floor of their cell, turned by their rotation (degrees
## about +Y); fences run along the cell's -Z edge before rotation.

const TYPES: Array[StringName] = [
	&"tree_small", &"tree_tall", &"bush", &"lamp_post", &"flag", &"crate", &"fence", &"rock",
]

const TRUNK := Color("#8A5A3C")
const LEAVES := Color("#5FA35A")
const LEAVES_LIGHT := Color("#7DC266")
const POST := Color("#3A3550")
const LAMP := Color("#FFD9A0")
const BANNER := Color("#E07A5F")
const ROCK := Color("#B9B0A8")
const FENCE := Color("#D9A86C")
const CRATE := Color("#C98B52")
const CRATE_BAND := Color("#9C6A3E")
const TAPE := Color("#FFF1DC")

const BLOB_SHADER: Shader = preload("res://shaders/blob_shadow.gdshader")

static var _parcels: Dictionary = {}


## Collects parts by colour and bakes one surface per colour.
class _Batch:
	var _tools: Dictionary = {}
	var _materials: Dictionary = {}

	func add(mesh: Mesh, transform: Transform3D, color: Color, glow: float = 0.0) -> void:
		var key: String = "%s/%.2f" % [color.to_html(), glow]
		if not _tools.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tools[key] = tool
			_materials[key] = ClayShapes.material(color, glow)
		(_tools[key] as SurfaceTool).append_from(mesh, 0, transform)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _tools:
			(_tools[key] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[key])
		return mesh


## All of a level's props in one mesh (props from LevelData).
static func build_props(props: Array[Dictionary]) -> ArrayMesh:
	var batch := _Batch.new()
	for prop: Dictionary in props:
		var cell: Vector3i = prop["cell"]
		var base := Transform3D(Basis(Vector3.UP, deg_to_rad(prop["rotation"])), Vector3(cell) + Vector3(0.5, 0.0, 0.5))
		match prop["type"]:
			&"tree_small": _tree(batch, base, 3)
			&"tree_tall": _tree(batch, base, 4)
			&"bush": _bush(batch, base)
			&"lamp_post": _lamp_post(batch, base)
			&"flag": _flag(batch, base)
			&"crate": _crate(batch, base)
			&"fence": _fence(batch, base)
			&"rock": _rock(batch, base)
	return batch.commit()


## Every stairs block of [param grid] in one mesh, turned to climb along its
## facing ("stairs_wood" and "stairs_brick" take those colours).
static func build_stairs(grid: Grid) -> ArrayMesh:
	var batch := _Batch.new()
	for cell: Vector3i in grid.cells:
		var stairs_type: StringName = grid.cells[cell]
		if not Grid.is_stairs(stairs_type):
			continue
		var climb: Vector3i = grid.facing.get(cell, Vector3i(1, 0, 0))
		# The mesh climbs towards +X.
		var turn := Basis(Vector3.UP, atan2(-float(climb.z), float(climb.x)))
		var material: StringName = StringName(String(stairs_type).trim_prefix("stairs").trim_prefix("_"))
		var color: Color = Palette.block_color(material if material != &"" else &"stone")
		batch.add(ClayShapes.stairs(), Transform3D(turn, Vector3(cell) + Vector3(0.5, 0.0, 0.5)), color)
	return batch.commit()


## Bars for a gate's cells (level coordinates): five posts per cell with
## accent caps.
static func gate_bars(cells: Array[Vector3i]) -> ArrayMesh:
	var batch := _Batch.new()
	for cell: Vector3i in cells:
		var base := Transform3D(Basis.IDENTITY, Vector3(cell) + Vector3(0.5, 0.0, 0.5))
		for spot: Vector2 in [Vector2(-0.27, -0.27), Vector2(0.27, -0.27), Vector2.ZERO,
				Vector2(-0.27, 0.27), Vector2(0.27, 0.27)]:
			batch.add(_cylinder(0.055, 0.82), base * _at(spot.x, 0.41, spot.y), POST)
			batch.add(_sphere(0.075, 0.12), base * _at(spot.x, 0.84, spot.y), Palette.ACCENT)
	return batch.commit()


## A taped parcel of a package colour, resting on y = 0.
static func parcel(color: StringName) -> ArrayMesh:
	if not _parcels.has(color):
		var batch := _Batch.new()
		var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.14, 0.0))
		batch.add(ClayShapes.rounded_box(Vector3(0.34, 0.28, 0.34), 0.05), lift, Palette.PACKAGE[color])
		batch.add(ClayShapes.rounded_box(Vector3(0.355, 0.29, 0.07), 0.02), lift, TAPE)
		batch.add(ClayShapes.rounded_box(Vector3(0.07, 0.29, 0.355), 0.02), lift, TAPE)
		_parcels[color] = batch.commit()
	return _parcels[color]


## A soft round contact shadow, [param size] metres across, lying on y = 0.
static func blob_shadow(size: float) -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = BLOB_SHADER
	blob.material_override = material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.012
	return blob


static func _tree(batch: _Batch, base: Transform3D, tiers: int) -> void:
	var trunk_height: float = 0.3 if tiers <= 3 else 0.42
	batch.add(_cylinder(0.065, trunk_height), base * _at(0.0, trunk_height * 0.5, 0.0), TRUNK)
	var y: float = trunk_height + 0.1
	var radius: float = 0.34 if tiers <= 3 else 0.36
	for tier in tiers:
		var height: float = radius * 1.15
		var color: Color = LEAVES_LIGHT if tier == tiers - 1 else LEAVES
		batch.add(_cone(radius, height), base * _at(0.0, y + height * 0.3, 0.0), color)
		y += height * 0.55
		radius *= 0.76


static func _bush(batch: _Batch, base: Transform3D) -> void:
	for blob: Vector4 in [Vector4(0.0, 0.14, 0.0, 0.19), Vector4(0.15, 0.1, 0.07, 0.13),
			Vector4(-0.12, 0.1, -0.08, 0.12), Vector4(0.03, 0.25, -0.04, 0.11)]:
		var color: Color = LEAVES_LIGHT if blob.y > 0.2 else LEAVES
		batch.add(_sphere(blob.w, blob.w * 1.7), base * _at(blob.x, blob.y, blob.z), color)


static func _lamp_post(batch: _Batch, base: Transform3D) -> void:
	batch.add(ClayShapes.rounded_box(Vector3(0.16, 0.06, 0.16), 0.02), base * _at(0.0, 0.03, 0.0), POST)
	batch.add(_cylinder(0.03, 0.82), base * _at(0.0, 0.45, 0.0), POST)
	batch.add(_sphere(0.085, 0.17), base * _at(0.0, 0.9, 0.0), LAMP, 1.2)
	batch.add(_cone(0.11, 0.08), base * _at(0.0, 1.01, 0.0), POST)


static func _flag(batch: _Batch, base: Transform3D) -> void:
	batch.add(_cylinder(0.022, 0.92), base * _at(0.0, 0.46, 0.0), POST)
	batch.add(_sphere(0.035, 0.07), base * _at(0.0, 0.94, 0.0), POST)
	batch.add(ClayShapes.rounded_box(Vector3(0.3, 0.18, 0.02), 0.008), base * _at(0.16, 0.78, 0.0), BANNER)


static func _crate(batch: _Batch, base: Transform3D) -> void:
	batch.add(ClayShapes.rounded_box(Vector3(0.46, 0.4, 0.46), 0.04), base * _at(0.0, 0.2, 0.0), CRATE)
	for y: float in [0.08, 0.32]:
		batch.add(ClayShapes.rounded_box(Vector3(0.48, 0.055, 0.48), 0.02), base * _at(0.0, y, 0.0), CRATE_BAND)


static func _fence(batch: _Batch, base: Transform3D) -> void:
	for x: float in [-0.42, 0.0, 0.42]:
		batch.add(_cylinder(0.035, 0.38), base * _at(x, 0.19, -0.42), FENCE)
	for y: float in [0.14, 0.29]:
		batch.add(ClayShapes.rounded_box(Vector3(0.94, 0.045, 0.03), 0.012), base * _at(0.0, y, -0.42), FENCE)


static func _rock(batch: _Batch, base: Transform3D) -> void:
	var big := _at(0.0, 0.08, 0.0).scaled_local(Vector3(1.25, 1.0, 1.0))
	batch.add(_sphere(0.2, 0.26), base * big, ROCK)
	batch.add(_sphere(0.1, 0.13), base * _at(0.2, 0.04, 0.12), ROCK)


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _cone(radius: float, height: float) -> CylinderMesh:
	var cone := _cylinder(radius, height)
	cone.top_radius = 0.0
	return cone


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	cylinder.rings = 1
	return cylinder


static func _sphere(radius: float, height: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = 14
	sphere.rings = 7
	return sphere
