# test_combat_rules.gd
extends "res://tests/UTcommon.gd"

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

func test_attack_redirects_to_controlled_card():
	var attacker = _make_card("8-bit Kris")
	var defender = _make_card("Dess")
	var shield = _make_card("Aqua")
	var tm = cfc.NMAP.board.turn_manager
	_place_in_zone(defender, p2, 1)
	_place_in_zone(shield, p1, 0)
	defender.controlled_card = shield
	shield.controlling_card = defender

	tm.execute_attack(attacker, defender)

	assert_eq(shield.accumulated_attack, 3, "Attack damage went to the shield")
	assert_eq(defender.accumulated_attack, 0, "Controller took no damage")
	assert_eq(shield.knocked_out_turns, 0, "Shield survived")
	assert_eq(defender.knocked_out_turns, 0, "Controller survived")

func test_knocked_out_controlled_card_does_not_shield():
	var attacker = _make_card("8-bit Kris")
	var defender = _make_card("Aqua")
	var shield = _make_card("Bloxer")
	var tm = cfc.NMAP.board.turn_manager
	_place_in_zone(defender, p2, 1)
	_place_in_zone(shield, p1, 0)
	defender.controlled_card = shield
	shield.controlling_card = defender
	shield.set_knocked_out(1)

	tm.execute_attack(attacker, defender)

	assert_eq(shield.accumulated_attack, 0, "Knocked-out shield was skipped")
	assert_eq(defender.accumulated_attack, 3, "Attack hit the controller")

func test_knockout_increases_attacker_lv():
	var attacker = _make_card("8-bit Kris")
	var defender = _make_card("Bloxer")
	var tm = cfc.NMAP.board.turn_manager
	_place_in_zone(defender, p2, 1)
	var original_lv = attacker.get_lv()

	tm.execute_attack(attacker, defender)

	assert_eq(defender.knocked_out_turns, 1, "Defender was knocked out")
	assert_eq(attacker.get_lv(), original_lv + 1, "Attacker gained one LV")

func test_lv_gain_breaks_control_above_control_value():
	var controller = _make_card("Lancer")
	var target = _make_card("Bloxer")
	var tm = cfc.NMAP.board.turn_manager
	_place_in_zone(target, p2, 1)

	assert_true(tm.execute_control(controller, target), "Control started")
	assert_eq(controller.get_control_value(), 2, "Controller has two Control")

	target.gain_lv(1)

	assert_eq(target.get_lv(), 3, "Controlled card reached LV 3")
	assert_null(target.controlling_card, "Control was lost")
	assert_null(controller.controlled_card, "Controller no longer tracks card")
	assert_eq(target.current_owner, 1, "Card returned to its owner")
	assert_eq(target._placement_slot.owner_grid, p2, "Card is back in its owner's zone")

func test_lv_gain_equal_to_control_keeps_control():
	var controller = _make_card("Lancer")
	var target = _make_card("Bloxer")
	var tm = cfc.NMAP.board.turn_manager
	target.properties["LV"] = 1
	_place_in_zone(target, p2, 1)

	assert_true(tm.execute_control(controller, target), "Control started")
	target.gain_lv(1)

	assert_eq(target.get_lv(), 2, "Card gained LV")
	assert_eq(target.controlling_card, controller, "Control remains at the threshold")
	assert_eq(controller.controlled_card, target, "Controller still tracks card")

func test_equip_adds_item_action_and_defense_values():
	var host = _make_card("Aqua")
	var item = _make_card("Hearts Donut")
	var tm = cfc.NMAP.board.turn_manager
	item.properties["AT"] = 2
	item.properties["ActionType"] = "Control"
	item.properties["HP"] = 4
	item.properties["DefenseType"] = "Mercy"
	_place_in_zone(item, p1, 0)

	assert_eq(host.get_attack_value(), 3, "Host starts with three Attack")
	assert_eq(host.get_control_value(), 0, "Host starts with no Control")
	assert_eq(host.get_defense_value("Mercy"), 0, "Host starts with no Mercy defence")

	assert_true(tm.execute_equip(item, host), "Equip succeeded")

	assert_eq(item.equipped_to, host, "Item tracks its host")
	assert_eq(host.get_attack_value(), 3, "Attack does not receive Control item value")
	assert_eq(host.get_control_value(), 2, "Control item added to Control")
	assert_eq(host.get_spare_value(), 0, "Spare stayed at zero")
	assert_eq(host.get_defense_value("Mercy"), 4, "Item defence added to Mercy")
	assert_eq(host.get_defense_value("Fight"), 0, "Item defence did not add to Fight")

func test_equip_rejects_non_items_and_items():
	var host = _make_card("Aqua")
	var item = _make_card("Hearts Donut")
	var tm = cfc.NMAP.board.turn_manager
	_place_in_zone(item, p1, 0)

	assert_false(tm.execute_equip(host, item), "Characters cannot be equipped as items")
	assert_true(tm.execute_equip(item, host), "Items can be equipped to characters")
	assert_false(tm.execute_equip(item, item), "Items cannot equip themselves")

func test_item_action_buttons_show_only_equip():
	var item = _make_card("Hearts Donut")
	var character = _make_card("Aqua")
	var container = board.get_node("ActionContainer")
	_place_in_zone(item, p1, 0)
	_place_in_zone(character, p1, 1)

	board.select_card_for_action(item)
	assert_true(container.visible, "Action container opened for item")
	assert_false(container.get_node("AttackBtn").visible, "Items cannot attack")
	assert_false(container.get_node("ControlBtn").visible, "Items cannot control")
	assert_false(container.get_node("SpareBtn").visible, "Items cannot spare")
	assert_true(container.get_node("EquipBtn").visible, "Items can equip")

	board.select_card_for_action(character)
	assert_true(container.get_node("AttackBtn").visible, "Characters can attack")
	assert_false(container.get_node("ControlBtn").visible,
			"Zero-power Control action is hidden")
	assert_false(container.get_node("SpareBtn").visible,
			"Zero-power Spare action is hidden")
	assert_false(container.get_node("EquipBtn").visible, "Characters cannot equip")


func test_zero_power_character_actions_are_hidden():
	var controller = _make_card("Head Hathy")
	var container = board.get_node("ActionContainer")
	_place_in_zone(controller, p1, 1)

	board.select_card_for_action(controller)

	assert_false(container.get_node("AttackBtn").visible,
			"Zero-power Attack action is hidden")
	assert_true(container.get_node("ControlBtn").visible,
			"Positive-power Control action is shown")
	assert_false(container.get_node("SpareBtn").visible,
			"Zero-power Spare action is hidden")


func test_request_action_rejects_zero_power_actions():
	var card = _make_card("Goulden Sam")
	_place_in_zone(card, p1, 1)

	cfc.NMAP.board.turn_manager.request_action(card, "Attack")

	assert_null(cfc.NMAP.board.turn_manager.selected_action_card,
			"A zero-power action was not selected")
