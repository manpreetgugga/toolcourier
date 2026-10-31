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
## Nunito (SIL Open Font License, fonts/OFL.txt), a variable font with
## weights from 200 to 1000.
const FONT: FontFile = preload("res://fonts/Nunito.ttf")

## Pretend screen insets (left, top, right, bottom, in base-viewport units)
## for trying out a notch away from a phone; phones report their own.
static var simulated_insets := Vector4.ZERO

## Weight -> FontVariation.
static var _weights: Dictionary = {}


## The part of [param viewport]'s canvas clear of notches, rounded corners
## and system bars: the display's safe area on a phone, the whole canvas
## elsewhere (less [member simulated_insets]).
static func safe_rect(viewport: Viewport) -> Rect2:
	var canvas: Rect2 = viewport.get_visible_rect()
	var insets: Vector4 = simulated_insets
	if OS.has_feature("mobile") and viewport == viewport.get_tree().root:
		var window := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if window.x > 0.0 and safe.size.x > 0.0:
			var scale: Vector2 = canvas.size / window
			insets = Vector4(safe.position.x * scale.x, safe.position.y * scale.y,
				(window.x - safe.end.x) * scale.x, (window.y - safe.end.y) * scale.y).max(Vector4.ZERO)
	return Rect2(canvas.position + Vector2(insets.x, insets.y),
		canvas.size - Vector2(insets.x + insets.z, insets.y + insets.w))


## Sets [param control]'s offsets so that, anchored to the full canvas, it
## covers only the safe area (see [method safe_rect]).
static func fit_to_safe_area(control: Control) -> void:
	var canvas: Rect2 = control.get_viewport().get_visible_rect()
	var safe: Rect2 = safe_rect(control.get_viewport())
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = safe.position.x - canvas.position.x
	control.offset_top = safe.position.y - canvas.position.y
	control.offset_right = safe.end.x - canvas.end.x
	control.offset_bottom = safe.end.y - canvas.end.y


## Nunito at [param weight].
static func font(weight: int) -> Font:
	if not _weights.has(weight):
		var variation := FontVariation.new()
		variation.base_font = FONT
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_weights[weight] = variation
	return _weights[weight]


## Extra-bold Nunito (the soft clay look wants round, bold text).
static func bold_font() -> Font:
	return font(800)


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


## Draws icon [param icon_name] ("undo", "restart", "hint", "pause", "play",
## "home", "levels", "settings", "back" or "lock") on [param canvas],
## centred on [param center], about [param size] across.
static func draw_icon(canvas: CanvasItem, icon_name: StringName, center: Vector2, size: float, color: Color) -> void:
	var width: float = size * 0.12
	match icon_name:
		&"pause":
			for side: float in [-1.0, 1.0]:
				var x: float = center.x + side * size * 0.13
				_bar(canvas, Vector2(x, center.y - size * 0.2), Vector2(x, center.y + size * 0.2), size * 0.14, color)
		&"play":
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-size * 0.15, -size * 0.25), center + Vector2(size * 0.27, 0.0),
				center + Vector2(-size * 0.15, size * 0.25),
			]), color)
		&"home":
			# A roof over a house with a door gap.
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-size * 0.34, -size * 0.02), center + Vector2(0.0, -size * 0.32),
				center + Vector2(size * 0.34, -size * 0.02),
			]), color)
			var body: Array[Vector2] = [
				Vector2(-0.22, -0.08), Vector2(0.22, -0.08), Vector2(0.22, 0.28), Vector2(0.07, 0.28),
				Vector2(0.07, 0.1), Vector2(-0.07, 0.1), Vector2(-0.07, 0.28), Vector2(-0.22, 0.28),
			]
			var points := PackedVector2Array()
			for point: Vector2 in body:
				points.append(center + point * size)
			canvas.draw_colored_polygon(points, color)
		&"levels":
			# A grid of four tiles.
			var tile: float = size * 0.24
			for i in 4:
				var corner: Vector2 = center + Vector2((i % 2) - 1.0, (i >> 1) - 1.0) * (tile + size * 0.07) \
					+ Vector2.ONE * size * 0.035
				_rounded_rect(canvas, Rect2(corner, Vector2(tile, tile)), tile * 0.25, color)
		&"settings":
			# A gear: a ring with eight teeth.
			canvas.draw_arc(center, size * 0.2, 0.0, TAU, 32, color, size * 0.13, true)
			for i in 8:
				var direction: Vector2 = Vector2.from_angle(TAU * i / 8.0)
				_bar(canvas, center + direction * size * 0.25, center + direction * size * 0.33, size * 0.13, color)
		&"back":
			var tip: Vector2 = center + Vector2(-size * 0.11, 0.0)
			_bar(canvas, tip, tip + Vector2(size * 0.22, -size * 0.22), width * 1.1, color)
			_bar(canvas, tip, tip + Vector2(size * 0.22, size * 0.22), width * 1.1, color)
		&"lock":
			var hub: Vector2 = center + Vector2(0.0, -size * 0.08)
			canvas.draw_arc(hub, size * 0.15, PI, TAU, 16, color, size * 0.09, true)
			for side: float in [-1.0, 1.0]:
				canvas.draw_line(hub + Vector2(side * size * 0.15, 0.0), hub + Vector2(side * size * 0.15, size * 0.08),
					color, size * 0.09, true)
			_rounded_rect(canvas, Rect2(center + Vector2(-size * 0.24, -size * 0.04), Vector2(size * 0.48, size * 0.36)),
				size * 0.07, color)
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


## A thick line with round ends.
static func _bar(canvas: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	canvas.draw_line(from, to, color, width, true)
	canvas.draw_circle(from, width * 0.5, color, true, -1.0, true)
	canvas.draw_circle(to, width * 0.5, color, true, -1.0, true)


static func _rounded_rect(canvas: CanvasItem, rect: Rect2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	var corners: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - radius, radius), rect.end - Vector2(radius, radius),
		rect.position + Vector2(radius, rect.size.y - radius), rect.position + Vector2(radius, radius),
	]
	for i in 4:
		for step in 5:
			points.append(corners[i] + Vector2.from_angle(-PI * 0.5 + PI * 0.5 * (i + step / 4.0)) * radius)
	canvas.draw_colored_polygon(points, color)


static func _arrow_head(canvas: CanvasItem, tip_base: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var forward: Vector2 = direction.normalized()
	var side: Vector2 = forward.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([
		tip_base + forward * size * 0.75, tip_base + side * size * 0.55, tip_base - side * size * 0.55,
	]), color)
