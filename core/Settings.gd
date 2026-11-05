class_name Settings
extends RefCounted
## The player's settings: music and sound volumes, tilt-shift, haptics, the
## graphics quality, the daily reminders (see Reminders) and the statistics
## and crash reports (see Analytics). Kept as JSON in
## user://settings.json, written whole
## to a temporary file and then moved into place (like Progress). Everything
## is static; the file is read on first use.
##
## [signal changed] fires on [member events] after every change, so the
## audio buses, the camera blur and the renderer follow at once.

enum Quality { LOW, MEDIUM, HIGH }

const DEFAULT_PATH: String = "user://settings.json"
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Most pixels the 3D view is drawn with at each quality (a 1080 x 2400
## phone has 2.6 million): see [method apply_quality].
const PIXEL_BUDGET: Array[float] = [0.8e6, 1.3e6, 2.6e6]

static var path: String = DEFAULT_PATH
## Emits changed(key: StringName) after each change.
static var events := Events.new()

## 0 to 1.
static var music: float = 0.7
static var sfx: float = 0.9
static var tilt_shift: bool = true
static var haptics: bool = true
static var quality: Quality = Quality.HIGH
## The daily reminders (Android only).
static var reminders: bool = true
## Statistics and crash reports (Android only), and whether the player has
## said either way: on the menu's question, or in Settings. Where the
## player must be asked first, nothing is sent until they say yes.
static var statistics: bool = true
static var statistics_asked: bool = false

static var _loaded: bool = false


class Events:
	extends RefCounted
	signal changed(key: StringName)


## Switches to another settings file (tests use their own); with
## [param fresh] it starts from the defaults and deletes what was there.
static func use_file(file_path: String, fresh: bool = true) -> void:
	path = file_path
	if fresh:
		_defaults()
		_loaded = true
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		load_file()


## Reads settings from the file (on first use).
static func ensure_loaded() -> void:
	if not _loaded:
		load_file()


## Changes one setting ("music", "sfx", "tilt_shift", "haptics", "quality",
## "reminders" or "statistics", which also counts as the player's answer),
## saves (unless [param persist] is false, as while a slider is still being
## dragged) and tells everyone.
static func set_value(key: StringName, value: Variant, persist: bool = true) -> void:
	ensure_loaded()
	match key:
		&"music":
			music = clampf(value, 0.0, 1.0)
		&"sfx":
			sfx = clampf(value, 0.0, 1.0)
		&"tilt_shift":
			tilt_shift = bool(value)
		&"haptics":
			haptics = bool(value)
		&"quality":
			quality = clampi(int(value), Quality.LOW, Quality.HIGH) as Quality
		&"reminders":
			reminders = bool(value)
		&"statistics":
			statistics = bool(value)
			statistics_asked = true
		_:
			push_warning("Settings: no setting %s" % key)
			return
	if persist:
		save()
	if key == &"quality":
		apply_quality((Engine.get_main_loop() as SceneTree).root)
	events.changed.emit(key)


static func get_value(key: StringName) -> Variant:
	ensure_loaded()
	match key:
		&"music":
			return music
		&"sfx":
			return sfx
		&"tilt_shift":
			return tilt_shift
		&"haptics":
			return haptics
		&"quality":
			return quality
		&"reminders":
			return reminders
		&"statistics":
			return statistics
		&"statistics_asked":
			return statistics_asked
	return null


## Decibels for a 0 to 1 slider: a gentle curve so the low end still fades
## smoothly, and silence at 0.
static func volume_db(amount: float) -> float:
	return -80.0 if amount <= 0.001 else linear_to_db(amount * amount)


## Applies the graphics quality to [param viewport]: the 3D render size,
## multisampling, the shadow map size and softness, and the tilt-shift blur.
## StageLighting does the rest (shadow splits, glow). On phones the frame
## rate is held at 60 whatever the screen can do, to spare the battery.
##
## The 3D view is drawn at no more than [constant PIXEL_BUDGET] pixels and
## scaled up to the screen; the interface is drawn at full size, so its text
## stays sharp. Most of a frame's cost is per pixel (the blur, multisampling,
## the sky), so this is what lets a large phone screen keep up.
static func apply_quality(viewport: Viewport) -> void:
	ensure_loaded()
	match quality:
		Quality.LOW:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		Quality.MEDIUM:
			viewport.msaa_3d = Viewport.MSAA_2X
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		Quality.HIGH:
			viewport.msaa_3d = Viewport.MSAA_4X
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	# Below High the tilt-shift blur takes fewer samples in a box, which
	# looks much the same on a soft background at a fraction of the cost.
	if quality == Quality.HIGH:
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_LOW, false)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_HEXAGON)
	else:
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_VERY_LOW, false)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_BOX)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_fit_render_scale(viewport)
	if not viewport.size_changed.is_connected(_fit_render_scale):
		viewport.size_changed.connect(_fit_render_scale.bind(viewport))
	if OS.has_feature("mobile"):
		Engine.max_fps = 60


## The share of [param viewport]'s width (and height) the 3D view is drawn at.
static func render_scale(viewport: Viewport) -> float:
	var pixels: Vector2 = Vector2((viewport as Window).size) if viewport is Window else Vector2((viewport as SubViewport).size)
	return clampf(sqrt(PIXEL_BUDGET[quality] / maxf(pixels.x * pixels.y, 1.0)), 0.5, 1.0)


static func _fit_render_scale(viewport: Viewport) -> void:
	viewport.scaling_3d_scale = render_scale(viewport)


static func save() -> void:
	var text: String = JSON.stringify({
		"music": music, "sfx": sfx, "tilt_shift": tilt_shift, "haptics": haptics,
		"quality": QUALITY_NAMES[quality].to_lower(), "reminders": reminders,
		"statistics": statistics, "statistics_asked": statistics_asked,
	}, "\t")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	file.close()
	var error: Error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		push_warning("Settings: cannot replace %s (%s)" % [path, error_string(error)])


## Reads the settings file; anything missing or unreadable keeps its default.
static func load_file() -> void:
	_loaded = true
	_defaults()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Settings: %s is unreadable; using the defaults" % path)
		return
	if typeof(parsed.get("music")) in [TYPE_INT, TYPE_FLOAT]:
		music = clampf(parsed["music"], 0.0, 1.0)
	if typeof(parsed.get("sfx")) in [TYPE_INT, TYPE_FLOAT]:
		sfx = clampf(parsed["sfx"], 0.0, 1.0)
	if typeof(parsed.get("tilt_shift")) == TYPE_BOOL:
		tilt_shift = parsed["tilt_shift"]
	if typeof(parsed.get("haptics")) == TYPE_BOOL:
		haptics = parsed["haptics"]
	var level: int = QUALITY_NAMES.find(str(parsed.get("quality", "")).capitalize())
	if level >= 0:
		quality = level as Quality
	if typeof(parsed.get("reminders")) == TYPE_BOOL:
		reminders = parsed["reminders"]
	if typeof(parsed.get("statistics")) == TYPE_BOOL:
		statistics = parsed["statistics"]
	if typeof(parsed.get("statistics_asked")) == TYPE_BOOL:
		statistics_asked = parsed["statistics_asked"]


static func _defaults() -> void:
	music = 0.7
	sfx = 0.9
	tilt_shift = true
	haptics = true
	reminders = true
	statistics = true
	statistics_asked = false
	# Phones start on Medium, which a mid-range one runs at 60 fps.
	quality = Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH
