class_name MapDecor
extends RefCounted
## What stands about on the islands of the level map (see LevelMap), drawn
## in code in the colours of the props in the levels. Pieces: trees and
## bushes in the season's colours, pines, rocks, flowers, sunflowers,
## houses, lamps, flags, crates, pumpkins, hay, snowmen, ponds and fences.
## Landmarks, one to an island, move a little: a windmill's sails turn, a
## lighthouse's light sweeps round, a clock tower keeps the phone's time, a
## barn's weathervane swings, smoke curls up from a cabin and a hot-air
## balloon bobs on its rope; the flag at the end of the trail waves. Each stands on (0, 0), drawn [param size] times as
## big as at size 1, where a piece is 20 to 75 px tall and a landmark 100 to
## 130.

## Each palette's islands: the ground, the cliffs under it and the trail
## across it, the pieces scattered about (by how often each comes up) and
## the landmarks, taken in turn from island to island.
const LOOKS: Dictionary = {
	&"meadow": {
		"ground": Color("#9DD27F"), "cliff": Color("#A3968C"), "trail": Color("#FBEBC8"),
		"pieces": {&"tree": 6, &"bush": 3, &"flowers": 3, &"rock": 1, &"house": 1, &"fence": 1},
		"landmarks": [&"windmill", &"barn"],
	},
	&"harbor": {
		"ground": Color("#E9DFCB"), "cliff": Color("#A3968C"), "trail": Color("#FFF8EC"),
		"pieces": {&"lamp": 2, &"flag": 2, &"crate": 3, &"tree": 2, &"pond": 2, &"house": 2, &"rock": 1},
		"landmarks": [&"lighthouse"],
	},
	&"old_town": {
		"ground": Color("#EBD8BE"), "cliff": Color("#A3968C"), "trail": Color("#FFF8EC"),
		"pieces": {&"house": 6, &"lamp": 2, &"flag": 1, &"bush": 2, &"tree": 1, &"flowers": 1},
		"landmarks": [&"tower"],
	},
	&"orchard": {
		"ground": Color("#E3B562"), "cliff": Color("#A3968C"), "trail": Color("#FBEBC8"),
		"pieces": {&"tree": 6, &"pumpkin": 3, &"hay": 2, &"bush": 1, &"crate": 1, &"fence": 1},
		"landmarks": [&"barn", &"windmill"],
	},
	&"frost_peaks": {
		"ground": Color("#F3F6FA"), "cliff": Color("#8E98B0"), "trail": Color("#DDE7F2"),
		"pieces": {&"pine": 7, &"snowman": 2, &"rock": 2, &"pond": 1},
		"landmarks": [&"cabin"],
	},
	&"blossom_valley": {
		"ground": Color("#AADB8E"), "cliff": Color("#A3968C"), "trail": Color("#FFF3EF"),
		"pieces": {&"tree": 6, &"bush": 3, &"flowers": 4, &"fence": 1, &"pond": 1},
		"landmarks": [&"windmill", &"barn"],
	},
	&"sunflower_fields": {
		"ground": Color("#B7D86B"), "cliff": Color("#A3968C"), "trail": Color("#FFF3D6"),
		"pieces": {&"sunflower": 6, &"hay": 2, &"tree": 2, &"bush": 2, &"flowers": 2, &"fence": 1},
		"landmarks": [&"balloon", &"windmill"],
	},
}
## How tall each piece and landmark stands and how far it reaches either
## side, at size 1.
const EXTENTS: Dictionary = {
	&"tree": Vector2(28.0, 70.0), &"pine": Vector2(24.0, 72.0), &"bush": Vector2(22.0, 25.0),
	&"rock": Vector2(18.0, 20.0), &"flowers": Vector2(18.0, 16.0), &"house": Vector2(28.0, 58.0),
	&"lamp": Vector2(12.0, 74.0), &"flag": Vector2(16.0, 68.0), &"crate": Vector2(16.0, 28.0),
	&"pumpkin": Vector2(18.0, 27.0), &"hay": Vector2(18.0, 20.0), &"snowman": Vector2(16.0, 49.0),
	&"pond": Vector2(38.0, 22.0), &"fence": Vector2(24.0, 22.0), &"sunflower": Vector2(24.0, 76.0),
	&"windmill": Vector2(52.0, 126.0), &"lighthouse": Vector2(30.0, 120.0), &"tower": Vector2(24.0, 132.0),
	&"barn": Vector2(38.0, 86.0), &"cabin": Vector2(34.0, 110.0), &"balloon": Vector2(30.0, 124.0),
	&"goal": Vector2(58.0, 112.0),
}
const FLOWERS: Array[Color] = [Color("#F4B3C6"), Color("#FFFFFF"), Color("#F6C343"), Color("#C9B8E8")]
const ROOFS: Array[Color] = [Color("#E8845E"), Color("#7FA7C9"), Color("#C96F5B"), Color("#8E98B0")]
const WALLS: Array[Color] = [Color("#FFF1DC"), Color("#F4DEAA"), Color("#EBD9CC")]
const FLAGS: Array[Color] = [Color("#E07A5F"), Color("#3E7CB1"), Color("#F3C623"), Color("#4C9F70")]
const SAIL := Color("#F7EBDD")
const APPLE := Color("#D9483B")
const HAY := Color("#E8C468")
const BARN := Color("#C9503F")
const BARN_ROOF := Color("#8C3B30")
const SMOKE := Color("#C9CDD8")
## The balloon's gores, in turn.
const BALLOON: Array[Color] = [Color("#EE6C4D"), Color("#FFF1DC"), Color("#F6C343")]
const SHADOW := Color(0.227, 0.208, 0.314, 0.16)


## The look of [param palette]'s islands (the meadow's for a palette without one).
static func look(palette: StringName) -> Dictionary:
	return LOOKS.get(palette, LOOKS[&"meadow"])


## Half the width and the height of [param kind] at size 1.
static func extent(kind: StringName) -> Vector2:
	return EXTENTS.get(kind, Vector2(20.0, 30.0))


## Draws piece [param kind] on [param canvas], standing on (0, 0), in
## [param season]'s colours; [param variant] picks among its colours.
static func draw_piece(canvas: CanvasItem, kind: StringName, size: float, season: StringName, variant: int) -> void:
	var winter: bool = season == &"winter"
	match kind:
		&"tree":
			# Some of autumn's golden trees bear apples.
			_tree(canvas, size, _leaves(season, variant), season == &"autumn" and variant % 3 == 2)
		&"pine":
			_pine(canvas, size, winter)
		&"bush":
			_bush(canvas, size, _leaves(season, variant + 1))
		&"rock":
			_rock(canvas, size, winter)
		&"flowers":
			_flowers(canvas, size, variant)
		&"house":
			_house(canvas, size, WALLS[variant % WALLS.size()], ROOFS[variant % ROOFS.size()], winter)
		&"lamp":
			_lamp(canvas, size)
		&"flag":
			_flag(canvas, size, FLAGS[variant % FLAGS.size()])
		&"crate":
			_crate(canvas, size)
		&"pumpkin":
			_pumpkin(canvas, size)
		&"hay":
			_hay(canvas, size)
		&"snowman":
			_snowman(canvas, size)
		&"pond":
			_pond(canvas, size, winter, not winter and variant % 2 == 0)
		&"fence":
			_fence(canvas, size)
		&"sunflower":
			_sunflowers(canvas, size, variant)


## Draws landmark [param kind] on [param canvas], standing on (0, 0), as it
## is [param time] seconds in.
static func draw_landmark(canvas: CanvasItem, kind: StringName, size: float, season: StringName, time: float) -> void:
	match kind:
		&"windmill":
			_windmill(canvas, size, time)
		&"lighthouse":
			_lighthouse(canvas, size, time)
		&"tower":
			_tower(canvas, size)
		&"barn":
			_barn(canvas, size, time, season == &"winter")
		&"cabin":
			_cabin(canvas, size, time)
		&"balloon":
			_balloon(canvas, size, time)
		&"goal":
			_goal(canvas, size, time)


## The colours of the bits piece [param kind] sheds when tapped: leaves or
## blossom, petals, snow, wisps of hay or a splash (none for a piece that
## sheds nothing).
static func shed(kind: StringName, season: StringName, variant: int) -> Array[Color]:
	var colors: Array[Color] = []
	match kind:
		&"tree", &"bush":
			var leaves: Color = _leaves(season, variant if kind == &"tree" else variant + 1)
			colors.assign([leaves, leaves.lightened(0.2)])
		&"pine":
			colors.append(PropFactory.SNOW if season == &"winter" else PropFactory.PINE)
		&"flowers":
			colors.assign(FLOWERS)
		&"sunflower":
			colors.assign([PropFactory.SUNFLOWER, PropFactory.SUNFLOWER.lightened(0.25)])
		&"hay":
			colors.assign([HAY, HAY.lightened(0.2)])
		&"snowman":
			colors.append(PropFactory.SNOW)
		&"pond":
			colors.append(Palette.block_color(&"ice" if season == &"winter" else &"water").lightened(0.35))
	return colors


## A filled ellipse.
static func ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		points.append(center + Vector2.from_angle(TAU * i / 20.0) * radii)
	canvas.draw_colored_polygon(points, color)


## Leaves in [param season]: blossom in spring, green in summer, orange, red
## or gold in autumn.
static func _leaves(season: StringName, variant: int) -> Color:
	match season:
		&"spring":
			return PropFactory.BLOSSOMS[variant % PropFactory.BLOSSOMS.size()]
		&"autumn":
			return PropFactory.AUTUMN_LEAVES[variant % PropFactory.AUTUMN_LEAVES.size()]
	return PropFactory.LEAVES if variant % 2 == 0 else PropFactory.LEAVES_LIGHT


static func _tree(canvas: CanvasItem, s: float, leaves: Color, fruit: bool) -> void:
	_shadow(canvas, 24.0 * s)
	_box(canvas, Rect2(-5.0, -28.0, 10.0, 28.0), s, PropFactory.TRUNK)
	var shade: Color = leaves.darkened(0.18)
	_dot(canvas, Vector2(0.0, -40.0), 25.0, s, shade)
	_dot(canvas, Vector2(-15.0, -36.0), 16.0, s, shade)
	_dot(canvas, Vector2(15.0, -36.0), 16.0, s, shade)
	_dot(canvas, Vector2(0.0, -47.0), 22.0, s, leaves)
	_dot(canvas, Vector2(-12.0, -42.0), 14.0, s, leaves)
	_dot(canvas, Vector2(12.0, -43.0), 14.0, s, leaves)
	_dot(canvas, Vector2(-7.0, -56.0), 7.0, s, leaves.lightened(0.25))
	if fruit:
		for spot: Vector2 in [Vector2(-11.0, -38.0), Vector2(9.0, -48.0), Vector2(3.0, -33.0), Vector2(15.0, -37.0)]:
			_dot(canvas, spot, 3.5, s, APPLE)


static func _pine(canvas: CanvasItem, s: float, snowy: bool) -> void:
	_shadow(canvas, 20.0 * s)
	_box(canvas, Rect2(-4.0, -12.0, 8.0, 12.0), s, PropFactory.TRUNK)
	for tier in 3:
		var half: float = 24.0 - tier * 6.0
		var base: float = -9.0 - tier * 17.0
		var tip: float = base - 30.0 + tier * 2.0
		_shape(canvas, [Vector2(-half, base), Vector2(half, base), Vector2(0.0, tip)], s,
			PropFactory.PINE.darkened(0.12 - tier * 0.06))
		if snowy:
			var cap: float = tip + (base - tip) * 0.42
			_shape(canvas, [Vector2(-half * 0.42, cap), Vector2(half * 0.42, cap), Vector2(0.0, tip)], s, PropFactory.SNOW)


static func _bush(canvas: CanvasItem, s: float, leaves: Color) -> void:
	_shadow(canvas, 20.0 * s)
	var shade: Color = leaves.darkened(0.18)
	_dot(canvas, Vector2(-10.0, -9.0), 10.0, s, shade)
	_dot(canvas, Vector2(10.0, -9.0), 10.0, s, shade)
	_dot(canvas, Vector2(0.0, -13.0), 12.0, s, leaves)
	_dot(canvas, Vector2(-9.0, -11.0), 8.0, s, leaves)
	_dot(canvas, Vector2(9.0, -11.0), 8.0, s, leaves)
	_dot(canvas, Vector2(-4.0, -19.0), 4.5, s, leaves.lightened(0.25))


static func _rock(canvas: CanvasItem, s: float, snowy: bool) -> void:
	_shadow(canvas, 18.0 * s)
	_shape(canvas, [Vector2(-18.0, 0.0), Vector2(-16.0, -10.0), Vector2(-7.0, -19.0), Vector2(6.0, -20.0),
		Vector2(15.0, -12.0), Vector2(18.0, 0.0)], s, PropFactory.ROCK.darkened(0.12))
	_shape(canvas, [Vector2(-13.0, -8.0), Vector2(-6.0, -17.0), Vector2(5.0, -18.0), Vector2(12.0, -10.0),
		Vector2(4.0, -6.0)], s, PropFactory.ROCK)
	if snowy:
		_shape(canvas, [Vector2(-9.0, -14.0), Vector2(-6.0, -18.5), Vector2(5.0, -19.5), Vector2(11.0, -13.0),
			Vector2(1.0, -12.0)], s, PropFactory.SNOW)


static func _flowers(canvas: CanvasItem, s: float, variant: int) -> void:
	var spots: Array[Vector2] = [Vector2(-13.0, -4.0), Vector2(-2.0, -11.0), Vector2(11.0, -5.0), Vector2(2.0, 2.0)]
	for i in spots.size():
		var petal: Color = FLOWERS[(variant + i) % FLOWERS.size()]
		for k in 5:
			_dot(canvas, spots[i] + Vector2.from_angle(TAU * k / 5.0) * 3.4, 3.0, s, petal)
		_dot(canvas, spots[i], 2.2, s, Ui.STAR if petal != FLOWERS[2] else ROOFS[0])


## A clump of three sunflowers, their heads turned up to the sun.
static func _sunflowers(canvas: CanvasItem, s: float, variant: int) -> void:
	_shadow(canvas, 20.0 * s)
	var flip: float = 1.0 if variant % 2 == 0 else -1.0
	# Each head's middle (x, y) and radius, back to front.
	var heads: Array[Vector3] = [Vector3(9.0 * flip, -62.0, 9.0), Vector3(-10.0 * flip, -50.0, 8.0),
		Vector3(2.0 * flip, -36.0, 7.0)]
	for head: Vector3 in heads:
		var top := Vector2(head.x, head.y)
		var foot := Vector2(head.x * 0.4, 0.0)
		canvas.draw_line(foot * s, top * s, PropFactory.SUNFLOWER_STEM, 3.0 * s, true)
		var leaf: Vector2 = foot.lerp(top, 0.45)
		var out: float = 1.0 if head.x >= 0.0 else -1.0
		_shape(canvas, [leaf, leaf + Vector2(6.0 * out, -8.0), leaf + Vector2(14.0 * out, -6.0), leaf + Vector2(8.0 * out, -1.0)],
			s, PropFactory.SUNFLOWER_STEM.lightened(0.1))
	for head: Vector3 in heads:
		var middle := Vector2(head.x, head.y)
		for k in 10:
			_dot(canvas, middle + Vector2.from_angle(TAU * k / 10.0) * head.z, head.z * 0.42, s, PropFactory.SUNFLOWER)
		_dot(canvas, middle, head.z * 0.62, s, PropFactory.SUNFLOWER_HEART)
		_dot(canvas, middle - Vector2.ONE * head.z * 0.18, head.z * 0.22, s, PropFactory.SUNFLOWER_HEART.lightened(0.2))


static func _house(canvas: CanvasItem, s: float, wall: Color, roof: Color, snowy: bool) -> void:
	_shadow(canvas, 30.0 * s)
	_box(canvas, Rect2(-22.0, -32.0, 44.0, 32.0), s, wall)
	_box(canvas, Rect2(10.0, -32.0, 12.0, 32.0), s, wall.darkened(0.08))
	_shape(canvas, [Vector2(-27.0, -30.0), Vector2(27.0, -30.0), Vector2(0.0, -58.0)], s, roof)
	_shape(canvas, [Vector2(0.0, -58.0), Vector2(27.0, -30.0), Vector2(13.0, -30.0)], s, roof.darkened(0.12))
	if snowy:
		_shape(canvas, [Vector2(-15.0, -44.0), Vector2(15.0, -44.0), Vector2(0.0, -58.0)], s, PropFactory.SNOW)
	_box(canvas, Rect2(-5.0, -16.0, 10.0, 16.0), s, PropFactory.BEAM)
	_box(canvas, Rect2(-17.0, -24.0, 8.0, 8.0), s, PropFactory.LAMP)


static func _lamp(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 10.0 * s)
	_box(canvas, Rect2(-5.0, -4.0, 10.0, 4.0), s, PropFactory.POST)
	_box(canvas, Rect2(-2.0, -56.0, 4.0, 54.0), s, PropFactory.POST)
	_dot(canvas, Vector2(0.0, -62.0), 14.0, s, Color(PropFactory.LAMP, 0.35))
	_dot(canvas, Vector2(0.0, -62.0), 7.0, s, PropFactory.LAMP)
	_shape(canvas, [Vector2(-9.0, -66.0), Vector2(9.0, -66.0), Vector2(0.0, -74.0)], s, PropFactory.POST)


static func _flag(canvas: CanvasItem, s: float, cloth: Color) -> void:
	_shadow(canvas, 8.0 * s)
	_box(canvas, Rect2(-2.0, -64.0, 4.0, 64.0), s, PropFactory.POST)
	_shape(canvas, [Vector2(2.0, -63.0), Vector2(30.0, -55.0), Vector2(2.0, -46.0)], s, cloth)
	_dot(canvas, Vector2(0.0, -66.0), 3.5, s, PropFactory.LAMP)


static func _crate(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 18.0 * s)
	_box(canvas, Rect2(-14.0, -28.0, 28.0, 28.0), s, PropFactory.CRATE)
	canvas.draw_rect(Rect2(Vector2(-14.0, -28.0) * s, Vector2(28.0, 28.0) * s), PropFactory.CRATE_BAND, false, 3.0 * s)
	_box(canvas, Rect2(-2.0, -28.0, 4.0, 28.0), s, PropFactory.TAPE)


static func _pumpkin(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 18.0 * s)
	_dot(canvas, Vector2(-8.0, -10.0), 10.0, s, PropFactory.PUMPKIN.darkened(0.1))
	_dot(canvas, Vector2(8.0, -10.0), 10.0, s, PropFactory.PUMPKIN.darkened(0.1))
	_dot(canvas, Vector2(0.0, -11.0), 11.0, s, PropFactory.PUMPKIN)
	_box(canvas, Rect2(-2.0, -27.0, 4.0, 7.0), s, PropFactory.STEM)


static func _hay(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 20.0 * s)
	_box(canvas, Rect2(-17.0, -20.0, 34.0, 20.0), s, HAY)
	_box(canvas, Rect2(-17.0, -20.0, 34.0, 5.0), s, HAY.lightened(0.2))
	for x: float in [-8.0, 8.0]:
		_box(canvas, Rect2(x - 1.5, -20.0, 3.0, 20.0), s, HAY.darkened(0.25))


static func _snowman(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 18.0 * s)
	_dot(canvas, Vector2(1.5, -13.0), 15.0, s, PropFactory.SNOW.darkened(0.1))
	_dot(canvas, Vector2(0.0, -14.0), 14.0, s, PropFactory.SNOW)
	_dot(canvas, Vector2(1.0, -37.0), 10.5, s, PropFactory.SNOW.darkened(0.1))
	_dot(canvas, Vector2(0.0, -38.0), 10.0, s, PropFactory.SNOW)
	_box(canvas, Rect2(-11.0, -30.0, 22.0, 5.0), s, PropFactory.SCARF)
	_box(canvas, Rect2(4.0, -28.0, 5.0, 11.0), s, PropFactory.SCARF)
	_shape(canvas, [Vector2(0.0, -39.5), Vector2(11.0, -37.5), Vector2(0.0, -35.5)], s, PropFactory.CARROT)
	for spot: Vector2 in [Vector2(-4.0, -42.0), Vector2(4.0, -42.0), Vector2(0.0, -18.0), Vector2(0.0, -10.0)]:
		_dot(canvas, spot, 1.6, s, Ui.INK)


static func _pond(canvas: CanvasItem, s: float, icy: bool, boat: bool) -> void:
	var water: Color = Palette.block_color(&"ice" if icy else &"water")
	ellipse(canvas, Vector2(0.0, -6.0) * s, Vector2(38.0, 15.0) * s, Color(Ui.INK, 0.12))
	ellipse(canvas, Vector2(0.0, -7.0) * s, Vector2(35.0, 13.0) * s, water)
	ellipse(canvas, Vector2(-12.0, -10.0) * s, Vector2(9.0, 2.5) * s, water.lightened(0.35))
	if boat:
		_shape(canvas, [Vector2(-9.0, -10.0), Vector2(10.0, -10.0), Vector2(6.0, -5.0), Vector2(-6.0, -5.0)], s, PropFactory.CRATE)
		_box(canvas, Rect2(-0.8, -24.0, 1.6, 14.0), s, PropFactory.BEAM)
		_shape(canvas, [Vector2(1.0, -24.0), Vector2(9.0, -12.0), Vector2(1.0, -12.0)], s, Ui.CREAM)


static func _fence(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 24.0 * s)
	for x: float in [-20.0, 0.0, 20.0]:
		_box(canvas, Rect2(x - 2.5, -22.0, 5.0, 22.0), s, PropFactory.FENCE.darkened(0.12))
	for y: float in [-17.0, -9.0]:
		_box(canvas, Rect2(-23.0, y, 46.0, 4.0), s, PropFactory.FENCE)


static func _windmill(canvas: CanvasItem, s: float, time: float) -> void:
	_shadow(canvas, 34.0 * s)
	_shape(canvas, [Vector2(-21.0, 0.0), Vector2(21.0, 0.0), Vector2(13.0, -78.0), Vector2(-13.0, -78.0)], s, WALLS[0])
	_shape(canvas, [Vector2(6.0, 0.0), Vector2(21.0, 0.0), Vector2(13.0, -78.0), Vector2(4.0, -78.0)], s, WALLS[0].darkened(0.08))
	_shape(canvas, [Vector2(-17.0, -76.0), Vector2(17.0, -76.0), Vector2(0.0, -98.0)], s, ROOFS[2])
	_box(canvas, Rect2(-6.0, -18.0, 12.0, 18.0), s, PropFactory.BEAM)
	_box(canvas, Rect2(-4.0, -50.0, 8.0, 10.0), s, PropFactory.LAMP)
	var hub := Vector2(0.0, -72.0)
	for i in 4:
		var along: Vector2 = Vector2.from_angle(time * 0.9 + i * PI * 0.5)
		var side: Vector2 = along.orthogonal()
		_shape(canvas, [hub + along * 9.0 + side * 2.0, hub + along * 50.0 + side * 2.0,
			hub + along * 50.0 + side * 13.0, hub + along * 12.0 + side * 13.0], s, SAIL)
		canvas.draw_line(hub * s, (hub + along * 52.0) * s, PropFactory.BEAM, 3.0 * s, true)
	_dot(canvas, hub, 4.5, s, PropFactory.POST)


static func _lighthouse(canvas: CanvasItem, s: float, time: float) -> void:
	_shadow(canvas, 26.0 * s)
	_shape(canvas, [Vector2(-17.0, 0.0), Vector2(17.0, 0.0), Vector2(11.0, -86.0), Vector2(-11.0, -86.0)], s, Ui.CREAM)
	# Two red bands round the tower, which narrows going up.
	for band: Vector2 in [Vector2(-16.0, -30.0), Vector2(-46.0, -60.0)]:
		var low: float = 17.0 + band.x * 6.0 / 86.0
		var high: float = 17.0 + band.y * 6.0 / 86.0
		_shape(canvas, [Vector2(-low, band.x), Vector2(low, band.x), Vector2(high, band.y), Vector2(-high, band.y)], s,
			PropFactory.BANNER)
	_box(canvas, Rect2(-15.0, -92.0, 30.0, 6.0), s, PropFactory.POST)
	_box(canvas, Rect2(-8.0, -106.0, 16.0, 14.0), s, PropFactory.LAMP)
	_shape(canvas, [Vector2(-11.0, -106.0), Vector2(11.0, -106.0), Vector2(0.0, -120.0)], s, PropFactory.BANNER)
	# The light turning: its beam swings out one way, back and out the other.
	var turn: float = cos(time * 1.4)
	if absf(turn) > 0.08:
		var lamp := Vector2(0.0, -99.0)
		_shape(canvas, [lamp, lamp + Vector2(120.0 * turn, -14.0), lamp + Vector2(120.0 * turn, 14.0)], s,
			Color(PropFactory.LAMP, 0.32 * absf(turn)))


static func _tower(canvas: CanvasItem, s: float) -> void:
	_shadow(canvas, 24.0 * s)
	_box(canvas, Rect2(-16.0, -100.0, 32.0, 100.0), s, WALLS[2])
	_box(canvas, Rect2(6.0, -100.0, 10.0, 100.0), s, WALLS[2].darkened(0.08))
	_shape(canvas, [Vector2(-20.0, -98.0), Vector2(20.0, -98.0), Vector2(0.0, -132.0)], s, ROOFS[0])
	_shape(canvas, [Vector2(0.0, -132.0), Vector2(20.0, -98.0), Vector2(9.0, -98.0)], s, ROOFS[0].darkened(0.12))
	_box(canvas, Rect2(-6.0, -20.0, 12.0, 20.0), s, PropFactory.BEAM)
	_box(canvas, Rect2(-4.0, -50.0, 8.0, 12.0), s, PropFactory.LAMP)
	# The clock keeps the phone's time.
	var face := Vector2(0.0, -78.0)
	_dot(canvas, face, 12.0, s, PropFactory.POST)
	_dot(canvas, face, 10.0, s, Ui.CREAM)
	var now: Dictionary = Time.get_time_dict_from_system()
	var minutes: float = float(now["minute"]) + float(now["second"]) / 60.0
	var hours: float = fmod(float(now["hour"]), 12.0) + minutes / 60.0
	canvas.draw_line(face * s, (face + Vector2.from_angle(TAU * hours / 12.0 - PI * 0.5) * 5.5) * s, Ui.INK, 2.4 * s, true)
	canvas.draw_line(face * s, (face + Vector2.from_angle(TAU * minutes / 60.0 - PI * 0.5) * 8.0) * s, Ui.INK, 1.8 * s, true)


static func _barn(canvas: CanvasItem, s: float, time: float, snowy: bool) -> void:
	_shadow(canvas, 36.0 * s)
	_box(canvas, Rect2(-30.0, -40.0, 60.0, 40.0), s, BARN)
	_box(canvas, Rect2(14.0, -40.0, 16.0, 40.0), s, BARN.darkened(0.1))
	_shape(canvas, [Vector2(-35.0, -38.0), Vector2(35.0, -38.0), Vector2(24.0, -60.0), Vector2(0.0, -70.0),
		Vector2(-24.0, -60.0)], s, BARN_ROOF)
	if snowy:
		_shape(canvas, [Vector2(-22.0, -58.0), Vector2(22.0, -58.0), Vector2(0.0, -70.0)], s, PropFactory.SNOW)
	# The door, crossed in white, and the hayloft over it.
	var door := Rect2(Vector2(-11.0, -26.0) * s, Vector2(22.0, 26.0) * s)
	canvas.draw_rect(door, BARN.darkened(0.25))
	canvas.draw_rect(door, Ui.CREAM, false, 2.5 * s)
	canvas.draw_line(door.position, door.end, Ui.CREAM, 2.5 * s, true)
	canvas.draw_line(Vector2(door.end.x, door.position.y), Vector2(door.position.x, door.end.y), Ui.CREAM, 2.5 * s, true)
	_box(canvas, Rect2(-6.0, -54.0, 12.0, 10.0), s, HAY)
	# A weathervane on the ridge, swinging round in the wind.
	var vane := Vector2(0.0, -84.0)
	var swing: float = sin(time * 1.1) * 10.0
	canvas.draw_line(Vector2(0.0, -70.0) * s, vane * s, PropFactory.POST, 2.0 * s, true)
	canvas.draw_line((vane - Vector2(swing, 0.0)) * s, (vane + Vector2(swing, 0.0)) * s, PropFactory.POST, 2.5 * s, true)
	_dot(canvas, vane + Vector2(swing, 0.0), 2.5, s, PropFactory.POST)


static func _cabin(canvas: CanvasItem, s: float, time: float) -> void:
	_shadow(canvas, 32.0 * s)
	_box(canvas, Rect2(10.0, -58.0, 9.0, 18.0), s, PropFactory.ROCK)
	_box(canvas, Rect2(-27.0, -34.0, 54.0, 34.0), s, PropFactory.PLANK)
	for row in 4:
		_box(canvas, Rect2(-27.0, -31.0 + row * 8.0, 54.0, 2.0), s, PropFactory.PLANK_DARK)
	_shape(canvas, [Vector2(-33.0, -32.0), Vector2(33.0, -32.0), Vector2(0.0, -60.0)], s, PropFactory.BEAM)
	_shape(canvas, [Vector2(-27.0, -37.0), Vector2(27.0, -37.0), Vector2(0.0, -60.0)], s, PropFactory.SNOW)
	_box(canvas, Rect2(-6.0, -18.0, 12.0, 18.0), s, PropFactory.BEAM)
	_box(canvas, Rect2(-20.0, -27.0, 9.0, 9.0), s, PropFactory.LAMP)
	# Smoke curling up from the chimney.
	for i in 3:
		var rise: float = fmod(time * 12.0 + i * 16.0, 48.0)
		var puff := Vector2(14.5 + sin(time * 1.5 + i) * 3.0 + rise * 0.15, -62.0 - rise)
		_dot(canvas, puff, 4.0 + rise * 0.1, s, Color(SMOKE, 0.75 * (1.0 - rise / 48.0)))


## A hot-air balloon tied to a peg, bobbing on its rope; now and then its
## burner flares.
static func _balloon(canvas: CanvasItem, s: float, time: float) -> void:
	_shadow(canvas, 14.0 * s)
	var bob := Vector2(sin(time * 0.7) * 3.0, sin(time * 1.3) * 4.0)
	var basket := Vector2(0.0, -40.0) + bob
	canvas.draw_line(Vector2(0.0, -6.0) * s, (basket + Vector2(0.0, 6.0)) * s, PropFactory.BEAM, 1.6 * s, true)
	_box(canvas, Rect2(-3.0, -7.0, 6.0, 7.0), s, PropFactory.POST)
	# The envelope: a round top narrowing to the skirt, in gores of colour,
	# the far ones in shade.
	var width: float = 26.0
	var skirt: float = basket.y - 16.0
	var equator: float = skirt - 1.25 * width
	var gores: int = 6
	for k in gores:
		var edges: Array[float] = [sin(PI * (float(k) / gores - 0.5)), sin(PI * (float(k + 1) / gores - 0.5))]
		var left := PackedVector2Array([Vector2(bob.x, equator - width) * s])
		var right := PackedVector2Array()
		for i in range(1, 13):
			var y: float = equator - width * cos(PI * 0.5 * i / 6.0)
			var radius: float = width * sin(PI * 0.5 * i / 6.0)
			if i > 6:
				var v: float = (i - 6) / 6.0
				y = equator + v * (skirt - equator)
				radius = width * lerpf(1.0, 0.32, v * v * (3.0 - 2.0 * v))
			left.append(Vector2(bob.x + radius * edges[0], y) * s)
			right.append(Vector2(bob.x + radius * edges[1], y) * s)
		right.reverse()
		left.append_array(right)
		var cloth: Color = BALLOON[k % BALLOON.size()]
		canvas.draw_colored_polygon(left, cloth.darkened(0.1) if k >= gores / 2 else cloth)
	_dot(canvas, Vector2(bob.x - width * 0.45, equator - width * 0.5), width * 0.2, s, Color(1.0, 1.0, 1.0, 0.25))
	# The ropes down to the basket, and the burner flaring between them.
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(Vector2(bob.x + side * width * 0.32, skirt) * s, (basket + Vector2(side * 7.0, -5.0)) * s,
			PropFactory.POST, 1.2 * s, true)
	var flare: float = clampf(sin(time * 0.8) * 4.0 - 3.0, 0.0, 1.0)
	if flare > 0.0:
		_dot(canvas, basket + Vector2(0.0, -11.0), 7.0, s, Color(PropFactory.LAMP, 0.35 * flare))
		_dot(canvas, basket + Vector2(0.0, -11.0), 3.0 * flare, s, Color("#FF9F45"))
	_box(canvas, Rect2(basket.x - 8.0, basket.y - 6.0, 16.0, 12.0), s, PropFactory.CRATE)
	_box(canvas, Rect2(basket.x - 9.0, basket.y - 7.0, 18.0, 3.0), s, PropFactory.CRATE_BAND)


## The flag at the end of a world's trail, on a round stone.
static func _goal(canvas: CanvasItem, s: float, time: float) -> void:
	_shadow(canvas, 26.0 * s)
	ellipse(canvas, Vector2(0.0, -5.0) * s, Vector2(24.0, 10.0) * s, PropFactory.ROCK.darkened(0.12))
	ellipse(canvas, Vector2(0.0, -8.0) * s, Vector2(20.0, 8.0) * s, PropFactory.ROCK)
	_box(canvas, Rect2(-2.5, -104.0, 5.0, 96.0), s, PropFactory.POST)
	# The cloth ripples out from the pole.
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 7:
		var x: float = 2.0 + 9.0 * i
		var wave: float = sin(time * 3.4 - x * 0.09) * 5.0 * x / 56.0
		top.append(Vector2(x, -102.0 + wave) * s)
		bottom.append(Vector2(x, -66.0 + wave) * s)
	bottom.reverse()
	top.append_array(bottom)
	canvas.draw_colored_polygon(top, Ui.ACCENT)
	var middle := Vector2(29.0, -84.0 + sin(time * 3.4 - 29.0 * 0.09) * 5.0 * 29.0 / 56.0)
	Ui.draw_star(canvas, middle * s, 10.0 * s, Ui.CREAM)
	_dot(canvas, Vector2(0.0, -106.0), 5.0, s, Ui.STAR)


static func _shadow(canvas: CanvasItem, half_width: float) -> void:
	ellipse(canvas, Vector2(0.0, -1.0), Vector2(half_width, half_width * 0.3), SHADOW)


static func _dot(canvas: CanvasItem, at: Vector2, radius: float, s: float, color: Color) -> void:
	canvas.draw_circle(at * s, radius * s, color, true, -1.0, true)


static func _box(canvas: CanvasItem, rect: Rect2, s: float, color: Color) -> void:
	canvas.draw_rect(Rect2(rect.position * s, rect.size * s), color)


static func _shape(canvas: CanvasItem, points: Array, s: float, color: Color) -> void:
	var scaled := PackedVector2Array()
	for point: Vector2 in points:
		scaled.append(point * s)
	canvas.draw_colored_polygon(scaled, color)
