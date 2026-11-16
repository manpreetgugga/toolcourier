class_name ParcelSymbol
## A shape for each parcel colour, printed in ink on the parcel's top and on
## its pad, so that matching a parcel to its pad never rests on colour alone
## (for colour-blind players; testers' report, 1.2.0). Red and green, the
## pair most often confused, get the two least alike shapes.

const SHAPES: Dictionary = {
	&"red": &"heart",
	&"green": &"triangle",
	&"blue": &"circle",
	&"yellow": &"star",
}
## Dark enough to read on every parcel colour and on the cream tape.
const INK := Color("#3A3550")

static var _meshes: Dictionary = {}


## The flat symbol for [param color], [param size] metres across, lying on
## y = 0 (its top face at [param thickness]) and pointing towards -Z.
static func mesh(color: StringName, size: float, thickness: float) -> ArrayMesh:
	var key: String = "%s/%.3f/%.3f" % [color, size, thickness]
	if not _meshes.has(key):
		var profile := PackedVector2Array()
		for p: Vector2 in outline(SHAPES[color]):
			profile.append(p * size)
		var flat: ArrayMesh = ClayShapes.extrusion(profile, thickness, thickness * 0.4, 2)
		# The profile's plane (XY) to the floor (XZ): up the screen becomes -Z.
		var lay := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, thickness * 0.5, 0.0))
		var arrays: Array = flat.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] = lay * vertices[i]
			normals[i] = lay.basis * normals[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var laid := ArrayMesh.new()
		laid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes[key] = laid
	return _meshes[key]


## The closed, counter-clockwise outline of [param shape], fitting a square
## one unit across centred on the origin.
static func outline(shape: StringName) -> PackedVector2Array:
	var points := PackedVector2Array()
	match shape:
		&"circle":
			for i in 24:
				var a: float = TAU * i / 24.0
				points.append(Vector2(cos(a), sin(a)) * 0.5)
		&"triangle":
			var corners := PackedVector2Array()
			for i in 3:
				var a: float = PI * 0.5 + TAU * i / 3.0
				corners.append(Vector2(cos(a), sin(a)) * 0.56 + Vector2(0.0, -0.08))
			points = ClayShapes.rounded_polygon(corners, 0.09)
		&"star":
			var corners := PackedVector2Array()
			for i in 10:
				var a: float = PI * 0.5 + TAU * i / 10.0
				corners.append(Vector2(cos(a), sin(a)) * (0.52 if i % 2 == 0 else 0.23) + Vector2(0.0, -0.03))
			points = ClayShapes.rounded_polygon(corners, 0.035)
		&"heart":
			# Two round lobes and the lines from the tip that touch them, the
			# notch between the lobes softened (a sharp notch folds over when
			# the edges are rounded).
			var tip := Vector2(0.0, -0.47)
			var lobe := Vector2(0.22, 0.17)
			var radius: float = 0.25
			var reach: float = tip.distance_to(lobe)
			var touch_angle: float = (lobe - tip).angle() - asin(radius / reach)
			var touch: Vector2 = tip + Vector2.from_angle(touch_angle) * sqrt(reach * reach - radius * radius)
			var start: float = (touch - lobe).angle()
			var notch: float = (Vector2(0.0, lobe.y + sqrt(radius * radius - lobe.x * lobe.x)) - lobe).angle()
			var corners := PackedVector2Array([tip])
			for i in 15:
				corners.append(lobe + Vector2.from_angle(lerpf(start, notch, i / 14.0)) * radius)
			var left := Vector2(-lobe.x, lobe.y)
			for i in range(1, 15):
				corners.append(left + Vector2.from_angle(lerpf(PI - notch, PI - start, i / 14.0)) * radius)
			points = ClayShapes.rounded_polygon(corners, 0.05)
	if _signed_area(points) < 0.0:
		points.reverse()
	return points


static func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
