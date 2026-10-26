extends "res://tests/UTcommon.gd"

const GameFormatScript = preload("res://src/custom/formats/GameFormat.gd")


func before_each():
	cfc.is_testing = true
	cfc._setup()


func after_each():
	GameFormatScript.delete_format("test_format_ids")


func test_builtin_formats_load_objectives_as_names():
	var format := GameFormatScript.load_format(
			"res://src/custom/formats/three_heroes.json")
	assert_false(format.empty())
	assert_eq(format.objective_cards.size(), 3)
	for expected in ["First Hero", "Second Hero", "Third Hero"]:
		assert_true(expected in format.objective_cards,
				"%s resolved from its id" % expected)


func test_normalize_converts_ids_to_names():
	var card_id = cfc.card_id_for_name("First Hero")
	var normalized := GameFormatScript.normalize({
		"id": "x", "name": "X",
		"objective_cards": [card_id], "banned_cards": [],
	})
	assert_eq(str(normalized.objective_cards[0]), "First Hero")


func test_refs_are_saved_as_ids():
	var ids = GameFormatScript._refs_to_ids(["First Hero", "Second Hero"])
	assert_eq(str(ids[0]), cfc.card_id_for_name("First Hero"))
	assert_eq(str(ids[1]), cfc.card_id_for_name("Second Hero"))


func test_save_format_persists_ids():
	var format := {
		"id": "test_format_ids",
		"name": "Test",
		"objective_cards": ["First Hero"],
		"banned_cards": ["Second Hero"],
		"min_deck_size": 1,
		"max_deck_size": 60,
		"max_copies": 3,
	}
	assert_eq(GameFormatScript.save_format(format), OK)
	var file := File.new()
	assert_eq(file.open("user://Formats/test_format_ids.json", File.READ), OK)
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	assert_eq(parsed.error, OK)
	assert_eq(str(parsed.result.objective_cards[0]),
			cfc.card_id_for_name("First Hero"))
	assert_eq(str(parsed.result.banned_cards[0]),
			cfc.card_id_for_name("Second Hero"))


func test_builtin_format_validates_name_keyed_decks():
	var format := GameFormatScript.load_format(
			"res://src/custom/formats/three_heroes.json")
	var errors := GameFormatScript.validate_deck(
			{"cards": {"Kris": 3, "Susie": 3}, "total": 6}, format)
	for error in errors:
		assert_ne(str(error.code), "unknown_card")
		assert_ne(str(error.code), "banned_card")
