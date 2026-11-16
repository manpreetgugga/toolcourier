class_name RateCard
extends Control
## The question asked when a world is finished for the first time (see
## Rating): five stars, a line about the world just finished, Rate it (which
## opens the game's page on Google Play) and Not now (or the back button).
## Sizes are in the 720 x 1280 base viewport.

signal answered(rate: bool)

const SIZE := Vector2(600.0, 640.0)

var _card: Control
var _text: Label
var _asking: bool = false


func _init() -> void:
	name = "RateQuestion"
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

	_card.add_child(_label("Enjoying it?", 52, Ui.INK, Rect2(0.0, 36.0, SIZE.x, 76.0)))
	var stars := _Stars.new()
	stars.position = Vector2((SIZE.x - stars.size.x) * 0.5, 124.0)
	_card.add_child(stars)
	_text = _label("", 28, Ui.MUTED, Rect2(48.0, 196.0, SIZE.x - 96.0, 170.0))
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_text)

	var rate := TouchButton.new(Vector2(340.0, 104.0))
	rate.name = "Rate"
	rate.text = "Rate it"
	rate.font_size = 36
	rate.color = Ui.ACCENT
	rate.position = Vector2((SIZE.x - 340.0) * 0.5, 392.0)
	rate.pressed.connect(answer.bind(true))
	_card.add_child(rate)
	var later := TouchButton.new(Vector2(240.0, 88.0))
	later.name = "NotNow"
	later.text = "Not now"
	later.font_size = 30
	later.color = Ui.CREAM.darkened(0.06)
	later.position = Vector2((SIZE.x - 240.0) * 0.5, 516.0)
	later.pressed.connect(answer.bind(false))
	_card.add_child(later)


## Shows the card for world [param world] just finished, and counts the ask.
func open(world: int) -> void:
	_text.text = "You finished %s! If Tiny Courier made your day a little calmer, a rating on Google Play helps other puzzle fans find it." \
		% LevelCatalog.world_name(world)
	Rating.asked()
	_asking = true
	visible = true
	modulate.a = 0.0
	_card.scale = Vector2(0.9, 0.9)
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Whether the card is up, waiting for an answer.
func is_asking() -> bool:
	return _asking


## Rate it opens the store; either way the card goes.
func answer(rate: bool) -> void:
	if not _asking:
		return
	_asking = false
	if rate:
		Rating.open_store()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.tween_callback(hide)
	answered.emit(rate)


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


## Five gold stars in a row.
class _Stars:
	extends Control

	const RADIUS: float = 26.0
	const GAP: float = 12.0

	func _init() -> void:
		size = Vector2(RADIUS * 10.0 + GAP * 4.0, RADIUS * 2.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 5:
			Ui.draw_star(self, Vector2(RADIUS + i * (RADIUS * 2.0 + GAP), RADIUS), RADIUS, Ui.STAR)
