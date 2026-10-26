extends "res://tests/UTcommon.gd"

const CAMPAIGN_START = preload("res://src/custom/campaign/CampaignStart.tscn")
const DEPTH_SCRIPT = preload("res://src/custom/campaign/DepthBackground.gd")


func _open_scene():
	cfc.is_testing = true
	cfc._setup()
	var holder := Control.new()
	holder.rect_min_size = Vector2(1280, 720)
	holder.rect_size = Vector2(1280, 720)
	add_child_autofree(holder)
	var scene = CAMPAIGN_START.instance()
	holder.add_child(scene)
	return scene


func test_first_objective_shows_its_options():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	assert_eq(scene.get_step_index(), 0)
	assert_eq(scene.get_objective_name(), "First Hero")
	assert_eq(scene.get_options().size(), 3)
	var options = scene.get_node("Options")
	assert_eq(options.get_child_count(), 3, "One clickable option per candidate")
	assert_true(options.get_child(0) is Button, "Options are buttons")


func test_choosing_an_option_adds_to_deck_and_advances():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	scene._on_option_pressed("Kris")
	yield(yield_for(0.1), YIELD)
	assert_eq(scene.get_deck(), ["Kris"], "Chosen card was added to the deck")
	assert_eq(scene.get_objective_name(), "Second Hero")
	assert_eq(scene.get_options(), ["Susie", "Noelle", "Dess", "Aqua"])


func test_all_three_objectives_can_be_answered():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	scene._on_option_pressed("Kris")
	yield(yield_for(0.1), YIELD)
	assert_eq(scene.get_objective_name(), "Second Hero")
	scene._on_option_pressed("Noelle")
	yield(yield_for(0.1), YIELD)
	assert_eq(scene.get_objective_name(), "Third Hero")
	scene._on_option_pressed("Ralsei")
	yield(yield_for(0.1), YIELD)
	assert_eq(scene.get_deck(), ["Kris", "Noelle", "Ralsei"])
	assert_eq(scene.get_step_index(), 3, "All three heroes answered")
	assert_eq(scene.get_objective_name(), "")


func test_after_three_heroes_recommendations_appear():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	scene._on_option_pressed("Ribcage Roaring Knight")
	yield(yield_for(0.1), YIELD)
	scene._on_option_pressed("Dess")
	yield(yield_for(0.1), YIELD)
	scene._on_option_pressed("Mantle Boss ERAM")
	yield(yield_for(0.3), YIELD)
	assert_true(scene.get_node("Recommendations").visible,
			"Recommendation list is shown")
	assert_gt(scene.get_node("Recommendations/Grid").get_child_count(), 0,
			"Recommended cards are listed")


func test_adding_a_recommended_card_grows_the_deck():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	scene._deck = ["Ribcage Roaring Knight", "Dess", "Mantle Boss ERAM"]
	scene._show_recommendations()
	yield(yield_for(0.3), YIELD)
	var entry = scene._count_labels.keys()[0]
	var before = scene.get_deck().size()
	scene._on_recommend_pressed(entry)
	assert_eq(scene.get_deck().size(), before + 1, "Deck grew by one")


func test_recommendations_cap_copies_at_three():
	var scene = _open_scene()
	yield(yield_for(0.3), YIELD)
	scene._deck = ["Ribcage Roaring Knight", "Dess", "Mantle Boss ERAM"]
	scene._show_recommendations()
	yield(yield_for(0.3), YIELD)
	var entry = scene._count_labels.keys()[0]
	for _i in range(6):
		scene._on_recommend_pressed(entry)
	assert_eq(scene._card_count(entry), 3, "At most three copies of a card")


func test_depth_background_builds_tiles_and_zoom_copies():
	var scene = _open_scene()
	yield(yield_for(0.4), YIELD)
	var depth = scene.get_node("Depth")
	assert_eq(depth._zoom_instances.size(), 40,
			"4 mirrored quadrants x 10 zooming copies")
	# The container also holds the four static mirrored tiles.
	assert_eq(depth._container.get_child_count(), 44,
			"4 static tiles + 40 animated copies")


func test_zoom_copies_grow_over_time():
	var scene = _open_scene()
	yield(yield_for(0.4), YIELD)
	var depth = scene.get_node("Depth")
	var node = depth._zoom_instances[0]["node"]
	var before = node.rect_scale.x
	yield(yield_for(0.6), YIELD)
	var after = node.rect_scale.x
	assert_gt(after, before, "The copy is zooming in")


func test_copy_sizes_are_linearly_spaced_by_default():
	var scene = _open_scene()
	var depth = scene.get_node("Depth")
	assert_false(depth.geometric_scale, "Linear zoom is the default")
	yield(yield_for(0.4), YIELD)
	var scales := []
	for i in range(DEPTH_SCRIPT.INSTANCES_PER_QUADRANT):
		scales.append(depth._zoom_instances[i]["node"].rect_scale.x)
	scales.sort()
	var expected_step = (DEPTH_SCRIPT.MAX_SCALE - DEPTH_SCRIPT.MIN_SCALE) \
			/ float(DEPTH_SCRIPT.INSTANCES_PER_QUADRANT)
	for i in range(1, scales.size()):
		assert_almost_eq(scales[i] - scales[i - 1], expected_step, 0.001,
				"Consecutive copy sizes share a constant difference")


func test_copy_sizes_are_geometrically_spaced_when_enabled():
	var scene = _open_scene()
	var depth = scene.get_node("Depth")
	depth.geometric_scale = true
	yield(yield_for(0.4), YIELD)
	var scales := []
	for i in range(DEPTH_SCRIPT.INSTANCES_PER_QUADRANT):
		scales.append(depth._zoom_instances[i]["node"].rect_scale.x)
	scales.sort()
	var expected_ratio = pow(DEPTH_SCRIPT.MAX_SCALE / DEPTH_SCRIPT.MIN_SCALE,
			1.0 / float(DEPTH_SCRIPT.INSTANCES_PER_QUADRANT))
	for i in range(1, scales.size()):
		assert_almost_eq(scales[i] / scales[i - 1], expected_ratio, 0.001,
				"Consecutive copy sizes share a constant ratio")


func test_copies_never_shrink_below_a_full_quadrant():
	var scene = _open_scene()
	yield(yield_for(0.4), YIELD)
	var depth = scene.get_node("Depth")
	for instance in depth._zoom_instances:
		var value = instance["node"].rect_scale.x
		assert_true(value >= DEPTH_SCRIPT.MIN_SCALE - 0.0001,
				"A copy is never smaller than one quadrant (no visible edge)")


func test_zoom_copies_pin_their_inner_corner_to_screen_centre():
	var scene = _open_scene()
	yield(yield_for(0.4), YIELD)
	var depth = scene.get_node("Depth")
	var centre = depth.rect_size / 2.0
	for instance in depth._zoom_instances:
		var node = instance["node"]
		assert_eq(node.rect_position + node.rect_pivot_offset, centre,
				"Inner corner is pinned to the screen centre")


func test_zoom_copy_alpha_stays_in_range():
	var scene = _open_scene()
	yield(yield_for(0.4), YIELD)
	var depth = scene.get_node("Depth")
	for instance in depth._zoom_instances:
		var alpha = instance["node"].modulate.a
		assert_between(alpha, 0.0, 1.0, "Alpha stays valid")
