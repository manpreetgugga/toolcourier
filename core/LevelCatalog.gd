class_name LevelCatalog
extends RefCounted
## The game's levels in play order: res://levels/world_<w>/level_<n>.json,
## worlds by number, then levels by number. Gaps are allowed; files that do
## not follow the naming are ignored.

const ROOT: String = "res://levels"
## What each world is called on the menus.
const WORLD_NAMES: Dictionary = {1: "Meadow", 2: "Harbour", 3: "Old Town", 4: "Orchard", 5: "Frost Peaks"}


static func world_name(world: int) -> String:
	return WORLD_NAMES.get(world, "World %d" % world)


## The world [param path] belongs to (0 outside the catalog's folders).
static func world_of(path: String) -> int:
	return _number(path.get_base_dir().get_file(), "world_", "")


## Whether [param path] can be played: the very first level always, every
## other once the level before it is finished.
static func is_unlocked(path: String) -> bool:
	var order: Array[String] = all()
	var index: int = order.find(path)
	if index <= 0:
		return true
	return not Progress.best(Progress.level_id(order[index - 1])).is_empty()


## The level to play next: the first one not finished yet that is open, or
## the last level once all are done.
static func next_to_play() -> String:
	var order: Array[String] = all()
	for path: String in order:
		if Progress.best(Progress.level_id(path)).is_empty():
			return path if is_unlocked(path) else order[0]
	return order[-1] if not order.is_empty() else ""


## Stars earned in world [param world], and how many it has to give.
static func world_stars(world: int) -> Vector2i:
	var earned: int = 0
	var paths: Array[String] = levels(world)
	for path: String in paths:
		earned += int(Progress.best(Progress.level_id(path)).get("stars", 0))
	return Vector2i(earned, paths.size() * 3)


## How many of world [param world]'s levels are finished.
static func world_finished(world: int) -> int:
	var count: int = 0
	for path: String in levels(world):
		if not Progress.best(Progress.level_id(path)).is_empty():
			count += 1
	return count


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
