class_name StarRow
extends Control
## Three stars in a row, the first few gold and the rest dim. A star that
## lights up pops in with a little overshoot; one that goes out shrinks away.

var star_radius: float
var gap: float
## Stars lit (0 to 3).
var lit: int = 0

## How much of each gold star shows (0 to 1, a bit over while popping).
var _shown: Array[float] = [0.0, 0.0, 0.0]
var _tweens: Array[Tween] = [null, null, null]


func _init(radius: float = 22.0, spacing: float = 8.0) -> void:
	star_radius = radius
	gap = spacing
	custom_minimum_size = Vector2(radius * 6.0 + spacing * 2.0, radius * 2.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lights the first [param count] stars. Animated, each newly lit star pops
## [param stagger] seconds after the one before it.
func set_lit(count: int, animate: bool = true, stagger: float = 0.0) -> void:
	var before: int = lit
	lit = clampi(count, 0, 3)
	for i in 3:
		var target: float = 1.0 if i < lit else 0.0
		if _tweens[i]:
			_tweens[i].kill()
			_tweens[i] = null
		if not animate:
			_shown[i] = target
			continue
		if is_equal_approx(_shown[i], target):
			continue
		var tween: Tween = create_tween()
		if target > 0.0:
			tween.tween_interval(stagger * maxi(i - before, 0))
			tween.tween_method(_set_shown.bind(i), _shown[i], 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_method(_set_shown.bind(i), _shown[i], 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tweens[i] = tween
	queue_redraw()


func _draw() -> void:
	for i in 3:
		var center := Vector2(star_radius + i * (star_radius * 2.0 + gap), star_radius)
		Ui.draw_star(self, center, star_radius, Ui.STAR_EMPTY)
		if _shown[i] > 0.01:
			var radius: float = star_radius * _shown[i]
			# A darker lip under the gold, like the clay blocks.
			Ui.draw_star(self, center + Vector2(0.0, star_radius * 0.08), radius, Ui.STAR.darkened(0.18))
			Ui.draw_star(self, center, radius, Ui.STAR)


func _set_shown(value: float, index: int) -> void:
	_shown[index] = value
	queue_redraw()
