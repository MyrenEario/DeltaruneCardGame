extends "res://tests/UTcommon.gd"

const CARD_PREVIEW = preload("res://src/core/CardViewer/CVGridCardObject.tscn")


func _layout_card(card_name):
	cfc.is_testing = true
	cfc._setup()
	var holder = CenterContainer.new()
	holder.rect_min_size = Vector2(150, 240)
	add_child_autofree(holder)
	var obj = CARD_PREVIEW.instance()
	holder.add_child(obj)
	var card = cfc.instance_card(card_name)
	obj.setup(card)
	return card


func test_empty_abilities_are_hidden():
	var card = _layout_card("Jevil")
	yield(yield_for(0.8), YIELD)
	var abilities = card.card_front.find_node("Abilities")
	assert_false(abilities.visible, "Empty abilities box is hidden")


func test_tags_reserve_only_the_lines_they_need():
	var card = _layout_card("Jevil")
	yield(yield_for(0.8), YIELD)
	var tags = card.card_front.find_node("Tags")
	assert_lt(tags.rect_min_size.y, 70.0,
			"Tags reserve fewer than the full five lines")


func test_illustration_grows_past_old_cap():
	var card = _layout_card("Jevil")
	yield(yield_for(0.8), YIELD)
	var illustration = card.card_front.find_node("Illustration")
	# The old layout overflowed and pinned the art to its ~17px floor at the
	# thumbnail scale; it should now be a healthy size instead.
	assert_gt(illustration.rect_size.y, 25.0,
			"Illustration grew well past the old minimum")


func test_illustration_expands_vertically():
	var card = _layout_card("Dess")
	yield(yield_for(0.8), YIELD)
	var illustration = card.card_front.find_node("Illustration")
	assert_eq(illustration.size_flags_vertical, Control.SIZE_EXPAND_FILL,
			"Illustration is the element that absorbs spare space")

func test_obeys_text_is_shown():
	var card = _layout_card("8-bit Kris")
	yield(yield_for(1.5), YIELD)
	var obeys = card.card_front.card_labels.get("Weakness")
	assert_not_null(obeys, "Weakness label exists")
	assert_true(obeys.visible, "Obeys text is shown")
	assert_eq(str(obeys.text), "Obeys: Kris")


func test_obeys_text_hidden_without_controller():
	var card = _layout_card("Dess")
	yield(yield_for(0.8), YIELD)
	var obeys = card.card_front.card_labels.get("Weakness")
	assert_not_null(obeys)
	assert_false(obeys.visible, "No Obeys text when there is no controller")

func test_weakness_display_variants():
	var card = _layout_card("Dess")
	yield(yield_for(1.0), YIELD)
	var node = card.card_front.card_labels.get("Weakness")
	assert_not_null(node)

	card.properties["WeaknessType"] = "Fight"
	card.properties["Weakness"] = ["Mad Ghost", "Fire"]
	card.card_front._apply_weakness()
	yield(yield_for(0.8), YIELD)
	assert_true(node.visible)
	assert_eq(str(node.text), "Weakness: Mad Ghost, Fire")

	card.properties["WeaknessType"] = "Mercy"
	card.properties["Weakness"] = ["Kris"]
	card.card_front._apply_weakness()
	yield(yield_for(0.8), YIELD)
	assert_eq(str(node.text), "Likes: Kris")

	card.properties["WeaknessType"] = "Control"
	card.properties["Weakness"] = ["Rouxls"]
	card.card_front._apply_weakness()
	yield(yield_for(0.8), YIELD)
	assert_eq(str(node.text), "Obeys: Rouxls")


func test_lv_stays_top_right_without_prefix():
	var card = _layout_card("Aaron")
	yield(yield_for(1.0), YIELD)
	var front = card.card_front
	var row = front.find_node("HeaderRow")
	var lv = front.find_node("LV")
	assert_eq(lv.align, 2, "LV text is right-aligned")
	assert_almost_eq(lv.rect_position.x + lv.rect_size.x, row.rect_size.x, 1.0,
			"LV is pinned to the right edge of the header row")


func test_lv_stays_top_right_with_prefix():
	var card = _layout_card("Apolitical Plugboy")
	yield(yield_for(1.0), YIELD)
	var front = card.card_front
	var row = front.find_node("HeaderRow")
	var lv = front.find_node("LV")
	assert_almost_eq(lv.rect_position.x + lv.rect_size.x, row.rect_size.x, 1.0,
			"LV is pinned to the right edge of the header row")


func test_lv_stays_top_right_in_hover_preview():
	cfc.is_testing = true
	cfc._setup()
	var popup = load("res://src/core/CardViewer/CVPreviewPopup.tscn").instance()
	add_child_autofree(popup)
	popup.show_preview_card("Aaron")
	yield(yield_for(1.5), YIELD)
	var front = popup.preview_card.card_front
	var row = front.find_node("HeaderRow")
	var lv = front.find_node("LV")
	assert_gt(row.rect_size.x, front.rect_size.x * 0.85,
			"Header row spans the card width")
	assert_almost_eq(lv.rect_position.x + lv.rect_size.x, row.rect_size.x, 1.0,
			"LV is pinned to the right edge in the hover preview")
