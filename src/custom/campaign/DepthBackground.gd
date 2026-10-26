# A looping "endless zoom" background built from a single small image.
#
# The image is tiled 4 times, mirrored horizontally and vertically about the
# centre of the screen, so the four copies fill the whole screen and join
# seamlessly. Inside every quadrant a number of copies of the same image are
# drawn on top; each one starts already filling the quadrant and then slowly
# zooms further in while fading out, staggered so that there is always another
# one growing behind it. Because the copies never get smaller than a full
# quadrant, the image's edge is never visible - it just keeps zooming into the
# picture.
extends Control

const TEXTURE_PATH := "res://assets/IMAGE_DEPTH_0.png"
# How many zooming copies live in each of the four mirrored quadrants.
const INSTANCES_PER_QUADRANT := 10
# Seconds for one copy to go from its smallest to its largest size.
const LOOP_PERIOD := 14.0
# Scale range of a zooming copy, relative to its quadrant size.
#
# MIN_SCALE is 1.0 on purpose: at scale 1 a copy exactly fills its quadrant, so
# the copies only ever zoom *further in* from there. The image's outer border
# can therefore never be seen - we only ever see a more and more zoomed-in part
# of it.
const MIN_SCALE := 1.0
const MAX_SCALE := 2.0
# Zoom interpolation. Linear is the original hand-tuned look. Geometric keeps
# the perceived zoom speed constant (equal time = equal growth ratio), which
# makes the copies evenly spaced in size.
export var geometric_scale := true
# Tweens used to soften the appear/disappear of each copy (fractions of t).
const FADE_IN_PORTION := 0.5
const FADE_OUT_PORTION := 0.5

var _texture: Texture = null
var _container: Control = null
# One dictionary per animated copy: {node, phase}
var _zoom_instances := []
var _elapsed := 4.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_clip_content = true
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_texture = load(TEXTURE_PATH)
	_container = Control.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_container)
	get_viewport().connect("size_changed", self, "_on_viewport_resized")
	connect("resized", self, "_on_viewport_resized")
	# rect_size is not resolved until after the first layout pass, so build on
	# the next idle frame instead of directly in _ready().
	call_deferred("_rebuild")
	set_process(true)


func _on_viewport_resized() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_instance_valid(_container):
		return
	for child in _container.get_children():
		child.queue_free()
	_zoom_instances = []
	if _texture == null:
		return
	var full := rect_size
	if full.x <= 0.0 or full.y <= 0.0:
		return
	var quad := full / 2.0
	# First pass: the four static mirrored tiles that always fill the screen.
	for qy in [0, 1]:
		for qx in [0, 1]:
			var placement := _quadrant_placement(qx, qy, quad)
			var tile := _make_piece(quad, placement["pos"],
					placement["pivot"], qx == 1, qy == 1)
			tile.modulate = Color(1, 1, 1, 1)
			_container.add_child(tile)
	# Second pass: the zooming copies, drawn above the tiles.
	for qy in [0, 1]:
		for qx in [0, 1]:
			var placement := _quadrant_placement(qx, qy, quad)
			for i in range(INSTANCES_PER_QUADRANT):
				var node := _make_piece(quad, placement["pos"],
						placement["pivot"], qx == 1, qy == 1)
				node.modulate = Color(1, 1, 1, 0)
				_container.add_child(node)
				_zoom_instances.append({
					"node": node,
					"phase": float(i) / float(INSTANCES_PER_QUADRANT),
				})


# Places a quadrant-sized copy so that the corner which faces the centre of the
# screen sits exactly on the centre. Because that corner is also the scale
# pivot, growing the copy keeps that corner pinned to the screen centre and
# slides the rest of the copy outward, so the copy's inner border always stays
# aligned with the quadrant's inner border.
func _quadrant_placement(qx: int, qy: int, quad: Vector2) -> Dictionary:
	return {
		"pos": Vector2(qx * quad.x, qy * quad.y),
		"pivot": Vector2((1 - qx) * quad.x, (1 - qy) * quad.y),
	}


func _make_piece(piece_size: Vector2, piece_pos: Vector2, piece_pivot: Vector2,
		flip_h: bool, flip_v: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _texture
	rect.rect_size = piece_size
	rect.rect_position = piece_pos
	rect.rect_pivot_offset = piece_pivot
	rect.expand = true
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.flip_h = flip_h
	rect.flip_v = flip_v
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _process(delta: float) -> void:
	_elapsed += delta
	for instance in _zoom_instances:
		var node = instance["node"]
		if not is_instance_valid(node):
			continue
		var t: float = fmod(_elapsed / LOOP_PERIOD + instance["phase"], 1.0)
		var scale_value := _scale_at(t)
		node.rect_scale = Vector2(scale_value, scale_value)
		node.modulate.a = _fade(t)


func _scale_at(t: float) -> float:
	if geometric_scale:
		# Exponential zoom: equal time -> equal *ratio* of growth, so the
		# copies are evenly spaced in size and the perceived zoom speed is
		# constant.
		return MIN_SCALE * pow(MAX_SCALE / MIN_SCALE, t)
	# Linear zoom (the original look): equal time -> equal absolute growth.
	return lerp(MIN_SCALE, MAX_SCALE, t)


# Fully transparent at the very start and end, opaque in the middle, so copies
# gently fade in while small and fade out as they grow.
func _fade(t: float) -> float:
	var fade_in := clamp(t / FADE_IN_PORTION, 0.0, 1.0)
	var fade_out := clamp((1.0 - t) / FADE_OUT_PORTION, 0.0, 1.0)
	return min(fade_in, fade_out)
