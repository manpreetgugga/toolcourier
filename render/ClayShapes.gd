class_name ClayShapes
extends RefCounted
## Procedural clay meshes for props and characters (rounded extrusions,
## rounded boxes, stairs) and the shared clay materials they use.

const CLAY_SHADER: Shader = preload("res://shaders/clay.gdshader")

static var _materials: Dictionary = {}
static var _stairs: ArrayMesh


class _MeshData:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	func add_vertex(position: Vector3, normal: Vector3) -> int:
		vertices.append(position)
		normals.append(normal)
		return vertices.size() - 1

	## Godot treats clockwise triangles as front-facing; the order is fixed
	## from the vertex normals.
	func add_triangle(a: int, b: int, c: int) -> void:
		var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if cross.length_squared() < 1e-14:
			return
		indices.append(a)
		if cross.dot(normals[a] + normals[b] + normals[c]) > 0.0:
			indices.append(c)
			indices.append(b)
		else:
			indices.append(b)
			indices.append(c)

	func add_quad(a: int, b: int, c: int, d: int) -> void:
		add_triangle(a, b, c)
		add_triangle(a, c, d)

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Shared clay material for a colour; [param glow] adds self-illumination.
static func material(color: Color, glow: float = 0.0) -> ShaderMaterial:
	var key: String = "%s/%.2f" % [color.to_html(), glow]
	var mat: ShaderMaterial = _materials.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = CLAY_SHADER
		mat.set_shader_parameter(&"albedo", color)
		mat.set_shader_parameter(&"glow", glow)
		_materials[key] = mat
	return mat


## Rounds every corner of a closed polygon with an arc of up to
## [param radius] (less where the neighbouring edges are short). Works for
## convex and concave corners.
static func rounded_polygon(points: PackedVector2Array, radius: float, segments: int = 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = points.size()
	for k in n:
		var corner: Vector2 = points[k]
		var to_prev: Vector2 = points[(k - 1 + n) % n] - corner
		var to_next: Vector2 = points[(k + 1) % n] - corner
		var d1: Vector2 = to_prev.normalized()
		var d2: Vector2 = to_next.normalized()
		var half: float = acos(clampf(d1.dot(d2), -1.0, 1.0)) * 0.5
		# Leave nearly straight joints (such as points along an arc) alone.
		if half > deg_to_rad(80.0) or half < 0.01:
			_append_distinct(out, corner)
			continue
		var along: float = minf(radius / tan(half), minf(to_prev.length(), to_next.length()) * 0.5)
		var r: float = along * tan(half)
		var center: Vector2 = corner + (d1 + d2).normalized() * (r / sin(half))
		var a0: float = (corner + d1 * along - center).angle()
		var sweep: float = wrapf((corner + d2 * along - center).angle() - a0, -PI, PI)
		for s in segments + 1:
			_append_distinct(out, center + Vector2.from_angle(a0 + sweep * s / segments) * r)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 1e-5:
		out.remove_at(out.size() - 1)
	return out


## Extrudes a closed counter-clockwise profile (XY plane) along Z, centred
## and [param depth] deep, rounding the front and back edges by
## [param radius] in [param steps] segments. Round the profile's own corners
## with [method rounded_polygon] for a fully soft shape.
static func extrusion(profile: PackedVector2Array, depth: float, radius: float, steps: int = 3) -> ArrayMesh:
	var n: int = profile.size()
	var outward := PackedVector2Array()
	for k in n:
		var e1: Vector2 = (profile[k] - profile[(k - 1 + n) % n]).normalized()
		var e2: Vector2 = (profile[(k + 1) % n] - profile[k]).normalized()
		outward.append((Vector2(e1.y, -e1.x) + Vector2(e2.y, -e2.x)).normalized())
	var r: float = minf(radius, depth * 0.5)
	var m := _MeshData.new()

	# Rings of vertices from the back cap edge, round the back bevel, along
	# the side and round the front bevel to the front cap edge.
	var rings: Array[PackedInt32Array] = []
	var cap_points: Array[PackedVector2Array] = []
	for side: int in [-1, 1]:
		for i in steps + 1:
			var step: int = steps - i if side < 0 else i
			var theta: float = PI * 0.5 * step / steps
			var z: float = side * (depth * 0.5 - r + r * sin(theta))
			var inset: float = r * (1.0 - cos(theta))
			var ring := PackedInt32Array()
			var flat := PackedVector2Array()
			for k in n:
				var p: Vector2 = profile[k] - outward[k] * inset
				var normal := Vector3(outward[k].x * cos(theta), outward[k].y * cos(theta), side * sin(theta))
				ring.append(m.add_vertex(Vector3(p.x, p.y, z), normal.normalized()))
				flat.append(p)
			rings.append(ring)
			cap_points.append(flat)
	for i in rings.size() - 1:
		for k in n:
			var k2: int = (k + 1) % n
			m.add_quad(rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k])

	# Flat caps over the innermost rings.
	for cap: int in [0, rings.size() - 1]:
		var z: float = m.vertices[rings[cap][0]].z
		var normal := Vector3(0.0, 0.0, signf(z))
		var start: int = m.vertices.size()
		for p: Vector2 in cap_points[cap]:
			m.add_vertex(Vector3(p.x, p.y, z), normal)
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(cap_points[cap])
		for t in range(0, tris.size(), 3):
			m.add_triangle(start + tris[t], start + tris[t + 1], start + tris[t + 2])
	return m.commit()


## A box with every edge rounded, centred on the origin.
static func rounded_box(size: Vector3, radius: float) -> ArrayMesh:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var rect := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	return extrusion(rounded_polygon(rect, radius), size.z, radius)


## A one-cell flight of three clay steps. Local space: the cell spans
## x, z in [-0.5, 0.5] and y in [0, 1]; the steps climb towards +X.
static func stairs() -> ArrayMesh:
	if _stairs == null:
		var third: float = 1.0 / 3.0
		var profile := PackedVector2Array([
			Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 1.0),
			Vector2(0.5 - third, 1.0), Vector2(0.5 - third, 2.0 * third),
			Vector2(-0.5 + third, 2.0 * third), Vector2(-0.5 + third, third),
			Vector2(-0.5, third),
		])
		_stairs = extrusion(rounded_polygon(profile, 0.06), 1.0, 0.07)
	return _stairs


static func _append_distinct(points: PackedVector2Array, p: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1].distance_to(p) > 1e-5:
		points.append(p)
