extends SceneTree
## Renders the app icon from the game itself: the courier, its flag up, on a
## little grass island (dev/icon_level.json) against the meadow sky. Writes
## four 1024 px images into res://icons/:
##
##   icon.png             the whole picture (project and launcher icon)
##   icon_foreground.png  the courier and island on transparent, kept inside
##                        the middle two thirds an adaptive icon always shows
##   icon_background.png  the sky alone, behind the foreground
##   icon_monochrome.png  the courier as a white silhouette (themed icons)
##
## Needs a renderer (not --headless):
##   godot --path . -s res://tools/make_icon.gd

const SIZE: int = 1024
const LEVEL: String = "res://dev/icon_level.json"
const OUT: String = "res://icons"
## Where the camera looks from (towards the courier) and how far away.
const VIEW := Vector3(-0.42, 0.3, 1.0)
const DISTANCE: float = 2.2
## An adaptive icon's mask keeps at least the middle 72 of its 108 dp.
const SAFE_ZONE: float = 72.0 / 108.0

var _viewport: SubViewport
var _level: Level
var _camera: Camera3D


func _initialize() -> void:
	Settings.use_file("user://test_settings.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.msaa_3d = Viewport.MSAA_8X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	_level.level_path = LEVEL
	_level.show_hud = false
	_level.interactive = false
	_viewport.add_child(_level)
	_run()


func _run() -> void:
	await _frames(10)
	_level._exit.visible = false
	for particles: Node in _level.find_children("*", "CPUParticles3D", true, false):
		(particles as Node3D).visible = false
	var courier: Courier = _level.courier
	courier.set_carried([&"red"])
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.attributes = CameraAttributesPractical.new()
	_level.add_child(_camera)
	_camera.make_current()

	_aim(DISTANCE)
	await _save("icon.png")

	var shown: Dictionary = {}
	var shapes: Array[Node] = _level.find_children("*", "GeometryInstance3D", true, false)
	for shape: Node in shapes:
		shown[shape] = (shape as Node3D).visible
		(shape as Node3D).visible = false
	await _save("icon_background.png")
	for shape: Node in shapes:
		(shape as Node3D).visible = shown[shape]

	_level._stage.environment.background_mode = Environment.BG_CLEAR_COLOR
	_viewport.transparent_bg = true
	_aim(DISTANCE / SAFE_ZONE * 0.92)
	await _save("icon_foreground.png")

	# Android 13's themed icons: the courier alone, as a white silhouette.
	for shape: Node in shapes:
		(shape as Node3D).visible = courier.is_ancestor_of(shape) and shape.name != &"BlobShadow"
	await _save("icon_monochrome.png", true)
	quit()


## Points the camera at the courier from [param distance] away.
func _aim(distance: float) -> void:
	var target: Vector3 = _level.courier.global_position + Vector3(0.0, 0.3, 0.0)
	_camera.global_position = target + VIEW.normalized() * distance
	_camera.look_at(target)


## Saves the picture; a [param silhouette] keeps only its shape, in white.
func _save(file_name: String, silhouette: bool = false) -> void:
	# No blink in the picture.
	_level.courier._blink_in = 100.0
	await _frames(30)
	var path: String = ProjectSettings.globalize_path(OUT.path_join(file_name))
	var image: Image = _viewport.get_texture().get_image()
	if silhouette:
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, image.get_pixel(x, y).a))
	var error: Error = image.save_png(path)
	print("%s: %s" % [path, error_string(error)])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
