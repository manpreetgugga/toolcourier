class_name LevelPeek
extends Control
## A level's card, over the level map: its world and number, its name, a
## little diorama of it building itself up and turning, the stars earned
## and the moves to beat, and Play. A tap on the shade around the card (or
## the back button) closes it. Sizes are in the 720 x 1280 base viewport.

## Play was pressed for the level at [param path].
signal play_pressed(path: String)
signal closed

const SIZE := Vector2(600.0, 900.0)
const PICTURE: float = 420.0
## Degrees per second the diorama turns.
const ORBIT: float = 18.0

var _path: String = ""
var _open: bool = false
var _card: Panel
var _number: Label
var _title: Label
var _picture: TextureRect
var _stars: StarRow
var _note: Label
var _tween: Tween
## Whether the finger came down on the shade (a tap there closes the card).
var _shade_pressed: bool = false


func _init() -> void:
	name = "Peek"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(Ui.INK, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_card = Panel.new()
	_card.name = "Card"
	_card.add_theme_stylebox_override(&"panel", Ui.card(Ui.CREAM, 48))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left = -SIZE.x * 0.5
	_card.offset_right = SIZE.x * 0.5
	_card.offset_top = -SIZE.y * 0.5
	_card.offset_bottom = SIZE.y * 0.5
	_card.pivot_offset = SIZE * 0.5
	add_child(_card)

	_number = _label(24, Ui.MUTED, Rect2(40.0, 30.0, SIZE.x - 80.0, 46.0))
	_number.name = "Number"
	_card.add_child(_number)
	var close_button := TouchButton.new(Vector2(72.0, 72.0))
	close_button.name = "Close"
	close_button.icon = &"close"
	close_button.color = Ui.CREAM.darkened(0.06)
	close_button.position = Vector2(SIZE.x - 96.0, 22.0)
	close_button.pressed.connect(close)
	_card.add_child(close_button)
	_title = _label(44, Ui.INK, Rect2(40.0, 88.0, SIZE.x - 80.0, 64.0))
	_title.name = "Title"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_card.add_child(_title)
	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.position = Vector2((SIZE.x - PICTURE) * 0.5, 166.0)
	_picture.size = Vector2(PICTURE, PICTURE)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.material = Ui.picture_material()
	_card.add_child(_picture)
	_stars = StarRow.new(26.0, 10.0)
	_stars.name = "Stars"
	_stars.position = Vector2((SIZE.x - _stars.size.x) * 0.5, 606.0)
	_card.add_child(_stars)
	_note = _label(24, Ui.MUTED, Rect2(40.0, 668.0, SIZE.x - 80.0, 40.0))
	_note.name = "Note"
	_card.add_child(_note)
	var play := TouchButton.new(Vector2(320.0, 108.0))
	play.name = "Play"
	play.text = "Play"
	play.font_size = 46
	play.color = Ui.ACCENT
	play.position = Vector2((SIZE.x - 320.0) * 0.5, 752.0)
	play.pressed.connect(func() -> void: play_pressed.emit(_path))
	_card.add_child(play)


## Shows the card of the level at [param path].
func open(path: String) -> void:
	_path = path
	_open = true
	var level: LevelData = LevelLoader.load_file(path)
	var world: int = LevelCatalog.world_of(path)
	_number.text = "World %d  ·  Level %d" % [world, LevelCatalog.levels(world).find(path) + 1]
	_title.text = level.name
	var best: Dictionary = Progress.best(Progress.level_id(path))
	var stars: int = int(best.get("stars", 0))
	var three: int = level.stars[0] if not level.stars.is_empty() else 0
	if best.is_empty():
		_note.text = "3 stars in %d moves" % three if three > 0 else ""
	elif stars < 3 and three > 0:
		_note.text = "Best %d moves  ·  3 stars in %d" % [int(best["moves"]), three]
	else:
		_note.text = "Best %d moves" % int(best["moves"])
	_show_diorama()
	_stars.set_lit(0, false)

	visible = true
	modulate.a = 0.0
	_card.scale = Vector2(0.9, 0.9)
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_stars.set_lit.bind(stars, true, 0.12))


func close() -> void:
	if not _open:
		return
	_open = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.16)
	_tween.tween_callback(func() -> void:
		hide()
		_free_diorama())
	closed.emit()


func is_open() -> bool:
	return _open


## The level the card shows.
func path() -> String:
	return _path


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var outside: bool = not _card.get_rect().has_point(touch.position)
		if touch.pressed:
			_shade_pressed = outside
		elif _shade_pressed and outside:
			_shade_pressed = false
			close()
		accept_event()


## A diorama of the level in the picture, building itself up and turning.
func _show_diorama() -> void:
	_free_diorama()
	var viewport := SubViewport.new()
	viewport.name = "View"
	viewport.own_world_3d = true
	viewport.size = Vector2i.ONE * roundi(PICTURE * Ui.pixel_scale(get_viewport()))
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_picture.add_child(viewport)
	var level: Level = (load(Game.LEVEL) as PackedScene).instantiate()
	level.level_path = _path
	level.show_hud = false
	level.interactive = false
	level.intro = true
	level.idle_orbit_speed = ORBIT
	viewport.add_child(level)
	_picture.texture = viewport.get_texture()


func _free_diorama() -> void:
	_picture.texture = null
	var view: Node = _picture.get_node_or_null("View")
	if view != null:
		_picture.remove_child(view)
		view.queue_free()


static func _label(font_size: int, color: Color, rect: Rect2) -> Label:
	var label := Label.new()
	label.label_settings = Ui.label_settings(font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = rect.position
	label.size = rect.size
	return label
