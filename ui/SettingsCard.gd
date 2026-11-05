class_name SettingsCard
extends Control
## The settings, as a card over a shaded screen: music and sound volumes,
## haptics, the tilt-shift blur and the graphics quality, then the daily
## reminders and the statistics on phones that have them (see Reminders and
## Analytics) and Google's ad privacy options where the law gives the
## player a say (see Ads), with the version number and a link to the
## privacy policy at the foot. Each change goes to Settings at once (a
## volume slider saves when let go), so the sound and picture follow while
## the card is up. Sizes are in the 720 x 1280 base viewport.

signal closed

## Without the reminders, statistics and ad privacy rows, each of which adds
## a row's height.
const SIZE := Vector2(600.0, 860.0)
const ROW_TOP: float = 150.0
const ROW_HEIGHT: float = 108.0
## Where the reminders, statistics and ad privacy rows go, one under the
## other.
const EXTRA_ROW: int = 5

var _card: Control
var _reminder_row: Array[Control] = []
var _statistics_row: Array[Control] = []
var _ad_row: Array[Control] = []
var _done: TouchButton
var _foot: Array[Control] = []
var _sliders: Dictionary = {}
var _toggles: Dictionary = {}
var _quality: _Segmented
var _taps: int = 0
var _last_tap: int = 0


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
	_reminder_row.assign(_add_toggle(EXTRA_ROW, "Reminders", &"reminders"))
	_statistics_row.assign(_add_toggle(EXTRA_ROW, "Statistics", &"statistics"))
	var ad_label: Label = _row_label(EXTRA_ROW, "Ad privacy")
	_card.add_child(ad_label)
	var ad_options := TouchButton.new(Vector2(200.0, 68.0))
	ad_options.name = "AdPrivacy"
	ad_options.text = "Options"
	ad_options.font_size = 28
	ad_options.color = Ui.CREAM.darkened(0.06)
	ad_options.position = Vector2(SIZE.x - 48.0 - 200.0, _row_y(EXTRA_ROW) + 2.0)
	ad_options.pressed.connect(func() -> void: Ads.show_privacy_options())
	_card.add_child(ad_options)
	_ad_row.assign([ad_label, ad_options])

	_done = TouchButton.new(Vector2(260.0, 96.0))
	_done.name = "Done"
	_done.text = "Done"
	_done.font_size = 36
	_done.color = Ui.ACCENT
	_done.pressed.connect(close)
	_card.add_child(_done)

	var version: Label = _label("Version %s" % ProjectSettings.get_setting("application/config/version"), 20,
		HORIZONTAL_ALIGNMENT_LEFT, Rect2(56.0, 0.0, 240.0, 28.0))
	version.name = "Version"
	version.label_settings.font_color = Ui.MUTED
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_input)
	_card.add_child(version)
	var policy: Label = _label("Privacy policy", 20, HORIZONTAL_ALIGNMENT_RIGHT, Rect2(SIZE.x - 56.0 - 240.0, 0.0, 240.0, 28.0))
	policy.name = "Policy"
	policy.label_settings.font_color = Ui.ACCENT.darkened(0.2)
	policy.mouse_filter = Control.MOUSE_FILTER_STOP
	policy.gui_input.connect(_on_policy_input)
	_card.add_child(policy)
	_foot.assign([version, policy])
	_layout()
	Ads.events.changed.connect(_layout)
	Reminders.events.changed.connect(_show_reminders)
	Analytics.events.changed.connect(_show_statistics)


func _notification(what: int) -> void:
	# Back from Android's notification settings, which may have changed.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and visible:
		_show_reminders()


## Shows the card with the current settings.
func open() -> void:
	Settings.ensure_loaded()
	for key: StringName in _sliders:
		(_sliders[key] as _Slider).set_value(Settings.get_value(key))
	for key: StringName in _toggles:
		(_toggles[key] as _Toggle).set_on(_shows_on(key), false)
	_quality.set_index(Settings.quality)
	_layout()
	Analytics.screen("settings")
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


## Adds a switch for [param key] and returns it with its label.
func _add_toggle(row: int, text: String, key: StringName) -> Array[Control]:
	var label: Label = _row_label(row, text)
	_card.add_child(label)
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
	return [label, toggle]


## Whether the switch for [param key] shows on. The reminders switch shows
## whether reminders will come, which Android (its question, or its
## settings) can change after a tap, and the statistics switch whether
## they're collected.
static func _shows_on(key: StringName) -> bool:
	match key:
		&"reminders":
			return Reminders.is_on()
		&"statistics":
			return Analytics.is_collecting()
	return Settings.get_value(key)


func _show_reminders() -> void:
	if _toggles.has(&"reminders"):
		(_toggles[&"reminders"] as _Toggle).set_on(_shows_on(&"reminders"))


func _show_statistics() -> void:
	if _toggles.has(&"statistics"):
		(_toggles[&"statistics"] as _Toggle).set_on(_shows_on(&"statistics"))


## Shows the reminders and statistics rows only on phones that have them
## and the ad privacy row only where it is needed, one under the other, and
## sizes the card to fit.
func _layout() -> void:
	var extra: int = 0
	for row: Array in [[_reminder_row, Reminders.is_supported()], [_statistics_row, Analytics.is_supported()],
			[_ad_row, Ads.privacy_options_required()]]:
		for control: Control in row[0]:
			control.visible = row[1]
			control.position.y = _row_y(EXTRA_ROW + extra) + _row_offset(control)
		if row[1]:
			extra += 1
	var height: float = SIZE.y + ROW_HEIGHT * extra
	_card.offset_left = -SIZE.x * 0.5
	_card.offset_right = SIZE.x * 0.5
	_card.offset_top = -height * 0.5
	_card.offset_bottom = height * 0.5
	_card.pivot_offset = Vector2(SIZE.x, height) * 0.5
	_done.position = Vector2((SIZE.x - 260.0) * 0.5, height - 150.0)
	for control: Control in _foot:
		control.position.y = height - 44.0


func _on_policy_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.is_pressed():
		AudioManager.play(&"ui_click")
		OS.shell_open(Ads.PRIVACY_URL)


## Five quick taps on the version number turn the performance readout on or
## off (see PerfOverlay).
func _on_version_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.is_pressed()):
		return
	var now: int = Time.get_ticks_msec()
	_taps = _taps + 1 if now - _last_tap < 600 else 1
	_last_tap = now
	if _taps == 5:
		_taps = 0
		PerfOverlay.toggle()
		Haptics.snap()


func _row_label(row: int, text: String) -> Label:
	return _label(text, 32, HORIZONTAL_ALIGNMENT_LEFT, Rect2(48.0, _row_y(row), 220.0, 72.0))


static func _row_y(row: int) -> float:
	return ROW_TOP + ROW_HEIGHT * row


## How far below its row's top [param control] sits.
static func _row_offset(control: Control) -> float:
	if control is _Toggle:
		return 6.0
	return 2.0 if control is TouchButton else 0.0


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
