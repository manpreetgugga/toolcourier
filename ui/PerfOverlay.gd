class_name PerfOverlay
extends CanvasLayer
## A small readout for checking the game on a phone: frames per second, the
## CPU and GPU time of a frame, draw calls, the size the 3D view is drawn at
## and memory. Five quick taps on the version number at the foot of the
## settings card turn it on and off. It sits on the tree's root, so it stays
## up across scenes, and is not saved.
##
## Memory is shown as what the engine has allocated plus video memory; the
## whole app's share of the phone's memory comes from adb (see the README).

const UPDATE_EVERY: float = 0.5

static var _shown: PerfOverlay

var _label: Label
var _viewport_rid: RID
var _wait: float = 0.0


## Shows the readout, or takes it away if it is up.
static func toggle() -> void:
	if is_shown():
		_shown.queue_free()
		_shown = null
		return
	_shown = PerfOverlay.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_shown)


static func is_shown() -> bool:
	return is_instance_valid(_shown) and not _shown.is_queued_for_deletion()


func _init() -> void:
	name = "PerfOverlay"
	# Above the scene-change veil, and running while the game is paused.
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var safe := Control.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)
	Ui.fit_to_safe_area(safe)
	var panel := PanelContainer.new()
	var box: StyleBoxFlat = Ui.card(Color(Ui.CREAM, 0.85), 18)
	box.set_content_margin_all(14.0)
	panel.add_theme_stylebox_override(&"panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under the pause button, clear of the HUD and the menu's star count.
	panel.position = Vector2(16.0, 190.0)
	safe.add_child(panel)
	_label = Label.new()
	_label.label_settings = Ui.label_settings(18)
	panel.add_child(_label)
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_refresh()


func _exit_tree() -> void:
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = UPDATE_EVERY
		_refresh()


func _refresh() -> void:
	var window := get_viewport() as Window
	var size_3d := Vector2i(Vector2(window.size) * window.scaling_3d_scale)
	_label.text = "\n".join([
		"%d fps" % Engine.get_frames_per_second(),
		"CPU %.1f · GPU %.1f ms" % [RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)],
		"%d draw calls" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"3D %d×%d %s" % [size_3d.x, size_3d.y, Settings.QUALITY_NAMES[Settings.quality]],
		"%d + %d MB video" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0],
	])
