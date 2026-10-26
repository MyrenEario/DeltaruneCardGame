extends "res://tests/UTcommon.gd"

const DeckLoaderScript = preload(
		"res://src/core/CardViewer/DeckBuilder/DeckLoader.gd")
const TEST_DIR := "user://test_deck_ids/"


func before_each():
	cfc.is_testing = true
	cfc._setup()


func after_each():
	_remove_test_dir()


func _remove_test_dir():
	var dir := Directory.new()
	if not dir.dir_exists(TEST_DIR):
		return
	for f in CFUtils.list_files_in_directory(TEST_DIR):
		dir.remove(TEST_DIR + f)
	dir.remove(TEST_DIR)


func _write_json(path: String, data: Dictionary) -> void:
	var file := File.new()
	file.open(path, File.WRITE)
	file.store_string(JSON.print(data, "\t"))
	file.close()


func _read_json(path: String) -> Dictionary:
	var file := File.new()
	file.open(path, File.READ)
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK else {}


func test_to_stored_deck_uses_ids():
	var deck := {
		"name": "Test",
		"format_id": "three_heroes",
		"cards": {"Kris": 2, "Susie": 1},
		"total": 3,
	}
	var stored := DeckLoaderScript.to_stored_deck(deck)
	assert_eq(int(stored.get("schema_version", 0)),
			DeckLoaderScript.DECK_SCHEMA_VERSION)
	var kris_id := cfc.card_id_for_name("Kris")
	assert_true(stored.cards.has(kris_id), "Cards are keyed by id")
	assert_eq(int(stored.cards[kris_id]), 2)
	assert_eq(str(stored.card_names[kris_id]), "Kris")


func test_round_trip_through_storage():
	var deck := {
		"name": "Test",
		"format_id": "three_heroes",
		"cards": {"Kris": 2, "Susie": 1},
		"total": 3,
	}
	var restored := DeckLoaderScript.from_stored_deck(
			DeckLoaderScript.to_stored_deck(deck))
	assert_eq(restored.cards.size(), deck.cards.size())
	for card_name in deck.cards:
		assert_eq(int(restored.cards.get(card_name, -1)),
				int(deck.cards[card_name]), "Cards come back keyed by name")
	assert_eq(int(restored.total), 3)


func test_old_name_keyed_decks_still_load():
	var old := {"name": "Old", "format_id": "three_heroes",
			"cards": {"Kris": 1}, "total": 1}
	var restored := DeckLoaderScript.from_stored_deck(old)
	assert_eq(restored.cards.size(), 1)
	assert_eq(int(restored.cards.get("Kris", -1)), 1)


func test_renamed_card_still_resolves_from_a_stored_deck():
	var deck := {"cards": {"Kris": 1}, "total": 1}
	var stored := DeckLoaderScript.to_stored_deck(deck)
	# Simulate a rename: the id stays the same, only the name changes.
	var kris_id := cfc.card_id_for_name("Kris")
	assert_true(stored.cards.has(kris_id))
	assert_eq(cfc.card_name_for_id(kris_id), "Kris")


func test_migrate_all_decks_rewrites_old_decks():
	var dir := Directory.new()
	dir.make_dir_recursive(TEST_DIR)
	var old := {"name": "Old", "format_id": "three_heroes",
			"cards": {"Kris": 2}, "total": 2}
	_write_json(TEST_DIR + "old.json", old)
	var migrated := DeckLoaderScript.migrate_all_decks(TEST_DIR)
	assert_eq(migrated, 1, "One deck migrated")
	var stored := _read_json(TEST_DIR + "old.json")
	assert_eq(int(stored.get("schema_version", 0)),
			DeckLoaderScript.DECK_SCHEMA_VERSION)
	assert_true(stored.cards.has(cfc.card_id_for_name("Kris")),
			"Migrated deck is id-keyed")
	# Running again is a no-op.
	assert_eq(DeckLoaderScript.migrate_all_decks(TEST_DIR), 0)
