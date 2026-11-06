class_name Progress
extends RefCounted
## Saved progress: the best stars and moves for each level, and the level in
## progress so a closed app picks up where it left off. Kept as JSON in
## user://progress.json, written whole to a temporary file and then moved
## into place so a crash mid-write never loses it.
##
## Levels are named by their path under res://levels/ without the
## extension, e.g. "world_1/level_1". Everything is static; the file is read
## on first use.

const VERSION: int = 3
const DEFAULT_PATH: String = "user://progress.json"
## Saves before version 2 had world 1 as ten levels, which are now the
## openers of its ten chapters, at these numbers.
const WORLD_1_V1: Array[int] = [1, 4, 8, 12, 16, 21, 37, 53, 69, 85]
## Saves before version 3 had Frost Peaks as world 5, before Blossom Valley
## (6) and Sunflower Fields (7). Frost Peaks is now the last world, rebuilt
## with new levels, so what was saved for its old ones is dropped (""). Old
## world folder -> new.
const WORLDS_V2: Dictionary = {"world_5": "", "world_6": "world_5", "world_7": "world_6"}

static var path: String = DEFAULT_PATH

## id -> {"stars": int, "moves": int}
static var _levels: Dictionary = {}
## {"level": id, "fingerprint": String, "history": [snapshot json], "state": snapshot json}
static var _resume: Dictionary = {}
static var _loaded: bool = false


## Switches to another save file (tests use their own); with [param fresh]
## it starts empty and deletes what was there.
static func use_file(file_path: String, fresh: bool = true) -> void:
	path = file_path
	if fresh:
		_levels.clear()
		_resume.clear()
		_loaded = true
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		load_file()


static func level_id(level_path: String) -> String:
	return level_path.trim_prefix("res://levels/").get_basename()


## {"stars": int, "moves": int} for the best finish of [param id], or an
## empty Dictionary if it has never been finished.
static func best(id: String) -> Dictionary:
	_load_once()
	return _levels.get(id, {})


static func total_stars() -> int:
	_load_once()
	var total: int = 0
	for id: String in _levels:
		total += _levels[id]["stars"]
	return total


## Records a finish and saves. Returns true when it beats the best so far
## (more stars, or as many in fewer moves).
static func record(id: String, moves: int, stars: int) -> bool:
	_load_once()
	var previous: Dictionary = best(id)
	var better: bool = previous.is_empty() or stars > previous["stars"] \
			or (stars == previous["stars"] and moves < previous["moves"])
	if better:
		_levels[id] = {"stars": stars, "moves": moves}
	if _resume.get("level") == id:
		_resume.clear()
	save()
	return better


## Keeps [param id]'s game in progress: the undo [param history] and the
## current [param state], both as LevelState snapshots.
static func keep_in_progress(id: String, fingerprint: String, history: Array[Dictionary], state: Dictionary) -> void:
	_load_once()
	var saved_history: Array = []
	for snapshot: Dictionary in history:
		saved_history.append(LevelState.snapshot_to_json(snapshot))
	_resume = {
		"level": id, "fingerprint": fingerprint, "history": saved_history,
		"state": LevelState.snapshot_to_json(state),
	}
	save()


## Forgets the game in progress if it is [param id]'s.
static func drop_in_progress(id: String) -> void:
	_load_once()
	if _resume.get("level") == id:
		_resume.clear()
		save()


## The game in progress for [param id] as {"history": [snapshot], "state":
## snapshot}, decoded against [param state]'s level; empty when there is none
## for this version of the level or it no longer fits.
static func in_progress(id: String, fingerprint: String, state: LevelState) -> Dictionary:
	_load_once()
	if _resume.get("level") != id or _resume.get("fingerprint") != fingerprint:
		return {}
	var current: Dictionary = state.snapshot_from_json(_resume.get("state"))
	if current.is_empty() or current["completed"]:
		return {}
	var history: Array[Dictionary] = []
	var saved_history: Variant = _resume.get("history")
	if typeof(saved_history) != TYPE_ARRAY:
		return {}
	for entry: Variant in saved_history:
		var snapshot: Dictionary = state.snapshot_from_json(entry)
		if snapshot.is_empty():
			return {}
		history.append(snapshot)
	return {"history": history, "state": current}


static func save() -> void:
	var text: String = JSON.stringify({"version": VERSION, "levels": _levels, "in_progress": _resume}, "\t")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Progress: cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	file.close()
	var error: Error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		push_warning("Progress: cannot replace %s (%s)" % [path, error_string(error)])


## Reads the save file, moving an older one's levels to where they are now.
## A file that cannot be read is kept as .bad and progress starts empty.
static func load_file() -> void:
	_loaded = true
	_levels.clear()
	_resume.clear()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("levels")) != TYPE_DICTIONARY:
		push_warning("Progress: %s is unreadable (%s); starting afresh (kept as .bad)"
			% [path, json.get_error_message() if parsed == null else "not a save file"])
		DirAccess.rename_absolute(path, path + ".bad")
		return
	for id: Variant in parsed["levels"]:
		var entry: Variant = parsed["levels"][id]
		if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("stars")) in [TYPE_INT, TYPE_FLOAT] \
				and typeof(entry.get("moves")) in [TYPE_INT, TYPE_FLOAT]:
			_levels[str(id)] = {"stars": clampi(int(entry["stars"]), 0, 3), "moves": int(entry["moves"])}
	if typeof(parsed.get("in_progress")) == TYPE_DICTIONARY:
		_resume = parsed["in_progress"]
	var version: int = int(parsed["version"]) if typeof(parsed.get("version")) in [TYPE_INT, TYPE_FLOAT] else 1
	if version < 2:
		_move_ids(_v1_id)
	if version < 3:
		_move_ids(_v2_id)


## Renames every saved level id (and the game in progress) by [param rename],
## dropping those it renames to "".
static func _move_ids(rename: Callable) -> void:
	var moved: Dictionary = {}
	for id: String in _levels:
		var to: String = rename.call(id)
		if not to.is_empty():
			moved[to] = _levels[id]
	_levels = moved
	if _resume.has("level"):
		var to: String = rename.call(str(_resume["level"]))
		if to.is_empty():
			_resume.clear()
		else:
			_resume["level"] = to


## Where version 1's [param id] is now (see [constant WORLD_1_V1]).
static func _v1_id(id: String) -> String:
	var number: int = id.trim_prefix("world_1/level_").to_int() if id.begins_with("world_1/level_") else 0
	return "world_1/level_%d" % WORLD_1_V1[number - 1] if number >= 1 and number <= WORLD_1_V1.size() else id


## Where version 2's [param id] is now, or "" if it is gone (see
## [constant WORLDS_V2]).
static func _v2_id(id: String) -> String:
	var folder: String = id.get_slice("/", 0)
	if not WORLDS_V2.has(folder):
		return id
	var to: String = WORLDS_V2[folder]
	return "" if to.is_empty() else to + id.trim_prefix(folder)


static func _load_once() -> void:
	if not _loaded:
		load_file()
