extends "res://tests/UTcommon.gd"

const FORMAT_TRACKER = preload(
		"res://src/custom/formats/FormatTracker.tscn")

var tracker
var p1: BoardPlacementGrid
var p2: BoardPlacementGrid


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")
	p1 = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	p1.name = "Player1Zone"
	board.add_child(p1)
	cfc.NMAP["player1zone"] = p1
	p2 = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	p2.name = "Player2Zone"
	board.add_child(p2)
	cfc.NMAP["player2zone"] = p2


func after_each():
	cfc.game_paused = false
	if cfc.NMAP.has("board") and is_instance_valid(cfc.NMAP.board.turn_manager):
		cfc.NMAP.board.turn_manager.game_over = false


func test_turn_start_ends_when_all_objectives_are_affordable():
	tracker = add_child_autofree(FORMAT_TRACKER.instance())
	tracker._refresh_scores()
	var needed: int = tracker.costs[0]
	assert_gt(needed, 0, "Objectives have a total cost")
	var turn_manager = cfc.NMAP.board.turn_manager
	turn_manager.player_resources[0] = needed - 1
	tracker._on_turn_started(0, 1)
	assert_false(tracker.finished, "One resource short does not end the game")
	turn_manager.player_resources[0] = needed
	tracker._on_turn_started(0, 1)
	assert_true(tracker.finished, "Affording every objective ends the game")
	assert_true(turn_manager.game_over, "Turns are locked after the game ends")


func test_higher_score_wins():
	tracker = add_child_autofree(FORMAT_TRACKER.instance())
	tracker.scores = [12, 7]
	tracker.costs = [20, 20]
	tracker._finish_game(0)
	assert_eq(tracker._game_over_title.text, "Player 1 wins!")
	assert_true(cfc.NMAP.board.turn_manager.game_over,
			"Turns are locked after the game ends")
