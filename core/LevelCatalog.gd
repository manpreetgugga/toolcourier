class_name LevelCatalog
extends RefCounted
## The game's levels in play order: res://levels/world_<w>/level_<n>.json,
## worlds by number, then levels by number. Gaps are allowed; files that do
## not follow the naming are ignored.

const ROOT: String = "res://levels"


## World numbers that have levels, lowest first.
static func worlds() -> Array[int]:
	var result: Array[int] = []
	for folder: String in DirAccess.get_directories_at(ROOT):
		var number: int = _number(folder, "world_", "")
		if number > 0 and not levels(number).is_empty():
			result.append(number)
	result.sort()
	return result


## Paths of world [param world]'s levels, by number.
static func levels(world: int) -> Array[String]:
	var folder: String = ROOT.path_join("world_%d" % world)
	var numbers: Array[int] = []
	for file: String in DirAccess.get_files_at(folder):
		var number: int = _number(file, "level_", ".json")
		if number > 0:
			numbers.append(number)
	numbers.sort()
	var result: Array[String] = []
	for number: int in numbers:
		result.append(folder.path_join("level_%d.json" % number))
	return result


## Every level path, in play order.
static func all() -> Array[String]:
	var result: Array[String] = []
	for world: int in worlds():
		result.append_array(levels(world))
	return result


## The level played after [param path] ("" after the last one, or for a
## level outside the catalog).
static func next_after(path: String) -> String:
	var order: Array[String] = all()
	var index: int = order.find(path)
	return order[index + 1] if index >= 0 and index + 1 < order.size() else ""


## The number in "<prefix><number><suffix>", or 0 if [param name] is not
## named that way.
static func _number(name: String, prefix: String, suffix: String) -> int:
	if not name.begins_with(prefix) or not name.ends_with(suffix):
		return 0
	var digits: String = name.trim_prefix(prefix).trim_suffix(suffix)
	return digits.to_int() if digits.is_valid_int() else 0
