class_name Walkthrough
extends Control
## The first level's walkthrough (testers' report, 1.2.0), for a player who
## has never finished it: a panel under the level's name says what to do,
## step by step, and the game's own hint arrow (see [method Level.show_hint])
## points at where to tap.
##  1. Turn: drag to turn the island (a swipe cue sways over it).
##  2. Pick up: walk to the parcel.
##  3. Deliver: take it to the pad of the same colour and symbol.
##  4. Exit: walk to the flag.
## The steps follow the level, so undo, restart or a walk somewhere else
## just bring the right one back. Skip ends it at once; finishing the level
## ends it too, and either way it never shows again
## ([member Settings.walkthrough_done]). Its arrows don't count as hints.
## Sizes are in the 720 x 1280 base viewport.

enum Step { TURN, PICK_UP, DELIVER, EXIT, DONE }

const FIRST_LEVEL: String = "res://levels/world_1/level_1.json"
const TEXTS: Dictionary = {
	Step.TURN: "Welcome! Drag anywhere to turn the island, and pinch to zoom.",
	Step.PICK_UP: "Tap where the arrow points to walk there and pick up the parcel.",
	Step.DELIVER: "Now take it to the pad with the same colour and symbol.",
	Step.EXIT: "Delivered! The flag is up: walk to it to finish.",
}
## How far (radians) the island must turn to finish the first step.
const TURN_ENOUGH: float = 0.35
const PANEL_SIZE := Vector2(640.0, 156.0)
## Below the level's name card (see Hud).
const PANEL_TOP: float = 196.0

var level: Level
var step: Step = Step.TURN

var _panel: Panel
var _text: Label
var _dots: _Dots
var _cue: _SwipeCue
var _start_yaw: float = NAN


## Whether [param for_level] gets the walkthrough: the first level, never
## finished, and the walkthrough not yet done or skipped.
static func applies_to(for_level: Level) -> bool:
	return for_level.level_path == FIRST_LEVEL and for_level.interactive and not Settings.walkthrough_done \
		and Progress.best(Progress.level_id(FIRST_LEVEL)).is_empty()


func _init() -> void:
	name = "Walkthrough"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Stops under the pause card.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	_cue = _SwipeCue.new()
	add_child(_cue)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", Ui.card(Ui.INK, 36))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_top = PANEL_TOP
	_panel.offset_bottom = PANEL_TOP + PANEL_SIZE.y
	add_child(_panel)
	_text = Label.new()
	_text.name = "Text"
	_text.label_settings = Ui.label_settings(28, Ui.CREAM)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.position = Vector2(30.0, 12.0)
	_text.size = Vector2(PANEL_SIZE.x - 60.0, 84.0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	_dots = _Dots.new()
	_dots.position = Vector2(34.0, 112.0)
	_panel.add_child(_dots)
	var skip := TouchButton.new(Vector2(124.0, 52.0))
	skip.name = "Skip"
	skip.text = "Skip"
	skip.font_size = 24
	skip.color = Ui.CREAM
	skip.position = Vector2(PANEL_SIZE.x - 124.0 - 22.0, PANEL_SIZE.y - 52.0 - 16.0)
	skip.pressed.connect(skip_it)
	_panel.add_child(skip)
	_show_step(Step.TURN)
	modulate.a = 0.0


func _process(_delta: float) -> void:
	if step == Step.DONE or level == null:
		return
	if level.state.completed:
		_end()
		return
	# Hidden while the island builds itself up.
	var target: float = 0.0 if level.is_assembling() else 1.0
	modulate.a = move_toward(modulate.a, target, 0.08)
	if level.is_assembling():
		return
	if step == Step.TURN:
		if is_nan(_start_yaw):
			_start_yaw = level.camera.yaw
		var turned: bool = absf(angle_difference(_start_yaw, level.camera.yaw)) > TURN_ENOUGH
		if turned or level.state.moves > 0 or level.courier.is_moving():
			_show_step(_step_for_state())
		return
	var wanted: Step = _step_for_state()
	if wanted != step:
		_show_step(wanted)
	# The next thing to do, once the courier stands still.
	if not level.has_hint() and level.can_hint():
		level.show_hint(false)


## Ends the walkthrough now, for good.
func skip_it() -> void:
	_end()


## The step that fits the level as it stands.
func _step_for_state() -> Step:
	if level.state.all_delivered():
		return Step.EXIT
	if not level.state.carried.is_empty():
		return Step.DELIVER
	return Step.PICK_UP


func _show_step(new_step: Step) -> void:
	step = new_step
	_text.text = TEXTS[step]
	_dots.current = step
	_dots.queue_redraw()
	_cue.visible = step == Step.TURN


func _end() -> void:
	if step == Step.DONE:
		return
	step = Step.DONE
	Settings.set_value(&"walkthrough_done", true)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


## Four dots, the current step's filled.
class _Dots:
	extends Control

	var current: int = 0

	func _init() -> void:
		size = Vector2(4 * 22.0, 20.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 4:
			var centre := Vector2(10.0 + i * 22.0, 10.0)
			if i == current:
				draw_circle(centre, 7.0, Ui.ACCENT)
			else:
				draw_circle(centre, 5.0, Color(Ui.CREAM, 0.45))


## A finger swaying along an arc with arrows at both ends: drag to turn.
## Angles are the screen's (y down), so the arc between them bows downwards.
class _SwipeCue:
	extends Control

	const RADIUS: float = 170.0
	const FROM: float = deg_to_rad(30.0)
	const TO: float = deg_to_rad(150.0)
	const PERIOD: float = 2.2

	var _time: float = 0.0

	func _init() -> void:
		name = "SwipeCue"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_CENTER)
		offset_left = -RADIUS - 40.0
		offset_right = RADIUS + 40.0
		offset_top = 230.0
		offset_bottom = 350.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var centre := Vector2(size.x * 0.5, 100.0 - RADIUS)
		var shadow := Color(Ui.INK, 0.25)
		var ink := Color(Ui.CREAM, 0.95)
		for layer: Array in [[shadow, Vector2(0.0, 4.0)], [ink, Vector2.ZERO]]:
			var color: Color = layer[0]
			var shift: Vector2 = layer[1]
			draw_arc(centre + shift, RADIUS, FROM, TO, 32, color, 8.0, true)
			for end: Array in [[FROM, -1.0], [TO, 1.0]]:
				var a: float = end[0]
				var tip: Vector2 = centre + shift + Vector2.from_angle(a) * RADIUS
				var along: Vector2 = Vector2(-sin(a), cos(a)) * float(end[1])
				var side: Vector2 = along.orthogonal()
				draw_colored_polygon(PackedVector2Array([tip + along * 24.0, tip + side * 16.0, tip - side * 16.0]), color)
		# The finger: back and forth, easing at the ends.
		var t: float = 0.5 - 0.5 * cos(_time * TAU / PERIOD)
		var finger: Vector2 = centre + Vector2.from_angle(lerpf(FROM + 0.12, TO - 0.12, t)) * RADIUS
		draw_circle(finger + Vector2(0.0, 4.0), 24.0, shadow)
		draw_circle(finger, 24.0, Ui.CREAM)
		draw_circle(finger, 24.0, Color(Ui.ACCENT, 0.9), false, 5.0, true)
