class_name Game
extends RefCounted
## Moves the game between the menu and the levels: a soft cream veil fades
## in, the scene is swapped under it, and the veil fades away once the new
## scene has drawn. Remembers where the menu should open and whether the
## splash has played this launch. Everything is static.
##
##   Game.open_level("res://levels/world_1/level_3.json")
##   Game.open_menu(&"levels", 1)

const MENU: String = "res://ui/Menu.tscn"
const LEVEL: String = "res://game/Level.tscn"
const FADE: float = 0.22

## The screen the menu opens on next ("main", "worlds" or "levels") and the
## world it shows (0 for the world of the next level to play).
static var menu_screen: StringName = &"main"
static var menu_world: int = 0
## The splash plays once per launch.
static var splash_done: bool = false

static var _veil: ColorRect
static var _swapping: bool = false


## Opens the level at [param path], building itself up.
static func open_level(path: String) -> void:
	_swap(func() -> Node:
		var level: Level = (load(LEVEL) as PackedScene).instantiate()
		level.level_path = path
		level.intro = true
		return level)


## Opens the menu on [param screen], showing world [param world].
static func open_menu(screen: StringName = &"main", world: int = 0) -> void:
	menu_screen = screen
	menu_world = world
	_swap(func() -> Node: return (load(MENU) as PackedScene).instantiate())


## Whether a swap of scene is under way.
static func is_swapping() -> bool:
	return _swapping


static func _swap(make: Callable) -> void:
	if _swapping:
		return
	_swapping = true
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	var veil: ColorRect = _veil_in(tree)
	veil.visible = true
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.modulate.a = 0.0
	var tween: Tween = veil.create_tween()
	tween.tween_property(veil, "modulate:a", 1.0, FADE)
	await tween.finished
	var old: Node = tree.current_scene
	var scene: Node = make.call()
	if old:
		old.queue_free()
	tree.root.add_child(scene)
	tree.current_scene = scene
	# Let the new scene draw (and its shaders settle) under the veil.
	await tree.process_frame
	await tree.process_frame
	tween = veil.create_tween()
	tween.tween_property(veil, "modulate:a", 0.0, FADE * 1.6)
	await tween.finished
	veil.visible = false
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swapping = false


## The veil, on a layer over everything that outlives the scenes.
static func _veil_in(tree: SceneTree) -> ColorRect:
	if is_instance_valid(_veil):
		return _veil
	var layer := CanvasLayer.new()
	layer.name = "Veil"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.color = Ui.CREAM
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.visible = false
	layer.add_child(_veil)
	return _veil
