class_name StatisticsCard
extends Control
## The menu's one question about statistics and crash reports (see
## Analytics), as a card over a shaded screen: asked once, where the player
## must say yes before anything is sent. Share and No thanks (or the back
## button) set [member Settings.statistics] either way, and Settings shows
## it from then on, to change at any time. Sizes are in the 720 x 1280 base
## viewport.

signal answered(yes: bool)

const SIZE := Vector2(600.0, 760.0)
const TEXT: String = "Can the game send the developer statistics on how you play (levels, moves, time) " \
	+ "and reports of any crash? They go through Google Firebase and help fix bugs and tune the levels. " \
	+ "Nothing that names you is sent."

var _card: Control
## Up, and not yet answered.
var _asking: bool = false


func _init() -> void:
	name = "StatisticsQuestion"
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

	_card.add_child(_label("Share statistics?", 52, Ui.INK, Rect2(0.0, 36.0, SIZE.x, 76.0)))
	var text: Label = _label(TEXT, 28, Ui.MUTED, Rect2(48.0, 128.0, SIZE.x - 96.0, 290.0))
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(text)
	var later: Label = _label("You can change this any time in Settings.", 24, Ui.MUTED, Rect2(48.0, 420.0, SIZE.x - 96.0, 36.0))
	_card.add_child(later)
	var policy: Label = _label("Privacy policy", 24, Ui.ACCENT.darkened(0.2), Rect2((SIZE.x - 240.0) * 0.5, 458.0, 240.0, 40.0))
	policy.name = "Policy"
	policy.mouse_filter = Control.MOUSE_FILTER_STOP
	policy.gui_input.connect(_on_policy_input)
	_card.add_child(policy)

	var share := TouchButton.new(Vector2(340.0, 104.0))
	share.name = "Share"
	share.text = "Share"
	share.font_size = 36
	share.color = Ui.ACCENT
	share.position = Vector2((SIZE.x - 340.0) * 0.5, 520.0)
	share.pressed.connect(answer.bind(true))
	_card.add_child(share)
	var no := TouchButton.new(Vector2(240.0, 88.0))
	no.name = "NoThanks"
	no.text = "No thanks"
	no.font_size = 30
	no.color = Ui.CREAM.darkened(0.06)
	no.position = Vector2((SIZE.x - 240.0) * 0.5, 644.0)
	no.pressed.connect(answer.bind(false))
	_card.add_child(no)


## Shows the card.
func open() -> void:
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


## The player's answer, kept in Settings; the card goes.
func answer(yes: bool) -> void:
	if not _asking:
		return
	_asking = false
	Settings.set_value(&"statistics", yes)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.tween_callback(hide)
	answered.emit(yes)


func _on_policy_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.is_pressed():
		AudioManager.play(&"ui_click")
		OS.shell_open(Ads.PRIVACY_URL)


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
