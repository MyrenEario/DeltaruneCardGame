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
	var controller = _make_card("December Holiday Lancer")
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
	var controller = _make_card("December Holiday Lancer")
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
	var controller = _make_card("December Holiday Lancer")
	var low = _make_card("Bloxer")
	var high = _make_card("Aaron")
	low.properties["LV"] = 1
	high.properties["LV"] = 2
	_place_in_zone(controller, p1, 0)
	_place_in_zone(low, p2, 1)
	_place_in_zone(high, p2, 1)

	_make_ai(0).take_turn()
	yield(yield_for(1.0), YIELD)

	assert_eq(high.current_owner, 0, "AI controlled the highest LV target")
	assert_eq(low.current_owner, 1, "Lower LV target stayed with its owner")
