# test_control.gd
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

func _make_card(name: String):
	var card = cfc.instance_card(name)
	board.add_child(card)
	return card

func _place_in_zone(card, zone, owner: int) -> void:
	var slot = zone.find_available_slot()
	slot.occupying_card = card
	card._placement_slot = slot
	card.current_owner = owner
	card.original_owner = owner

func test_control_moves_target_into_active_zone():
	var controller = _make_card("Mad Ghost")
	var target = _make_card("Aqua")
	_place_in_zone(target, p2, 1)
	var tm = cfc.NMAP.board.turn_manager

	assert_true(tm.execute_control(controller, target), "Control succeeds with room")
	assert_eq(target.current_owner, 0, "Target belongs to active player")
	assert_eq(controller.controlled_card, target, "Controller tracks the target")
	assert_eq(target.controlling_card, controller, "Target tracks its controller")
	assert_not_null(target._placement_slot, "Target occupies a slot")
	if target._placement_slot:
		assert_eq(target._placement_slot.owner_grid, p1, "Target is in the active zone")

func test_control_fails_when_zone_full():
	var controller = _make_card("Mad Ghost")
	var target = _make_card("Aqua")
	_place_in_zone(target, p2, 1)
	# Fill the active player's zone completely
	for slot in p1.get_all_slots():
		slot.occupying_card = _make_card("Dess")
	var tm = cfc.NMAP.board.turn_manager

	assert_false(tm.execute_control(controller, target), "Control fails with no room")
	assert_eq(target.current_owner, 1, "Target ownership unchanged")
	assert_null(controller.controlled_card, "No card is controlled")
	assert_eq(target._placement_slot.owner_grid, p2, "Target stayed in the opponent zone")

func test_control_swap_frees_slot_in_full_zone():
	var controller = _make_card("Mad Ghost")
	var old_controlled = _make_card("Aqua")
	var target = _make_card("Bloxer")
	# Zone is full except for the slot held by the already-controlled card
	var slots = p1.get_all_slots()
	_place_in_zone(old_controlled, p1, 0)
	old_controlled.original_owner = 1
	old_controlled.controlling_card = controller
	controller.controlled_card = old_controlled
	for i in range(1, slots.size()):
		slots[i].occupying_card = _make_card("Dess")
	_place_in_zone(target, p2, 1)
	var tm = cfc.NMAP.board.turn_manager

	assert_true(tm.execute_control(controller, target), "Control succeeds by swapping")
	assert_eq(controller.controlled_card, target, "Controller now holds the new target")
	assert_eq(old_controlled.current_owner, 1, "Old controlled card returned to its owner")
	assert_eq(old_controlled._placement_slot.owner_grid, p2, "Old card returned to opponent zone")
