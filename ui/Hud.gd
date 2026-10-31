class_name Hud
extends CanvasLayer
## The level's 2D interface: the level name, moves and star meter at the
## top; Restart, Undo and Hint at the bottom; a toast saying what a hint
## means; and the card shown on finishing, with the stars earned, the best
## so far and Replay / Next. Sizes are in the 720 x 1280 base viewport.
##
## Keys for the desktop: Z or Backspace undoes, R restarts, H shows a hint.

## Gap to the screen edges.
const MARGIN: float = 36.0
const TOP_SIZE := Vector2(400.0, 136.0)
const BUTTON_SIZE: float = 112.0
## Centre-to-centre distance of the bottom buttons.
const BUTTON_SPACING: float = 210.0
const TOAST_SECONDS: float = 3.5
## Celebration shown before the finish card.
const FINISH_DELAY: float = 0.9
const FINISH_SIZE := Vector2(580.0, 620.0)

var level: Level

var _moves: Label
var _limit: Label
var _meter: StarRow
var _restart: TouchButton
var _undo: TouchButton
var _hint: TouchButton
var _toast: Control
var _toast_label: Label
var _toast_tween: Tween
var _toast_left: float = 0.0
## The toast explains the hint marker, so it goes when the marker does.
var _toast_for_hint: bool = false
var _finish: Control
var _finish_card: Control
var _finish_stars: StarRow
var _finish_moves: Label
var _finish_best: Label
var _replay: TouchButton
var _next: TouchButton
var _next_path: String = ""


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top(root)
	_build_buttons(root)
	_build_toast(root)
	_build_finish(root)
	level.moves_changed.connect(_on_moves_changed)
	level.level_completed.connect(_on_completed)
	_on_moves_changed(level.state.moves, false)


func _process(delta: float) -> void:
	_restart.disabled = not level.can_restart()
	_undo.disabled = not level.can_undo()
	_hint.disabled = not level.can_hint()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 or (_toast_for_hint and not level.has_hint()):
			_hide_toast()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_Z, KEY_BACKSPACE:
			_on_undo()
		KEY_R:
			_on_restart()
		KEY_H:
			_on_hint()
		_:
			return
	get_viewport().set_input_as_handled()


## Whether the finish card is up.
func is_finish_showing() -> bool:
	return _finish.visible


## The toast's text while it shows ("" otherwise).
func toast_text() -> String:
	return _toast_label.text if _toast_left > 0.0 else ""


func _on_moves_changed(moves: int, animate: bool = true) -> void:
	_moves.text = str(moves)
	var stars: int = level.data.stars_for(moves)
	_meter.set_lit(stars, animate)
	if stars > 0:
		_limit.text = "%d %s up to %d" % [stars, "star" if stars == 1 else "stars", level.data.stars[3 - stars]]
	else:
		_limit.text = "past %d moves" % level.data.stars[-1]


func _on_restart() -> void:
	if not level.can_restart():
		return
	_hide_toast()
	_hide_finish()
	level.restart()


func _on_undo() -> void:
	if level.undo():
		_hide_toast()


func _on_hint() -> void:
	var message: String = level.show_hint()
	if not message.is_empty():
		_show_toast(message, level.has_hint())


func _on_next() -> void:
	if not _next_path.is_empty():
		level.go_to(_next_path)


func _on_completed(moves: int, stars: int) -> void:
	_hide_toast()
	_finish_moves.text = "%d moves" % moves
	var best: Dictionary = Progress.best(Progress.level_id(level.level_path))
	if level.finished_best:
		_finish_best.text = "New best!"
		_finish_best.label_settings.font_color = Ui.ACCENT.darkened(0.15)
	else:
		_finish_best.text = "Best: %d moves, %d %s" % [best["moves"], best["stars"], "star" if best["stars"] == 1 else "stars"]
		_finish_best.label_settings.font_color = Ui.MUTED
	_next_path = level.next_level_path()
	_next.visible = not _next_path.is_empty()
	_replay.position.x = 50.0 if _next.visible else (FINISH_SIZE.x - _replay.size.x) * 0.5
	_finish_stars.set_lit(0, false)
	await get_tree().create_timer(FINISH_DELAY).timeout
	if not level.state.completed:
		return
	_finish.visible = true
	_finish.modulate.a = 0.0
	_finish_card.scale = Vector2(0.85, 0.85)
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(_finish, "modulate:a", 1.0, 0.25)
	tween.tween_property(_finish_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_finish_stars.set_lit.bind(stars, true, 0.22))


func _hide_finish() -> void:
	if not _finish.visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_finish, "modulate:a", 0.0, 0.18)
	tween.tween_callback(_finish.hide)


func _show_toast(text: String, for_hint: bool) -> void:
	_toast_label.text = text
	_toast_for_hint = for_hint
	_toast_left = TOAST_SECONDS
	if _toast_tween:
		_toast_tween.kill()
	_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)


func _hide_toast() -> void:
	_toast_left = 0.0
	if not _toast.visible:
		return
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.25)
	_toast_tween.tween_callback(_toast.hide)


func _build_top(root: Control) -> void:
	var card := Panel.new()
	card.name = "Top"
	card.add_theme_stylebox_override(&"panel", Ui.card())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.offset_left = -TOP_SIZE.x * 0.5
	card.offset_right = TOP_SIZE.x * 0.5
	card.offset_top = MARGIN
	card.offset_bottom = MARGIN + TOP_SIZE.y
	root.add_child(card)
	var half: float = TOP_SIZE.x * 0.5
	card.add_child(_label(level.data.name, 24, Ui.MUTED, Rect2(0.0, 10.0, TOP_SIZE.x, 34.0)))
	_moves = _label("0", 56, Ui.INK, Rect2(16.0, 40.0, half - 16.0, 64.0))
	card.add_child(_moves)
	card.add_child(_label("moves", 20, Ui.MUTED, Rect2(16.0, 98.0, half - 16.0, 28.0)))
	_meter = StarRow.new(22.0, 8.0)
	_meter.position = Vector2(half + (half - _meter.size.x) * 0.5 - 8.0, 50.0)
	card.add_child(_meter)
	_limit = _label("", 20, Ui.MUTED, Rect2(half - 8.0, 98.0, half, 28.0))
	card.add_child(_limit)


func _build_buttons(root: Control) -> void:
	var bar := Control.new()
	bar.name = "Buttons"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_top = -(MARGIN + BUTTON_SIZE + 48.0)
	bar.offset_bottom = -MARGIN
	root.add_child(bar)
	_restart = _round_button(bar, &"restart", "Restart", -BUTTON_SPACING, Ui.CREAM)
	_undo = _round_button(bar, &"undo", "Undo", 0.0, Ui.CREAM)
	_hint = _round_button(bar, &"hint", "Hint", BUTTON_SPACING, Ui.HINT)
	_restart.pressed.connect(_on_restart)
	_undo.pressed.connect(_on_undo)
	_hint.pressed.connect(_on_hint)


func _build_toast(root: Control) -> void:
	_toast = CenterContainer.new()
	_toast.name = "Toast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -(MARGIN + BUTTON_SIZE + 160.0)
	_toast.offset_bottom = -(MARGIN + BUTTON_SIZE + 70.0)
	_toast.visible = false
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = Ui.card(Ui.INK, 32)
	box.content_margin_left = 30.0
	box.content_margin_right = 30.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override(&"panel", box)
	_toast.add_child(panel)
	_toast_label = Label.new()
	_toast_label.label_settings = Ui.label_settings(24, Ui.CREAM)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_toast_label)


func _build_finish(root: Control) -> void:
	_finish = Control.new()
	_finish.name = "Finish"
	_finish.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Blocks the diorama behind it.
	_finish.mouse_filter = Control.MOUSE_FILTER_STOP
	_finish.visible = false
	root.add_child(_finish)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(Ui.INK, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish.add_child(shade)

	var card := Panel.new()
	card.name = "Card"
	card.add_theme_stylebox_override(&"panel", Ui.card(Ui.CREAM, 48))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -FINISH_SIZE.x * 0.5
	card.offset_right = FINISH_SIZE.x * 0.5
	card.offset_top = -FINISH_SIZE.y * 0.5
	card.offset_bottom = FINISH_SIZE.y * 0.5
	card.pivot_offset = FINISH_SIZE * 0.5
	_finish.add_child(card)
	_finish_card = card

	card.add_child(_label("Delivered!", 60, Ui.INK, Rect2(0.0, 34.0, FINISH_SIZE.x, 76.0)))
	_finish_stars = StarRow.new(52.0, 16.0)
	_finish_stars.position = Vector2((FINISH_SIZE.x - _finish_stars.size.x) * 0.5, 128.0)
	card.add_child(_finish_stars)
	_finish_moves = _label("", 40, Ui.INK, Rect2(0.0, 252.0, FINISH_SIZE.x, 54.0))
	card.add_child(_finish_moves)
	_finish_best = _label("", 28, Ui.MUTED, Rect2(0.0, 308.0, FINISH_SIZE.x, 40.0))
	card.add_child(_finish_best)
	var limits: Array[int] = level.data.stars
	card.add_child(_label("3 stars in %d  ·  2 in %d  ·  1 in %d" % [limits[0], limits[1], limits[2]], 22, Ui.MUTED,
		Rect2(0.0, 362.0, FINISH_SIZE.x, 34.0)))

	_replay = _pill_button(card, "Replay", Vector2(50.0, 450.0), Ui.CREAM.darkened(0.06))
	_next = _pill_button(card, "Next", Vector2(310.0, 450.0), Ui.ACCENT)
	_replay.pressed.connect(_on_restart)
	_next.pressed.connect(_on_next)


func _round_button(bar: Control, icon_name: StringName, caption: String, offset_x: float, color: Color) -> TouchButton:
	var button := TouchButton.new(Vector2(BUTTON_SIZE, BUTTON_SIZE))
	button.name = caption
	button.icon = icon_name
	button.caption = caption
	button.color = color
	button.position = Vector2(offset_x - BUTTON_SIZE * 0.5, 0.0)
	bar.add_child(button)
	return button


func _pill_button(card: Control, text: String, at: Vector2, color: Color) -> TouchButton:
	var button := TouchButton.new(Vector2(220.0, 100.0))
	button.name = text
	button.text = text
	button.font_size = 36
	button.color = color
	button.position = at
	card.add_child(button)
	return button


static func _label(text: String, font_size: int, color: Color, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = Ui.label_settings(font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
