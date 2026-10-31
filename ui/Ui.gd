class_name Ui
extends RefCounted
## Shared look of the 2D interface: colours, fonts, the soft card style and
## the icons, all drawn in code. Sizes are in the 720 x 1280 base viewport.

const CREAM := Color("#FFF1DC")
const INK := Color("#3A3550")
const MUTED := Color(0.227, 0.208, 0.314, 0.55)
const ACCENT := Palette.ACCENT
## The Hint button (a paler HintMarker yellow).
const HINT := Color("#FFE08A")
const STAR := Color("#F6C343")
const STAR_EMPTY := Color(0.227, 0.208, 0.314, 0.16)
const SHADOW := Color(0.227, 0.208, 0.314, 0.22)

static var _bold: FontVariation


## The default font, made heavier (the soft clay look wants round, bold text).
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


## A rounded card with a soft drop shadow.
static func card(color: Color = CREAM, radius: int = 36) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.shadow_color = SHADOW
	box.shadow_size = 10
	box.shadow_offset = Vector2(0.0, 6.0)
	box.anti_aliasing = true
	return box


static func label_settings(size: int, color: Color = INK) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = bold_font()
	settings.font_size = size
	settings.font_color = color
	return settings


## Draws icon [param icon_name] ("undo", "restart" or "hint") on
## [param canvas], centred on [param center], about [param size] across.
static func draw_icon(canvas: CanvasItem, icon_name: StringName, center: Vector2, size: float, color: Color) -> void:
	var width: float = size * 0.12
	match icon_name:
		&"undo":
			# Three quarters of a circle, arrow at its upper left end.
			var radius: float = size * 0.3
			var hub: Vector2 = center + Vector2(size * 0.04, size * 0.04)
			var start: float = -PI * 0.95
			canvas.draw_arc(hub, radius, start, PI * 0.5, 24, color, width, true)
			_arrow_head(canvas, hub + Vector2.from_angle(start) * radius, Vector2(sin(start), -cos(start)), size * 0.22, color)
		&"restart":
			# Most of a circle, open at the top, arrow at its upper left end.
			var radius: float = size * 0.3
			var start: float = -PI * 0.3
			var finish: float = start + PI * 1.5
			canvas.draw_arc(center, radius, start, finish, 28, color, width, true)
			_arrow_head(canvas, center + Vector2.from_angle(finish) * radius, Vector2(-sin(finish), cos(finish)), size * 0.22, color)
		&"hint":
			# A light bulb.
			var bulb: Vector2 = center + Vector2(0.0, -size * 0.08)
			canvas.draw_circle(bulb, size * 0.24, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				bulb + Vector2(-size * 0.15, size * 0.14), bulb + Vector2(size * 0.15, size * 0.14),
				bulb + Vector2(size * 0.1, size * 0.3), bulb + Vector2(-size * 0.1, size * 0.3),
			]), color)
			for i in 2:
				var y: float = bulb.y + size * (0.36 + 0.1 * i)
				canvas.draw_line(Vector2(center.x - size * 0.1, y), Vector2(center.x + size * 0.1, y), color, size * 0.06, true)
			canvas.draw_circle(bulb + Vector2(-size * 0.08, -size * 0.07), size * 0.06, Color(1.0, 1.0, 1.0, 0.55))


## Draws a five-pointed star.
static func draw_star(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle: float = -PI * 0.5 + PI * 0.2 * i
		var reach: float = radius if i % 2 == 0 else radius * 0.48
		points.append(center + Vector2.from_angle(angle) * reach)
	canvas.draw_colored_polygon(points, color)


static func _arrow_head(canvas: CanvasItem, tip_base: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var forward: Vector2 = direction.normalized()
	var side: Vector2 = forward.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([
		tip_base + forward * size * 0.75, tip_base + side * size * 0.55, tip_base - side * size * 0.55,
	]), color)
