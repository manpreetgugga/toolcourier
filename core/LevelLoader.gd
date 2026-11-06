class_name LevelLoader
extends RefCounted
## Reads level JSON into LevelData and checks it, collecting every problem
## (with where it is) instead of stopping at the first. The format is
## documented in README.md.

const DIRECTIONS: Dictionary = {
	"+x": Vector3i(1, 0, 0), "-x": Vector3i(-1, 0, 0),
	"+z": Vector3i(0, 0, 1), "-z": Vector3i(0, 0, -1),
}
const STAIRS_MATERIALS: Array[String] = ["stairs", "stairs_stone", "stairs_wood", "stairs_brick"]
const AXES: Dictionary = {"x": Vector3i(1, 0, 0), "y": Vector3i(0, 1, 0), "z": Vector3i(0, 0, 1)}
## What a button can switch.
const BUTTON_TARGETS: Array[Mechanism.Kind] = [
	Mechanism.Kind.SLIDER, Mechanism.Kind.ELEVATOR, Mechanism.Kind.ROTATOR, Mechanism.Kind.CONVEYOR,
]


static func load_file(path: String) -> LevelData:
	if not FileAccess.file_exists(path):
		var missing := LevelData.new()
		missing.source_path = path
		missing.errors.append("file not found")
		return missing
	return parse(FileAccess.get_file_as_string(path), path)


static func parse(text: String, source: String = "<text>") -> LevelData:
	var data := LevelData.new()
	data.source_path = source
	data.fingerprint = text.md5_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		data.errors.append("line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return data
	if typeof(json.data) != TYPE_DICTIONARY:
		data.errors.append("the top level must be an object")
		return data
	var root: Dictionary = json.data

	data.name = str(root.get("name", ""))
	if data.name.is_empty():
		data.errors.append("name: missing")
	data.world = _integer(root.get("world", 1), "world", data)
	data.palette = StringName(str(root.get("palette", Palette.DEFAULT_THEME)))
	if not Palette.THEMES.has(data.palette):
		data.errors.append("palette: unknown \"%s\" (use %s)" % [data.palette, ", ".join(Palette.THEMES.keys())])
	data.carry_limit = _integer(root.get("carry", 2 if data.world >= 3 else 1), "carry", data)

	for i in _array(root, "blocks", data).size():
		_read_block(root["blocks"][i], "blocks[%d]" % i, data)
	if data.cells.is_empty():
		data.errors.append("blocks: the level has no blocks")
	for i in _array(root, "props", data, false).size():
		_read_prop(root["props"][i], "props[%d]" % i, data)
	for i in _array(root, "mechanisms", data, false).size():
		_read_mechanism(root["mechanisms"][i], "mechanisms[%d]" % i, data)
	_check_mechanisms(data)
	for i in _array(root, "packages", data, false).size():
		data.packages.append(_read_item(root["packages"][i], "packages[%d]" % i, data))
	for i in _array(root, "pads", data, false).size():
		data.pads.append(_read_item(root["pads"][i], "pads[%d]" % i, data))
	data.start = _cell(root.get("start"), "start", data)
	data.exit = _cell(root.get("exit"), "exit", data)

	var stars: Array = _array(root, "stars", data)
	for i in stars.size():
		data.stars.append(_integer(stars[i], "stars[%d]" % i, data))
	if data.stars.size() != 3:
		data.errors.append("stars: needs three move limits (three, two and one star)")
	elif not (0 < data.stars[0] and data.stars[0] <= data.stars[1] and data.stars[1] <= data.stars[2]):
		data.errors.append("stars: limits must be positive and not decreasing")

	if data.is_valid():
		_check_layout(data)
	return data


## Semantic checks that need the whole level.
static func _check_layout(data: LevelData) -> void:
	var paths := Pathfinder.new(LevelState.new(data).build_grid())
	var moving: Dictionary = {}
	for mechanism: Mechanism in data.mechanisms:
		if mechanism.moves_blocks():
			for cell: Vector3i in mechanism.cells_at(mechanism.initial):
				moving[cell] = mechanism.id
	var taken: Dictionary = {}
	var spots: Array[Array] = [["start", data.start], ["exit", data.exit]]
	for i in data.packages.size():
		spots.append(["packages[%d]" % i, data.packages[i]["cell"]])
	for i in data.pads.size():
		spots.append(["pads[%d]" % i, data.pads[i]["cell"]])
	for mechanism: Mechanism in data.mechanisms:
		if mechanism.kind == Mechanism.Kind.BUTTON:
			spots.append(["button \"%s\"" % mechanism.id, mechanism.cells[0]])
	for spot: Array in spots:
		var cell: Vector3i = spot[1]
		if not paths.is_walkable(cell):
			data.errors.append("%s: %s is not a cell the courier can stand in" % [spot[0], cell])
		if spot[0] != "start" and taken.has(cell):
			data.errors.append("%s: %s is already used by %s" % [spot[0], cell, taken[cell]])
		taken[cell] = spot[0]
		# Parcels and the courier may ride moving parts; fixtures may not.
		var label: String = spot[0]
		if moving.has(cell - Vector3i.UP) and label != "start" and not label.begins_with("packages"):
			data.errors.append("%s: %s stands on mechanism \"%s\", which moves" % [label, cell, moving[cell - Vector3i.UP]])
		# Only the courier crosses ice, dry boards, thin ice and springs (it
		# may start on ice or a spring).
		var ground: StringName = data.cells.get(cell - Vector3i.UP, &"")
		if Grid.is_fragile(ground) or (ground in [Grid.ICE, Grid.SPRING] and label != "start"):
			data.errors.append("%s: %s is on %s, which only the courier may cross" % [label, cell, ground])

	# Every parcel needs exactly one pad of its colour.
	var parcels: Dictionary = {}
	var pads: Dictionary = {}
	for item: Dictionary in data.packages:
		parcels[item["color"]] = parcels.get(item["color"], 0) + 1
	for item: Dictionary in data.pads:
		pads[item["color"]] = pads.get(item["color"], 0) + 1
	for color: StringName in parcels.merged(pads):
		if parcels.get(color, 0) != pads.get(color, 0):
			data.errors.append("%s: %d parcel(s) but %d pad(s)" % [color, parcels.get(color, 0), pads.get(color, 0)])


static func _read_block(entry: Variant, where: String, data: LevelData) -> void:
	if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
		data.errors.append("%s: expected [x, y, z, type] or [x, y, z, \"stairs\", facing]" % where)
		return
	var cell: Vector3i = _cell(entry.slice(0, 3), where, data)
	var block_type := StringName(str(entry[3]))
	if Grid.is_stairs(block_type):
		if not STAIRS_MATERIALS.has(String(block_type)):
			data.errors.append("%s: unknown stairs \"%s\" (use %s)" % [where, block_type, ", ".join(STAIRS_MATERIALS)])
		var facing: String = str(entry[4]) if entry.size() > 4 else ""
		if not DIRECTIONS.has(facing):
			data.errors.append("%s: stairs need a facing (+x, -x, +z or -z), got \"%s\"" % [where, facing])
		else:
			data.facing[cell] = DIRECTIONS[facing]
	elif not Palette.BLOCK.has(block_type) and block_type != BlockMaterials.ACCENT:
		data.errors.append("%s: unknown block type \"%s\"" % [where, block_type])
	if data.cells.has(cell):
		data.errors.append("%s: %s already holds a block" % [where, cell])
	data.cells[cell] = block_type


static func _read_mechanism(entry: Variant, where: String, data: LevelData) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		data.errors.append("%s: expected an object with \"id\" and \"type\"" % where)
		return
	var mechanism := Mechanism.new()
	mechanism.id = str(entry.get("id", ""))
	if mechanism.id.is_empty():
		data.errors.append("%s.id: missing" % where)
	elif data.mechanisms.any(func(other: Mechanism) -> bool: return other.id == mechanism.id):
		data.errors.append("%s.id: \"%s\" is used twice" % [where, mechanism.id])
	where = "mechanism \"%s\"" % mechanism.id
	var type_name: String = str(entry.get("type", ""))
	if not Mechanism.KINDS.has(type_name):
		data.errors.append("%s: unknown type \"%s\" (use %s)" % [where, type_name, ", ".join(Mechanism.KINDS.keys())])
		return
	mechanism.kind = Mechanism.KINDS[type_name]

	match mechanism.kind:
		Mechanism.Kind.SLIDER:
			mechanism.cells = _cells(entry, "cells", where, data)
			var axis: String = str(entry.get("axis", ""))
			if not AXES.has(axis):
				data.errors.append("%s.axis: use x, y or z, got \"%s\"" % [where, axis])
			else:
				mechanism.axis = AXES[axis]
			mechanism.min_value = _integer(entry.get("min", 0), where + ".min", data)
			mechanism.max_value = _integer(entry.get("max", 0), where + ".max", data)
			mechanism.initial = _integer(entry.get("start", 0), where + ".start", data)
			if not (mechanism.min_value < mechanism.max_value
					and mechanism.min_value <= mechanism.initial and mechanism.initial <= mechanism.max_value):
				data.errors.append("%s: needs min < max with start (default 0) between them" % where)
		Mechanism.Kind.ELEVATOR:
			mechanism.cells = _cells(entry, "cells", where, data)
			mechanism.travel = _integer(entry.get("travel", 0), where + ".travel", data)
			if mechanism.travel < 1:
				data.errors.append("%s.travel: the height between its stops must be at least 1" % where)
			mechanism.initial = 1 if str(entry.get("start", "bottom")) == "top" else 0
		Mechanism.Kind.ROTATOR:
			mechanism.cells = _cells(entry, "cells", where, data)
			mechanism.pivot = _cell(entry.get("pivot"), where + ".pivot", data)
			mechanism.handle = _cell(entry.get("handle"), where + ".handle", data)
			mechanism.initial = posmod(_integer(entry.get("start", 0), where + ".start", data), 4)
			if data.cells.has(mechanism.handle):
				data.errors.append("%s.handle: %s already holds a block" % [where, mechanism.handle])
			data.cells[mechanism.handle] = &"crank"
		Mechanism.Kind.CONVEYOR:
			mechanism.cells = _cells(entry, "cells", where, data)
			var direction: String = str(entry.get("dir", ""))
			if not DIRECTIONS.has(direction):
				data.errors.append("%s.dir: use +x, -x, +z or -z, got \"%s\"" % [where, direction])
			else:
				mechanism.axis = DIRECTIONS[direction]
			mechanism.initial = 1 if entry.get("running", true) else 0
		Mechanism.Kind.BUTTON:
			mechanism.cells.append(_cell(entry.get("pos"), where + ".pos", data))
			mechanism.links = _names(entry, "targets", where, data)
			mechanism.initial = 1 if entry.get("on", false) else 0
		Mechanism.Kind.GATE:
			mechanism.cells = _cells(entry, "cells", where, data)
			mechanism.links = _names(entry, "buttons", where, data)
	data.mechanisms.append(mechanism)


## Cross-checks between mechanisms, and against the static blocks.
static func _check_mechanisms(data: LevelData) -> void:
	var by_id: Dictionary = {}
	for mechanism: Mechanism in data.mechanisms:
		by_id[mechanism.id] = mechanism
	var used: Dictionary = {}
	for mechanism: Mechanism in data.mechanisms:
		var where: String = "mechanism \"%s\"" % mechanism.id
		if mechanism.has_blocks():
			for cell: Vector3i in mechanism.cells_at(mechanism.initial):
				if data.cells.has(cell) or used.has(cell):
					data.errors.append("%s: block %s overlaps %s" % [where, cell, used.get(cell, "a level block")])
				used[cell] = where
		if mechanism.kind == Mechanism.Kind.BUTTON:
			for target: String in mechanism.links:
				if not by_id.has(target):
					data.errors.append("%s.targets: no mechanism \"%s\"" % [where, target])
				elif not BUTTON_TARGETS.has((by_id[target] as Mechanism).kind):
					data.errors.append("%s.targets: \"%s\" cannot be switched by a button" % [where, target])
		if mechanism.kind == Mechanism.Kind.GATE:
			if mechanism.links.is_empty():
				data.errors.append("%s.buttons: a gate needs at least one button" % where)
			for button: String in mechanism.links:
				if not by_id.has(button) or (by_id[button] as Mechanism).kind != Mechanism.Kind.BUTTON:
					data.errors.append("%s.buttons: \"%s\" is not a button" % [where, button])
		if mechanism.kind == Mechanism.Kind.CONVEYOR and mechanism.axis != Vector3i.ZERO:
			# A belt is one straight run along its direction.
			var along: Array[int] = []
			for cell: Vector3i in mechanism.cells:
				along.append(cell.x * mechanism.axis.x + cell.z * mechanism.axis.z)
				var across: Vector3i = cell - mechanism.axis * along[-1]
				if across != mechanism.cells[0] - mechanism.axis * along[0]:
					data.errors.append("%s: belt cells must lie in one straight line along its direction" % where)
					break
			along.sort()
			for i in range(1, along.size()):
				if along[i] != along[i - 1] + 1:
					data.errors.append("%s: belt cells must be contiguous" % where)
					break


static func _cells(entry: Dictionary, key: String, where: String, data: LevelData) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var value: Variant = entry.get(key)
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		data.errors.append("%s.%s: expected a list of [x, y, z]" % [where, key])
		return result
	for i in value.size():
		result.append(_cell(value[i], "%s.%s[%d]" % [where, key, i], data))
	return result


static func _names(entry: Dictionary, key: String, where: String, data: LevelData) -> Array[String]:
	var result: Array[String] = []
	var value: Variant = entry.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		data.errors.append("%s.%s: expected a list of mechanism ids" % [where, key])
		return result
	for name: Variant in value:
		result.append(str(name))
	return result


static func _read_prop(entry: Variant, where: String, data: LevelData) -> void:
	if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
		data.errors.append("%s: expected [x, y, z, type, rotation?, solid?]" % where)
		return
	var prop_type := StringName(str(entry[3]))
	if not PropFactory.TYPES.has(prop_type):
		data.errors.append("%s: unknown prop \"%s\" (use %s)" % [where, prop_type, ", ".join(PropFactory.TYPES)])
	data.props.append({
		"cell": _cell(entry.slice(0, 3), where, data),
		"type": prop_type,
		"rotation": float(entry[4]) if entry.size() > 4 else 0.0,
		"solid": bool(entry[5]) if entry.size() > 5 else false,
	})


static func _read_item(entry: Variant, where: String, data: LevelData) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		data.errors.append("%s: expected {\"pos\": [x, y, z], \"color\": ...}" % where)
		return {"cell": Vector3i.ZERO, "color": &"red"}
	var color := StringName(str(entry.get("color", "")))
	if not Palette.PACKAGE.has(color):
		data.errors.append("%s: unknown color \"%s\" (use %s)" % [where, color, ", ".join(Palette.PACKAGE.keys())])
	return {"cell": _cell(entry.get("pos"), where + ".pos", data), "color": color}


static func _array(root: Dictionary, key: String, data: LevelData, required: bool = true) -> Array:
	var value: Variant = root.get(key)
	if value == null:
		if required:
			data.errors.append("%s: missing" % key)
		return []
	if typeof(value) != TYPE_ARRAY:
		data.errors.append("%s: expected a list" % key)
		return []
	return value


static func _cell(value: Variant, where: String, data: LevelData) -> Vector3i:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		data.errors.append("%s: expected [x, y, z]" % where)
		return Vector3i.ZERO
	return Vector3i(_integer(value[0], where, data), _integer(value[1], where, data), _integer(value[2], where, data))


static func _integer(value: Variant, where: String, data: LevelData) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)):
		return int(value)
	data.errors.append("%s: expected a whole number, got %s" % [where, value])
	return 0
