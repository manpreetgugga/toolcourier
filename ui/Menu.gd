class_name Menu
extends Node
## The game's front end. A splash with the title (once per launch), then the
## main menu over a live, slowly turning diorama of the next level to play,
## which builds itself up as the splash fades: Play, Levels and Settings.
## Levels opens the world select, a grid of worlds that scrolls, each a
## big turning diorama on a tile (a last world on its own across the whole
## row), and each world opens its map: a trail winding up through floating
## islands, with a badge for each level and the stars earned (see LevelMap).
## A badge opens the level's card, with a diorama of it and Play (see
## LevelPeek). A level opens once the one before it is finished, a world
## with its first level once the player has its stars too (see
## LevelCatalog.stars_needed). Each screen plays its world's music. Sizes are in
## the 720 x 1280 base viewport, kept to the screen's safe area. Where the
## law asks for it, the main menu first asks once whether the game may send
## statistics and crash reports (see StatisticsCard and Analytics).
##
## Keys for the desktop: Escape goes back (Android's back button too).

## Degrees per second the backdrop and the world previews turn.
const BACKDROP_ORBIT: float = 7.0
const PREVIEW_ORBIT: float = 16.0
const MARGIN: float = 36.0
const SPLASH_SECONDS: float = 1.3
const SPLASH_FADE: float = 0.5
## A world's tile in the grid, two to a row; a last world on its own spans
## the row (WORLD_WIDE).
const WORLD_TILE := Vector2(316.0, 452.0)
const WORLD_WIDE := Vector2(648.0, 452.0)
const WORLD_GAP: float = 16.0
## The diorama on a tile, and on the wide tile.
const PREVIEW: float = 288.0
const PREVIEW_WIDE: float = 392.0
## How much of its picture a world's diorama fills.
const PREVIEW_FILL: float = 0.92

## The diorama behind the main screen.
var backdrop: Level

var _screen: StringName = &""
var _world: int = 1
var _screens: Dictionary = {}
var _sky: _Sky
var _settings: SettingsCard
var _statistics: StatisticsCard
var _splash: Control
var _play_caption: Label
var _total: Label
var _world_cards: Dictionary = {}
var _previews: Array[SubViewport] = []
var _levels_title: Label
var _levels_stars: Label
var _map: LevelMap
var _peek: LevelPeek
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
	# It turns by itself, and a drag turns it by hand for a while.
	backdrop.orbit_only = true
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
	_peek = LevelPeek.new()
	_peek.play_pressed.connect(play)
	_peek.closed.connect(func() -> void: _map.frozen = false)
	root.add_child(_peek)
	_settings = SettingsCard.new()
	root.add_child(_settings)
	_statistics = StatisticsCard.new()
	root.add_child(_statistics)
	Analytics.start()
	Reminders.start()

	show_screen(Game.menu_screen if _screens.has(Game.menu_screen) else &"main", false)
	if not Game.splash_done:
		_play_splash(layer)
	else:
		Ads.start_for(next)
		_ask_statistics()


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


## The world the level map shows.
func world() -> int:
	return _world


## Shows [param name] ("main", "worlds" or "levels"; the map shows [method
## world]).
func show_screen(screen_name: StringName, animate: bool = true) -> void:
	_peek.close()
	var old: Control = _screens.get(_screen)
	_screen = screen_name
	Analytics.screen({&"main": "menu", &"worlds": "worlds", &"levels": "map"}.get(screen_name, str(screen_name)))
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


## Opens the map of world [param world_number].
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


## The back button (or Escape): answers the statistics question with a no,
## closes the settings or a level's card, goes up a screen, and from the
## main screen leaves the game (see [method _leave]).
func go_back() -> void:
	if _leaving:
		return
	if _statistics.is_asking():
		_statistics.answer(false)
	elif _settings.visible:
		_settings.close()
	elif _peek.is_open():
		_peek.close()
	elif _screen == &"levels":
		show_screen(&"worlds")
	elif _screen == &"worlds":
		show_screen(&"main")
	else:
		_leave()


## Back on the main screen. On Android the game goes to the background, like
## the home button, and is not shut down: shutting the engine down from a
## running game crashed for some Boomlets players (Crashlytics:
## "pthread_mutex_lock called on a destroyed mutex" in the engine's clean-up).
## Progress and settings are saved as they change, so nothing is lost.
func _leave() -> void:
	if OS.get_name() != "Android":
		get_tree().quit()
		return
	var activity: Variant = null
	if Engine.has_singleton("AndroidRuntime"):
		activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity != null:
		activity.moveTaskToBack(true)
	else:
		get_tree().quit()


## Asks whether the game may send statistics and crash reports, where the
## player must say yes first and hasn't been asked.
func _ask_statistics() -> void:
	if Analytics.needs_consent():
		_statistics.open()


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
		_splash = null
		# Google's consent form, where needed, comes up here (from world 1's
		# level 21 on), and so does the statistics question.
		Ads.start_for(LevelCatalog.next_to_play())
		_ask_statistics())
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
	var scroller := _Scroller.new()
	scroller.name = "Cards"
	scroller.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroller.offset_top = 132.0
	screen_root.add_child(scroller)
	var worlds: Array[int] = LevelCatalog.worlds()
	var y: float = 18.0
	for i in worlds.size():
		var number: int = worlds[i]
		var column: int = i % 2
		# A last world on its own gets the whole row.
		var wide: bool = column == 0 and i == worlds.size() - 1
		var tile: Vector2 = WORLD_WIDE if wide else WORLD_TILE
		var card := TouchButton.new(tile)
		card.name = "World_%d" % number
		card.radius = 40
		card.position = Vector2(column * (WORLD_TILE.x + WORLD_GAP), y)
		card.pressed.connect(open_world.bind(number))
		scroller.content.add_child(card)
		if column == 1 or i == worlds.size() - 1:
			y += tile.y + WORLD_GAP
		var side: float = PREVIEW_WIDE if wide else PREVIEW
		var picture := TextureRect.new()
		picture.name = "Preview"
		picture.position = Vector2(14.0, 14.0)
		picture.size = Vector2(side, side)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.material = Ui.picture_material()
		card.add_child(picture)
		# The words under the picture, or beside it on the wide tile.
		var x: float = side + 36.0 if wide else 22.0
		var top: float = 110.0 if wide else side + 22.0
		var width: float = tile.x - x - 18.0
		var subtitle := _label("Final world" if wide and i > 0 else "World %d" % number, 22, Ui.MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		subtitle.position = Vector2(x, top)
		subtitle.size = Vector2(width, 28.0)
		card.add_child(subtitle)
		# A shut world's lock, in front of "World 3" (which then moves along).
		var lock := _Glyph.new(&"lock", Ui.MUTED)
		lock.name = "Lock"
		lock.position = Vector2(x - 2.0, top + 1.0)
		lock.size = Vector2(26.0, 26.0)
		card.add_child(lock)
		var title := _label(LevelCatalog.world_name(number), 34 if wide else 30, Ui.INK, HORIZONTAL_ALIGNMENT_LEFT)
		title.position = Vector2(x, top + 26.0)
		title.size = Vector2(width, 96.0 if wide else 44.0)
		if wide:
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(title)
		var row: float = top + (128.0 if wide else 76.0)
		var glyph := _Glyph.new(&"star", Ui.STAR)
		glyph.position = Vector2(x, row)
		glyph.size = Vector2(30.0, 30.0)
		card.add_child(glyph)
		var stars := _label("", 26, Ui.INK, HORIZONTAL_ALIGNMENT_LEFT)
		stars.position = Vector2(x + 40.0, row - 4.0)
		stars.size = Vector2(width - 40.0, 38.0)
		card.add_child(stars)
		var note := _label("", 20, Ui.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		note.position = Vector2(x, row + 38.0)
		note.size = Vector2(width, 84.0 if wide else 30.0)
		if wide:
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		card.add_child(note)
		_world_cards[number] = {"card": card, "picture": picture, "glyph": glyph, "stars": stars, "note": note,
			"subtitle": subtitle, "lock": lock, "x": x, "row": row}
	scroller.content.size = Vector2(WORLD_WIDE.x, y + 24.0)
	return screen_root


func _build_levels(parent: Control) -> Control:
	var screen_root := _screen_root(parent, "Levels")
	_map = LevelMap.new()
	_map.level_chosen.connect(_open_peek)
	_map.world_chosen.connect(open_world)
	screen_root.add_child(_map)
	# The world's name and stars, on a card floating over the map.
	var banner := Panel.new()
	banner.name = "Banner"
	banner.add_theme_stylebox_override(&"panel", Ui.card(Ui.CREAM, 40))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -220.0
	banner.offset_right = 220.0
	banner.offset_top = 22.0
	banner.offset_bottom = 134.0
	screen_root.add_child(banner)
	_levels_title = _label("", 46, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_levels_title.position = Vector2(0.0, 8.0)
	_levels_title.size = Vector2(440.0, 60.0)
	banner.add_child(_levels_title)
	_levels_stars = _label("", 24, Ui.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_levels_stars.position = Vector2(0.0, 64.0)
	_levels_stars.size = Vector2(440.0, 36.0)
	banner.add_child(_levels_stars)
	var back: TouchButton = _back_button(screen_root, show_screen.bind(&"worlds"))
	_map.overlays.assign([back, banner])
	return screen_root


## Opens the card of the level at [param path] over the map.
func _open_peek(path: String) -> void:
	_map.frozen = true
	_peek.open(path)


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
		# A shut world waits for the one before it to be finished, or, once
		# it is, for stars.
		var waiting: bool = not open and LevelCatalog.waiting_world() == number
		var needed: int = LevelCatalog.stars_needed(number)
		var stars_label: Label = parts["stars"]
		var note: Label = parts["note"]
		if open:
			var stars: Vector2i = LevelCatalog.world_stars(number)
			stars_label.text = "%d / %d" % [stars.x, stars.y]
			note.text = "%d of %d delivered" % [LevelCatalog.world_finished(number), paths.size()]
		elif waiting:
			stars_label.text = "%d / %d" % [Progress.total_stars(), needed]
			note.text = "Need %d more. Try Hints!" % (needed - Progress.total_stars())
		else:
			stars_label.text = ""
			note.text = "Finish World %d first" % (number - 1)
		# Shut, the lock goes in front of "World 3"; with no stars to count,
		# the note moves up into the stars' row.
		var lock: _Glyph = parts["lock"]
		lock.visible = not open
		lock.color = Ui.STAR if waiting else Ui.MUTED
		lock.queue_redraw()
		var x: float = parts["x"]
		(parts["subtitle"] as Label).position.x = x if open else x + 32.0
		var counted: bool = open or waiting
		(parts["glyph"] as _Glyph).visible = counted
		stars_label.visible = counted
		note.position.y = float(parts["row"]) + (38.0 if counted else 0.0)
		var picture: TextureRect = parts["picture"]
		(picture.material as ShaderMaterial).set_shader_parameter(&"grey", 0.0 if open else 0.85)
		if make_previews:
			picture.texture = _make_preview(picture, paths[0])


## A little turning diorama of [param path] drawn into [param picture].
func _make_preview(picture: TextureRect, path: String) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.size = Vector2i.ONE * roundi(picture.size.x * Ui.pixel_scale(get_viewport()))
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	picture.add_child(viewport)
	var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
	level.level_path = path
	level.show_hud = false
	level.interactive = false
	level.idle_orbit_speed = PREVIEW_ORBIT
	# Filling the tile, so its turning shows.
	level.view_fill = PREVIEW_FILL
	viewport.add_child(level)
	_previews.append(viewport)
	return viewport.get_texture()


## Lays out the level map for [member _world].
func _fill_levels() -> void:
	_levels_title.text = LevelCatalog.world_name(_world)
	var stars: Vector2i = LevelCatalog.world_stars(_world)
	_levels_stars.text = "World %d  ·  %d / %d stars" % [_world, stars.x, stars.y]
	_map.show_world(_world)


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
	_back_button(screen_root, back)
	var title := _label(text, 56, Ui.INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26.0
	title.offset_bottom = 104.0
	screen_root.add_child(title)
	return title


## A back button at the top left, calling [param back].
func _back_button(screen_root: Control, back: Callable) -> TouchButton:
	var button := TouchButton.new(Vector2(96.0, 96.0))
	button.name = "Back"
	button.icon = &"back"
	button.position = Vector2(MARGIN - 8.0, 22.0)
	button.pressed.connect(back)
	screen_root.add_child(button)
	return button


func _round_button(parent: Control, icon_name: StringName, caption: String, center: Vector2) -> TouchButton:
	var button := TouchButton.new(Vector2(112.0, 112.0))
	button.name = caption
	button.icon = icon_name
	button.caption = caption
	button.position = center - Vector2(56.0, 0.0)
	parent.add_child(button)
	return button


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


## The world tiles, scrolled by a drag or a fling (or the mouse wheel) like
## the level map: a drag that starts on a tile scrolls instead of pressing it.
class _Scroller:
	extends Control

	const SLOP_PX: float = 16.0
	const WHEEL: float = 90.0
	## How quickly a fling slows (per second), and the speeds (px/s) it stops
	## at and starts at most.
	const FLING_DECAY: float = 3.0
	const FLING_MIN: float = 30.0
	const FLING_MAX: float = 5000.0

	## What scrolls; its size sets how far.
	var content: Control

	var _finger: int = -1
	var _press := Vector2.ZERO
	var _last := Vector2.ZERO
	var _last_usec: int = 0
	var _dragging: bool = false
	var _velocity: float = 0.0
	var _flinging: bool = false

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = Control.new()
		content.name = "Grid"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(content)
		content.resized.connect(_fit)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_fit()

	## Centres the tiles across and keeps the scroll within them.
	func _fit() -> void:
		content.position.x = roundf((size.x - content.size.x) * 0.5)
		scroll_by(0.0)

	## Moves the tiles [param amount] pixels down, kept within the list.
	func scroll_by(amount: float) -> void:
		content.position.y = clampf(content.position.y + amount, minf(size.y - content.size.y, 0.0), 0.0)

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree():
			_finger = -1
			return
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed and _finger < 0 and get_global_rect().has_point(touch.position):
				_finger = touch.index
				_press = touch.position
				_last = touch.position
				_last_usec = Time.get_ticks_usec()
				_dragging = false
				_flinging = false
				_velocity = 0.0
			elif not touch.pressed and touch.index == _finger:
				_finger = -1
				if _dragging:
					_dragging = false
					# A finger that stopped before it lifted does not fling.
					_flinging = absf(_velocity) > FLING_MIN and Time.get_ticks_usec() - _last_usec < 100000
					get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _finger:
			var drag := event as InputEventScreenDrag
			if not _dragging and _press.distance_to(drag.position) >= SLOP_PX:
				_dragging = true
				for child: Node in content.get_children():
					if child is TouchButton:
						(child as TouchButton).cancel()
			if _dragging:
				var moved: float = (drag.position.y - _last.y) / get_global_transform_with_canvas().get_scale().y
				var now: int = Time.get_ticks_usec()
				_velocity = clampf(lerpf(_velocity, moved / maxf((now - _last_usec) / 1000000.0, 0.001), 0.6),
					-FLING_MAX, FLING_MAX)
				_last = drag.position
				_last_usec = now
				scroll_by(moved)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed \
				and get_global_rect().has_point((event as InputEventMouseButton).position):
			var wheel: MouseButton = (event as InputEventMouseButton).button_index
			if wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				_flinging = false
				scroll_by(WHEEL if wheel == MOUSE_BUTTON_WHEEL_UP else -WHEEL)

	func _process(delta: float) -> void:
		if not _flinging:
			return
		var before: float = content.position.y
		scroll_by(_velocity * delta)
		_velocity *= exp(-FLING_DECAY * delta)
		if absf(_velocity) < FLING_MIN or is_equal_approx(content.position.y, before):
			_flinging = false


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
