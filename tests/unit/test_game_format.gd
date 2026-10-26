extends "res://tests/UTcommon.gd"

const GameFormat = preload("res://src/custom/formats/GameFormat.gd")
const PATH_DECKBUILDER = "res://src/custom/CGFDeckbuilder/CGFDeckBuilder.tscn"
const PATH_FORMAT_EDITOR = "res://src/custom/FormatEditor/FormatEditor.tscn"
const TEST_FORMAT_ID = "gut_test_format"
const TEST_DECK_NAME = "GUT Format Deck"

var deckbuilder


func before_each():
	cfc.is_testing = true
	cfc._setup()
	cfc.game_settings.deckbuilder_gridstyle = false


func after_each():
	cfc.game_settings.deckbuilder_gridstyle = true
	GameFormat.delete_format(TEST_FORMAT_ID)
	var dir := Directory.new()
	if dir.file_exists(CFConst.DECKS_PATH + TEST_DECK_NAME + ".json"):
		dir.remove(CFConst.DECKS_PATH + TEST_DECK_NAME + ".json")


func test_builtin_formats_load():
	var formats = GameFormat.load_all(false)
	assert_eq(formats.size(), 3, "All built-in formats load")
	assert_true(formats.has("three_heroes"))
	assert_true(formats.has("roaring_knight"))
	assert_true(formats.has("lord_of_the_hammer"))
	assert_eq(formats.three_heroes.objective_cards,
			["First Hero", "Second Hero", "Third Hero"])


func test_objectives_are_implicitly_banned():
	var format = GameFormat.new_format("example", "Example")
	format.objective_cards = ["First Hero", "Second Hero"]
	format.banned_cards = ["Third Hero", "First Hero"]
	assert_eq(GameFormat.effective_banned(format),
			["First Hero", "Second Hero", "Third Hero"],
			"Objectives are merged into the banned list without duplicates")


func test_validate_format():
	var definitions = {"First Hero": {}, "Second Hero": {}}
	var format = GameFormat.new_format("example", "Example")
	format.objective_cards = ["First Hero"]
	format.banned_cards = ["Second Hero"]
	assert_eq(GameFormat.validate_format(format, definitions).size(), 0,
			"Valid format has no errors")
	format.objective_cards = ["Missing Card"]
	assert_eq(GameFormat.validate_format(format, definitions)[0].code,
			"unknown_card", "Unknown objective cards are rejected")
	format.objective_cards = []
	assert_eq(GameFormat.validate_format(format, definitions)[0].code,
			"no_objectives", "Formats require objectives")


func test_validate_deck_bans_and_limits():
	var definitions = {"First Hero": {}, "Second Hero": {}, "Dess": {}}
	var format = GameFormat.new_format("example", "Example")
	format.objective_cards = ["First Hero"]
	format.banned_cards = ["Second Hero"]
	format.min_deck_size = 2
	format.max_deck_size = 4
	format.max_copies = 2
	var deck = {"cards": {"First Hero": 1, "Second Hero": 1}, "total": 2}
	var codes := []
	for format_error in GameFormat.validate_deck(deck, format, definitions):
		codes.append(format_error.code)
	assert_true("banned_card" in codes, "Objective cards are banned in decks")
	assert_false("too_few_cards" in codes, "Valid deck size accepted")
	deck = {"cards": {"Dess": 3}, "total": 3}
	codes = []
	for format_error in GameFormat.validate_deck(deck, format, definitions):
		codes.append(format_error.code)
	assert_true("too_many_copies" in codes, "Copy limit enforced")
	deck = {"cards": {"Dess": 1}, "total": 1}
	codes = []
	for format_error in GameFormat.validate_deck(deck, format, definitions):
		codes.append(format_error.code)
	assert_true("too_few_cards" in codes, "Minimum deck size enforced")


func test_user_format_save_and_load():
	var format = GameFormat.new_format(TEST_FORMAT_ID, "GUT Format")
	format.objective_cards = ["First Hero"]
	assert_eq(GameFormat.save_format(format), OK, "User format saves")
	var formats = GameFormat.load_all()
	assert_true(formats.has(TEST_FORMAT_ID), "User format loads")
	assert_eq(formats[TEST_FORMAT_ID].name, "GUT Format")
	assert_eq(GameFormat.delete_format(TEST_FORMAT_ID), OK,
			"User format deletes")


func test_format_editor_creates_and_saves_format():
	var editor = add_child_autofree(load(PATH_FORMAT_EDITOR).instance())
	yield(yield_for(0.1), YIELD)
	assert_eq(editor._format_list.get_item_count(), 3,
			"Format editor lists built-in formats")
	editor._on_New_pressed()
	editor._id_edit.text = TEST_FORMAT_ID
	editor._name_edit.text = "Editor Format"
	editor._open_card_picker("objective_cards")
	editor._card_search.text = "First Hero"
	editor._filter_card_picker("First Hero")
	editor._card_picker_list.select(0)
	editor._add_picker_selection()
	assert_eq(editor._format.objective_cards, ["First Hero"],
			"Editor adds objective card")
	editor._on_Save_pressed()
	assert_eq(editor._validation_label.text, "Format saved",
			"Editor validates and saves format")
	var formats = GameFormat.load_all()
	assert_true(formats.has(TEST_FORMAT_ID), "Editor format is persisted")
	assert_eq(formats[TEST_FORMAT_ID].name, "Editor Format")
	editor._on_Delete_pressed()
	assert_false(GameFormat.load_all().has(TEST_FORMAT_ID),
			"Editor deletes user formats")


func test_deck_builder_saves_format_and_removes_banned_cards():
	deckbuilder = add_child_autofree(load(PATH_DECKBUILDER).instance())
	yield(yield_for(0.2), YIELD)
	var format_index = deckbuilder._format_ids.find("three_heroes")
	assert_ne(format_index, -1, "Three Heroes format available")
	deckbuilder._format_select.select(format_index)
	deckbuilder._on_format_selected(format_index)
	var first_hero = _find_list_card("First Hero")
	var dess = _find_list_card("Dess")
	assert_not_null(first_hero)
	assert_not_null(dess)
	assert_eq(first_hero.max_allowed, 0, "Banned card cannot be added")
	assert_gt(dess.max_allowed, 0, "Non-banned card can be added")
	dess.set_quantity(1)
	deckbuilder._deck_name.text = TEST_DECK_NAME
	deckbuilder._on_Save_pressed()
	var file := File.new()
	assert_eq(file.open(CFConst.DECKS_PATH + TEST_DECK_NAME + ".json",
			File.READ), OK, "Formatted deck saves")
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	assert_eq(parsed.result.format_id, "three_heroes",
			"Deck stores its format")
	deckbuilder._on_Reset_pressed()
	deckbuilder._on_deck_loaded(parsed.result)
	assert_eq(deckbuilder._format_ids[deckbuilder._format_select.selected],
			"three_heroes", "Deck load restores its format")
	first_hero = _find_list_card("First Hero")
	dess = _find_list_card("Dess")
	assert_eq(first_hero.quantity, 0, "Banned cards stay out after load")
	assert_eq(dess.quantity, 1, "Allowed cards reload")


func _find_list_card(card_name: String):
	for list_card_object in deckbuilder._available_cards.get_children():
		if list_card_object.card_name == card_name:
			return list_card_object
	return null
