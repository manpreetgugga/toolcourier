class_name Menu
extends Node
## The game's front end. A splash with the title (once per launch), then the
## main menu over a live, slowly turning diorama of the next level to play,
## which builds itself up as the splash fades: Play, Levels and Settings.
## Levels opens the world select, each world a little turning diorama on a
## card, and each world opens its grid of levels with the stars earned. A
## level opens once the one before it is finished, a world with its first
## level. Each screen plays its world's music. Sizes are in the 720 x 1280
## base viewport, kept to the screen's safe area.
##
## Keys for the desktop: Escape goes back (Android's back button too).

## Degrees per second the backdrop and the world previews turn.
const BACKDROP_ORBIT: float = 7.0
const PREVIEW_ORBIT: float = 16.0
const MARGIN: float = 36.0
const SPLASH_SECONDS: float = 1.3
const SPLASH_FADE: float = 0.5
const WORLD_CARD := Vector2(648.0, 196.0)
const WORLD_GAP: float = 16.0
const PREVIEW: float = 168.0
const LEVEL_CARD := Vector2(312.0, 168.0)
const LEVEL_GAP := Vector2(24.0, 18.0)
const PREVIEW_SHADER: String = """
shader_type canvas_item;
// Rounds the corners of a world preview and greys out a locked world.
uniform float radius = 0.16;
uniform float grey = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(l) * 0.85 + 0.12, grey);
	vec2 q = abs(UV - 0.5) - (0.5 - radius);
	float d = length(max(q, 0.0)) - radius;
	float aa = fwidth(d);
	c.a *= 1.0 - smoothstep(-aa, aa, d);
	COLOR = c * COLOR;
}
"""

## The diorama behind the main screen.
var backdrop: Level

var _screen: StringName = &""
var _world: int = 1
var _screens: Dictionary = {}
var _sky: _Sky
var _settings: SettingsCard
var _splash: Control
var _play_caption: Label
var _total: Label
var _world_cards: Dictionary = {}
var _previews: Array[SubViewport] = []
var _levels_title: Label
var _levels_stars: Label
var _level_grid: Control
var _leaving: bool = false


func _ready() -> void:
	Settings.ensure_loaded()
	Settings.apply_quality(get_viewport())
	var next: String = LevelCatalog.next_to_play()
	_world = Game.menu_world if Game.menu_world > 0 else LevelCatalog.world_of(next)

	backdrop = (load(Game.LEVEL) as PackedScene).instantiate()
	backdrop.name = "Backdrop"
	backdrop.level_path = next
	backdrop.show_hud = false
	backdrop.interactive = false
	backdrop.intro = true
	backdrop.idle_orbit_speed = BACKDROP_ORBIT
	# Smaller, to leave room for the title and the buttons.
	backdrop.view_fill = 0.6
	if not Game.splash_done:
		backdrop.intro_delay = SPLASH_SECONDS + SPLASH_FADE * 0.4
	add_child(backdrop)

	var layer := CanvasLayer.new()
	layer.name = "Ui"
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_sky = _Sky.new()
	_sky.visible = false
	root.add_child(_sky)
	var safe := Control.new()
	safe.name = "Safe"
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(safe)
	Ui.fit_to_safe_area(safe)
	get_viewport().size_changed.connect(func() -> void: Ui.fit_to_safe_area(safe))
	_screens[&"main"] = _build_main(safe, next)
	_screens[&"worlds"] = _build_worlds(safe)
	_screens[&"levels"] = _build_levels(safe)
	_settings = SettingsCard.new()
	root.add_child(_settings)

	show_screen(Game.menu_screen if _screens.has(Game.menu_screen) else &"main", false)
	if not Game.splash_done:
		_play_splash(layer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not Game.is_swapping():
		go_back()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()


## The screen showing: "main", "worlds" or "levels".
func screen() -> StringName:
	return _screen


## The world the level grid shows.
func world() -> int:
	return _world


## Shows [param name] ("main", "worlds" or "levels"; the grid shows
## [method world]).
func show_screen(screen_name: StringName, animate: bool = true) -> void:
	var old: Control = _screens.get(_screen)
	_screen = screen_name
	var shown: Control = _screens[screen_name]
	match screen_name:
		&"worlds":
			_refresh_worlds()
		&"levels":
			_fill_levels()
	var on_main: bool = screen_name == &"main"
	backdrop.visible = on_main
	backdrop.process_mode = Node.PROCESS_MODE_INHERIT if on_main else Node.PROCESS_MODE_DISABLED
	_sky.visible = not on_main
	_sky.set_world(_world if screen_name == &"levels" else LevelCatalog.world_of(backdrop.level_path))
	for preview: SubViewport in _previews:
		preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if screen_name == &"worlds" \
			else SubViewport.UPDATE_DISABLED
	AudioManager.play_music(_world if screen_name == &"levels" else LevelCatalog.world_of(backdrop.level_path))
	for key: StringName in _screens:
		(_screens[key] as Control).visible = _screens[key] == shown or (animate and _screens[key] == old)
	if not animate or old == null or old == shown:
		shown.modulate.a = 1.0
		shown.position = Vector2.ZERO
		return
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(old, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(old.hide)
	shown.modulate.a = 0.0
	shown.position = Vector2(0.0, 24.0)
	tween.tween_property(shown, "modulate:a", 1.0, 0.25).set_delay(0.08)
	tween.tween_property(shown, "position", Vector2.ZERO, 0.35).set_delay(0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Opens the level grid of world [param world_number].
func open_world(world_number: int) -> void:
	_world = world_number
	show_screen(&"levels")


func open_settings() -> void:
	_settings.open()


## Plays the level at [param path] (the main screen's diorama takes itself
## down first).
func play(path: String) -> void:
	if _leaving or Game.is_swapping():
		return
	_leaving = true
	if _screen == &"main" and backdrop.level_path == path:
		create_tween().tween_property(_screens[&"main"], "modulate:a", 0.0, 0.25)
		backdrop.leave(func() -> void: Game.open_level(path))
	else:
		Game.open_level(path)


## The back button (or Escape): closes the settings, goes up a screen, and
## from the main screen closes the game.
func go_back() -> void:
	if _leaving:
		return
	if _settings.visible:
		_settings.close()
	elif _screen == &"levels":
		show_screen(&"worlds")
	elif _screen == &"worlds":
		show_screen(&"main")
	else:
		get_tree().quit()


func _play_splash(layer: CanvasLayer) -> void:
	_splash = ColorRect.new()
	_splash.name = "Splash"
	(_splash as ColorRect).color = Ui.CREAM
	_splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_splash)
	var mark := _Glyph.new(&"parcel", Ui.ACCENT)
	_centre(mark, Vector2(0.0, -150.0), Vector2(150.0, 150.0))
	_splash.add_child(mark)
	var title := _label("Tiny Courier", 92, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_centre(title, Vector2(0.0, 20.0), Vector2(720.0, 120.0))
	_splash.add_child(title)
	var tag := _label("a little delivery puzzle", 30, Ui.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_centre(tag, Vector2(0.0, 102.0), Vector2(720.0, 44.0))
	_splash.add_child(tag)

	mark.scale = Vector2(0.4, 0.4)
	title.scale = Vector2(0.7, 0.7)
	title.modulate.a = 0.0
	tag.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(mark, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(title, "scale", Vector2.ONE, 0.5).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(title, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tween.tween_property(tag, "modulate:a", 1.0, 0.4).set_delay(0.45)
	tween.chain().tween_interval(maxf(SPLASH_SECONDS - 0.85, 0.0))
	tween.chain().tween_property(_splash, "modulate:a", 0.0, SPLASH_FADE)
	tween.chain().tween_callback(func() -> void:
		Game.splash_done = true
		_splash.queue_free()
		_splash = null)
	AudioManager.play(&"pad_complete", -6.0)


func _build_main(parent: Control, next: String) -> Control:
	var screen_root := _screen_root(parent, "Main")
	var title := _label("Tiny Courier", 88, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.label_settings.outline_size = 22
	title.label_settings.outline_color = Ui.CREAM
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70.0
	title.offset_bottom = 186.0
	screen_root.add_child(title)

	var pill := Panel.new()
	pill.name = "Stars"
	pill.add_theme_stylebox_override(&"panel", Ui.card(Ui.CREAM, 32))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pill.offset_left = -130.0
	pill.offset_right = 130.0
	pill.offset_top = 200.0
	pill.offset_bottom = 264.0
	screen_root.add_child(pill)
	var star := _Glyph.new(&"star", Ui.STAR)
	star.position = Vector2(30.0, 12.0)
	star.size = Vector2(40.0, 40.0)
	pill.add_child(star)
	_total = _label("", 30, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_total.position = Vector2(66.0, 0.0)
	_total.size = Vector2(170.0, 64.0)
	pill.add_child(_total)
	_total.text = "%d / %d" % [Progress.total_stars(), LevelCatalog.all().size() * 3]

	var bottom := Control.new()
	bottom.name = "Bottom"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_top = -420.0
	bottom.offset_bottom = -MARGIN
	screen_root.add_child(bottom)
	var play_button := TouchButton.new(Vector2(440.0, 128.0))
	play_button.name = "Play"
	play_button.text = "Play"
	play_button.font_size = 52
	play_button.color = Ui.ACCENT
	play_button.position = Vector2(-220.0, 0.0)
	play_button.pressed.connect(func() -> void: play(backdrop.level_path))
	bottom.add_child(play_button)
	_play_caption = _label(_level_caption(next), 26, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_play_caption.label_settings.outline_size = 12
	_play_caption.label_settings.outline_color = Ui.CREAM
	_play_caption.position = Vector2(-340.0, 138.0)
	_play_caption.size = Vector2(680.0, 40.0)
	bottom.add_child(_play_caption)
	var levels := _round_button(bottom, &"levels", "Levels", Vector2(-110.0, 216.0))
	levels.pressed.connect(show_screen.bind(&"worlds"))
	var settings := _round_button(bottom, &"settings", "Settings", Vector2(110.0, 216.0))
	settings.pressed.connect(open_settings)
	return screen_root


func _build_worlds(parent: Control) -> Control:
	var screen_root := _screen_root(parent, "Worlds")
	_header(screen_root, "Worlds", show_screen.bind(&"main"))
	var list := Control.new()
	list.name = "Cards"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.set_anchors_preset(Control.PRESET_CENTER_TOP)
	list.offset_top = 150.0
	screen_root.add_child(list)
	var worlds: Array[int] = LevelCatalog.worlds()
	for i in worlds.size():
		var number: int = worlds[i]
		var card := TouchButton.new(WORLD_CARD)
		card.name = "World_%d" % number
		card.radius = 40
		card.position = Vector2(-WORLD_CARD.x * 0.5, i * (WORLD_CARD.y + WORLD_GAP))
		card.pressed.connect(open_world.bind(number))
		list.add_child(card)
		var picture := TextureRect.new()
		picture.name = "Preview"
		picture.position = Vector2(14.0, 14.0)
		picture.size = Vector2(PREVIEW, PREVIEW)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := Shader.new()
		shader.code = PREVIEW_SHADER
		var material := ShaderMaterial.new()
		material.shader = shader
		picture.material = material
		card.add_child(picture)
		var x: float = PREVIEW + 40.0
		var width: float = WORLD_CARD.x - x - 24.0
		var subtitle := _label("World %d" % number, 22, Ui.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		subtitle.position = Vector2(x, 22.0)
		subtitle.size = Vector2(width, 30.0)
		card.add_child(subtitle)
		var title := _label(LevelCatalog.world_name(number), 42, Ui.INK, HORIZONTAL_ALIGNMENT_LEFT)
		title.position = Vector2(x, 48.0)
		title.size = Vector2(width, 56.0)
		card.add_child(title)
		var glyph := _Glyph.new(&"star", Ui.STAR)
		glyph.position = Vector2(x, 114.0)
		glyph.size = Vector2(34.0, 34.0)
		card.add_child(glyph)
		var stars := _label("", 28, Ui.INK, HORIZONTAL_ALIGNMENT_LEFT)
		stars.position = Vector2(x + 44.0, 110.0)
		stars.size = Vector2(width - 44.0, 42.0)
		card.add_child(stars)
		var note := _label("", 22, Ui.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		note.position = Vector2(x, 150.0)
		note.size = Vector2(width, 32.0)
		card.add_child(note)
		_world_cards[number] = {"card": card, "picture": picture, "glyph": glyph, "stars": stars, "note": note}
	return screen_root


func _build_levels(parent: Control) -> Control:
	var screen_root := _screen_root(parent, "Levels")
	_levels_title = _header(screen_root, "", show_screen.bind(&"worlds"))
	_levels_stars = _label("", 26, Ui.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_levels_stars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_levels_stars.offset_top = 102.0
	_levels_stars.offset_bottom = 140.0
	screen_root.add_child(_levels_stars)
	_level_grid = Control.new()
	_level_grid.name = "Grid"
	_level_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_grid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_level_grid.offset_top = 164.0
	screen_root.add_child(_level_grid)
	return screen_root


## Brings the world cards up to date, making the turning previews the
## first time.
func _refresh_worlds() -> void:
	var make_previews: bool = _previews.is_empty()
	for number: int in _world_cards:
		var parts: Dictionary = _world_cards[number]
		var paths: Array[String] = LevelCatalog.levels(number)
		var open: bool = LevelCatalog.is_unlocked(paths[0])
		var card: TouchButton = parts["card"]
		card.disabled = not open
		var stars: Vector2i = LevelCatalog.world_stars(number)
		(parts["stars"] as Label).text = "%d / %d" % [stars.x, stars.y] if open else "Locked"
		(parts["glyph"] as _Glyph).icon = &"star" if open else &"lock"
		(parts["glyph"] as _Glyph).color = Ui.STAR if open else Ui.MUTED
		(parts["glyph"] as _Glyph).queue_redraw()
		var finished: int = LevelCatalog.world_finished(number)
		(parts["note"] as Label).text = ("%d of %d delivered" % [finished, paths.size()]) if open \
			else "Finish %s to open" % LevelCatalog.world_name(number - 1)
		var picture: TextureRect = parts["picture"]
		(picture.material as ShaderMaterial).set_shader_parameter(&"grey", 0.0 if open else 0.85)
		if make_previews:
			picture.texture = _make_preview(picture, paths[0])


## A little turning diorama of [param path] drawn into [param picture].
func _make_preview(picture: TextureRect, path: String) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.size = Vector2i.ONE * roundi(PREVIEW * _pixel_scale())
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	picture.add_child(viewport)
	var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
	level.level_path = path
	level.show_hud = false
	level.interactive = false
	level.idle_orbit_speed = PREVIEW_ORBIT
	viewport.add_child(level)
	_previews.append(viewport)
	return viewport.get_texture()


## Fills the level grid for [member _world].
func _fill_levels() -> void:
	for child: Node in _level_grid.get_children():
		child.queue_free()
	_levels_title.text = LevelCatalog.world_name(_world)
	var stars: Vector2i = LevelCatalog.world_stars(_world)
	_levels_stars.text = "World %d  ·  %d / %d stars" % [_world, stars.x, stars.y]
	var next: String = LevelCatalog.next_to_play()
	var paths: Array[String] = LevelCatalog.levels(_world)
	var columns: int = 2
	var width: float = LEVEL_CARD.x * columns + LEVEL_GAP.x * (columns - 1)
	for i in paths.size():
		var path: String = paths[i]
		var open: bool = LevelCatalog.is_unlocked(path)
		var best: Dictionary = Progress.best(Progress.level_id(path))
		var card := TouchButton.new(LEVEL_CARD)
		card.name = "Level_%d" % (i + 1)
		card.radius = 36
		card.color = Ui.CREAM if open else Ui.CREAM.darkened(0.08)
		card.disabled = not open
		if path == next and open:
			card.outline = Ui.ACCENT
		card.position = Vector2(-width * 0.5 + (i % columns) * (LEVEL_CARD.x + LEVEL_GAP.x),
			floorf(float(i) / columns) * (LEVEL_CARD.y + LEVEL_GAP.y))
		card.pressed.connect(play.bind(path))
		_level_grid.add_child(card)
		var number := _label(str(i + 1), 64, Ui.INK if open else Ui.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		number.position = Vector2(26.0, 12.0)
		number.size = Vector2(120.0, 84.0)
		card.add_child(number)
		var name_label := _label(LevelLoader.load_file(path).name, 24, Ui.INK if open else Ui.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		name_label.position = Vector2(26.0, 104.0)
		name_label.size = Vector2(LEVEL_CARD.x - 52.0, 40.0)
		card.add_child(name_label)
		if open:
			var row := StarRow.new(20.0, 5.0)
			row.position = Vector2(LEVEL_CARD.x - 26.0 - row.size.x, 36.0)
			row.set_lit(int(best.get("stars", 0)), false)
			card.add_child(row)
		else:
			var lock := _Glyph.new(&"lock", Ui.MUTED)
			lock.position = Vector2(LEVEL_CARD.x - 26.0 - 56.0, 22.0)
			lock.size = Vector2(56.0, 56.0)
			card.add_child(lock)


## "World 1 · Level 3 · First Steps"
func _level_caption(path: String) -> String:
	var number: int = LevelCatalog.levels(LevelCatalog.world_of(path)).find(path) + 1
	return "World %d  ·  Level %d  ·  %s" % [LevelCatalog.world_of(path), number, LevelLoader.load_file(path).name]


## Centres [param control], of [param control_size], [param offset] from the
## middle of its parent.
static func _centre(control: Control, offset: Vector2, control_size: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.offset_left = offset.x - control_size.x * 0.5
	control.offset_right = offset.x + control_size.x * 0.5
	control.offset_top = offset.y - control_size.y * 0.5
	control.offset_bottom = offset.y + control_size.y * 0.5
	control.pivot_offset = control_size * 0.5


func _screen_root(parent: Control, screen_name: String) -> Control:
	var screen_root := Control.new()
	screen_root.name = screen_name
	screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_root.visible = false
	parent.add_child(screen_root)
	return screen_root


## A back button and a title along the top. Returns the title.
func _header(screen_root: Control, text: String, back: Callable) -> Label:
	var button := TouchButton.new(Vector2(96.0, 96.0))
	button.name = "Back"
	button.icon = &"back"
	button.position = Vector2(MARGIN - 8.0, 22.0)
	button.pressed.connect(back)
	screen_root.add_child(button)
	var title := _label(text, 56, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26.0
	title.offset_bottom = 104.0
	screen_root.add_child(title)
	return title


func _round_button(parent: Control, icon_name: StringName, caption: String, center: Vector2) -> TouchButton:
	var button := TouchButton.new(Vector2(112.0, 112.0))
	button.name = caption
	button.icon = icon_name
	button.caption = caption
	button.position = center - Vector2(56.0, 0.0)
	parent.add_child(button)
	return button


func _pixel_scale() -> float:
	var viewport: Viewport = get_viewport()
	var pixels: Vector2 = Vector2((viewport as Window).size) if viewport is Window else Vector2((viewport as SubViewport).size)
	return clampf(pixels.x / maxf(viewport.get_visible_rect().size.x, 1.0), 1.0, 2.0)


static func _label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = Ui.label_settings(font_size, color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The sky behind the world and level screens: the world's sky colours top
## to bottom, with a few soft clouds low down.
class _Sky:
	extends Control

	var _top: Color = Color("#C9B8E8")
	var _bottom: Color = Color("#FDE3CF")

	func _init() -> void:
		name = "Sky"
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_world(world_number: int) -> void:
		var paths: Array[String] = LevelCatalog.levels(world_number)
		var palette: StringName = LevelLoader.load_file(paths[0]).palette if not paths.is_empty() else Palette.DEFAULT_THEME
		var colours: Dictionary = Palette.theme(palette)
		_top = colours["sky_top"]
		_bottom = colours["sky_horizon"]
		queue_redraw()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size)
		draw_polygon(PackedVector2Array([area.position, Vector2(area.end.x, 0.0), area.end, Vector2(0.0, area.end.y)]),
			PackedColorArray([_top, _top, _bottom, _bottom]))
		var cloud := Color(1.0, 1.0, 1.0, 0.35)
		for puff: Vector3 in [Vector3(0.12, 0.93, 0.2), Vector3(0.38, 0.97, 0.26), Vector3(0.7, 0.94, 0.22),
				Vector3(0.95, 0.98, 0.25), Vector3(0.55, 1.02, 0.3)]:
			draw_circle(Vector2(puff.x * size.x, puff.y * size.y), puff.z * size.x, cloud, true, -1.0, true)


## A star, a lock or a parcel drawn in code.
class _Glyph:
	extends Control

	var icon: StringName
	var color: Color

	func _init(glyph: StringName, tint: Color) -> void:
		icon = glyph
		color = tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var side: float = minf(size.x, size.y)
		match icon:
			&"star":
				Ui.draw_star(self, center, side * 0.5, color)
			&"parcel":
				# A rounded box tied with a ribbon.
				var box := StyleBoxFlat.new()
				box.bg_color = color
				box.set_corner_radius_all(int(side * 0.18))
				box.shadow_color = Ui.SHADOW
				box.shadow_size = 12
				box.shadow_offset = Vector2(0.0, 8.0)
				box.anti_aliasing = true
				draw_style_box(box, Rect2(Vector2.ZERO, size))
				var ribbon: Color = Ui.CREAM
				draw_rect(Rect2(center.x - side * 0.06, 0.0, side * 0.12, size.y), ribbon)
				draw_rect(Rect2(0.0, center.y - side * 0.06, size.x, side * 0.12), ribbon)
				for direction: float in [-1.0, 1.0]:
					draw_circle(center + Vector2(direction * side * 0.1, -side * 0.08), side * 0.1, ribbon, false,
						side * 0.05, true)
			_:
				Ui.draw_icon(self, icon, center, side, color)
