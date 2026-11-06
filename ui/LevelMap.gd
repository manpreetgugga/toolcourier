class_name LevelMap
extends Control
## A world's levels as a map to explore: a trail winding up through floating
## islands joined by rope bridges, five levels to an island, from level 1 at
## the foot to a flag at the top. Each level is a round badge on the trail,
## with its stars under it once finished and a lock while it is shut. The
## level to play next is the orange one, with a parcel bobbing at its
## shoulder; past it the trail is only
## dotted in, and islands not reached yet lie in a haze behind a bank of
## cloud. Each island is dressed in the world's look (see MapDecor) around
## a landmark that moves, and is there to be poked: pieces wobble, trees
## and bushes shed a few leaves (or petals, or snow) and landmarks hurry for
## a moment. Clouds drift behind, a little slower than the map scrolls,
## birds fly past, and petals, leaves or snow fall by season. Once a world
## is finished, the button by its flag goes on to the next.
##
## Drag or fling to scroll (a drag that starts on a badge scrolls instead of
## pressing it), or use the mouse wheel. Sizes are in the 720 x 1280 base
## viewport.

## A level's badge was pressed.
signal level_chosen(path: String)
## The button by the flag was pressed, for world [param world].
signal world_chosen(world: int)

const WIDTH: float = 720.0
const BADGE: float = 96.0
const NEXT_BADGE: float = 116.0
## How far the trail climbs from one level to the next, and how far it sways
## either side of the middle, once each WAVELENGTH of climb.
const SPACING: float = 126.0
const SWING: float = 172.0
const WAVELENGTH: float = 780.0
## Levels to an island.
const CHAPTER: int = 5
## Ground below an island's first level and above its last, and the sky
## between islands.
const ISLAND_PAD: float = 92.0
const SKY_GAP: float = 150.0
## How near an island's sides come to the map's, how much ground they keep
## either side of the trail (a little more, at random, so islands differ),
## and how round their corners are.
const ISLAND_INSET: float = 36.0
const TRAIL_ROOM: float = 96.0
const CORNER := Vector2(120.0, 190.0)
## How deep the earth shows under an island's grass.
const CLIFF: float = 44.0
const TRAIL_WIDTH: float = 30.0
## From the last level up to the flag, the ground over the flag (more with
## the button for the next world) and the sky over the top island.
const GOAL_RISE: float = 150.0
const GOAL_ROOM: float = 130.0
const GOAL_BUTTON_ROOM: float = 120.0
const TOP_SKY: float = 160.0
## Sky and ground under the first level.
const BOTTOM_ROOM: float = 330.0
const GOAL_BUTTON := Vector2(340.0, 84.0)
## Room over the button for the note saying the next world wants more stars.
const GATE_NOTE := Vector2(560.0, 80.0)
const SCROLL_SLOP_PX: float = 16.0
const WHEEL_SCROLL: float = 90.0
## How quickly a fling slows (per second), and the speeds (px/s) it stops
## at and starts at most.
const FLING_DECAY: float = 3.0
const FLING_MIN: float = 30.0
const FLING_MAX: float = 5000.0
## Where the level to play shows when the map opens, down from the top.
const FOCUS: float = 0.58

## Each island's ground, rock and scenery, by world, island and height: the
## same every time, so made once.
static var _dressings: Dictionary = {}
static var _textures: Dictionary = {}

## Takes no notice of the finger while something covers the map (a level's
## card).
var frozen: bool = false:
	set(value):
		frozen = value
		_finger = -1
		_dragging = false
		_flinging = false
## Controls over the map (the screen's back button): a touch that starts on
## one is theirs.
var overlays: Array[Control] = []

var _world: int = 0
var _paths: Array[String] = []
var _content: Control
var _badges: Control
var _clouds: _Clouds
var _weather: CPUParticles2D
var _season: StringName = &"summer"
## What drifts across the screen (see Palette.weather).
var _weather_kind: StringName = &"summer"
## Island by chapter, the first at the foot.
var _islands: Array[_Island] = []
## Height of the whole map.
var _height: float = 0.0
## 1 when the trail first sways right, -1 left (it changes with the world).
var _sway: float = 1.0
var _next_world: int = 0
## The next world wants more stars than the player has (see
## LevelCatalog.stars_open).
var _gated: bool = false
var _goal_room: float = GOAL_ROOM
## The finger on the map (-1 for none), where it pressed, where and when it
## was last, and whether it has moved far enough to scroll.
var _finger: int = -1
var _press := Vector2.ZERO
var _last := Vector2.ZERO
var _last_usec: int = 0
var _dragging: bool = false
## Speed (px/s, down when positive) of the scroll, kept going by a fling.
var _velocity: float = 0.0
var _flinging: bool = false


func _init() -> void:
	name = "Map"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clouds = _Clouds.new()
	add_child(_clouds)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	add_child(_Birds.new())
	_weather = CPUParticles2D.new()
	_weather.name = "Weather"
	_weather.local_coords = true
	add_child(_weather)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_content.position.x = roundf((size.x - WIDTH) * 0.5)
		_scroll_to(_content.position.y)
		_place_weather()


## Lays out world [param world]'s map and scrolls to the level to play next
## (to the flag once the world is finished, to the first level before the
## world opens).
func show_world(world: int) -> void:
	_world = world
	frozen = false
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_islands.clear()
	_badges = null
	_paths = LevelCatalog.levels(world)
	_height = 0.0
	if _paths.is_empty():
		return
	var palette: StringName = LevelLoader.load_file(_paths[0]).palette
	var look: Dictionary = MapDecor.look(palette)
	var sky: Dictionary = Palette.theme(palette)
	_season = Palette.season(palette)
	_weather_kind = Palette.weather(palette)
	_sway = 1.0 if world % 2 == 1 else -1.0
	var worlds: Array[int] = LevelCatalog.worlds()
	var place: int = worlds.find(world)
	_next_world = worlds[place + 1] if place >= 0 and place + 1 < worlds.size() else 0
	_gated = _next_world > 0 and not LevelCatalog.stars_open(_next_world)
	_goal_room = GOAL_ROOM + (GOAL_BUTTON_ROOM if _next_world > 0 else 0.0) + (GATE_NOTE.y if _gated else 0.0)
	var count: int = _paths.size()
	_height = _goal_rise() + _goal_room + TOP_SKY
	_content.size = Vector2(WIDTH, _height)

	# Levels open in play order: this world's first is that far into it.
	var first: int = LevelCatalog.all().find(_paths[0])
	var open_levels: int = clampi(LevelCatalog.open_count() - first, 0, count)
	var finished: bool = LevelCatalog.world_finished(world) == count
	# The level to play here: the first open one not finished yet.
	var next_index: int = -1
	for i in open_levels:
		if Progress.best(Progress.level_id(_paths[i])).is_empty():
			next_index = i
			break
	# The trail is walked up to the level to play, all the way once the
	# world is finished, and not at all before it opens.
	var walked: float = _rise(next_index) if next_index >= 0 else (_goal_rise() if finished else -INF)

	var chapters: int = ceili(count / float(CHAPTER))
	# The top island first, so each island stands in front of the one above.
	for chapter in range(chapters - 1, -1, -1):
		var island: _Island = _make_island(chapter, look, walked)
		_content.add_child(island)
		_islands.push_front(island)
	for chapter in chapters:
		if chapter * CHAPTER >= open_levels:
			var mist := _Mist.new()
			mist.size = _content.size
			mist.line = _height - (_rise(chapter * CHAPTER) - ISLAND_PAD)
			mist.haze = sky["sky_horizon"]
			_content.add_child(mist)
			break

	_badges = Control.new()
	_badges.name = "Badges"
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_badges)
	for i in count:
		_add_badge(i, i < open_levels, i == next_index)
	if _next_world > 0:
		_add_goal_button()
	if next_index >= 0:
		# Over the badges, with the parcel on the side away from the level
		# after, where nothing hides it.
		var ahead: float = _spot(next_index + 1).x if next_index + 1 < count else _trail_x(_goal_rise())
		var beacon := _Beacon.new(NEXT_BADGE * 0.5, -1.0 if ahead > _spot(next_index).x else 1.0)
		beacon.name = "Beacon"
		beacon.position = _spot(next_index)
		_badges.add_child(beacon)

	_clouds.tint = (sky["sky_horizon"] as Color).lerp(Color.WHITE, 0.6)
	_set_weather()
	_content.position.x = roundf((size.x - WIDTH) * 0.5)
	var focus: float = _rise(next_index) if next_index >= 0 else (_goal_rise() if finished else _rise(0))
	_scroll_to(_view_height() * FOCUS - (_height - focus))


## Scrolls the map [param amount] px down, bringing higher levels into view
## (back down when negative), as far as its ends.
func scroll_by(amount: float) -> void:
	_scroll_to(_content.position.y + amount)


## How far the map is scrolled: 0 with its top at the top of the screen,
## below 0 further down it.
func scroll_offset() -> float:
	return _content.position.y


## Level [param number]'s badge (null if there is none).
func badge(number: int) -> TouchButton:
	return _badges.get_node_or_null("Level_%d" % number) as TouchButton if _badges != null else null


func badge_count() -> int:
	return _paths.size() if _badges != null else 0


func island_count() -> int:
	return _islands.size()


func _input(event: InputEvent) -> void:
	if frozen or not is_visible_in_tree():
		_finger = -1
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _finger < 0 and _on_map(touch.position):
			_finger = touch.index
			_press = touch.position
			_last = touch.position
			_last_usec = Time.get_ticks_usec()
			_dragging = false
			_flinging = false
			_velocity = 0.0
		elif not touch.pressed and touch.index == _finger:
			_finger = -1
			if _dragging:
				_dragging = false
				# A finger that stopped before it lifted does not fling.
				_flinging = absf(_velocity) > FLING_MIN and Time.get_ticks_usec() - _last_usec < 100000
				get_viewport().set_input_as_handled()
			else:
				_poke(touch.position)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _finger:
		var drag := event as InputEventScreenDrag
		if not _dragging and _press.distance_to(drag.position) >= SCROLL_SLOP_PX:
			_dragging = true
			for child: Node in _badges.get_children():
				if child is TouchButton:
					(child as TouchButton).cancel()
		if _dragging:
			var moved: float = (drag.position.y - _last.y) / get_global_transform_with_canvas().get_scale().y
			var now: int = Time.get_ticks_usec()
			_velocity = clampf(lerpf(_velocity, moved / maxf((now - _last_usec) / 1000000.0, 0.001), 0.6),
				-FLING_MAX, FLING_MAX)
			_last = drag.position
			_last_usec = now
			scroll_by(moved)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var wheel: MouseButton = (event as InputEventMouseButton).button_index
		if wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_flinging = false
			scroll_by(WHEEL_SCROLL if wheel == MOUSE_BUTTON_WHEEL_UP else -WHEEL_SCROLL)


func _process(delta: float) -> void:
	if not _flinging:
		return
	var before: float = _content.position.y
	scroll_by(_velocity * delta)
	_velocity *= exp(-FLING_DECAY * delta)
	if absf(_velocity) < FLING_MIN or is_equal_approx(_content.position.y, before):
		_flinging = false


func _on_map(point: Vector2) -> bool:
	if not get_global_rect().has_point(point):
		return false
	for control: Control in overlays:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return false
	return true


## A tap on the scenery: a landmark hurries, a piece wobbles.
func _poke(point: Vector2) -> void:
	# The islands at the foot stand in front.
	for island: _Island in _islands:
		var local: Vector2 = island.get_global_transform().affine_inverse() * point
		for landmark: _Landmark in island.landmarks:
			if Rect2(landmark.position + landmark.box().position, landmark.box().size).has_point(local):
				landmark.poke()
				return
		var index: int = island.piece_at(local)
		if index >= 0:
			island.poke(index)
			return


func _scroll_to(y: float) -> void:
	var view: float = _view_height()
	if _height <= view:
		_content.position.y = roundf((view - _height) * 0.5)
	else:
		_content.position.y = clampf(y, view - _height, 0.0)
	_clouds.scroll = _content.position.y


func _view_height() -> float:
	return size.y if size.y > 0.0 else get_viewport_rect().size.y


## How far level [param index] (0 for the first) is up from the map's foot.
func _rise(index: int) -> float:
	return BOTTOM_ROOM + index * SPACING + floorf(index / float(CHAPTER)) * (SKY_GAP + ISLAND_PAD * 2.0 - SPACING)


## How far the flag is up from the map's foot.
func _goal_rise() -> float:
	return _rise(_paths.size() - 1) + GOAL_RISE


## Where the trail is across the map, [param rise] up from its foot.
func _trail_x(rise: float) -> float:
	return WIDTH * 0.5 + _sway * SWING * sin(TAU * (rise - BOTTOM_ROOM) / WAVELENGTH)


## Where level [param index]'s badge goes on the map.
func _spot(index: int) -> Vector2:
	return Vector2(_trail_x(_rise(index)), _height - _rise(index))


## Where the button for the next world goes on the map: over the flag.
func _goal_rect() -> Rect2:
	var middle := Vector2(clampf(_trail_x(_goal_rise()) + 28.0, GOAL_BUTTON.x * 0.5 + 24.0,
		WIDTH - GOAL_BUTTON.x * 0.5 - 24.0), _height - _goal_rise() - 180.0)
	return Rect2(middle - GOAL_BUTTON * 0.5, GOAL_BUTTON)


## Where the note over the button goes while the next world wants stars.
func _gate_note_rect() -> Rect2:
	var button: Rect2 = _goal_rect()
	var x: float = clampf(button.get_center().x - GATE_NOTE.x * 0.5, 8.0, WIDTH - GATE_NOTE.x - 8.0)
	return Rect2(Vector2(x, button.position.y - GATE_NOTE.y - 6.0), GATE_NOTE)


func _add_badge(index: int, open: bool, next: bool) -> void:
	var path: String = _paths[index]
	var best: Dictionary = Progress.best(Progress.level_id(path))
	var side: float = NEXT_BADGE if next else BADGE
	var button := TouchButton.new(Vector2(side, side))
	button.name = "Level_%d" % (index + 1)
	button.text = str(index + 1)
	button.font_size = 46 if next else 36
	button.position = _spot(index) - Vector2(side, side) * 0.5
	if next:
		button.color = Ui.ACCENT
		button.ink = Color.WHITE
		button.outline = Ui.CREAM
	elif not open:
		button.color = Ui.CREAM.darkened(0.1)
		button.disabled = true
		button.badge = &"lock"
	button.pressed.connect(func() -> void: level_chosen.emit(path))
	_badges.add_child(button)
	if not best.is_empty():
		var stars := StarRow.new(11.0, 2.0)
		stars.position = Vector2((side - stars.size.x) * 0.5, side - 12.0)
		stars.set_lit(int(best["stars"]), false)
		button.add_child(stars)


func _add_goal_button() -> void:
	var open: bool = LevelCatalog.is_unlocked(LevelCatalog.levels(_next_world)[0])
	var button := TouchButton.new(GOAL_BUTTON)
	button.name = "Goal"
	button.text = "On to %s" % LevelCatalog.world_name(_next_world)
	if _gated:
		button.text = "%d / %d stars" % [Progress.total_stars(), LevelCatalog.stars_needed(_next_world)]
		var note := Label.new()
		note.name = "GateNote"
		note.text = "Collect stars to open %s.\nA Hint shows the three-star route." % LevelCatalog.world_name(_next_world)
		note.label_settings = Ui.label_settings(24, Ui.INK)
		note.label_settings.outline_size = 12
		note.label_settings.outline_color = Ui.CREAM
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rect: Rect2 = _gate_note_rect()
		note.position = rect.position
		note.size = rect.size
		_badges.add_child(note)
	button.font_size = 28
	button.color = Ui.ACCENT if open else Ui.CREAM
	button.ink = Color.WHITE if open else Ui.INK
	button.disabled = not open
	if not open:
		button.badge = &"lock"
	button.position = _goal_rect().position
	var next_world: int = _next_world
	button.pressed.connect(func() -> void: world_chosen.emit(next_world))
	_badges.add_child(button)


## Island [param chapter] (0 for the first): its ground, its stretch of the
## trail with the bridge up to the next, and its scenery.
func _make_island(chapter: int, look: Dictionary, walked: float) -> _Island:
	var count: int = _paths.size()
	var first: int = chapter * CHAPTER
	var last: int = mini(first + CHAPTER, count) - 1
	var top: bool = last == count - 1
	var foot: float = _rise(first) - ISLAND_PAD
	var head: float = _goal_rise() + _goal_room if top else _rise(last) + ISLAND_PAD
	var island := _Island.new()
	island.name = "Island_%d" % (chapter + 1)
	island.position = Vector2(0.0, _height - head)
	island.size = Vector2(WIDTH, head - foot)
	island.season = _season
	island.ground = look["ground"]
	island.cliff = look["cliff"]
	island.trail = look["trail"]

	# The trail across it, from its foot (from under level 1 on the first)
	# to its head (to the flag on the last): solid as far as it has been
	# walked, dotted on from there.
	var from: float = foot if chapter > 0 else _rise(0) - 44.0
	var to: float = _goal_rise() if top else head
	var trod := PackedVector2Array()
	var ahead := PackedVector2Array()
	# How far left and right the trail goes on the island.
	var span := Vector2(INF, -INF)
	var rise: float = from
	while true:
		var point := Vector2(_trail_x(rise), head - rise)
		if rise <= walked:
			trod.append(point)
		else:
			ahead.append(point)
		span = Vector2(minf(span.x, point.x), maxf(span.y, point.x))
		if rise >= to:
			break
		rise = minf(rise + 10.0, to)
	island.walked = trod
	island.dots = _dotted(ahead, 26.0)

	# Scenery keeps off the badges and the stars under them, the flag and the
	# button for the next world.
	var blockers: Array[Rect2] = []
	for i in range(first, last + 1):
		var spot := Vector2(_trail_x(_rise(i)), head - _rise(i))
		blockers.append(Rect2(spot.x - 74.0, spot.y - 100.0, 148.0, 172.0))
	var flag := Vector2(_trail_x(_goal_rise()), head - _goal_rise())
	if top:
		blockers.append(Rect2(flag.x - 34.0, flag.y - 120.0, 104.0, 140.0))
		if _next_world > 0:
			var button: Rect2 = _goal_rect()
			blockers.append(Rect2(button.position - island.position, button.size).grow(16.0))
			if _gated:
				var note: Rect2 = _gate_note_rect()
				blockers.append(Rect2(note.position - island.position, note.size).grow(8.0))
	var dressing: Dictionary = _dress(chapter, island.size, head, span, look, blockers)
	island.outline = dressing["outline"]
	island.underside = dressing["underside"]
	island.patches.assign(dressing["patches"])
	island.pieces.assign(dressing["pieces"])
	for landmark: Array in dressing["landmarks"]:
		island.add_landmark(landmark[0], landmark[1])
	if top:
		island.add_landmark(&"goal", flag)
	if not top:
		var next_foot: float = _rise(last + 1) - ISLAND_PAD
		island.bridge = PackedVector2Array([Vector2(_trail_x(head - 14.0), 14.0),
			Vector2(_trail_x(next_foot + 14.0), head - next_foot - 14.0)])
	return island


## The ground, rock and scenery of island [param chapter], [param area] in
## size, its top [param head] up from the map's foot: ground round the
## trail, which goes from [param span].x to [param span].y across it, and
## on it a landmark of the world's and pieces scattered about, clear of the
## trail and of [param blockers].
func _dress(chapter: int, area: Vector2, head: float, span: Vector2, look: Dictionary,
		blockers: Array[Rect2]) -> Dictionary:
	var key: String = "%d/%d/%d" % [_world, chapter, roundi(area.y)]
	if _dressings.has(key):
		return _dressings[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var left: float = maxf(span.x - TRAIL_ROOM - rng.randf_range(0.0, 80.0), ISLAND_INSET)
	var right: float = minf(span.y + TRAIL_ROOM + rng.randf_range(0.0, 80.0), WIDTH - ISLAND_INSET)
	var ground := Rect2(left, 0.0, right - left, area.y)
	var corner: float = minf(rng.randf_range(CORNER.x, CORNER.y), minf(ground.size.x, ground.size.y) * 0.5)
	var patches: Array[Vector4] = []
	for attempt in 40:
		if patches.size() >= int(area.y / 150.0):
			break
		var at := Vector2(rng.randf_range(left + 74.0, right - 74.0), rng.randf_range(60.0, area.y - 60.0))
		if _on_island(at, ground, corner, 70.0):
			patches.append(Vector4(at.x, at.y, rng.randf_range(50.0, 100.0), rng.randf_range(22.0, 40.0)))

	var placed: Array[Rect2] = []
	var landmarks: Array = []
	var kinds: Array = look["landmarks"]
	var kind: StringName = kinds[chapter % kinds.size()]
	var spot: Vector2 = _find_spot(kind, 1.0, ground, corner, head, blockers, placed, rng, 80)
	if spot.is_finite():
		landmarks.append([kind, spot])
		var reach: Vector2 = MapDecor.extent(kind)
		# Room under it too, so nothing stands in front of it.
		blockers.append(Rect2(spot.x - reach.x - 10.0, spot.y - reach.y, reach.x * 2.0 + 20.0, reach.y + 34.0))

	var bag: Array[StringName] = []
	var weights: Dictionary = look["pieces"]
	for piece: StringName in weights:
		for i in int(weights[piece]):
			bag.append(piece)
	var pieces: Array[Dictionary] = []
	var wanted: int = clampi(int(area.y / 46.0), 4, 32)
	for attempt in wanted * 8:
		if pieces.size() >= wanted:
			break
		var piece: StringName = bag[rng.randi() % bag.size()]
		var scale_by: float = rng.randf_range(0.85, 1.15)
		var at: Vector2 = _find_spot(piece, scale_by, ground, corner, head, blockers, placed, rng, 1)
		if not at.is_finite():
			continue
		var reach: Vector2 = MapDecor.extent(piece) * scale_by
		placed.append(_foot(piece, Rect2(at.x - reach.x, at.y - reach.y, reach.x * 2.0, reach.y + 4.0)))
		pieces.append({"kind": piece, "at": at, "size": scale_by, "variant": rng.randi() % 12, "flip": rng.randf() < 0.5})
	# Back to front.
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector2).y < (b["at"] as Vector2).y)
	var dressing: Dictionary = {"outline": _outline(ground, corner, rng), "underside": _underside(ground, rng),
		"patches": patches, "pieces": pieces, "landmarks": landmarks}
	_dressings[key] = dressing
	return dressing


## A spot on an island's [param ground], with corners [param corner] round,
## where [param kind] stands at [param scale_by] clear of the trail, [param
## blockers] and the feet of [param placed] pieces, or Vector2.INF if [param
## tries] spots all fail.
func _find_spot(kind: StringName, scale_by: float, ground: Rect2, corner: float, head: float,
		blockers: Array[Rect2], placed: Array[Rect2], rng: RandomNumberGenerator, tries: int) -> Vector2:
	var reach: Vector2 = MapDecor.extent(kind) * scale_by
	for attempt in tries:
		var at := Vector2(rng.randf_range(ground.position.x + reach.x, ground.end.x - reach.x),
			rng.randf_range(reach.y * 0.4 + 10.0, ground.end.y - 12.0))
		if not (_on_island(at - Vector2(reach.x * 0.7, 0.0), ground, corner)
				and _on_island(at + Vector2(reach.x * 0.7, 0.0), ground, corner)):
			continue
		var body := Rect2(at.x - reach.x, at.y - reach.y, reach.x * 2.0, reach.y + 4.0)
		if _near_trail(body, head) or _overlaps(body, blockers) or _overlaps(_foot(kind, body), placed):
			continue
		return at
	return Vector2.INF


## Whether the trail passes near [param rect] on an island whose top is
## [param head] up from the map's foot.
func _near_trail(rect: Rect2, head: float) -> bool:
	# Kept wide, as the trail slants across.
	var margin: float = TRAIL_WIDTH * 0.5 + 20.0
	var y: float = rect.position.y - margin
	while y <= rect.end.y + margin:
		var x: float = _trail_x(head - y)
		if x > rect.position.x - margin and x < rect.end.x + margin:
			return true
		y += 8.0
	return false


## Petals in spring, leaves in autumn, snow in winter, motes of sunlight
## drifting up in summer, or dandelion seeds floating by.
func _set_weather() -> void:
	var colors: Array[Color] = []
	_weather.texture = _texture(&"petal" if _weather_kind in [&"spring", &"autumn"] else &"dot")
	_weather.lifetime = 16.0
	_weather.preprocess = 16.0
	_weather.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_weather.angle_min = 0.0
	_weather.angle_max = 360.0
	_weather.gravity = Vector2(6.0, 6.0)
	_weather.direction = Vector2(0.35, 1.0)
	_weather.spread = 20.0
	_weather.initial_velocity_min = 50.0
	_weather.initial_velocity_max = 80.0
	_weather.angular_velocity_min = -150.0
	_weather.angular_velocity_max = 150.0
	_weather.scale_amount_min = 0.8
	_weather.scale_amount_max = 1.3
	_weather.color_ramp = _fade(1.0, false)
	match _weather_kind:
		&"spring":
			colors.assign(PropFactory.BLOSSOMS)
			_weather.amount = 20
		&"autumn":
			colors.assign(PropFactory.AUTUMN_LEAVES)
			_weather.amount = 16
			_weather.angular_velocity_min = -220.0
			_weather.angular_velocity_max = 220.0
			_weather.scale_amount_min = 1.0
			_weather.scale_amount_max = 1.5
		&"winter":
			colors.append(PropFactory.SNOW)
			_weather.amount = 44
			_weather.direction = Vector2(0.1, 1.0)
			_weather.spread = 12.0
			_weather.initial_velocity_min = 40.0
			_weather.initial_velocity_max = 70.0
			_weather.scale_amount_min = 0.5
			_weather.scale_amount_max = 1.1
		&"seeds":
			_weather.texture = Effects.seed_texture()
			colors.assign([Color.WHITE, Color("#FFF6DF")])
			_weather.amount = 12
			_weather.gravity = Vector2(0.0, -3.0)
			_weather.direction = Vector2(1.0, -0.2)
			_weather.spread = 18.0
			_weather.initial_velocity_min = 18.0
			_weather.initial_velocity_max = 34.0
			_weather.angular_velocity_min = -40.0
			_weather.angular_velocity_max = 40.0
			_weather.scale_amount_min = 0.5
			_weather.scale_amount_max = 0.8
			_weather.color_ramp = _fade(0.9, true)
		_:
			colors.append(Color("#FFF6D8"))
			_weather.amount = 14
			_weather.gravity = Vector2(0.0, -2.0)
			_weather.direction = Vector2.UP
			_weather.spread = 40.0
			_weather.initial_velocity_min = 6.0
			_weather.initial_velocity_max = 14.0
			_weather.scale_amount_min = 0.4
			_weather.scale_amount_max = 0.8
			_weather.color_ramp = _fade(0.7, true)
	_weather.color_initial_ramp = _choices(colors)
	_place_weather()
	_weather.restart()


## Lets the weather fall from over the top of the screen, or, in summer,
## drift about all over it.
func _place_weather() -> void:
	if _weather_kind in [&"summer", &"seeds"]:
		_weather.position = size * 0.5
		_weather.emission_rect_extents = size * 0.5
	else:
		_weather.position = Vector2(size.x * 0.5, -24.0)
		_weather.emission_rect_extents = Vector2(size.x * 0.5 + 60.0, 8.0)


## Whether [param point] lies on an island's [param ground], with corners
## [param corner] round, [param inset] in from its edge.
static func _on_island(point: Vector2, ground: Rect2, corner: float, inset: float = 20.0) -> bool:
	var inner: Rect2 = ground.grow(-inset)
	if not inner.has_point(point):
		return false
	var round_by: float = maxf(corner - inset, 0.0)
	var nearest := Vector2(clampf(point.x, inner.position.x + round_by, inner.end.x - round_by),
		clampf(point.y, inner.position.y + round_by, inner.end.y - round_by))
	return point.distance_to(nearest) <= round_by


## The edge of an island's [param ground]: a box with corners [param
## radius] round and a gentle wave.
static func _outline(ground: Rect2, radius: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var left: float = ground.position.x
	var right: float = ground.end.x
	var bottom: float = ground.end.y
	# Each corner's centre, and the way its arc starts.
	var corners: Array[Vector3] = [
		Vector3(right - radius, radius, -PI * 0.5), Vector3(right - radius, bottom - radius, 0.0),
		Vector3(left + radius, bottom - radius, PI * 0.5), Vector3(left + radius, radius, PI),
	]
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	for i in 4:
		var corner: Vector3 = corners[i]
		var centre := Vector2(corner.x, corner.y)
		for step in 7:
			var out: Vector2 = Vector2.from_angle(corner.z + PI * 0.5 * step / 6.0)
			points.append(centre + out * radius)
			normals.append(out)
		var after: Vector3 = corners[(i + 1) % 4]
		var from: Vector2 = centre + Vector2.from_angle(corner.z + PI * 0.5) * radius
		var to: Vector2 = Vector2(after.x, after.y) + Vector2.from_angle(after.z) * radius
		var steps: int = int(from.distance_to(to) / 40.0)
		for step in range(1, steps):
			points.append(from.lerp(to, float(step) / steps))
			normals.append(Vector2.from_angle(corner.z + PI * 0.5))
	var waves := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var outline := PackedVector2Array()
	var along: float = 0.0
	for i in points.size():
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		outline.append(points[i] + normals[i] * (6.0 * sin(along * 0.021 + waves.x) + 4.0 * sin(along * 0.053 + waves.y)))
	return outline


## The rock hanging under an island's [param ground], jagged at the bottom.
static func _underside(ground: Rect2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var top: float = ground.end.y - 6.0
	var left: float = ground.position.x + 60.0
	var right: float = ground.end.x - 60.0
	var points := PackedVector2Array([Vector2(left, top), Vector2(right, top)])
	for i in range(1, 9):
		var t: float = i / 9.0
		var depth: float = sin(t * PI) * rng.randf_range(90.0, 150.0) * (1.0 if i % 2 == 0 else 0.75)
		points.append(Vector2(lerpf(right, left, t) + rng.randf_range(-10.0, 10.0), top + 30.0 + depth))
	return points


## Dots every [param gap] px along [param points].
static func _dotted(points: PackedVector2Array, gap: float) -> PackedVector2Array:
	var dots := PackedVector2Array()
	var next_at: float = gap * 0.5
	var travelled: float = 0.0
	for i in range(1, points.size()):
		var length: float = points[i - 1].distance_to(points[i])
		while next_at <= travelled + length:
			dots.append(points[i - 1].lerp(points[i], (next_at - travelled) / maxf(length, 0.001)))
			next_at += gap
		travelled += length
	return dots


## The part of a piece's [param body] others may not stand on: its foot, or
## all of a flat one.
static func _foot(kind: StringName, body: Rect2) -> Rect2:
	if kind in [&"pond", &"flowers"]:
		return body
	return Rect2(body.position.x, body.end.y - body.size.y * 0.45, body.size.x, body.size.y * 0.45)


static func _overlaps(rect: Rect2, others: Array[Rect2]) -> bool:
	for other: Rect2 in others:
		if rect.intersects(other):
			return true
	return false


## A puff of bits in [param colors] thrown up from [param at] in [param
## parent], falling and fading.
static func _burst(parent: Node, at: Vector2, radius: float, colors: Array[Color]) -> void:
	var burst := CPUParticles2D.new()
	burst.position = at
	burst.local_coords = true
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = 10
	burst.lifetime = 1.4
	burst.texture = _texture(&"petal")
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = radius
	burst.direction = Vector2.UP
	burst.spread = 75.0
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 130.0
	burst.gravity = Vector2(0.0, 260.0)
	burst.damping_min = 30.0
	burst.damping_max = 60.0
	burst.angle_min = 0.0
	burst.angle_max = 360.0
	burst.angular_velocity_min = -300.0
	burst.angular_velocity_max = 300.0
	burst.scale_amount_min = 0.8
	burst.scale_amount_max = 1.3
	burst.color_initial_ramp = _choices(colors)
	burst.color_ramp = _fade(1.0, false)
	parent.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


## A soft "petal" (an oval) or "dot" for particles, white to tint.
static func _texture(shape: StringName) -> Texture2D:
	if not _textures.has(shape):
		var texture := GradientTexture2D.new()
		texture.width = 18 if shape == &"petal" else 12
		texture.height = 10 if shape == &"petal" else 12
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
		texture.gradient = gradient
		_textures[shape] = texture
	return _textures[shape]


## One of [param colors] for each particle.
static func _choices(colors: Array[Color]) -> Gradient:
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	return ramp


## A particle's opacity over its life: [param peak], fading in first if
## [param fade_in], and out at the end.
static func _fade(peak: float, fade_in: bool) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0 if fade_in else peak), Color(1.0, 1.0, 1.0, peak),
		Color(1.0, 1.0, 1.0, peak), Color(1.0, 1.0, 1.0, 0.0)])
	return ramp


## One island: earth and rock under a grassy top, a stretch of the trail
## with the bridge up to the next island, and the scenery standing on it.
class _Island:
	extends Control

	## Seconds a tapped piece wobbles.
	const WOBBLE: float = 0.9

	var season: StringName
	var ground: Color
	var cliff: Color
	var trail: Color
	var outline: PackedVector2Array
	var underside: PackedVector2Array
	## Lighter patches of ground: centre (x, y) and size (z, w).
	var patches: Array[Vector4] = []
	## {"kind", "at", "size", "variant", "flip"}, back to front.
	var pieces: Array[Dictionary] = []
	## The trail as far as it has been walked, and dots along the rest.
	var walked := PackedVector2Array()
	var dots := PackedVector2Array()
	## The bridge up to the next island, from this one's top (none on the
	## last island).
	var bridge := PackedVector2Array()
	var landmarks: Array[LevelMap._Landmark] = []
	## Piece index -> seconds into its wobble.
	var _wobbles: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_process(false)

	func add_landmark(kind: StringName, at: Vector2) -> void:
		var landmark := LevelMap._Landmark.new(kind, season)
		landmark.position = at
		add_child(landmark)
		landmarks.append(landmark)

	## The piece at [param point] (front-most first), or -1.
	func piece_at(point: Vector2) -> int:
		for i in range(pieces.size() - 1, -1, -1):
			var piece: Dictionary = pieces[i]
			var reach: Vector2 = MapDecor.extent(piece["kind"]) * float(piece["size"])
			var at: Vector2 = piece["at"]
			if Rect2(at.x - reach.x, at.y - reach.y, reach.x * 2.0, reach.y + 8.0).grow(8.0).has_point(point):
				return i
		return -1

	## Wobbles piece [param index], and shakes a few bits off it.
	func poke(index: int) -> void:
		_wobbles[index] = 0.0
		set_process(true)
		var piece: Dictionary = pieces[index]
		var colors: Array[Color] = MapDecor.shed(piece["kind"], season, piece["variant"])
		if not colors.is_empty():
			var reach: Vector2 = MapDecor.extent(piece["kind"]) * float(piece["size"])
			LevelMap._burst(self, (piece["at"] as Vector2) - Vector2(0.0, reach.y * 0.6), reach.x * 0.7, colors)
		AudioManager.play(&"tap")
		Haptics.tap()

	func _process(delta: float) -> void:
		for index: int in _wobbles.keys():
			_wobbles[index] += delta
			if _wobbles[index] >= WOBBLE:
				_wobbles.erase(index)
		queue_redraw()
		if _wobbles.is_empty():
			set_process(false)

	func _draw() -> void:
		var edge: Color = ground.darkened(0.12)
		draw_colored_polygon(underside, cliff.darkened(0.24))
		_layer(LevelMap.CLIFF, cliff)
		_layer(LevelMap.CLIFF * 0.55, cliff.darkened(0.08))
		_layer(9.0, ground.darkened(0.16))
		_layer(0.0, ground)
		for i in patches.size():
			var patch: Vector4 = patches[i]
			MapDecor.ellipse(self, Vector2(patch.x, patch.y), Vector2(patch.z, patch.w),
				ground.lightened(0.06) if i % 2 == 0 else ground.darkened(0.035))
		if walked.size() > 1:
			_path(walked, LevelMap.TRAIL_WIDTH + 8.0, edge)
			_path(walked, LevelMap.TRAIL_WIDTH, trail)
		for dot: Vector2 in dots:
			draw_circle(dot, 8.0, edge, true, -1.0, true)
			draw_circle(dot, 6.0, trail, true, -1.0, true)
		if bridge.size() == 2:
			_bridge()
		for i in pieces.size():
			var piece: Dictionary = pieces[i]
			var turn: float = 0.0
			var squash: float = 0.0
			if _wobbles.has(i):
				var t: float = _wobbles[i]
				var swing: float = sin(t * 19.0) * exp(-t * 4.5)
				turn = swing * 0.22
				squash = swing * 0.07
			draw_set_transform(piece["at"], turn, Vector2((-1.0 if piece["flip"] else 1.0) * (1.0 + squash), 1.0 - squash))
			MapDecor.draw_piece(self, piece["kind"], piece["size"], season, piece["variant"])
		draw_set_transform(Vector2.ZERO)

	## The island's outline [param drop] px down, filled with [param color].
	func _layer(drop: float, color: Color) -> void:
		var shape: PackedVector2Array = Transform2D(0.0, Vector2(0.0, drop)) * outline
		draw_colored_polygon(shape, color)
		shape.append(shape[0])
		draw_polyline(shape, color, 1.5, true)

	func _path(points: PackedVector2Array, width: float, color: Color) -> void:
		draw_polyline(points, color, width, true)
		draw_circle(points[0], width * 0.5, color, true, -1.0, true)
		draw_circle(points[-1], width * 0.5, color, true, -1.0, true)

	## Planks between two ropes, across the sky to the next island.
	func _bridge() -> void:
		var from: Vector2 = bridge[0]
		var to: Vector2 = bridge[1]
		var along: Vector2 = (to - from).normalized()
		var side: Vector2 = along.orthogonal() * 22.0
		var planks: int = maxi(int(from.distance_to(to) / 13.0), 1)
		for i in planks + 1:
			var middle: Vector2 = from.lerp(to, float(i) / planks)
			draw_colored_polygon(PackedVector2Array([middle - side - along * 4.5, middle + side - along * 4.5,
				middle + side + along * 4.5, middle - side + along * 4.5]),
				PropFactory.PLANK if i % 2 == 0 else PropFactory.PLANK_DARK)
		for end: float in [-1.15, 1.15]:
			draw_line(from + side * end, to + side * end, PropFactory.BEAM, 3.0, true)
			draw_circle(from + side * end, 5.0, PropFactory.BEAM, true, -1.0, true)
			draw_circle(to + side * end, 5.0, PropFactory.BEAM, true, -1.0, true)


## A landmark on an island, which keeps moving (see MapDecor) and hurries
## for a moment when tapped.
class _Landmark:
	extends Control

	var kind: StringName
	var season: StringName
	var reach: Vector2
	var _time: float = 0.0
	## Extra speed after a tap (1 just after), wearing off.
	var _hurry: float = 0.0

	func _init(landmark: StringName, in_season: StringName) -> void:
		kind = landmark
		season = in_season
		reach = MapDecor.extent(landmark)
		_time = randf() * 20.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Where it stands around its foot.
	func box() -> Rect2:
		return Rect2(-reach.x, -reach.y, reach.x * 2.0, reach.y + 6.0)

	func poke() -> void:
		_hurry = 1.0
		var tween: Tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.08, 0.9), 0.08)
		tween.tween_property(self, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		AudioManager.play(&"whoosh" if kind in [&"goal", &"balloon"] else &"creak")
		Haptics.tap()

	func _process(delta: float) -> void:
		_hurry = maxf(_hurry - delta * 0.7, 0.0)
		_time += delta * (1.0 + _hurry * 5.0)
		if is_visible_in_tree() and (get_global_transform() * box()).intersects(get_viewport_rect()):
			queue_redraw()

	func _draw() -> void:
		MapDecor.draw_landmark(self, kind, 1.0, season, _time)


## Marks the level to play next: rings swelling out from its badge, and a
## parcel bobbing at its shoulder, on [member side].
class _Beacon:
	extends Control

	var radius: float
	## 1 for the parcel on the right, -1 on the left.
	var side: float
	var _parcel: StyleBoxFlat
	var _time: float = 0.0

	func _init(badge_radius: float, parcel_side: float) -> void:
		radius = badge_radius
		side = parcel_side
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_parcel = Ui.card(PropFactory.CRATE, 8)
		_parcel.shadow_size = 6
		_parcel.shadow_offset = Vector2(0.0, 4.0)

	func _process(delta: float) -> void:
		_time += delta
		var reach: float = radius + 60.0
		if is_visible_in_tree() and (get_global_transform() * Rect2(-reach, -reach, reach * 2.0, reach * 2.0)) \
				.intersects(get_viewport_rect()):
			queue_redraw()

	func _draw() -> void:
		for i in 2:
			var t: float = fmod(_time * 0.55 + i * 0.5, 1.0)
			draw_arc(Vector2.ZERO, radius + 6.0 + t * 30.0, 0.0, TAU, 48, Color(Ui.CREAM, 0.85 * (1.0 - t)),
				6.0 * (1.0 - t * 0.6), true)
		var bob: float = sin(_time * 2.8)
		draw_set_transform(Vector2(side * (radius * 0.85 + 16.0), -radius * 0.85 - 8.0 + bob * 6.0), side * (0.22 + bob * 0.06))
		var box := Rect2(-25.0, -21.0, 50.0, 42.0)
		draw_style_box(_parcel, box)
		draw_rect(Rect2(-4.0, box.position.y, 8.0, box.size.y), PropFactory.TAPE)
		for loop: float in [-1.0, 1.0]:
			draw_circle(Vector2(loop * 5.0, box.position.y - 3.0), 5.0, PropFactory.TAPE, false, 2.5, true)
		draw_set_transform(Vector2.ZERO)


## Haze over the islands not reached yet, behind a bank of cloud along the
## edge of the way so far.
class _Mist:
	extends Control

	## How far down the map the cloud bank lies.
	var line: float
	var haze: Color

	func _init() -> void:
		name = "Mist"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(-400.0, 0.0, size.x + 800.0, line), Color(haze, 0.34))
		var cloud: Color = haze.lerp(Color.WHITE, 0.7)
		for row in 2:
			var x: float = -420.0 + row * 34.0
			var i: int = 0
			while x < size.x + 420.0:
				var puff: float = 44.0 + 14.0 * sin(i * 1.9 + row)
				draw_circle(Vector2(x, line + 30.0 + row * 26.0 + 8.0 * sin(i * 2.7)), puff,
					cloud.darkened(0.05 * (1 - row)), true, -1.0, true)
				x += puff * 1.15
				i += 1


## Clouds drifting across behind the islands, a third as far as the map
## scrolls.
class _Clouds:
	extends Control

	## Each cloud: across and down (0 to 1), size, and drift (px/s).
	const PUFFS: Array[Vector4] = [
		Vector4(0.08, 0.05, 1.0, 7.0), Vector4(0.62, 0.2, 0.7, 11.0), Vector4(0.3, 0.37, 1.2, 5.0),
		Vector4(0.85, 0.52, 0.8, 9.0), Vector4(0.15, 0.68, 0.9, 8.0), Vector4(0.55, 0.85, 1.1, 6.0),
	]
	## A cloud's puffs: where (x, y) and how big.
	const BLOBS: Array[Vector3] = [
		Vector3(-44.0, 8.0, 26.0), Vector3(-14.0, -10.0, 36.0), Vector3(22.0, -2.0, 30.0), Vector3(50.0, 10.0, 20.0),
	]

	var tint := Color.WHITE
	var scroll: float = 0.0
	var _time: float = 0.0

	func _init() -> void:
		name = "Clouds"
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_time += delta
			queue_redraw()

	func _draw() -> void:
		var span: Vector2 = size + Vector2(360.0, 600.0)
		for puff: Vector4 in PUFFS:
			var at := Vector2(fposmod(puff.x * span.x + _time * puff.w, span.x) - 180.0,
				fposmod(puff.y * span.y + scroll * 0.35, span.y) - 300.0)
			for blob: Vector3 in BLOBS:
				draw_circle(at + Vector2(blob.x, blob.y) * puff.z, blob.z * puff.z, tint, true, -1.0, true)
			draw_rect(Rect2(at + Vector2(-44.0, 8.0) * puff.z, Vector2(94.0, 22.0) * puff.z), tint)


## A few birds flying across now and then.
class _Birds:
	extends Control

	## Seconds the flock takes to cross the screen.
	const CROSSING: float = 26.0
	const FLOCK: Array[Vector2] = [Vector2.ZERO, Vector2(-28.0, -15.0), Vector2(-28.0, 15.0)]

	var _time: float = 9.0

	func _init() -> void:
		name = "Birds"
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_time += delta
			queue_redraw()

	func _draw() -> void:
		var lead := Vector2(lerpf(-60.0, size.x + 100.0, fmod(_time, CROSSING) / CROSSING),
			size.y * 0.24 + sin(_time * 0.4) * 24.0)
		for i in FLOCK.size():
			var at: Vector2 = lead + FLOCK[i]
			var flap: float = sin(_time * 7.5 + i * 1.9) * 5.0
			draw_polyline(PackedVector2Array([at + Vector2(-12.0, -3.0 - flap), at + Vector2(-5.0, -flap * 0.3), at,
				at + Vector2(5.0, -flap * 0.3), at + Vector2(12.0, -3.0 - flap)]), Color(Ui.INK, 0.45), 2.5, true)
