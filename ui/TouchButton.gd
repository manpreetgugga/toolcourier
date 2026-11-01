class_name TouchButton
extends Control
## A soft round (icon) or pill (text) button made for touch: it presses on a
## touch, squashes while held and fires [signal pressed] when the finger
## lifts over it. Only screen touches count (the mouse arrives as touches
## too, see project input settings), so one press never fires twice. Drags
## and the mouse wheel pass through, so orbiting across a button still works.
## A press clicks and ticks the phone (see AudioManager and Haptics).

signal pressed

## Icon from [method Ui.draw_icon]; when empty the button shows [member text].
var icon: StringName = &""
var text: String = ""
## Small label under a round button.
var caption: String = ""
var color: Color = Ui.CREAM
var ink: Color = Ui.INK
## Corner radius; below 0 the ends are fully round.
var radius: int = -1
## A ring around the button (none when transparent).
var outline: Color = Color.TRANSPARENT
var font_size: int = 34
## Icon of a small mark at the top right (none when empty), like the play
## mark on Hint while a hint needs a video first.
var badge: StringName = &"":
	set(value):
		if value != badge:
			badge = value
			queue_redraw()
var disabled: bool = false:
	set(value):
		if value != disabled:
			disabled = value
			if disabled:
				_held = false
			_update_look()

var _held: bool = false
var _box: StyleBoxFlat


func _init(button_size: Vector2 = Vector2(116.0, 116.0)) -> void:
	custom_minimum_size = button_size
	size = button_size
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	pivot_offset = size * 0.5
	_box = Ui.card(color, radius if radius >= 0 else int(minf(size.x, size.y) * 0.5))
	if outline.a > 0.0:
		_box.border_color = outline
		_box.set_border_width_all(5)
	_update_look()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not disabled:
				_held = true
				_update_look()
		elif _held:
			_held = false
			_update_look()
			if Rect2(Vector2.ZERO, size).has_point(touch.position):
				AudioManager.play(&"ui_click")
				Haptics.tap()
				pressed.emit()
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var content: Color = ink if not disabled else Color(ink, 0.35)
	if icon != &"":
		Ui.draw_icon(self, icon, size * 0.5, minf(size.x, size.y) * 0.62, content)
	else:
		var font: Font = Ui.bold_font()
		var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, Vector2(0.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, content)
	if not caption.is_empty():
		draw_string(Ui.bold_font(), Vector2(-20.0, size.y + 34.0), caption, HORIZONTAL_ALIGNMENT_CENTER,
			size.x + 40.0, 22, Ui.MUTED if not disabled else Color(Ui.MUTED, 0.25))
	if badge != &"":
		var radius: float = minf(size.x, size.y) * 0.2
		var spot := Vector2(size.x - radius * 0.7, radius * 0.7)
		draw_circle(spot + Vector2(0.0, 2.0), radius + 1.0, Ui.SHADOW, true, -1.0, true)
		draw_circle(spot, radius, ink if not disabled else Color(ink, 0.35), true, -1.0, true)
		Ui.draw_icon(self, badge, spot, radius * 2.0, Ui.CREAM)


func _update_look() -> void:
	if _box == null:
		return
	_box.bg_color = color if not disabled else color.lerp(Ui.CREAM, 0.4)
	_box.shadow_size = 4 if _held else 10
	_box.shadow_offset = Vector2(0.0, 2.0 if _held else 6.0)
	var squash := Vector2(1.06, 0.9) if _held else Vector2.ONE
	create_tween().tween_property(self, "scale", squash, 0.08 if _held else 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()
