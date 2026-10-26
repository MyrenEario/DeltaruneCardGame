# test_plueypoker.gd
extends "res://tests/UTcommon.gd"

func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")

func test_pluey_cards_loaded():
	assert_gt(cfc.card_definitions.size(), 70, "Should have loaded Pluey cards")
	assert_true(cfc.card_definitions.has("Dess"), "Should have Dess")
	assert_true(cfc.card_definitions.has("Roaring Knight"), "Should have Roaring Knight")
	assert_true(cfc.card_definitions.has("Stick Antler Susie"), "Should have Stick Antler Susie")

func test_card_instantiation():
	var knight = cfc.instance_card("Roaring Knight")
	cfc.NMAP.board.add_child(knight)
	assert_not_null(knight, "Knight should be instanced")
	assert_eq(knight.properties.get("LV"), 7, "Knight LV should be 7")
	assert_eq(knight.properties.get("Cost"), 15, "Knight Cost should be 15")
	knight.queue_free()

func test_tag_note_ignored_for_matching():
	var relations = load("res://src/custom/cards/TagRelations.gd").new()
	relations.setup(
			[["𝅘𝅥𝅮Music", "Sound"]],
			[["𝅘𝅥𝅮Lancer", "Pierce"]],
			["𝅘𝅥𝅮Lancer", "Music"])
	assert_true(relations.related("𝅘𝅥𝅮Lancer", "Lancer"), "Note prefix should be ignored")
	assert_true(relations.related("Lancer", "𝅘𝅥𝅮Lancer"), "Note prefix should be ignored both ways")
	assert_true(relations.implies("Lancer", "Pierce"), "Note prefix should be ignored in implications")
	assert_true(relations.related("𝅘𝅥𝅮Music", "Sound"), "Note prefix should be ignored in equalities")
	assert_eq(relations.count_matches(["𝅘𝅥𝅮Lancer"], ["Lancer", "Music"]), 1)
	assert_eq(relations.count_matches(["𝅘𝅥𝅮Lancer", "Lancer"], ["Lancer"]), 1,
			"Duplicate spellings of the same tag should count once")
	assert_false("𝅘𝅥𝅮Lancer" in relations.tags, "Tag universe should use normalized names")


func test_card_name_is_implicit_specific_tag():
	var lancer = cfc.instance_card("December Holiday Lancer")
	cfc.NMAP.board.add_child(lancer)
	var lancer_tags = lancer._all_tags(lancer)
	assert_true("Lancer" in lancer_tags, "Prefixed card should have its unprefixed name as a tag")
	assert_false("December Holiday Lancer" in lancer_tags, "Prefixed full name should not be the implicit tag")
	lancer.queue_free()
	var dess = cfc.instance_card("Dess")
	cfc.NMAP.board.add_child(dess)
	assert_true("Dess" in dess._all_tags(dess), "Unprefixed card should have its name as a tag")
	dess.queue_free()


func test_tag_cost_reduction():
	var dess = cfc.instance_card("Dess")
	var knight = cfc.instance_card("Roaring Knight")
	
	cfc.NMAP.board.turn_manager.active_player = 0
	var zone = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	zone.name = "Player1Zone"
	cfc.NMAP.board.add_child(zone)
	cfc.NMAP["player1zone"] = zone
	var slot = zone.find_available_slot()
	cfc.NMAP.board.add_child(dess)
	cfc.NMAP.board.add_child(knight)
	slot.occupying_card = dess
	dess.current_owner = 0
	
	assert_eq(knight.get_calculated_cost(), 15,
			"Playing into a free slot applies no tag reductions")
	assert_eq(knight.get_calculated_cost(dess), 12,
			"Roaring Knight cost should be reduced from 15 to 12 by the normal Antlers match, rounded up")
	
	zone.queue_free()
	dess.queue_free()
	knight.queue_free()
