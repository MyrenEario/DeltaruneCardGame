# test_play_rules.gd
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

func test_placement_grid_has_five_slots():
	assert_eq(p1.get_slot_count(), 5, "The field has five slots")


func test_free_slot_play_applies_no_tag_reductions():
	var dess = _make_card("Dess")
	var ally = _make_card("Ribcage Roaring Knight")
	var knight = _make_card("Roaring Knight")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(ally, p1.get_slot(1))

	assert_eq(knight.get_calculated_cost(), 15,
			"A free-slot play ignores every card already on the board")

func test_base_char_on_char_gets_reduction_without_stacking():
	var dess = _make_card("Dess")
	var ally = _make_card("Ribcage Roaring Knight")
	var knight = _make_card("Roaring Knight")
	_place_in_slot(dess, p1.get_slot(0))
	_place_in_slot(ally, p1.get_slot(1))

	assert_eq(knight.get_calculated_cost(dess), 12,
			"Normal tags only contribute half a reduction, rounded up")
	assert_false(knight.can_stack_on(dess),
			"Base Chars do not merge unless they are name variants")

func test_specific_tags_double_the_cost_reduction():
	var dad = _make_card("Dad Cat")
	var berdly = _make_card("Burned Wing Berdly")
	_place_in_slot(dad, p1.get_slot(0))

	assert_eq(berdly.get_calculated_cost(dad), 4,
			"Lost Hand matches specific-to-specific for 2x reduction")

func test_mixed_specificity_uses_the_normal_cost_reduction():
	var shadowguy = _make_card("Shadowguy")
	var jevil = _make_card("Jevil")
	_place_in_slot(shadowguy, p1.get_slot(0))

	assert_eq(jevil.get_calculated_cost(shadowguy), 8,
			"Chaos matching specific-to-normal gives the normal reduction")

func test_character_name_counts_as_a_specific_tag():
	var k_round = _make_card("K. Round")
	var king = _make_card("Mantleholder King")
	_place_in_slot(k_round, p1.get_slot(0))

	assert_eq(king.get_calculated_cost(k_round), 3,
			"King's name matches K. Round's specific King tag for 2x reduction")

func test_free_slot_play_charges_base_cost():
	var knight = _make_card("Roaring Knight")
	var tm = cfc.NMAP.board.turn_manager
	tm.player_resources[0] = 20

	var result = knight.common_pre_move_scripts(board, cfc.NMAP.hand, [])

	assert_eq(result, board, "Card was allowed onto the board")
	assert_eq(tm.player_resources[0], 5, "Free-slot play paid the full cost")
	assert_eq(knight.original_owner, 0, "Card remembers its owner")
	p1.get_slot(0).set_highlight(false)

func test_base_char_on_char_charges_reduction_and_uses_free_slot():
	var dad = _make_card("Dad Cat")
	var berdly = _make_card("Burned Wing Berdly")
	var target_slot = p1.get_slot(0)
	var free_slot = p1.get_slot(1)
	_place_in_slot(dad, target_slot)
	target_slot.set_highlight(true)
	var tm = cfc.NMAP.board.turn_manager
	tm.player_resources[0] = 20

	var result = berdly.common_pre_move_scripts(board, cfc.NMAP.hand, [])

	assert_eq(result, board, "Char was allowed onto the board")
	assert_eq(tm.player_resources[0], 16, "Char paid the Dad Cat-discounted cost")
	assert_eq(berdly._pending_stack_below, null, "Char will not merge into Dad Cat")
	assert_eq(berdly.get_potential_placement_slot(), free_slot,
			"Char is redirected to a free slot")
	assert_eq(target_slot.occupying_card, dad, "Dad Cat keeps the target slot")
	free_slot.set_highlight(false)

func test_role_play_charges_only_the_discounted_cost():
	var dess = _make_card("Dess")
	var role = _make_card("ROOTS Tail of Hell")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	slot.set_highlight(true)
	var tm = cfc.NMAP.board.turn_manager
	tm.player_resources[0] = 20

	var result = role.common_pre_move_scripts(board, cfc.NMAP.hand, [])

	assert_eq(result, board, "Role was allowed onto the occupied slot")
	assert_eq(tm.player_resources[0], 10, "Role paid the Dess-discounted cost")
	assert_eq(role._pending_stack_below, dess, "Role remembers the card below")
	assert_eq(role.get_potential_placement_slot(), slot, "Role keeps the occupied slot")
	slot.set_highlight(false)

func test_same_name_variants_merge_at_zero_cost():
	var ribcage = _make_card("Ribcage Roaring Knight")
	var knight = _make_card("Roaring Knight")
	var slot = p1.get_slot(0)
	_place_in_slot(ribcage, slot)
	slot.set_highlight(true)
	var tm = cfc.NMAP.board.turn_manager
	tm.player_resources[0] = 3

	assert_eq(knight.get_calculated_cost(ribcage), 0,
			"Name variants cost nothing to merge")
	assert_true(knight.can_stack_on(ribcage),
			"Name variants are allowed to merge")
	var result = knight.common_pre_move_scripts(board, cfc.NMAP.hand, [])

	assert_eq(result, board, "Variant was allowed onto the occupied slot")
	assert_eq(tm.player_resources[0], 3, "Variant merge did not spend resources")
	assert_eq(knight._pending_stack_below, ribcage, "Variant remembers the card below")
	assert_eq(knight.get_potential_placement_slot(), slot, "Variant keeps the occupied slot")
	slot.set_highlight(false)

func test_only_roles_and_name_variants_can_merge():
	var dess = _make_card("Dess")
	var role = _make_card("Angel")
	var knight = _make_card("Roaring Knight")
	var ribcage = _make_card("Ribcage Roaring Knight")
	var item = _make_card("Hearts Donut")

	assert_true(role.can_stack_on(dess),
			"Char-Role cards merge regardless of shared tags")
	assert_false(knight.can_stack_on(dess),
			"Base Chars do not merge unless they are name variants")
	assert_true(ribcage.can_stack_on(knight),
			"Same-name variants merge even though both are base Chars")
	assert_false(item.can_stack_on(dess), "Items cannot be played as roles")

func test_base_char_without_matching_tags_pays_full_cost():
	var aaron = _make_card("Aaron")
	var knight = _make_card("Roaring Knight")

	assert_false(knight.can_stack_on(aaron), "No merge and no shared tags")
	assert_eq(knight.get_calculated_cost(aaron), 15,
			"An incompatible target provides no reduction")

func test_occupied_slot_targeting_follows_the_merge_rules():
	var dess = _make_card("Dess")
	var aaron = _make_card("Aaron")
	var role = _make_card("Angel")
	var knight = _make_card("Roaring Knight")
	var dess_slot = p1.get_slot(0)
	var aaron_slot = p1.get_slot(1)
	_place_in_slot(dess, dess_slot)
	_place_in_slot(aaron, aaron_slot)
	var mouse = board.mouse_pointer

	cfc.card_drag_ongoing = role
	assert_true(mouse._is_placement_slot_valid(dess_slot, [dess]),
			"Roles can target any occupied character slot")

	cfc.card_drag_ongoing = knight
	assert_true(mouse._is_placement_slot_valid(dess_slot, [dess]),
			"Base Chars can target cards that provide a cost reduction")
	assert_false(mouse._is_placement_slot_valid(aaron_slot, [aaron]),
			"Base Chars cannot target cards without a reduction")
	assert_true(knight.can_be_placed_on_occupied_slot(dess_slot),
			"Shared tags make the occupied slot a valid cost target")
	assert_false(knight.can_be_placed_on_occupied_slot(aaron_slot),
			"An incompatible occupied slot stays invalid")
	cfc.card_drag_ongoing = null

func test_role_stacking_uses_same_slot_and_unions_tags():
	var dess = _make_card("Dess")
	var role = _make_card("Angel")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(role, slot)

	assert_true(role.stack_on(dess), "Angel can merge with Dess")
	assert_eq(slot.occupying_card, role, "The role is the top card in the slot")
	assert_eq(role._placement_slot, slot, "Role uses the same placement slot")
	assert_eq(dess._placement_slot, slot, "Old character stays in the same slot")
	assert_eq(role.get_stack_cards(), [dess, role], "Both cards form one stack")
	assert_eq(dess.global_position.y + 56.0, role.global_position.y,
			"The role is vertically splayed below the old card")

	var tags = role._all_tags(role)
	assert_true("Dess" in tags, "Stack keeps Dess's name tag")
	assert_true("Angel" in tags, "Stack keeps Angel's name tag")
	assert_true("Antlers" in tags, "Stack keeps the base card's normal tags")
	assert_true("Cry" in tags, "Stack keeps the role's normal tags")

func test_base_char_accepts_arbitrarily_many_roles():
	var dess = _make_card("Dess")
	var role = _make_card("Angel")
	var second_role = _make_card("SMashing Fighters Green Lizard")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(role, slot)
	_place_in_slot(second_role, slot)

	assert_true(role.stack_on(dess), "First role merges with the base Char")
	assert_true(second_role.stack_on(role), "Another role merges on top")
	assert_eq(second_role.get_stack_cards(), [dess, role, second_role],
			"The stack keeps one base Char and multiple roles")
	assert_eq(slot.occupying_card, second_role, "Newest role is the top card")
	assert_eq(dess.global_position.y + 56.0, role.global_position.y,
			"First role keeps its splay offset")
	assert_eq(dess.global_position.y + 112.0, second_role.global_position.y,
			"Second role is splayed below the first role")


func test_role_stack_uses_max_level_and_stats():
	var dess = _make_card("Dess")
	var unused = _make_card("UNUSED")
	dess.properties["ActionType"] = "Fight"
	dess.properties["AT"] = 3
	dess.properties["DefenseType"] = "Control"
	dess.properties["HP"] = 4
	unused.properties["ActionType"] = "Control"
	unused.properties["AT"] = 2
	unused.properties["DefenseType"] = "Fight"
	unused.properties["HP"] = 1
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(unused, slot)
	assert_true(unused.stack_on(dess), "UNUSED merged onto Dess")

	assert_eq(unused.get_lv(), 5, "Stack level is Dess's level 5")
	assert_eq(unused.get_attack_value(), 3, "Attack is the maximum")
	assert_eq(unused.get_control_value(), 2, "Control is the maximum")
	assert_eq(unused.get_spare_value(), 0, "Neither card has Mercy strength")
	assert_eq(unused.get_defense_value("Control"), 4,
			"Control defense is the maximum")
	assert_eq(unused.get_defense_value("Fight"), 1,
			"Fight defense is the maximum")
	assert_eq(unused.get_defense_value("Mercy"), 0,
			"Neither card has Mercy defense")


func test_role_stack_level_prevents_a_weak_knockout():
	var dess = _make_card("Dess")
	var unused = _make_card("UNUSED")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(unused, slot)
	assert_true(unused.stack_on(dess), "UNUSED merged onto Dess")

	var p2 = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	p2.name = "Player2Zone"
	board.add_child(p2)
	cfc.NMAP["player2zone"] = p2
	var attacker = _make_card("Aaron")
	attacker.properties["ActionType"] = "Fight"
	attacker.properties["AT"] = 1
	_place_in_slot(attacker, p2.get_slot(0))
	attacker.current_owner = 1
	attacker.original_owner = 1
	var tm = cfc.NMAP.board.turn_manager
	tm.active_player = 1
	tm.execute_attack(attacker, unused)

	assert_eq(unused.get_lv(), 5, "Stack defense level is Dess's 5")
	assert_eq(unused.knocked_out_turns, 0,
			"An attack too weak for Dess does not knock out the stack")


func test_role_stack_contributes_to_objectives():
	var dess = _make_card("Dess")
	var unused = _make_card("UNUSED")
	var slot = p1.get_slot(0)
	_place_in_slot(dess, slot)
	_place_in_slot(unused, slot)
	assert_true(unused.stack_on(dess), "UNUSED merged onto Dess")

	var third_hero = _make_card("Third Hero")
	var score := FormatScoring.score([third_hero], p1)
	assert_gt(score, 0,
			"The fused stack contributes to the Third Hero objective")
