extends SceneTree
## Makes the Play Store's phone screenshots (docs/store/screenshots/): a scene
## of the game at phone size, under a caption in the game's own font, on the
## cream and orange of its cards. 1080 x 1920 each, which Play takes as
## phone screenshots (9:16, at least 1080 pixels on the short side).
##
## Needs a real renderer and a 1080 x 1920 window, so that the interface is
## laid out in the 720 x 1280 base viewport and drawn sharp at that size:
##   godot --path . --rendering-method mobile --resolution 1080x1920 \
##       -s res://tools/store_screenshots.gd
## On a server, under Xvfb with a screen at least that big:
##   xvfb-run -s "-screen 0 1080x1920x24" godot ...
## --only=<name> makes just that one (e.g. --only=3_mechanisms); --out=<dir>
## writes elsewhere. Captions are in [constant SHOTS]; keep them in step with
## docs/store/listing.md.

const SIZE := Vector2i(1080, 1920)
const OUT: String = "res://docs/store/screenshots"
## In the 720 x 1280 base viewport: the caption's band at the top, and the
## screenshot under it, scaled to fit.
const CAPTION_TOP: float = 52.0
const CAPTION_HEIGHT: float = 170.0
const PICTURE_TOP: float = 250.0
const PICTURE_BOTTOM: float = 1240.0
const PICTURE_RADIUS: float = 34.0
const BACKGROUND_TOP := Color("#FFF1DC")
const BACKGROUND_BOTTOM := Color("#F6C88E")

## name: the file (docs/store/screenshots/<name>.png); caption: up to two
## lines; level: the level shown; yaw: radians turned from its first view;
## zoom: the camera's zoom (1 = as it opens); action: "walkthrough" (the
## first level's walkthrough, on its second step), "hint" (Hint pressed),
## "finish" (the finish card, on three stars) or "worlds" (the world
## select). Every level is open (Settings.explore), so a finish card offers
## Next.
const SHOTS: Array[Dictionary] = [
	{"name": "1_calm", "caption": "A calm puzzle game on\nfloating clay islands",
		"level": "res://levels/world_6/level_5.json", "yaw": 0.0, "zoom": 1.0},
	{"name": "2_walkthrough", "caption": "Learn as you play,\none step at a time",
		"level": "res://levels/world_1/level_1.json", "action": "walkthrough"},
	{"name": "3_mechanisms", "caption": "Slide bridges, ride lifts\nand open gates",
		"level": "res://levels/world_5/level_30.json", "yaw": 0.0, "zoom": 1.5},
	{"name": "4_hint", "caption": "Stuck? A hint shows\nthe next step",
		"level": "res://levels/world_3/level_10.json", "action": "hint"},
	{"name": "5_symbols", "caption": "Every parcel has a colour\nand a symbol to match",
		"level": "res://levels/world_2/level_40.json", "yaw": 0.0, "zoom": 2.2},
	{"name": "6_worlds", "caption": "460 levels across\nseven worlds", "action": "worlds"},
	{"name": "7_stars", "caption": "No timers, no lives:\njust stars to earn",
		"level": "res://levels/world_4/level_20.json", "action": "finish"},
]

var _out: String = OUT
var _only: String = ""
var _failures: int = 0


func _initialize() -> void:
	# The game as a new player sees it, at its best quality, with no ads.
	Settings.use_file("user://store_screenshots_settings.json")
	Settings.set_value(&"quality", Settings.Quality.HIGH)
	Settings.set_value(&"walkthrough_done", true)
	Settings.set_value(&"explore", true)
	Progress.use_file("user://store_screenshots_progress.json")
	Ads.enabled = false
	Game.splash_done = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_out = ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _run() -> void:
	await _wait(0.2)
	if root.size != SIZE:
		push_error("store_screenshots: the window is %s, not %s; run with --resolution 1080x1920" % [root.size, SIZE])
		quit(1)
		return
	for shot: Dictionary in SHOTS:
		if not _only.is_empty() and shot["name"] != _only:
			continue
		var picture: Image = await _scene(shot)
		if picture == null:
			_failures += 1
			continue
		await _compose(shot, picture)
	quit(1 if _failures > 0 else 0)


## Sets up [param shot]'s scene as the current scene and returns what the
## window shows once it has settled.
func _scene(shot: Dictionary) -> Image:
	var action: String = shot.get("action", "")
	if action == "worlds":
		# A player some way in: Meadow done, Harbour started.
		Progress.use_file("user://store_screenshots_progress.json")
		for path: String in LevelCatalog.levels(1):
			Progress.record(Progress.level_id(path), 1, 3)
		for path: String in LevelCatalog.levels(2).slice(0, 24):
			Progress.record(Progress.level_id(path), 1, 3)
		Game.menu_screen = &"worlds"
		change_scene_to_file("res://ui/Menu.tscn")
		await _wait(4.0)
		var picture: Image = root.get_texture().get_image()
		Progress.use_file("user://store_screenshots_progress.json")
		return picture

	if action == "walkthrough":
		Progress.use_file("user://store_screenshots_progress.json")
		Settings.set_value(&"walkthrough_done", false)
	var level: Level = (load("res://game/Level.tscn") as PackedScene).instantiate()
	level.level_path = shot["level"]
	change_scene_to_node(level)
	await _wait(1.0)
	if not is_instance_valid(level) or level.state == null:
		push_error("store_screenshots: %s did not load" % shot["level"])
		return null
	level.camera._target_yaw += float(shot.get("yaw", 0.0))
	level.camera._target_zoom = float(shot.get("zoom", 1.0))
	match action:
		"walkthrough":
			level.camera._target_yaw += 0.7
			await _wait(1.5)
		"hint":
			await _wait(1.0)
			level.hud._on_hint()
		"finish":
			var moves: int = level.data.stars[0]
			level.state.moves = moves
			level.hud._on_moves_changed(moves, false)
			level.state.completed = true
			level.finished_best = true
			level.hud._on_completed(moves, 3)
			await _wait(2.4)
	await _wait(2.0)
	var image: Image = root.get_texture().get_image()
	Settings.set_value(&"walkthrough_done", true)
	return image


## Lays [param picture] out under [param shot]'s caption and saves it.
func _compose(shot: Dictionary, picture: Image) -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.set_color(0, BACKGROUND_TOP)
	gradient.set_color(1, BACKGROUND_BOTTOM)
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	var background := TextureRect.new()
	background.texture = fill
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)

	var caption := Label.new()
	caption.text = shot["caption"]
	caption.label_settings = Ui.label_settings(56, Ui.INK)
	caption.label_settings.line_spacing = -6.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.position = Vector2(30.0, CAPTION_TOP)
	caption.size = Vector2(660.0, CAPTION_HEIGHT)
	page.add_child(caption)

	picture.generate_mipmaps()
	var height: float = PICTURE_BOTTOM - PICTURE_TOP
	var width: float = height * float(picture.get_width()) / float(picture.get_height())
	var frame := Rect2((720.0 - width) * 0.5, PICTURE_TOP, width, height)
	var shadow := Panel.new()
	var box: StyleBoxFlat = Ui.card(Color(Ui.INK, 0.0), int(PICTURE_RADIUS))
	box.shadow_color = Color(Ui.INK, 0.28)
	box.shadow_size = 26
	box.shadow_offset = Vector2(0.0, 12.0)
	shadow.add_theme_stylebox_override(&"panel", box)
	shadow.position = frame.position
	shadow.size = frame.size
	page.add_child(shadow)
	var shown := TextureRect.new()
	shown.texture = ImageTexture.create_from_image(picture)
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.position = frame.position
	shown.size = frame.size
	var rounding := ShaderMaterial.new()
	rounding.shader = Shader.new()
	rounding.shader.code = ROUNDED
	rounding.set_shader_parameter(&"size", frame.size)
	rounding.set_shader_parameter(&"radius", PICTURE_RADIUS)
	shown.material = rounding
	page.add_child(shown)

	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(page)
	change_scene_to_node(layer)
	await _wait(0.5)
	var image: Image = root.get_texture().get_image()
	var path: String = _out.path_join(shot["name"] + ".png")
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("store_screenshots: cannot write %s (%s)" % [path, error_string(err)])
		_failures += 1
	else:
		print("saved %s %s" % [path, image.get_size()])


## Rounds a picture's corners by [param radius] canvas units, whatever its
## shape.
const ROUNDED: String = """
shader_type canvas_item;
uniform vec2 size;
uniform float radius;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 q = abs((UV - 0.5) * size) - (0.5 * size - radius);
	float d = length(max(q, 0.0)) - radius;
	float aa = fwidth(d);
	c.a *= 1.0 - smoothstep(-aa, aa, d);
	COLOR = c * COLOR;
}
"""


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
