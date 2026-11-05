class_name LevelCatalog
extends RefCounted
## The game's levels in play order: res://levels/world_<w>/level_<n>.json,
## worlds by number, then levels by number. Gaps are allowed; files that do
## not follow the naming are ignored.

const ROOT: String = "res://levels"
## What each world is called on the menus.
const WORLD_NAMES: Dictionary = {
	1: "Meadow", 2: "Harbour", 3: "Old Town", 4: "Orchard", 5: "Frost Peaks", 6: "Blossom Valley",
	7: "Sunflower Fields",
}

## Each world's level paths in order, by world number (lowest first), listed
## from the folders once: on Android every file a listing passes is a call
## into Java, and the menus ask for the levels again for every level card.
static var _listing: Dictionary = {}
## Level names by path, for the level map and the level cards.
static var _names: Dictionary = {}


static func world_name(world: int) -> String:
	return WORLD_NAMES.get(world, "World %d" % world)


## The world [param path] belongs to (0 outside the catalog's folders).
static func world_of(path: String) -> int:
	return _number(path.get_base_dir().get_file(), "world_", "")


## [param path]'s number in its world, from its file name (0 if it is not
## named level_<n>.json).
static func number_of(path: String) -> int:
	return _number(path.get_file(), "level_", ".json")


## Whether [param path] can be played: the very first level always, every
## other once the level before it is finished. A level at or before one
## already finished stays open too, so new levels put in ahead of a player
## never lock what they have reached.
static func is_unlocked(path: String) -> bool:
	var index: int = all().find(path)
	return index <= 0 or index < open_count()


## How many levels can be played, counted from the first in play order: all
## of them up to one past the furthest finished.
static func open_count() -> int:
	var order: Array[String] = all()
	for i in range(order.size() - 1, -1, -1):
		if not Progress.best(Progress.level_id(order[i])).is_empty():
			return mini(i + 2, order.size())
	return mini(1, order.size())


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
	result.assign(_listed().keys())
	return result


## Paths of world [param world]'s levels, by number.
static func levels(world: int) -> Array[String]:
	var result: Array[String] = []
	result.assign(_listed().get(world, []))
	return result


## Every level path, in play order.
static func all() -> Array[String]:
	var result: Array[String] = []
	for paths: Array in _listed().values():
		result.append_array(paths)
	return result


## The name of the level at [param path], read from its file the first time.
static func name_of(path: String) -> String:
	if not _names.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_names[path] = str((parsed as Dictionary).get("name", "")) if parsed is Dictionary else ""
	return _names[path]


## The level played after [param path] ("" after the last one, or for a
## level outside the catalog).
static func next_after(path: String) -> String:
	var order: Array[String] = all()
	var index: int = order.find(path)
	return order[index + 1] if index >= 0 and index + 1 < order.size() else ""


## [member _listing], read from the folders the first time.
static func _listed() -> Dictionary:
	if not _listing.is_empty():
		return _listing
	var worlds_found: Array[int] = []
	for folder: String in DirAccess.get_directories_at(ROOT):
		var number: int = _number(folder, "world_", "")
		if number > 0:
			worlds_found.append(number)
	worlds_found.sort()
	for world: int in worlds_found:
		var folder: String = ROOT.path_join("world_%d" % world)
		var numbers: Array[int] = []
		for file: String in DirAccess.get_files_at(folder):
			var number: int = _number(file, "level_", ".json")
			if number > 0:
				numbers.append(number)
		if numbers.is_empty():
			continue
		numbers.sort()
		var paths: Array[String] = []
		for number: int in numbers:
			paths.append(folder.path_join("level_%d.json" % number))
		_listing[world] = paths
	return _listing


## The number in "<prefix><number><suffix>", or 0 if [param name] is not
## named that way.
static func _number(name: String, prefix: String, suffix: String) -> int:
	if not name.begins_with(prefix) or not name.ends_with(suffix):
		return 0
	var digits: String = name.trim_prefix(prefix).trim_suffix(suffix)
	return digits.to_int() if digits.is_valid_int() else 0
