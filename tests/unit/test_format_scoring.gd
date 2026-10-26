extends "res://tests/UTcommon.gd"

const FormatScoring = preload("res://src/custom/formats/FormatScoring.gd")

var p1: BoardPlacementGrid


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")
	cfc.NMAP.board.turn_manager.active_player = 0
	p1 = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	p1.name = "Player1Zone"
	board.add_child(p1)
	cfc.NMAP["player1zone"] = p1


func _make_card(card_name: String):
	var card = cfc.instance_card(card_name)
	board.add_child(card)
	return card


func _place_in_slot(card, slot) -> void:
	slot.occupying_card = card
	card._placement_slot = slot
	card.current_owner = 0
	card.original_owner = 0


func test_empty_zone_scores_zero_reduction():
	var objective = _make_card("Roaring Knight")
	var result = FormatScoring.evaluate([objective], p1)
	assert_eq(result.base_cost, 15, "Base cost is used without a target")
	assert_eq(result.cost, 15, "No board slot can discount the objective")
	assert_eq(result.score, 0, "Empty board scores no reduction")


func test_lowest_cost_slot_is_used():
	_place_in_slot(_make_card("Dess"), p1.get_slot(0))
	_place_in_slot(_make_card("Ribcage Roaring Knight"), p1.get_slot(1))
	var objective = _make_card("Roaring Knight")
	var result = FormatScoring.evaluate([objective], p1)
	assert_eq(result.cost, 0, "The best occupied slot sets the objective cost")
	assert_eq(result.score, 15, "The best reduction is scored once")


func test_scores_sum_each_objective():
	_place_in_slot(_make_card("Ribcage Roaring Knight"), p1.get_slot(0))
	var roaring_knight = _make_card("Roaring Knight")
	var dess = _make_card("Dess")
	var result = FormatScoring.evaluate([roaring_knight, dess], p1)
	assert_eq(result.base_cost, 27, "Base costs are summed")
	assert_eq(result.cost, 8, "Each objective uses its own best slot")
	assert_eq(result.score, 19, "Reductions are summed across objectives")
	assert_eq(FormatScoring.best_cost([roaring_knight, dess], p1),
			result.cost, "Best-cost helper matches the evaluation")


func test_only_the_top_card_in_a_slot_is_used():
	var slot = p1.get_slot(0)
	_place_in_slot(_make_card("Dess"), slot)
	_place_in_slot(_make_card("Ribcage Roaring Knight"), slot)
	var objective = _make_card("Roaring Knight")
	var result = FormatScoring.evaluate([objective], p1)
	assert_eq(result.score, 15, "The visible top card determines the discount")
