class_name SettingsCard
extends Control
## The settings, as a card over a shaded screen: music and sound volumes,
## haptics, the tilt-shift blur and the graphics quality. Each change goes
## to Settings at once (a volume slider saves when let go), so the sound and
## picture follow while the card is up. Sizes are in the 720 x 1280 base
## viewport.

signal closed

const SIZE := Vector2(600.0, 840.0)
const ROW_TOP: float = 150.0
const ROW_HEIGHT: float = 108.0

var _card: Control
var _sliders: Dictionary = {}
var _toggles: Dictionary = {}
var _quality: _Segmented


func _init() -> void:
	name = "Settings"
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
	_card.add_child(_label("Settings", 52, HORIZONTAL_ALIGNMENT_CENTER, Rect2(0.0, 40.0, SIZE.x, 70.0)))

	_add_slider(0, "Music", &"music")
	_add_slider(1, "Sounds", &"sfx")
	_add_toggle(2, "Haptics", &"haptics")
	_add_toggle(3, "Tilt-shift", &"tilt_shift")
	_card.add_child(_row_label(4, "Quality"))
	_quality = _Segmented.new(Settings.QUALITY_NAMES)
	_quality.name = "Quality"
	_quality.position = Vector2(SIZE.x - 48.0 - 330.0, _row_y(4) + 4.0)
	_quality.size = Vector2(330.0, 64.0)
	_quality.picked.connect(func(index: int) -> void: Settings.set_value(&"quality", index))
	_card.add_child(_quality)

	var done := TouchButton.new(Vector2(260.0, 96.0))
	done.name = "Done"
	done.text = "Done"
	done.font_size = 36
	done.color = Ui.ACCENT
	done.position = Vector2((SIZE.x - 260.0) * 0.5, SIZE.y - 130.0)
	done.pressed.connect(close)
	_card.add_child(done)


## Shows the card with the current settings.
func open() -> void:
	Settings.ensure_loaded()
	for key: StringName in _sliders:
		(_sliders[key] as _Slider).set_value(Settings.get_value(key))
	for key: StringName in _toggles:
		(_toggles[key] as _Toggle).set_on(Settings.get_value(key), false)
	_quality.set_index(Settings.quality)
	visible = true
	modulate.a = 0.0
	_card.scale = Vector2(0.9, 0.9)
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.tween_callback(hide)
	closed.emit()


func _add_slider(row: int, text: String, key: StringName) -> void:
	_card.add_child(_row_label(row, text))
	var slider := _Slider.new()
	slider.name = text
	slider.position = Vector2(SIZE.x - 48.0 - 300.0, _row_y(row) + 6.0)
	slider.size = Vector2(300.0, 60.0)
	slider.moved.connect(func(value: float, done: bool) -> void: Settings.set_value(key, value, done))
	if key == &"sfx":
		slider.moved.connect(func(_value: float, done: bool) -> void:
			if done:
				AudioManager.play(&"pickup"))
	_card.add_child(slider)
	_sliders[key] = slider


func _add_toggle(row: int, text: String, key: StringName) -> void:
	_card.add_child(_row_label(row, text))
	var toggle := _Toggle.new()
	toggle.name = text
	toggle.position = Vector2(SIZE.x - 48.0 - 120.0, _row_y(row) + 6.0)
	toggle.size = Vector2(120.0, 60.0)
	toggle.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		if key == &"haptics" and on:
			Haptics.snap())
	_card.add_child(toggle)
	_toggles[key] = toggle


func _row_label(row: int, text: String) -> Label:
	return _label(text, 32, HORIZONTAL_ALIGNMENT_LEFT, Rect2(48.0, _row_y(row), 220.0, 72.0))


static func _row_y(row: int) -> float:
	return ROW_TOP + ROW_HEIGHT * row


static func _label(text: String, font_size: int, align: HorizontalAlignment, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = Ui.label_settings(font_size, Ui.INK)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Draws a thick line with round ends.
static func _bar(canvas: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	canvas.draw_line(from, to, color, width, true)
	canvas.draw_circle(from, width * 0.5, color, true, -1.0, true)
	canvas.draw_circle(to, width * 0.5, color, true, -1.0, true)


## A volume slider: touch or drag anywhere along it.
class _Slider:
	extends Control

	## [param done] once the finger lifts.
	signal moved(value: float, done: bool)

	const KNOB: float = 24.0

	var value: float = 0.5
	var _held: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_value(new_value: float) -> void:
		value = clampf(new_value, 0.0, 1.0)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				_held = true
				_move_to(touch.position.x, false)
			elif _held:
				_held = false
				_move_to(touch.position.x, true)
			accept_event()
		elif event is InputEventScreenDrag and _held:
			_move_to((event as InputEventScreenDrag).position.x, false)
			accept_event()
		elif event is InputEventMouseButton:
			accept_event()

	func _move_to(x: float, done: bool) -> void:
		set_value((x - KNOB) / maxf(size.x - KNOB * 2.0, 1.0))
		moved.emit(value, done)

	func _draw() -> void:
		var y: float = size.y * 0.5
		var left := Vector2(KNOB, y)
		var right := Vector2(size.x - KNOB, y)
		var knob: Vector2 = left.lerp(right, value)
		SettingsCard._bar(self, left, right, 16.0, Color(Ui.INK, 0.12))
		SettingsCard._bar(self, left, knob, 16.0, Ui.ACCENT)
		draw_circle(knob + Vector2(0.0, 3.0), KNOB + 1.0, Ui.SHADOW, true, -1.0, true)
		draw_circle(knob, KNOB, Color.WHITE, true, -1.0, true)
		draw_circle(knob, KNOB * 0.45, Ui.ACCENT, true, -1.0, true)


## An on / off switch.
class _Toggle:
	extends Control

	signal toggled(on: bool)

	var on: bool = false
	var _shown: float = 0.0
	var _tween: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_on(value: bool, animate: bool = true) -> void:
		on = value
		if _tween:
			_tween.kill()
		if animate:
			_tween = create_tween()
			_tween.tween_method(_show, _shown, 1.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			_show(1.0 if on else 0.0)

	func _show(amount: float) -> void:
		_shown = amount
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if not (event as InputEventScreenTouch).pressed:
				set_on(not on)
				AudioManager.play(&"ui_click")
				toggled.emit(on)
			accept_event()
		elif event is InputEventMouseButton:
			accept_event()

	func _draw() -> void:
		var radius: float = size.y * 0.5
		var left := Vector2(radius, radius)
		var right := Vector2(size.x - radius, radius)
		SettingsCard._bar(self, left, right, size.y, Color(Ui.INK, 0.14).lerp(Ui.ACCENT, clampf(_shown, 0.0, 1.0)))
		var knob: Vector2 = left.lerp(right, _shown)
		draw_circle(knob + Vector2(0.0, 2.0), radius - 5.0, Ui.SHADOW, true, -1.0, true)
		draw_circle(knob, radius - 6.0, Color.WHITE, true, -1.0, true)


## One of a few choices side by side.
class _Segmented:
	extends Control

	signal picked(index: int)

	var choices: Array[String] = []
	var index: int = 0

	func _init(names: Array[String]) -> void:
		choices = names
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_index(value: int) -> void:
		index = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if not touch.pressed and Rect2(Vector2.ZERO, size).has_point(touch.position):
				var chosen: int = clampi(int(touch.position.x / size.x * choices.size()), 0, choices.size() - 1)
				if chosen != index:
					set_index(chosen)
					AudioManager.play(&"ui_click")
					picked.emit(index)
			accept_event()
		elif event is InputEventMouseButton:
			accept_event()

	func _draw() -> void:
		var radius: float = size.y * 0.5
		SettingsCard._bar(self, Vector2(radius, radius), Vector2(size.x - radius, radius), size.y, Color(Ui.INK, 0.1))
		var width: float = size.x / choices.size()
		var font: Font = Ui.bold_font()
		for i in choices.size():
			var font_size: int = 26
			if i == index:
				var inner: float = radius - 5.0
				var from := Vector2(width * i + radius, radius)
				var to := Vector2(width * (i + 1) - radius, radius)
				SettingsCard._bar(self, from + Vector2(0.0, 2.0), to + Vector2(0.0, 2.0), inner * 2.0, Ui.SHADOW)
				SettingsCard._bar(self, from, to, inner * 2.0, Color.WHITE)
			var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(width * i, baseline), choices[i], HORIZONTAL_ALIGNMENT_CENTER, width, font_size,
				Ui.INK if i == index else Ui.MUTED)
