extends "res://tests/UTcommon.gd"

const MoveRules = preload("res://src/custom/ai/AIMoveRules.gd")
const AIControllerScript = preload("res://src/custom/ai/AIController.gd")

var p1: BoardPlacementGrid
var p2: BoardPlacementGrid


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")
	p1 = board.get_node("BoardPlacementGrid")
	p2 = load("res://src/core/BoardPlacementGrid.tscn").instance()
	p2.name = "Player2Zone"
	board.add_child(p2)
	for _i in range(3):
		p2.add_slot()
	cfc.NMAP["player1zone"] = p1
	cfc.NMAP["player2zone"] = p2
	cfc.NMAP.board.turn_manager.active_player = 0
	cfc.NMAP.board.turn_manager.current_phase = TurnManager.Phase.ACTION_PHASE


func _make_card(card_name: String):
	var card = cfc.instance_card(card_name)
	board.add_child(card)
	return card


func _place_in_zone(card, zone, owner: int) -> void:
	var slot = zone.find_available_slot()
	slot.occupying_card = card
	card._placement_slot = slot
	card.current_owner = owner
	card.original_owner = owner


func _add_to_hand(card) -> void:
	var hand = cfc.NMAP.hand
	var parent = card.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(card)
	hand.add_child(card)
	card.state = Card.CardState.IN_HAND


func _make_ai(player_id := 0):
	var ai = AIControllerScript.new()
	ai.board = board
	ai.player_id = player_id
	ai.action_delay = 0.0
	board.add_child(ai)
	return ai


func test_zero_power_card_has_no_legal_actions():
	var card = _make_card("Goulden Sam")
	_place_in_zone(card, p1, 0)

	assert_eq(MoveRules.action_power(card, "Attack"), 0)
	assert_eq(MoveRules.action_power(card, "Control"), 0)
	assert_eq(MoveRules.action_power(card, "Spare"), 0)
	assert_true(MoveRules.get_legal_moves(card, 0, board).empty(),
			"Cards without positive action power cannot act")


func test_positive_power_card_only_exposes_its_action():
	var attacker = _make_card("Aqua")
	var defender = _make_card("Dess")
	_place_in_zone(attacker, p1, 0)
	_place_in_zone(defender, p2, 1)

	var moves = MoveRules.get_legal_moves(attacker, 0, board)

	assert_eq(moves.size(), 1)
	assert_eq(moves[0].action_type, "Attack")
	assert_eq(moves[0].targets, [defender])


func test_attack_targets_exclude_knocked_out_cards():
	var attacker = _make_card("Aqua")
	var available = _make_card("Dess")
	var knocked_out = _make_card("Bloxer")
	_place_in_zone(attacker, p1, 0)
	_place_in_zone(available, p2, 1)
	_place_in_zone(knocked_out, p2, 1)
	knocked_out.set_knocked_out(1)

	var targets = MoveRules.get_attack_targets(attacker, 0, board)

	assert_eq(targets, [available])


func test_control_targets_respect_power_and_highest_lv():
	var controller = _make_card("Lancer")
	var low = _make_card("Bloxer")
	var high = _make_card("Aaron")
	var too_high = _make_card("Dess")
	low.properties["LV"] = 1
	high.properties["LV"] = 2
	too_high.properties["LV"] = 3
	_place_in_zone(controller, p1, 0)
	_place_in_zone(low, p2, 1)
	_place_in_zone(high, p2, 1)
	_place_in_zone(too_high, p2, 1)

	var targets = MoveRules.get_control_targets(controller, 0, board)
	var chosen = MoveRules.choose_target("Control", targets, 0)

	assert_eq(targets.size(), 2)
	assert_eq(chosen, high, "Control picks the highest LV legal target")


func test_spare_prefers_a_controlled_card():
	var sparer = _make_card("Green")
	var controller = _make_card("Lancer")
	var stolen = _make_card("Bloxer")
	var other = _make_card("Roaring Knight")
	_place_in_zone(sparer, p1, 0)
	_place_in_zone(controller, p1, 0)
	_place_in_zone(stolen, p2, 1)
	_place_in_zone(other, p2, 1)
	assert_true(cfc.NMAP.board.turn_manager.execute_control(controller, stolen),
			"Setup control succeeded")

	var targets = MoveRules.get_spare_targets(sparer, 0, board)

	assert_eq(targets, [stolen])


func test_spare_uses_highest_attack_without_controlled_card():
	var sparer = _make_card("Green")
	var weak = _make_card("Bloxer")
	var strong = _make_card("Roaring Knight")
	_place_in_zone(sparer, p1, 0)
	_place_in_zone(weak, p2, 1)
	_place_in_zone(strong, p2, 1)

	var targets = MoveRules.get_spare_targets(sparer, 0, board)

	assert_eq(targets, [strong])


func test_ai_plays_cards_until_slots_run_out():
	var free_card = _make_card("Goulden Sam")
	var second_free_card = _make_card("Lancer")
	_add_to_hand(free_card)
	_add_to_hand(second_free_card)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.PLAY_PHASE
	tm.player_resources[0] = 10

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(p1.get_all_cards().size(), 2, "AI played both affordable cards")
	assert_eq(cfc.NMAP.hand.get_card_count(), 0, "Played cards left the hand")
	assert_eq(tm.active_player, 1, "AI ended its turn")


func test_ai_controls_highest_lv_target():
	var controller = _make_card("Lancer")
	var low = _make_card("Bloxer")
	var high = _make_card("Aaron")
	low.properties["LV"] = 1
	high.properties["LV"] = 2
	_place_in_zone(controller, p1, 0)
	_place_in_zone(low, p2, 1)
	_place_in_zone(high, p2, 1)

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(high.current_owner, 0, "AI controlled the highest LV target")
	assert_eq(low.current_owner, 1, "Lower LV target stayed with its owner")


func test_ai_discards_lowest_card_when_board_is_full():
	var lowest = _make_card("Bloxer")
	var second = _make_card("Goulden Sam")
	var third = _make_card("Head Hathy")
	var fourth = _make_card("Napstablook")
	lowest.properties["LV"] = 1
	second.properties["LV"] = 2
	third.properties["LV"] = 3
	fourth.properties["LV"] = 4
	for card in [lowest, second, third, fourth]:
		_place_in_zone(card, p1, 0)
	var new_card = _make_card("Aaron")
	new_card.properties["LV"] = 5
	_add_to_hand(new_card)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.PLAY_PHASE
	tm.player_resources[0] = 10

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_false(p1.get_all_cards().has(lowest),
			"Lowest-LV card left the board")
	assert_true(discard.get_all_cards().has(lowest),
			"Lowest-LV card was discarded")
	assert_true(p1.get_all_cards().has(new_card),
			"The new card was played after making room")
	assert_eq(p1.get_all_cards().size(), 4, "The board is full again")


func test_ai_stacks_name_variant_instead_of_using_a_slot():
	var base = _make_card("Roaring Knight")
	var variant = _make_card("Ribcage Roaring Knight")
	_place_in_zone(base, p1, 0)
	_add_to_hand(variant)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.PLAY_PHASE
	tm.player_resources[0] = 3

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(base.stack_above, variant, "Variant stack was created")
	assert_eq(variant.stack_below, base, "Variant remembers the base card")
	assert_eq(p1.get_slot(0).occupying_card, variant,
			"Variant is the top card in the same slot")
	assert_eq(p1.get_all_cards().size(), 1, "Stacking did not use a new slot")
	assert_eq(tm.player_resources[0], 3, "Variant merge cost no resources")


func test_ai_uses_cost_reduction_and_plays_in_a_free_slot():
	var dad = _make_card("Dad Cat")
	var berdly = _make_card("Burned Wing Berdly")
	_place_in_zone(dad, p1, 0)
	_add_to_hand(berdly)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.PLAY_PHASE
	tm.player_resources[0] = 20

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(p1.get_all_cards().size(), 2,
			"The reduced-cost card was played")
	assert_eq(berdly.stack_below, null, "Base Chars did not merge")
	assert_ne(berdly._placement_slot, dad._placement_slot,
			"The card used a free slot, not Dad Cat's slot")
	assert_eq(tm.player_resources[0], 16,
			"The AI paid the Dad Cat-discounted cost")


func test_ai_does_not_discard_for_a_worse_card():
	var first = _make_card("Bloxer")
	var second = _make_card("Goulden Sam")
	var third = _make_card("Head Hathy")
	var fourth = _make_card("Napstablook")
	first.properties["LV"] = 5
	second.properties["LV"] = 6
	third.properties["LV"] = 7
	fourth.properties["LV"] = 8
	for card in [first, second, third, fourth]:
		_place_in_zone(card, p1, 0)
	var worse = _make_card("Aaron")
	worse.properties["LV"] = 0
	_add_to_hand(worse)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.PLAY_PHASE
	tm.player_resources[0] = 10

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(p1.get_all_cards().size(), 4, "Board was left intact")
	assert_true(p1.get_all_cards().has(first),
			"No board card was discarded for a worse card")
	assert_eq(cfc.NMAP.hand.get_card_count(), 1,
			"The worse card stayed in hand")
	assert_eq(discard.get_all_cards().size(), 0, "Nothing was discarded")


func test_ai_discards_to_steal_a_better_enemy_card():
	var controller = _make_card("Mad Ghost")
	var low = _make_card("Goulden Sam")
	var mid = _make_card("Bloxer")
	var high = _make_card("Aaron")
	low.properties["LV"] = 1
	mid.properties["LV"] = 2
	high.properties["LV"] = 3
	_place_in_zone(controller, p1, 0)
	_place_in_zone(low, p1, 0)
	_place_in_zone(mid, p1, 0)
	_place_in_zone(high, p1, 0)
	var prize = _make_card("Roaring Knight")
	prize.properties["LV"] = 5
	_place_in_zone(prize, p2, 1)
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 0
	tm.current_phase = TurnManager.Phase.ACTION_PHASE
	tm.player_resources[0] = 10

	_make_ai(0).take_turn()
	yield(yield_for(2.0), YIELD)

	assert_eq(prize.current_owner, 0, "AI stole the better enemy card")
	assert_true(discard.get_all_cards().has(low),
			"The lowest-value own card was discarded to make room")
	assert_false(p1.get_all_cards().has(low),
			"The discarded card left the board")


func test_card_score_includes_objective_relevance():
	var objective = _make_card("Roaring Knight")
	var helpful = _make_card("Ribcage Roaring Knight")
	var ai = _make_ai(0)
	ai._objectives = [objective]
	assert_eq(ai._card_score(helpful),
			ai._card_lv(helpful) * 100 + 15,
			"Cards that reduce objective costs score higher")
	ai._objectives = []
	assert_eq(ai._card_score(helpful), ai._card_lv(helpful) * 100,
			"Without objectives only level matters")
