class_name CourierBuilder
extends RefCounted
## Builds the courier, a little walking mailbox, from procedural clay parts.
##
## Local space has the feet at the origin and the front facing -Z: two stubby
## legs, an arch-topped body, a cream door on the front with two big eyes and
## a latch, and a red flag on the right side that rises while it carries a
## parcel. About 0.4 m wide and 0.6 m tall, so it reads at phone scale.

const BODY_COLOR := Color("#4C62D0")
const DOOR_COLOR := Color("#FFF1DC")
const INK_COLOR := Color("#2B2D42")
const FLAG_COLOR := Color("#E4572E")
const LEG_COLOR := Color("#3A3550")
const GLINT_COLOR := Color("#FFFFFF")

const WIDTH: float = 0.40
const DEPTH: float = 0.44
## Straight part of the body below the arch.
const BOX_HEIGHT: float = 0.18
## Bottom of the body above the floor.
const HIP_HEIGHT: float = 0.17
## Flag pivot angle when lowered (pole lying back along the body).
const FLAG_LOWERED: float = PI * 0.5

const BLOB_SHADER: Shader = preload("res://shaders/blob_shadow.gdshader")


## Handles to the parts the Courier animates.
class Rig:
	## Lifted for hops; holds legs and body.
	var root: Node3D
	## Bobs, leans, sways and squashes (pivot at the feet).
	var body: Node3D
	var leg_left: Node3D
	var leg_right: Node3D
	## Hinged at the door's bottom edge; rotate -X to open.
	var door_hinge: Node3D
	## Scaled flat to blink.
	var eyes: Array[Node3D] = []
	var open_eyes: Array[Node3D] = []
	var happy_eyes: Array[Node3D] = []
	var flag_pivot: Node3D


static func build(owner: Node3D) -> Rig:
	var rig := Rig.new()

	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	var blob_material := ShaderMaterial.new()
	blob_material.shader = BLOB_SHADER
	blob.material_override = blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.012
	owner.add_child(blob)

	rig.root = _node(owner, "Rig", Vector3.ZERO)
	rig.leg_left = _leg(rig.root, "LegLeft", -0.095)
	rig.leg_right = _leg(rig.root, "LegRight", 0.095)
	rig.body = _node(rig.root, "Body", Vector3.ZERO)

	var shell := _mesh(rig.body, "Shell", ClayShapes.extrusion(_arch_profile(WIDTH, BOX_HEIGHT, 0.06), DEPTH, 0.04), BODY_COLOR)
	shell.position.y = HIP_HEIGHT

	# Door on the front face, hinged at its bottom edge.
	rig.door_hinge = _node(rig.body, "DoorHinge", Vector3(0.0, HIP_HEIGHT + 0.035, -DEPTH * 0.5))
	var door := _mesh(rig.door_hinge, "Door", ClayShapes.extrusion(_arch_profile(0.32, 0.12, 0.04), 0.03, 0.012), DOOR_COLOR)
	door.position.z = -0.012
	var latch := _mesh(rig.door_hinge, "Latch", ClayShapes.rounded_box(Vector3(0.07, 0.022, 0.02), 0.009), INK_COLOR)
	latch.position = Vector3(0.0, 0.25, -0.03)
	for side: float in [-1.0, 1.0]:
		_eye(rig, Vector3(side * 0.072, 0.165, -0.03))

	# Flag on the right side, lowered until there is a parcel to carry.
	rig.flag_pivot = _node(rig.body, "FlagPivot", Vector3(WIDTH * 0.5 + 0.012, HIP_HEIGHT + 0.13, 0.1))
	var pole := _mesh(rig.flag_pivot, "Pole", ClayShapes.rounded_box(Vector3(0.022, 0.2, 0.022), 0.009), LEG_COLOR)
	pole.position.y = 0.1
	var flag := _mesh(rig.flag_pivot, "Flag", ClayShapes.rounded_box(Vector3(0.014, 0.075, 0.11), 0.006), FLAG_COLOR)
	flag.position = Vector3(0.0, 0.16, 0.055)
	rig.flag_pivot.rotation.x = FLAG_LOWERED
	return rig


## Arch-topped outline (rounded bottom corners, half-circle top), base at
## y = 0, counter-clockwise.
static func _arch_profile(width: float, box_height: float, corner: float) -> PackedVector2Array:
	var half: float = width * 0.5
	var points := PackedVector2Array([Vector2(-half, 0.0), Vector2(half, 0.0), Vector2(half, box_height)])
	for i in range(1, 12):
		var angle: float = PI * i / 12.0
		points.append(Vector2(cos(angle) * half, box_height + sin(angle) * half))
	points.append(Vector2(-half, box_height))
	return ClayShapes.rounded_polygon(points, corner)


static func _leg(parent: Node3D, leg_name: String, x: float) -> Node3D:
	var hip := _node(parent, leg_name, Vector3(x, HIP_HEIGHT + 0.04, 0.02))
	var leg := _mesh(hip, "Leg", _capsule(0.045, 0.2), LEG_COLOR)
	leg.position.y = -0.09
	var foot := _mesh(hip, "Foot", _sphere(0.05, 0.06), LEG_COLOR)
	foot.position = Vector3(0.0, -0.18, -0.025)
	foot.scale = Vector3(1.0, 1.0, 1.35)
	return hip


## One eye: a tall dark oval with a glint, plus a hidden "^" for happy moments.
static func _eye(rig: Rig, at: Vector3) -> void:
	var eye := _node(rig.door_hinge, "Eye", at)
	rig.eyes.append(eye)

	var open := _node(eye, "Open", Vector3.ZERO)
	var pupil := _mesh(open, "Pupil", _sphere(0.042, 0.1), INK_COLOR)
	pupil.scale.z = 0.4
	var glint := _mesh(open, "Glint", _sphere(0.014, 0.028, 8), GLINT_COLOR, 0.8)
	glint.position = Vector3(-0.014, 0.022, -0.014)
	rig.open_eyes.append(open)

	var happy := _node(eye, "Happy", Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var part := _mesh(happy, "Stroke", _capsule(0.013, 0.07), INK_COLOR)
		part.position = Vector3(side * 0.017, 0.0, -0.01)
		part.rotation.z = side * 0.6
	happy.visible = false
	rig.happy_eyes.append(happy)


## Primitive meshes default to far more segments than parts this small need.
static func _sphere(radius: float, height: float, segments: int = 16) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = segments
	sphere.rings = segments / 2
	return sphere


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	capsule.radial_segments = 12
	capsule.rings = 3
	return capsule


static func _node(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


static func _mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = ClayShapes.material(color, glow)
	parent.add_child(instance)
	return instance
