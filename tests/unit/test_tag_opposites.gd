extends "res://tests/UTcommon.gd"

const TagRelations = preload("res://src/custom/cards/TagRelations.gd")

var p2: BoardPlacementGrid


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")
	cfc.NMAP.board.turn_manager.active_player = 0
	p2 = load("res://src/core/BoardPlacementGrid.tscn").instance()
	p2.name = "Player2Zone"
	board.add_child(p2)
	for _i in range(3):
		p2.add_slot()
	cfc.NMAP["player2zone"] = p2


func _make_card(card_name: String):
	var card = cfc.instance_card(card_name)
	board.add_child(card)
	return card


func _place_in_zone(card, zone, owner: int) -> void:
	var slot = zone.find_available_slot()
	slot.occupying_card = card
	card._placement_slot = slot
	card.current_owner = owner
	card.original_owner = owner


func test_tag_opposites_affect_cost_and_attack():
	var pairs = TagRelations.load_opposite_pairs()
	var has_shining_darkness := false
	for pair in pairs:
		if pair.size() < 2:
			continue
		var a := TagRelations.normalize_tag(pair[0])
		var b := TagRelations.normalize_tag(pair[1])
		if (a == "Shining" and b == "Darkness") \
				or (a == "Darkness" and b == "Shining"):
			has_shining_darkness = true
	assert_true(has_shining_darkness, "The tag opposites file defines Shining/Darkness")

	var relations = TagRelations.new()
	relations.setup([], [], ["Shining", "Darkness"], pairs)
	assert_true(relations.are_opposites("Shining", "Darkness"),
			"Opposites are detected in the stored direction")
	assert_true(relations.are_opposites("Darkness", "Shining"),
			"Opposites are symmetric")
	assert_eq(relations.count_opposites(["Shining"], ["Darkness"]), 1,
			"Opposing tags are counted once per tag")

	var rouxls = _make_card("Shining Rouxls")
	var gaster = _make_card("Entry 17 Gaster")
	var rudinn = _make_card("Rudinn")
	assert_false(rouxls.can_use_for_cost_reduction(gaster),
			"Shining Rouxls has no matching tag with Gaster")
	assert_eq(rouxls.get_calculated_cost(gaster), 21,
			"Specific Shining/Darkness adds 2x Gaster's LV to the cost")

	_place_in_zone(gaster, p2, 1)
	assert_true(rouxls.can_be_placed_on_occupied_slot(gaster._placement_slot),
			"Opposing tags make the occupied slot a valid cost target")

	var tm = cfc.NMAP.board.turn_manager
	tm.execute_attack(rudinn, gaster)
	assert_eq(gaster.accumulated_attack, 2,
			"Rudinn's 1 Attack gains 1 for its opposite Shining tag")


func test_tag_editor_opposites_round_trip():
	var editor = load("res://src/custom/TagEditor/TagEditor.gd").new()
	editor.OPPOSITES_FILE = "user://tag_opposites_gut_test.json"
	editor.opposite_pairs = [["Darkness", "Shining"], ["B", "A"],
			["Shining", "Darkness"]]
	assert_true(editor._write_opposites(), "Opposites are written")
	editor.opposite_pairs = []
	editor._load_opposites()
	assert_eq(editor.opposite_pairs, [["A", "B"], ["Darkness", "Shining"]],
			"Opposite pairs are sorted and deduplicated")
	assert_true(editor._has_opposite_pair("Shining", "Darkness"),
			"Stored pairs are found in either direction")
	assert_true(editor._has_opposite_pair("Darkness", "Shining"),
			"Stored pairs are found in either direction")
	var dir := Directory.new()
	dir.remove(editor.OPPOSITES_FILE)
	editor.free()
