extends "res://tests/UTcommon.gd"

const CGF_BOARD = preload("res://src/custom/CGFBoard.tscn")

var match_board


func before_each():
	cfc.is_testing = true
	cfc._setup()
	match_board = add_child_autofree(CGF_BOARD.instance())
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")


func after_each():
	cfc.game_paused = false
	teardown_board()


func test_match_loads_a_separate_deck_per_player():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 8},
		"total": 8,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck)
	assert_eq(match_board.get_player_deck(0).get_card_count(), 3)
	assert_eq(match_board.get_player_hand(0).get_card_count(), 5)
	assert_eq(match_board.get_player_deck(1).get_card_count(), 8)
	assert_eq(match_board.get_player_hand(1).get_card_count(), 0)
	assert_true(match_board.get_player_deck(0).visible)
	assert_false(match_board.get_player_deck(1).visible)


func test_each_deck_draws_into_its_own_hand():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 1},
		"total": 1,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 1},
		"total": 1,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck)
	assert_true(match_board.get_player_deck(0).is_connected(
			"draw_card", match_board.get_player_hand(0), "draw_card"))
	assert_true(match_board.get_player_deck(1).is_connected(
			"draw_card", match_board.get_player_hand(1), "draw_card"))
	assert_false(match_board.get_player_deck(1).is_connected(
			"draw_card", match_board.get_player_hand(0), "draw_card"))


func test_active_player_switches_visible_containers():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 1},
		"total": 1,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 1},
		"total": 1,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck)
	match_board.turn_manager.end_turn()
	assert_false(match_board.get_player_deck(0).visible)
	assert_true(match_board.get_player_deck(1).visible)
	assert_false(match_board.get_player_hand(0).visible)
	assert_true(match_board.get_player_hand(1).visible)

func test_turn_start_draws_to_five_then_draws_one():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 8},
		"total": 8,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck)
	assert_eq(match_board.get_player_hand(0).get_card_count(), 5)
	assert_eq(match_board.get_player_deck(0).get_card_count(), 3)
	match_board.turn_manager.end_turn()
	assert_eq(match_board.get_player_hand(1).get_card_count(), 5)
	assert_eq(match_board.get_player_deck(1).get_card_count(), 3)
	match_board.turn_manager.end_turn()
	assert_eq(match_board.get_player_hand(0).get_card_count(), 6)
	assert_eq(match_board.get_player_deck(0).get_card_count(), 2)


func test_deck_click_is_not_drawing_cards():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 8},
		"total": 8,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck)
	var deck = match_board.get_player_deck(0)
	assert_false(deck.get_node("Control").is_connected(
			"gui_input", deck, "_on_Deck_input_event"))


func test_ai_match_locks_input_on_ai_turn_and_unlocks_on_human_turn():
	var player1_deck := {
		"name": "Player 1 Deck",
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	var player2_deck := {
		"name": "Player 2 Deck",
		"format_id": "three_heroes",
		"cards": {"Berdly": 8},
		"total": 8,
	}
	match_board.start_match("three_heroes", player1_deck, player2_deck, 1)
	assert_false(match_board.is_ai_turn(), "Player 1 starts and is human")
	assert_false(match_board.get_node("AIInputBlocker").visible, "Input blocker hidden on P1 turn")
	assert_false(match_board.get_node("TurnInfo/NextPhaseBtn").disabled, "NextPhaseBtn enabled on P1 turn")

	match_board.set_input_locked(true)
	assert_true(match_board.get_node("AIInputBlocker").visible, "Input blocker visible when locked")
	assert_true(match_board.get_node("TurnInfo/NextPhaseBtn").disabled, "NextPhaseBtn disabled when locked")
	assert_true(match_board.mouse_pointer.is_disabled, "MousePointer disabled when locked")

	match_board.set_input_locked(false)
	assert_false(match_board.get_node("AIInputBlocker").visible, "Input blocker hidden when unlocked")
	assert_false(match_board.get_node("TurnInfo/NextPhaseBtn").disabled, "NextPhaseBtn enabled when unlocked")
	assert_false(match_board.mouse_pointer.is_disabled, "MousePointer enabled when unlocked")
