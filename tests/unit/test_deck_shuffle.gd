extends "res://tests/UTcommon.gd"


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")


func _names(pile) -> Array:
	var names := []
	for card in pile.get_all_cards():
		names.append(card.canonical_name)
	return names


func test_deck_load_shuffles_synchronously():
	var deck := {
		"name": "Test Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 3, "Aaron": 3, "Bloxer": 3, "Lancer": 3},
		"total": 12,
	}
	var pile = board.get_node("Deck")
	cfc.game_rng_seed = "seed-one"
	board._clear_deck(pile)
	board._load_deck_into(pile, deck)
	var first := _names(pile)
	cfc.game_rng_seed = "seed-two"
	board._clear_deck(pile)
	board._load_deck_into(pile, deck)
	var second := _names(pile)
	assert_eq(first.size(), 12, "All cards loaded")
	assert_ne(first, second,
			"Different game seeds produce different deck orders")
