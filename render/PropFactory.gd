class_name PropFactory
extends RefCounted
## Procedural clay decor: trees, bushes, lamp posts, flags, crates, fences,
## rocks, pumpkins, leaf piles, snowmen, sunflowers and hay bales, Frost
## Peaks' igloos, ice crystals, sleds, ice lanterns, signposts, cable-car
## gondolas and bunting, plus the
## level's stairs, dry boards, springs and the parcel and pad meshes. Parts are merged into one mesh with
## a surface per colour, so a level's decor costs a handful of draw calls.
##
## Props stand on the floor of their cell, turned by their rotation (degrees
## about +Y); fences run along the cell's -Z edge before rotation. The season
## dresses them: spring trees and bushes blossom pink or white, autumn ones
## turn orange, red or gold, and in winter pines, bushes, lamps, crates and
## rocks wear snow.

const TYPES: Array[StringName] = [
	&"tree_small", &"tree_tall", &"bush", &"lamp_post", &"flag", &"crate", &"fence", &"rock",
	&"pumpkin", &"leaf_pile", &"snowman", &"sunflower", &"hay_bale",
	&"igloo", &"ice_crystal", &"sled", &"ice_lantern", &"signpost", &"gondola", &"bunting",
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
const AUTUMN_LEAVES: Array[Color] = [Color("#E07B39"), Color("#C94F3D"), Color("#E6AE45")]
const PINE := Color("#4F8A6C")
const BLOSSOMS: Array[Color] = [Color("#F4B3C6"), Color("#F8CFDC"), Color("#E994B0")]
const SNOW := Color("#F4F7FB")
const PUMPKIN := Color("#E8822F")
const STEM := Color("#6B7A3A")
const CARROT := Color("#EE8A3A")
const SCARF := Color("#D9534A")
const PLANK := Color("#B07B50")
const PLANK_DARK := Color("#9A6842")
const BEAM := Color("#6E4B33")
const SUNFLOWER := Color("#F6C343")
const SUNFLOWER_HEART := Color("#7A4E2D")
const SUNFLOWER_STEM := Color("#6E9E4A")
const HAY := Color("#E8C468")
const HAY_CORD := Color("#C99A45")
const THIN_ICE := Color("#A6E3EC")
const THIN_ICE_DEEP := Color("#7CC7DA")
const ICE_CRACK := Color("#E9FBFF")
const SNOW_SHADE := Color("#DCE1F0")
const DOORWAY := Color("#3E4270")
const CRYSTAL := Color("#8EE6F2")
const CRYSTAL_DEEP := Color("#4DB3D6")
const RUNNER := Color("#C8443B")
const BLANKET := Color("#5E7FC4")
const STEEL := Color("#5D6283")
const GONDOLA := Color("#E0564A")
const BUNTING: Array[Color] = [Color("#F27D6B"), Color("#F6C445"), Color("#6CC3A0"), Color("#6FA8DC"), Color("#B48ED8")]
const SPRING_BOX := Color("#5B9BD5")
const COIL := Color("#D5DAE3")
## How far above its cell's floor a spring's coil stands (see
## [method spring_top]).
const SPRING_FOOT: float = 0.6

const BLOB_SHADER: Shader = preload("res://shaders/blob_shadow.gdshader")

static var _parcels: Dictionary = {}
static var _spring_box: ArrayMesh
static var _spring_top: ArrayMesh


## Collects parts by colour and bakes one surface per colour. While
## [member anchored], every part also stores [member anchor] in CUSTOM0: the
## point it builds up from and when it starts (see Assembly).
class _Batch:
	var anchored: bool = false
	var anchor := Vector4.ZERO
	var _surfaces: Dictionary = {}
	var _materials: Dictionary = {}

	class _Surface:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var anchors := PackedFloat32Array()
		var indices := PackedInt32Array()

	func add(mesh: Mesh, transform: Transform3D, color: Color, glow: float = 0.0) -> void:
		var key: String = "%s/%.2f" % [color.to_html(), glow]
		if not _surfaces.has(key):
			_surfaces[key] = _Surface.new()
			_materials[key] = ClayShapes.material(color, glow)
		var surface: _Surface = _surfaces[key]
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var offset: int = surface.vertices.size()
		surface.vertices.append_array(transform * vertices)
		var turn: Basis = transform.basis.inverse().transposed()
		for normal: Vector3 in normals:
			surface.normals.append((turn * normal).normalized())
		if anchored:
			var one := PackedFloat32Array([anchor.x, anchor.y, anchor.z, anchor.w])
			for i in vertices.size():
				surface.anchors.append_array(one)
		if indices.is_empty():
			for i in vertices.size():
				surface.indices.append(offset + i)
		else:
			for index: int in indices:
				surface.indices.append(offset + index)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _surfaces:
			var surface: _Surface = _surfaces[key]
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surface.vertices
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
			arrays[Mesh.ARRAY_INDEX] = surface.indices
			var flags: int = 0
			if anchored:
				arrays[Mesh.ARRAY_CUSTOM0] = surface.anchors
				flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[key])
		return mesh


## All of a level's props in one mesh (props from LevelData), dressed for
## [param season] (see [method Palette.season]). Each builds up from its
## foot at the time [param delays] gives its cell (see Assembly).
static func build_props(props: Array[Dictionary], season: StringName = &"summer", delays: Dictionary = {}) -> ArrayMesh:
	var batch := _Batch.new()
	batch.anchored = true
	var snowy: bool = season == &"winter"
	for prop: Dictionary in props:
		var cell: Vector3i = prop["cell"]
		var base := Transform3D(Basis(Vector3.UP, deg_to_rad(prop["rotation"])), Vector3(cell) + Vector3(0.5, 0.0, 0.5))
		batch.anchor = Vector4(base.origin.x, base.origin.y, base.origin.z, delays.get(cell, 0.0))
		var leaves: Array[Color] = _foliage(season, cell)
		match prop["type"]:
			&"tree_small": _tree(batch, base, 3, leaves, snowy)
			&"tree_tall": _tree(batch, base, 4, leaves, snowy)
			&"bush": _bush(batch, base, leaves, snowy)
			&"lamp_post": _lamp_post(batch, base, snowy)
			&"flag": _flag(batch, base)
			&"crate": _crate(batch, base, snowy)
			&"fence": _fence(batch, base)
			&"rock": _rock(batch, base, snowy)
			&"pumpkin": _pumpkin(batch, base)
			&"leaf_pile": _leaf_pile(batch, base, cell)
			&"snowman": _snowman(batch, base)
			&"sunflower": _sunflower(batch, base)
			&"hay_bale": _hay_bale(batch, base)
			&"igloo": _igloo(batch, base)
			&"ice_crystal": _ice_crystal(batch, base, cell)
			&"sled": _sled(batch, base)
			&"ice_lantern": _ice_lantern(batch, base)
			&"signpost": _signpost(batch, base, snowy)
			&"gondola": _gondola(batch, base, snowy)
			&"bunting": _bunting(batch, base)
	return batch.commit()


## A dry board: planks over two beams filling the top of a block cell (the
## origin is the middle of the cell's floor), with a couple of fallen
## leaves. The planks lie across [param along], the way the board is
## crossed; [param cell] varies the sag and the leaves.
static func board(along: Vector3i, cell: Vector3i) -> ArrayMesh:
	var batch := _Batch.new()
	# The mesh is crossed along +X, so its planks lie along Z.
	var base := Transform3D(Basis(Vector3.UP, atan2(-float(along.z), float(along.x))), Vector3.ZERO)
	for i in 3:
		var sag: float = 0.012 * _hash(cell * 3 + Vector3i(i, 0, 0))
		batch.add(ClayShapes.rounded_box(Vector3(0.29, 0.12, 0.96), 0.03), base * _at(-0.32 + 0.32 * i, 0.93 + sag, 0.0),
			PLANK if i % 2 == 0 else PLANK_DARK)
	for z: float in [-0.3, 0.3]:
		batch.add(ClayShapes.rounded_box(Vector3(0.98, 0.1, 0.12), 0.03), base * _at(0.0, 0.82, z), BEAM)
	for i in 2:
		var spot := Vector2(_hash(cell + Vector3i(i, 7, 0)), _hash(cell + Vector3i(0, 7, i))) * 0.3
		var leaf := _at(spot.x, 1.0, spot.y).rotated_local(Vector3.UP, _hash(cell + Vector3i(i, 3, 1)) * PI)
		batch.add(_sphere(0.075, 0.03), base * leaf.scaled_local(Vector3(1.0, 1.0, 0.6)),
			AUTUMN_LEAVES[(i + absi(cell.x + cell.z)) % AUTUMN_LEAVES.size()])
	return batch.commit()


## A thin ice slab: a pale glassy sheet across the top of a block cell (the
## origin is the middle of the cell's floor) with a deeper rim, white crack
## lines, a drift of snow at one corner and icicles hanging under its edge.
## [param cell] varies the cracks, the snow and the icicles.
static func thin_ice(cell: Vector3i) -> ArrayMesh:
	var batch := _Batch.new()
	batch.add(ClayShapes.rounded_box(Vector3(0.98, 0.1, 0.98), 0.04), _at(0.0, 0.9, 0.0), THIN_ICE_DEEP)
	batch.add(ClayShapes.rounded_box(Vector3(0.9, 0.06, 0.9), 0.03), _at(0.0, 0.95, 0.0), THIN_ICE, 0.15)
	# Cracks fan out from a point near the middle.
	var centre := Vector2(_hash(cell + Vector3i(2, 0, 0)), _hash(cell + Vector3i(0, 0, 2))) * 0.12
	var turn: float = _hash(cell + Vector3i(1, 1, 1)) * PI
	for i in 4:
		var angle: float = turn + TAU * i / 4.0 + 0.35 * _hash(cell + Vector3i(i, 5, 0))
		var reach: float = 0.2 + 0.08 * _hash(cell + Vector3i(0, 5, i))
		var mid := Vector2(cos(angle), sin(angle)) * reach * 0.5 + centre
		var crack := _at(mid.x, 0.985, mid.y).rotated_local(Vector3.UP, -angle)
		batch.add(ClayShapes.rounded_box(Vector3(reach, 0.014, 0.022), 0.006), crack, ICE_CRACK)
		# A short fork off each crack.
		var fork_at := Vector2(cos(angle), sin(angle)) * reach * 0.8 + centre
		var fork := _at(fork_at.x, 0.985, fork_at.y).rotated_local(Vector3.UP, -angle - 0.7)
		batch.add(ClayShapes.rounded_box(Vector3(0.12, 0.014, 0.018), 0.006), fork * _at(0.05, 0.0, 0.0), ICE_CRACK)
	var corner := Vector2(signf(_hash(cell + Vector3i(4, 0, 0)) + 0.01), signf(_hash(cell + Vector3i(0, 4, 0)) + 0.01)) * 0.3
	batch.add(_sphere(0.16, 0.07), _at(corner.x, 0.97, corner.y).scaled_local(Vector3(1.3, 1.0, 1.0)), SNOW)
	for i in 3:
		var side: float = -0.36 + 0.36 * i + 0.06 * _hash(cell + Vector3i(i, 9, 0))
		var length: float = 0.12 + 0.07 * absf(_hash(cell + Vector3i(0, 9, i)))
		var spot := Vector3(side, 0.85 - length * 0.5, 0.42) if (cell.x + i) % 2 == 0 else Vector3(0.42, 0.85 - length * 0.5, side)
		if (cell.z + i) % 3 == 0:
			spot = Vector3(-spot.x, spot.y, -spot.z)
		batch.add(_cone(0.035, length), Transform3D(Basis(Vector3.RIGHT, PI), spot), THIN_ICE_DEEP)
	return batch.commit()


## A spring's box: it fills the bottom of its block cell (the origin is the
## middle of the cell's floor) up to [constant SPRING_FOOT], with a cream
## band round the top. Shared by every spring.
static func spring_box() -> ArrayMesh:
	if _spring_box == null:
		var batch := _Batch.new()
		batch.add(ClayShapes.rounded_box(Vector3(0.98, SPRING_FOOT, 0.98), 0.06), _at(0.0, SPRING_FOOT * 0.5, 0.0), SPRING_BOX)
		batch.add(ClayShapes.rounded_box(Vector3(1.0, 0.08, 1.0), 0.03), _at(0.0, SPRING_FOOT - 0.09, 0.0), TAPE)
		_spring_box = batch.commit()
	return _spring_box


## A spring's coil and round pad, from the coil's foot (the origin, on top
## of [method spring_box]) to the pad, level with the top of the cell.
## Shared by every spring.
static func spring_top() -> ArrayMesh:
	if _spring_top == null:
		var batch := _Batch.new()
		for i in 3:
			batch.add(_torus(0.2, 0.26), _at(0.0, 0.05 + 0.09 * i, 0.0), COIL)
		var pad_y: float = 1.0 - SPRING_FOOT - 0.04
		batch.add(_cylinder(0.43, 0.08), _at(0.0, pad_y, 0.0), Palette.block_color(Grid.SPRING))
		batch.add(_torus(0.39, 0.47), _at(0.0, pad_y, 0.0), TAPE)
		batch.add(_cylinder(0.15, 0.086), _at(0.0, pad_y, 0.0), TAPE)
		_spring_top = batch.commit()
	return _spring_top


## Every stairs block of [param grid] in one mesh, turned to climb along its
## facing ("stairs_wood" and "stairs_brick" take those colours).
static func build_stairs(grid: Grid, delays: Dictionary = {}) -> ArrayMesh:
	var batch := _Batch.new()
	batch.anchored = true
	for cell: Vector3i in grid.cells:
		var stairs_type: StringName = grid.cells[cell]
		if not Grid.is_stairs(stairs_type):
			continue
		var centre := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		batch.anchor = Vector4(centre.x, centre.y, centre.z, delays.get(cell, 0.0))
		var climb: Vector3i = grid.facing.get(cell, Vector3i(1, 0, 0))
		# The mesh climbs towards +X.
		var turn := Basis(Vector3.UP, atan2(-float(climb.z), float(climb.x)))
		var material: StringName = StringName(String(stairs_type).trim_prefix("stairs").trim_prefix("_"))
		var color: Color = Palette.block_color(material if material != &"" else &"stone")
		batch.add(ClayShapes.stairs(), Transform3D(turn, Vector3(cell) + Vector3(0.5, 0.0, 0.5)), color)
	return batch.commit()


## Bars for a gate's cells (level coordinates): five posts per cell with
## accent caps.
static func gate_bars(cells: Array[Vector3i], delays: Dictionary = {}) -> ArrayMesh:
	var batch := _Batch.new()
	batch.anchored = true
	for cell: Vector3i in cells:
		var base := Transform3D(Basis.IDENTITY, Vector3(cell) + Vector3(0.5, 0.0, 0.5))
		batch.anchor = Vector4(base.origin.x, base.origin.y, base.origin.z, delays.get(cell, 0.0))
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


## A tree or bush's leaf colours, [main, top]: pink or pale blossom by cell
## in spring, green in summer, orange, red or gold by cell in autumn, dark
## pine in winter.
static func _foliage(season: StringName, cell: Vector3i) -> Array[Color]:
	match season:
		&"spring":
			var blossom: Color = BLOSSOMS[absi(cell.x * 5 + cell.z * 3 + cell.y) % BLOSSOMS.size()]
			return [blossom, blossom.lerp(Color.WHITE, 0.3)]
		&"autumn":
			var leaf: Color = AUTUMN_LEAVES[absi(cell.x * 7 + cell.z * 3 + cell.y) % AUTUMN_LEAVES.size()]
			return [leaf, leaf.lerp(Color.WHITE, 0.18)]
		&"winter":
			return [PINE, PINE.lerp(Color.WHITE, 0.12)]
	return [LEAVES, LEAVES_LIGHT]


static func _tree(batch: _Batch, base: Transform3D, tiers: int, leaves: Array[Color], snowy: bool) -> void:
	var trunk_height: float = 0.3 if tiers <= 3 else 0.42
	batch.add(_cylinder(0.065, trunk_height), base * _at(0.0, trunk_height * 0.5, 0.0), TRUNK)
	var y: float = trunk_height + 0.1
	var radius: float = 0.34 if tiers <= 3 else 0.36
	for tier in tiers:
		var height: float = radius * 1.15
		var color: Color = leaves[1] if tier == tiers - 1 else leaves[0]
		batch.add(_cone(radius, height), base * _at(0.0, y + height * 0.3, 0.0), color)
		if snowy:
			# Snow over the top half of the tier.
			batch.add(_cone(radius * 0.54, height * 0.5), base * _at(0.0, y + height * 0.55, 0.0), SNOW)
		y += height * 0.55
		radius *= 0.76


static func _bush(batch: _Batch, base: Transform3D, leaves: Array[Color], snowy: bool) -> void:
	for blob: Vector4 in [Vector4(0.0, 0.14, 0.0, 0.19), Vector4(0.15, 0.1, 0.07, 0.13),
			Vector4(-0.12, 0.1, -0.08, 0.12), Vector4(0.03, 0.25, -0.04, 0.11)]:
		var color: Color = leaves[1] if blob.y > 0.2 else leaves[0]
		batch.add(_sphere(blob.w, blob.w * 1.7), base * _at(blob.x, blob.y, blob.z), color)
		if snowy and blob.y > 0.12:
			batch.add(_sphere(blob.w * 0.8, blob.w * 0.7), base * _at(blob.x, blob.y + blob.w * 0.62, blob.z), SNOW)


static func _lamp_post(batch: _Batch, base: Transform3D, snowy: bool) -> void:
	batch.add(ClayShapes.rounded_box(Vector3(0.16, 0.06, 0.16), 0.02), base * _at(0.0, 0.03, 0.0), POST)
	batch.add(_cylinder(0.03, 0.82), base * _at(0.0, 0.45, 0.0), POST)
	batch.add(_sphere(0.085, 0.17), base * _at(0.0, 0.9, 0.0), LAMP, 1.2)
	batch.add(_cone(0.11, 0.08), base * _at(0.0, 1.01, 0.0), POST)
	if snowy:
		batch.add(_sphere(0.075, 0.06), base * _at(0.0, 1.05, 0.0), SNOW)


static func _flag(batch: _Batch, base: Transform3D) -> void:
	batch.add(_cylinder(0.022, 0.92), base * _at(0.0, 0.46, 0.0), POST)
	batch.add(_sphere(0.035, 0.07), base * _at(0.0, 0.94, 0.0), POST)
	batch.add(ClayShapes.rounded_box(Vector3(0.3, 0.18, 0.02), 0.008), base * _at(0.16, 0.78, 0.0), BANNER)


static func _crate(batch: _Batch, base: Transform3D, snowy: bool) -> void:
	batch.add(ClayShapes.rounded_box(Vector3(0.46, 0.4, 0.46), 0.04), base * _at(0.0, 0.2, 0.0), CRATE)
	for y: float in [0.08, 0.32]:
		batch.add(ClayShapes.rounded_box(Vector3(0.48, 0.055, 0.48), 0.02), base * _at(0.0, y, 0.0), CRATE_BAND)
	if snowy:
		batch.add(ClayShapes.rounded_box(Vector3(0.44, 0.06, 0.44), 0.03), base * _at(0.0, 0.42, 0.0), SNOW)


static func _fence(batch: _Batch, base: Transform3D) -> void:
	for x: float in [-0.42, 0.0, 0.42]:
		batch.add(_cylinder(0.035, 0.38), base * _at(x, 0.19, -0.42), FENCE)
	for y: float in [0.14, 0.29]:
		batch.add(ClayShapes.rounded_box(Vector3(0.94, 0.045, 0.03), 0.012), base * _at(0.0, y, -0.42), FENCE)


static func _rock(batch: _Batch, base: Transform3D, snowy: bool) -> void:
	var big := _at(0.0, 0.08, 0.0).scaled_local(Vector3(1.25, 1.0, 1.0))
	batch.add(_sphere(0.2, 0.26), base * big, ROCK)
	batch.add(_sphere(0.1, 0.13), base * _at(0.2, 0.04, 0.12), ROCK)
	if snowy:
		batch.add(_sphere(0.15, 0.08), base * _at(-0.02, 0.19, 0.0).scaled_local(Vector3(1.25, 1.0, 1.0)), SNOW)


## A ribbed pumpkin with a stubby stem.
static func _pumpkin(batch: _Batch, base: Transform3D) -> void:
	for i in 6:
		var angle: float = TAU * i / 6.0
		# Each rib is squashed across the way round.
		var rib := _at(cos(angle) * 0.07, 0.13, sin(angle) * 0.07).rotated_local(Vector3.UP, -angle)
		batch.add(_sphere(0.13, 0.25), base * rib.scaled_local(Vector3(1.0, 1.0, 0.7)), PUMPKIN)
	batch.add(_cylinder(0.025, 0.09), base * _at(0.0, 0.29, 0.0), STEM)


## Fallen leaves heaped in a low mound.
static func _leaf_pile(batch: _Batch, base: Transform3D, cell: Vector3i) -> void:
	for i in 9:
		var angle: float = TAU * i / 9.0 + _hash(cell + Vector3i(i, 0, 0))
		var reach: float = 0.06 + 0.11 * (i % 3)
		var leaf := _at(cos(angle) * reach, 0.1 - reach * 0.3 + 0.02 * (i % 2), sin(angle) * reach)
		leaf = leaf.rotated_local(Vector3.UP, angle * 1.7).rotated_local(Vector3.RIGHT, 0.4 * _hash(cell + Vector3i(0, i, 0)))
		batch.add(_sphere(0.09, 0.04), base * leaf.scaled_local(Vector3(1.0, 1.0, 0.6)), AUTUMN_LEAVES[i % AUTUMN_LEAVES.size()])


## Three snowballs with coal eyes and buttons, a carrot nose and a red scarf,
## facing +Z.
static func _snowman(batch: _Batch, base: Transform3D) -> void:
	batch.add(_sphere(0.2, 0.38), base * _at(0.0, 0.18, 0.0), SNOW)
	batch.add(_sphere(0.145, 0.28), base * _at(0.0, 0.47, 0.0), SNOW)
	batch.add(_sphere(0.105, 0.2), base * _at(0.0, 0.69, 0.0), SNOW)
	batch.add(_cylinder(0.12, 0.05), base * _at(0.0, 0.59, 0.0), SCARF)
	batch.add(ClayShapes.rounded_box(Vector3(0.05, 0.16, 0.03), 0.012), base * _at(0.07, 0.53, 0.11).rotated_local(Vector3.FORWARD, 0.3), SCARF)
	batch.add(_cone(0.025, 0.11), base * _at(0.0, 0.69, 0.13).rotated_local(Vector3.RIGHT, PI * 0.5), CARROT)
	for x: float in [-0.04, 0.04]:
		batch.add(_sphere(0.017, 0.034), base * _at(x, 0.73, 0.095), POST)
	for y: float in [0.43, 0.51]:
		batch.add(_sphere(0.018, 0.036), base * _at(0.0, y, 0.142), POST)


## A sunflower: a tall stem with two leaves and a big golden head with a
## brown heart, facing +Z and tipped up a little to the sun.
static func _sunflower(batch: _Batch, base: Transform3D) -> void:
	batch.add(_cylinder(0.025, 0.72), base * _at(0.0, 0.36, 0.0), SUNFLOWER_STEM)
	for side: float in [-1.0, 1.0]:
		var leaf := _at(side * 0.08, 0.28 + 0.1 * maxf(side, 0.0), 0.0).rotated_local(Vector3.BACK, side * 0.5)
		batch.add(_sphere(0.08, 0.03), base * leaf.scaled_local(Vector3(1.4, 1.0, 0.8)), LEAVES)
	# The head is a disc facing up its local +Y, turned to face +Z.
	var head := _at(0.0, 0.76, 0.03).rotated_local(Vector3.RIGHT, PI * 0.5 - 0.35)
	for i in 11:
		var angle: float = TAU * i / 11.0
		var petal := head * _at(cos(angle) * 0.14, 0.0, sin(angle) * 0.14).rotated_local(Vector3.UP, -angle)
		batch.add(_sphere(0.075, 0.025), base * petal.scaled_local(Vector3(1.0, 1.0, 0.5)), SUNFLOWER)
	batch.add(_cylinder(0.1, 0.05), base * head * _at(0.0, 0.01, 0.0), SUNFLOWER_HEART)


## A round hay bale lying on its side, bound with two cords.
static func _hay_bale(batch: _Batch, base: Transform3D) -> void:
	var lying := Basis(Vector3.BACK, PI * 0.5)
	batch.add(_cylinder(0.26, 0.44), base * Transform3D(lying, Vector3(0.0, 0.26, 0.0)), HAY)
	for x: float in [-0.11, 0.11]:
		batch.add(_cylinder(0.268, 0.035), base * Transform3D(lying, Vector3(x, 0.26, 0.0)), HAY_CORD)


## A snow-block dome with its rows picked out and a low entrance tunnel,
## facing +Z.
static func _igloo(batch: _Batch, base: Transform3D) -> void:
	batch.add(_sphere(0.4, 0.8), base * _at(0.0, 0.0, -0.02).scaled_local(Vector3(1.0, 1.05, 1.0)), SNOW)
	for row: Vector2 in [Vector2(0.13, 0.385), Vector2(0.26, 0.335)]:
		batch.add(_torus(row.y - 0.012, row.y + 0.01), base * _at(0.0, row.x, -0.02), SNOW_SHADE)
	batch.add(_sphere(0.11, 0.08), base * _at(0.0, 0.42, -0.02), SNOW_SHADE)
	var tunnel := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.12, 0.34))
	batch.add(_cylinder(0.15, 0.24), base * tunnel, SNOW)
	batch.add(_cylinder(0.1, 0.25), base * tunnel.translated_local(Vector3(0.0, 0.006, -0.02)), DOORWAY)


## A cluster of glowing ice crystals, tall in the middle, leaning out.
static func _ice_crystal(batch: _Batch, base: Transform3D, cell: Vector3i) -> void:
	batch.add(_sphere(0.2, 0.1), base * _at(0.0, 0.02, 0.0).scaled_local(Vector3(1.2, 1.0, 1.0)), SNOW)
	for i in 5:
		var angle: float = TAU * i / 5.0 + _hash(cell) * 0.6
		var lean: float = 0.0 if i == 0 else 0.42
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * (0.0 if i == 0 else 0.1)
		var height: float = 0.62 if i == 0 else 0.3 + 0.08 * absf(_hash(cell + Vector3i(i, 0, 0)))
		var shard := _at(spot.x, 0.0, spot.z).rotated_local(Vector3.UP, -angle).rotated_local(Vector3.BACK, -lean)
		var prism := _cylinder(0.065 if i == 0 else 0.05, height * 0.75)
		prism.radial_segments = 6
		var tip := _cone(0.065 if i == 0 else 0.05, height * 0.25)
		tip.radial_segments = 6
		var color: Color = CRYSTAL if i % 2 == 0 else CRYSTAL_DEEP
		batch.add(prism, base * shard * _at(0.0, height * 0.375, 0.0), color, 0.5)
		batch.add(tip, base * shard * _at(0.0, height * 0.875, 0.0), color, 0.5)


## A wooden sled with curled red runners and a rolled blue blanket, along X.
static func _sled(batch: _Batch, base: Transform3D) -> void:
	for z: float in [-0.15, 0.15]:
		batch.add(ClayShapes.rounded_box(Vector3(0.62, 0.035, 0.035), 0.012), base * _at(-0.02, 0.02, z), RUNNER)
		batch.add(_torus(0.04, 0.075), base * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.3, 0.075, z)), RUNNER)
		for x: float in [-0.2, 0.14]:
			batch.add(_cylinder(0.018, 0.1), base * _at(x, 0.08, z), RUNNER)
	for i in 4:
		batch.add(ClayShapes.rounded_box(Vector3(0.12, 0.035, 0.38), 0.012), base * _at(-0.24 + 0.135 * i, 0.145, 0.0),
			PLANK if i % 2 == 0 else PLANK_DARK)
	var roll := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.08, 0.23, 0.0))
	batch.add(_cylinder(0.075, 0.32), base * roll, BLANKET)
	batch.add(_cylinder(0.078, 0.03), base * roll.translated_local(Vector3(0.0, 0.08, 0.0)), TAPE)
	batch.add(_cylinder(0.078, 0.03), base * roll.translated_local(Vector3(0.0, -0.08, 0.0)), TAPE)


## Blocks of ice stacked round a warm candle glow, with a snow cap.
static func _ice_lantern(batch: _Batch, base: Transform3D) -> void:
	batch.add(_cylinder(0.07, 0.16), base * _at(0.0, 0.12, 0.0), LAMP, 1.6)
	for i in 4:
		var angle: float = TAU * i / 4.0
		var wall := _at(cos(angle) * 0.12, 0.13, sin(angle) * 0.12).rotated_local(Vector3.UP, -angle)
		batch.add(ClayShapes.rounded_box(Vector3(0.06, 0.26, 0.2), 0.025), base * wall, THIN_ICE, 0.35)
	batch.add(ClayShapes.rounded_box(Vector3(0.3, 0.05, 0.3), 0.02), base * _at(0.0, 0.285, 0.0), THIN_ICE, 0.35)
	batch.add(_sphere(0.13, 0.07), base * _at(0.0, 0.32, 0.0), SNOW)


## A trail signpost with two arrow boards pointing different ways.
static func _signpost(batch: _Batch, base: Transform3D, snowy: bool) -> void:
	batch.add(_cylinder(0.035, 0.8), base * _at(0.0, 0.4, 0.0), TRUNK)
	for arrow: Vector2 in [Vector2(0.66, 0.2), Vector2(0.5, -2.6)]:
		var board := _at(0.0, arrow.x, 0.0).rotated_local(Vector3.UP, arrow.y)
		batch.add(ClayShapes.rounded_box(Vector3(0.34, 0.09, 0.03), 0.012), base * board * _at(0.15, 0.0, 0.03), PLANK)
		var point := _cone(0.065, 0.07)
		point.radial_segments = 4
		batch.add(point, base * board * Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.355, 0.0, 0.03)), PLANK)
		if snowy:
			batch.add(ClayShapes.rounded_box(Vector3(0.3, 0.025, 0.04), 0.01), base * board * _at(0.14, 0.055, 0.03), SNOW)
	if snowy:
		batch.add(_sphere(0.05, 0.04), base * _at(0.0, 0.81, 0.0), SNOW)


## A cable-car pylon with a red gondola hanging from the cable, which runs
## along X.
static func _gondola(batch: _Batch, base: Transform3D, snowy: bool) -> void:
	batch.add(ClayShapes.rounded_box(Vector3(0.2, 0.08, 0.2), 0.03), base * _at(-0.3, 0.04, 0.0), STEEL)
	batch.add(_cylinder(0.04, 1.3), base * _at(-0.3, 0.68, 0.0), STEEL)
	batch.add(ClayShapes.rounded_box(Vector3(0.08, 0.06, 0.34), 0.02), base * _at(-0.3, 1.32, 0.0), STEEL)
	var cable := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 1.31, 0.13))
	batch.add(_cylinder(0.012, 1.0), base * cable, POST)
	batch.add(_cylinder(0.012, 0.34), base * _at(0.18, 1.14, 0.13), STEEL)
	batch.add(ClayShapes.rounded_box(Vector3(0.3, 0.26, 0.24), 0.06), base * _at(0.18, 0.84, 0.13), GONDOLA)
	batch.add(ClayShapes.rounded_box(Vector3(0.31, 0.08, 0.25), 0.03), base * _at(0.18, 0.88, 0.13), LAMP, 0.6)
	batch.add(ClayShapes.rounded_box(Vector3(0.32, 0.04, 0.26), 0.02), base * _at(0.18, 0.98, 0.13), STEEL)
	if snowy:
		batch.add(ClayShapes.rounded_box(Vector3(0.28, 0.035, 0.22), 0.015), base * _at(0.18, 1.0, 0.13), SNOW)
		batch.add(ClayShapes.rounded_box(Vector3(0.07, 0.03, 0.3), 0.012), base * _at(-0.3, 1.36, 0.0), SNOW)


## Two poles with a sagging string of bright pennants between them, along X.
static func _bunting(batch: _Batch, base: Transform3D) -> void:
	for x: float in [-0.44, 0.44]:
		batch.add(_cylinder(0.025, 0.78), base * _at(x, 0.39, 0.0), TRUNK)
		batch.add(_sphere(0.035, 0.07), base * _at(x, 0.79, 0.0), TRUNK)
	for i in 8:
		var t0: float = i / 8.0
		var t1: float = (i + 1) / 8.0
		var a := Vector2(lerpf(-0.44, 0.44, t0), 0.74 - 0.14 * sin(PI * t0))
		var b := Vector2(lerpf(-0.44, 0.44, t1), 0.74 - 0.14 * sin(PI * t1))
		var mid: Vector2 = (a + b) * 0.5
		var span: Vector2 = b - a
		var piece := Transform3D(Basis(Vector3.BACK, atan2(span.y, span.x) - PI * 0.5), Vector3(mid.x, mid.y, 0.0))
		batch.add(_cylinder(0.008, span.length()), base * piece, POST)
	for i in 6:
		var t: float = (i + 0.75) / 7.5
		var top := Vector2(lerpf(-0.44, 0.44, t), 0.74 - 0.14 * sin(PI * t))
		var pennant := _cone(0.07, 0.15)
		pennant.radial_segments = 3
		var hang := Transform3D(Basis(Vector3.RIGHT, PI), Vector3(top.x, top.y - 0.08, 0.0)).scaled_local(Vector3(1.0, 1.0, 0.25))
		batch.add(pennant, base * hang, BUNTING[i % BUNTING.size()])


## A steady value in [-1, 1] for a cell.
static func _hash(cell: Vector3i) -> float:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (cell.z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return float(h & 0xFFFF) / 32767.5 - 1.0


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


static func _torus(inner: float, outer: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 20
	torus.ring_segments = 8
	return torus


static func _sphere(radius: float, height: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = 14
	sphere.rings = 7
	return sphere
