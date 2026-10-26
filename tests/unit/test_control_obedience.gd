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
	board.turn_manager.active_player = 0
	board.turn_manager.current_phase = TurnManager.Phase.ACTION_PHASE


func _make_card(card_name):
	var card = cfc.instance_card(card_name)
	board.add_child(card)
	return card


func _place(card, zone, owner: int) -> void:
	var slot = zone.find_available_slot()
	slot.occupying_card = card
	card._placement_slot = slot
	card.current_owner = owner
	card.original_owner = owner


func _give_control(target, controller) -> void:
	target.controlling_card = controller
	target.current_owner = controller.current_owner
	controller.controlled_card = target


func test_obeying_controller_always_succeeds():
	# "Pink" obeys "Mad Ghost"; give it a very strong rival controller so that
	# only the obey rule (infinite strength) can win.
	var controller = _make_card("Mad Ghost")
	var target = _make_card("Pink")
	var rival = _make_card("Mad Ghost")
	rival.properties["AT"] = 99
	_place(controller, p1, 0)
	_place(target, p2, 1)
	_place(rival, p2, 1)
	_give_control(target, rival)

	assert_true(board.turn_manager.execute_control(controller, target),
			"Obeying controller always succeeds")
	assert_eq(target.current_owner, 0)
	assert_eq(target.controlling_card, controller)
	assert_null(rival.controlled_card, "Old controller releases the card")


func test_stronger_controller_can_steal():
	var strong = _make_card("Mad Ghost")          # control 5
	var target = _make_card("Dess")                # no Obeys
	var rival = _make_card("December Holiday Lancer")  # control 2
	_place(strong, p1, 0)
	_place(target, p2, 1)
	_place(rival, p2, 1)
	_give_control(target, rival)

	assert_true(board.turn_manager.execute_control(strong, target),
			"A stronger controller can steal")
	assert_eq(target.current_owner, 0)
	assert_eq(target.controlling_card, strong)
	assert_null(rival.controlled_card)


func test_weaker_controller_cannot_steal():
	var weak = _make_card("December Holiday Lancer")  # control 2
	var target = _make_card("Dess")
	var rival = _make_card("Mad Ghost")               # control 5
	_place(weak, p1, 0)
	_place(target, p2, 1)
	_place(rival, p2, 1)
	_give_control(target, rival)

	assert_false(board.turn_manager.execute_control(weak, target),
			"A weaker controller cannot steal")
	assert_eq(target.current_owner, 1)
	assert_eq(target.controlling_card, rival)
	assert_eq(rival.controlled_card, target)

func test_obey_matches_base_name_across_prefixes():
	var controller = _make_card("Pirate Rouxls")  # base name "Rouxls"
	var target = _make_card("K. Round")           # Obeys: Rouxls
	_place(controller, p1, 0)
	_place(target, p2, 1)

	assert_true(target.is_weak_to("Control", controller),
			"A prefixed controller obeys by its base name")
	assert_true(board.turn_manager.execute_control(controller, target),
			"Obeying control succeeds")
	assert_eq(target.current_owner, 0)


func test_obey_requires_the_exact_base_name():
	var controller = _make_card("Pirate Rouxls")  # base name "Rouxls"
	var target = _make_card("Lost in Forest Susie")  # Obeys: Lancer
	assert_false(target.is_weak_to("Control", controller),
			"A different base name does not obey")

func test_fight_weakness_knocks_out_regardless_of_lv():
	var attacker = _make_card("Aqua")  # Fight 3
	var target = _make_card("Dess")    # LV 5
	target.properties["WeaknessType"] = "Fight"
	target.properties["Weakness"] = ["Aqua"]
	_place(attacker, p1, 0)
	_place(target, p2, 1)

	board.turn_manager.execute_attack(attacker, target)

	assert_true(target.knocked_out_turns >= 1,
			"Fight weakness knocks out even without enough damage")


func test_fight_without_weakness_does_not_knock_out():
	var attacker = _make_card("Aqua")
	var target = _make_card("Dess")
	_place(attacker, p1, 0)
	_place(target, p2, 1)

	board.turn_manager.execute_attack(attacker, target)

	assert_eq(target.knocked_out_turns, 0,
			"Without a weakness, 3 damage vs LV 5 does not knock out")


func test_mercy_weakness_is_detected_and_spared():
	var sparer = _make_card("Green")  # Mercy 4
	var target = _make_card("Dess")
	target.properties["WeaknessType"] = "Mercy"
	target.properties["Weakness"] = ["Green"]
	_place(sparer, p1, 0)
	_place(target, p2, 1)

	assert_true(target.is_weak_to("Mercy", sparer),
			"Mercy weakness matches the sparer's name tag")
	board.turn_manager.execute_spare(sparer, target)
	assert_true(0 in target.spared_for_players, "The card was spared")
