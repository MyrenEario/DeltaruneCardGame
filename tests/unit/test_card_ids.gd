extends "res://tests/UTcommon.gd"

const CARD_EDITOR = preload("res://src/custom/CardEditor/CardEditor.tscn")


func before_each():
	cfc.is_testing = true
	cfc._setup()


func test_every_card_has_a_unique_id():
	var seen := {}
	for card_name in cfc.card_definitions.keys():
		var card = cfc.card_definitions[card_name]
		var card_id := str(card.get("id", ""))
		assert_false(card_id.empty(), "%s has an id" % card_name)
		assert_false(seen.has(card_id), "id is unique: %s" % card_id)
		seen[card_id] = card_name


func test_id_and_name_maps_round_trip():
	for card_name in cfc.card_definitions.keys():
		var card_id := cfc.card_id_for_name(card_name)
		assert_false(card_id.empty(), "%s has an id" % card_name)
		assert_eq(cfc.card_name_for_id(card_id), card_name)


func test_resolve_accepts_a_name_or_an_id():
	var card_id := cfc.card_id_for_name("Kris")
	assert_false(card_id.empty())
	assert_eq(cfc.resolve_card_name("Kris"), "Kris")
	assert_eq(cfc.resolve_card_name(card_id), "Kris")
	assert_eq(cfc.resolve_card_id("Kris"), card_id)
	assert_eq(cfc.resolve_card_id(card_id), card_id)
	assert_eq(cfc.resolve_card_name("No Such Card"), "")


func test_editor_assigns_and_preserves_ids():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.2), YIELD)
	var new_card = editor._default_card()
	assert_false(str(new_card.get("id", "")).empty(), "New card gets an id")
	var kept = editor._with_id({}, str(new_card["id"]))
	assert_eq(str(kept["id"]), str(new_card["id"]), "Existing id is preserved")
	var fresh = editor._with_id({}, "")
	assert_false(str(fresh["id"]).empty(), "A missing id is replaced")
	assert_ne(str(fresh["id"]), str(new_card["id"]), "A fresh id is different")
