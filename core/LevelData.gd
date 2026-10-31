class_name LevelData
extends RefCounted
## One level as read from JSON by LevelLoader. Positions of the start, exit,
## parcels and pads are standing cells (the empty cell the courier occupies,
## above the block it stands on).

var source_path: String = ""
var name: String = ""
var world: int = 1
var palette: StringName = Palette.DEFAULT_THEME
## Vector3i -> block type, for blocks that never move (mechanisms' blocks are
## kept in their Mechanism; rotator cranks are static "crank" cells here).
var cells: Dictionary = {}
## Vector3i -> Vector3i facing of oriented blocks (stairs).
var facing: Dictionary = {}
## {"cell": Vector3i, "type": StringName, "rotation": float (degrees), "solid": bool}
var props: Array[Dictionary] = []
var mechanisms: Array[Mechanism] = []
## {"cell": Vector3i, "color": StringName}
var packages: Array[Dictionary] = []
var pads: Array[Dictionary] = []
var start: Vector3i
var exit: Vector3i
## Move limits for three, two and one star.
var stars: Array[int] = []
## Parcels the courier can carry at once.
var carry_limit: int = 1
## Everything wrong with the file; the level is unusable unless empty.
var errors: PackedStringArray = []


func is_valid() -> bool:
	return errors.is_empty()


## 3, 2 or 1 star for finishing in [param moves]; 0 beyond the last limit.
func stars_for(moves: int) -> int:
	for i in stars.size():
		if moves <= stars[i]:
			return 3 - i
	return 0
