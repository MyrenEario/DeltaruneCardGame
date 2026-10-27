extends "res://tests/UTcommon.gd"

const CGF_BOARD = preload("res://src/custom/CGFBoard.tscn")
const CAMPAIGN_SCREEN = preload(
		"res://src/custom/campaign/CampaignScreen.tscn")
const CAMPAIGN_PROGRESS = preload(
		"res://src/custom/campaign/CampaignProgress.gd")
const GameFormat = preload("res://src/custom/formats/GameFormat.gd")

const TEST_SAVE_PATH := "user://test_campaign_progress.json"
const TEST_DECK_NAME := "campaign_player_deck_test"


func after_each():
	var dir := Directory.new()
	if dir.file_exists(TEST_SAVE_PATH):
		dir.remove(TEST_SAVE_PATH)
	if dir.file_exists(CFConst.DECKS_PATH + TEST_DECK_NAME + ".json"):
		dir.remove(CFConst.DECKS_PATH + TEST_DECK_NAME + ".json")
	cfc.campaign_player_deck_name = ""


func test_main_menu_has_campaign_button():
	cfc.is_testing = true
	cfc._setup()
	var menu = add_child_autofree(
			load("res://src/custom/MainMenu.tscn").instance())
	yield(yield_for(0.2), YIELD)
	var buttons = menu.get_node("MainMenu/VBox/Center/VButtons")
	assert_not_null(buttons.get_node_or_null("Campaign"),
			"Main menu exposes a Campaign entry")


func test_screen_lists_opponents_with_locks():
	cfc.is_testing = true
	cfc._setup()
	var screen = add_child_autofree(CAMPAIGN_SCREEN.instance())
	yield(yield_for(0.2), YIELD)
	var opponent_list = screen.get_node(
			"Center/Panel/Margin/VBox/OpponentList")
	assert_eq(opponent_list.get_child_count(), 6, "Six opponents listed")
	assert_false(opponent_list.get_child(0).disabled, "King is unlocked")
	assert_true(opponent_list.get_child(1).disabled, "Queen starts locked")


func test_opponent_detail_does_not_list_hero_candidates():
	cfc.is_testing = true
	cfc._setup()
	var screen = add_child_autofree(CAMPAIGN_SCREEN.instance())
	yield(yield_for(0.2), YIELD)
	screen._select_opponent("king")
	yield(yield_for(0.1), YIELD)
	assert_eq(screen._detail_label.text.find("Heroes"), -1,
			"Opponent detail no longer lists fixed hero candidates")
	assert_eq(screen._detail_label.text.find("Variant 1 Vessel"), -1,
			"The renamed starter card is not shown as a fixed hero")


func test_screen_offers_starter_deck():
	cfc.is_testing = true
	cfc._setup()
	var screen = add_child_autofree(CAMPAIGN_SCREEN.instance())
	yield(yield_for(0.2), YIELD)
	var starter_found := false
	for deck in screen.player_decks:
		if str(deck.get("name", "")) == "Three Heroes Starter":
			starter_found = true
			assert_eq(GameFormat.deck_total(deck), 20)
	assert_true(starter_found, "Starter deck is available in the campaign")


func test_new_campaign_deck_is_selected_by_default():
	cfc.is_testing = true
	cfc._setup()
	cfc.campaign_player_deck_name = TEST_DECK_NAME
	var dir := Directory.new()
	if not dir.dir_exists(CFConst.DECKS_PATH):
		dir.make_dir(CFConst.DECKS_PATH)
	var path := CFConst.DECKS_PATH + TEST_DECK_NAME + ".json"
	var deck := {
		"name": TEST_DECK_NAME,
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	var file := File.new()
	assert_eq(file.open(path, File.WRITE), OK)
	file.store_string(JSON.print(DeckLoader.to_stored_deck(deck), "\t"))
	file.close()
	var screen = add_child_autofree(CAMPAIGN_SCREEN.instance())
	yield(yield_for(0.3), YIELD)
	var found := -1
	for i in range(screen.player_decks.size()):
		if str(screen.player_decks[i].get("name", "")) == TEST_DECK_NAME:
			found = i
	assert_gt(found, -1, "Saved campaign deck appears in the selector")
	assert_eq(screen._deck_select.selected, found,
			"The saved campaign deck is selected by default")


func test_deck_builder_overlay_opens_and_closes():
	cfc.is_testing = true
	cfc._setup()
	var screen = add_child_autofree(CAMPAIGN_SCREEN.instance())
	yield(yield_for(0.2), YIELD)
	screen._on_deck_builder_pressed()
	yield(yield_for(0.5), YIELD)
	assert_true(is_instance_valid(screen._deck_builder), "Deck builder opened")
	screen._on_deck_builder_back()
	yield(yield_for(0.3), YIELD)
	assert_false(is_instance_valid(screen._deck_builder), "Deck builder closed")


func test_pending_campaign_match_starts_board():
	cfc.is_testing = true
	cfc._setup()
	cfc.pending_campaign_match = {}
	var board = add_child_autofree(CGF_BOARD.instance())
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	var player_deck := {
		"name": "Tester",
		"format_id": "three_heroes",
		"cards": {"Dess": 8},
		"total": 8,
	}
	cfc.pending_campaign_match = {
		"opponent_id": "king",
		"format_id": "three_heroes",
		"player_deck": player_deck,
	}
	board._start_pending_campaign_match()
	assert_true(board.campaign_match, "Board flagged as campaign match")
	assert_eq(board.campaign_opponent_id, "king")
	assert_true(board.match_started, "Match started")
	assert_true(is_instance_valid(board.ai_controller), "AI opponent created")
	assert_eq(board.ai_controller.player_id, 1)
	assert_gt(board.get_player_deck(1).get_card_count(), 0,
			"King deck loaded for the AI")


func _make_progress_board():
	var board = load("res://src/custom/CGFBoard.gd").new()
	board.campaign_match = true
	board.campaign_opponent_id = "king"
	board.campaign_save_path = TEST_SAVE_PATH
	return board


func test_win_records_campaign_completion():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_false(CAMPAIGN_PROGRESS.is_completed(progress, "king"))
	var board = _make_progress_board()
	board.on_match_finished(0)
	board.free()
	var reloaded = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_true(CAMPAIGN_PROGRESS.is_completed(reloaded, "king"),
			"Player 1 win unlocked the next opponent")


func test_loss_does_not_record_completion():
	var board = _make_progress_board()
	board.on_match_finished(1)
	board.free()
	var reloaded = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_false(CAMPAIGN_PROGRESS.is_completed(reloaded, "king"),
			"A loss leaves progress untouched")
