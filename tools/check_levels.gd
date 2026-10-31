extends SceneTree
## Checks levels without a window: loads each one, solves it with the Solver
## and compares the fewest moves with its three-star limit. Prints a line per
## level and any problems, and exits with status 1 if a level is broken,
## cannot be finished, or has a three-star limit other than its best.
## Warnings (a level the hint search finds slow, a world folder that does
## not match the file) do not fail the run.
##
##   godot --headless --path . -s res://tools/check_levels.gd
##   godot --headless --path . -s res://tools/check_levels.gd -- --plan res://levels/world_2/level_3.json
##   godot --headless --path . -s res://tools/check_levels.gd -- --fix-stars
##
## Without paths it checks every level in LevelCatalog order. --plan prints
## each level's shortest solution; --fix-stars rewrites each checked level's
## "stars" to [method suggested_stars].

## States a search from the start may look at before a level counts as slow
## for hints (they have to answer quickly on a phone).
const STATE_BUDGET: int = 5000

var _errors: int = 0
var _warnings: int = 0


func _initialize() -> void:
	var show_plan: bool = false
	var fix_stars: bool = false
	var paths: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--plan":
			show_plan = true
		elif arg == "--fix-stars":
			fix_stars = true
		else:
			paths.append(arg if arg.begins_with("res://") else "res://" + arg.trim_prefix("./"))
	if paths.is_empty():
		paths = LevelCatalog.all()
	var palettes: Dictionary = {}
	var started: int = Time.get_ticks_msec()
	for path: String in paths:
		_check(path, show_plan, fix_stars, palettes)
	print("%d level(s) checked in %.1f s: %d problem(s), %d warning(s)"
		% [paths.size(), (Time.get_ticks_msec() - started) / 1000.0, _errors, _warnings])
	quit(1 if _errors > 0 else 0)


## Three-, two- and one-star limits for a level whose fewest moves is
## [param best].
static func suggested_stars(best: int) -> Array[int]:
	return [best, best + maxi(2, roundi(best * 0.25)), best + maxi(4, roundi(best * 0.6))]


func _check(path: String, show_plan: bool, fix_stars: bool, palettes: Dictionary) -> void:
	var label: String = path.trim_prefix(LevelCatalog.ROOT + "/").get_basename()
	var data: LevelData = LevelLoader.load_file(path)
	if not data.is_valid():
		print("%-18s BROKEN" % label)
		for problem: String in data.errors:
			_problem(problem)
		return
	var solver := Solver.new(data)
	var timer: int = Time.get_ticks_usec()
	var plan: Array[Dictionary] = solver.solve(LevelState.new(data).snapshot())
	var ms: float = (Time.get_ticks_usec() - timer) / 1000.0
	var best: int = plan[-1]["moves"] if not plan.is_empty() else -1
	var works: int = plan.filter(func(action: Dictionary) -> bool: return action["action"] != Solver.Action.STEP).size()
	print("%-18s %-24s best %3s  stars %2d %2d %2d  parcels %d  works %d  states %5d  %6.1f ms"
		% [label, "\"%s\"" % data.name, str(best) if best >= 0 else "-", data.stars[0], data.stars[1], data.stars[2],
			data.packages.size(), works, solver.explored, ms])

	if plan.is_empty():
		_problem("gave up after %d states" % solver.explored if solver.gave_up else "cannot be finished")
		return
	if data.stars[0] != best:
		_problem("three-star limit is %d but the best is %d moves%s" % [data.stars[0], best,
			"" if fix_stars else " (--fix-stars sets %s)" % [suggested_stars(best)]])
	if solver.explored > STATE_BUDGET:
		_warning("%d states: hints may be slow on a phone (budget %d)" % [solver.explored, STATE_BUDGET])
	var folder: String = path.get_base_dir().get_file()
	if folder.begins_with("world_") and folder.trim_prefix("world_").to_int() != data.world:
		_warning("\"world\" is %d but the file is in %s" % [data.world, folder])
	if palettes.has(data.world) and palettes[data.world] != data.palette:
		_warning("palette \"%s\" differs from \"%s\" used earlier in world %d" % [data.palette, palettes[data.world], data.world])
	palettes[data.world] = data.palette
	if show_plan:
		print("    " + " ".join(_describe(plan)))
	if fix_stars:
		_write_stars(path, suggested_stars(best))


func _write_stars(path: String, stars: Array[int]) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var pattern := RegEx.create_from_string("\"stars\"\\s*:\\s*\\[[^\\]]*\\]")
	var fixed: String = pattern.sub(text, "\"stars\": [%d, %d, %d]" % stars)
	if fixed == text:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(fixed)
	file.close()
	print("    stars set to %s" % [stars])


static func _describe(plan: Array[Dictionary]) -> PackedStringArray:
	var steps := PackedStringArray()
	for action: Dictionary in plan:
		match action["action"]:
			Solver.Action.STEP:
				var cell: Vector3i = action["cell"]
				steps.append("%s%d,%d,%d%s" % ["~" if action["ride"] else "", cell.x, cell.y, cell.z, "*" if action["events"] else ""])
			Solver.Action.SLIDE:
				steps.append("[slide %s to %d]" % [action["id"], action["to"]])
			Solver.Action.TURN:
				steps.append("[turn %s]" % action["id"])
	return steps


func _problem(text: String) -> void:
	print("    PROBLEM  " + text)
	_errors += 1


func _warning(text: String) -> void:
	print("    warning  " + text)
	_warnings += 1
