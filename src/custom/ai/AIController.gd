class_name AIController
extends Node

const MoveRules = preload("res://src/custom/ai/AIMoveRules.gd")
const FormatScoring = preload("res://src/custom/formats/FormatScoring.gd")

const ACTION_DELAY := 0.5
const MAX_ANIMATION_WAIT := 1.0

var board = null
var player_id := 1
var rng = null
var action_delay := ACTION_DELAY
# Cards the AI played this turn, so it never discards one it just made room for.
var _played_this_turn := []
# Card instances for the match's objectives, used for relevance scoring.
var _objectives := []
# Controller/target reserved for a control steal (set when we make room).
var _control_plan := {}


func take_turn() -> void:
	_played_this_turn = []
	_objectives = _load_objectives()
	_control_plan = {}
	if not _can_take_turn():
		return
	yield(_run_play_phase(), "completed")
	if _turn_is_over():
		return
	var turn_manager = board.turn_manager
	if turn_manager.current_phase == TurnManager.Phase.PLAY_PHASE:
		turn_manager.next_phase()
		yield(_wait_action_delay(), "timeout")
	if _turn_is_over():
		return
	_prepare_control_room()
	yield(_run_action_phase(), "completed")
	if _turn_is_over():
		return
	if turn_manager.current_phase == TurnManager.Phase.ACTION_PHASE:
		turn_manager.next_phase()


func _can_take_turn() -> bool:
	if not is_instance_valid(board) or not is_instance_valid(board.turn_manager):
		return false
	var turn_manager = board.turn_manager
	if turn_manager.game_over:
		return false
	return turn_manager.active_player == player_id


func _turn_is_over() -> bool:
	if not is_instance_valid(board) or not is_instance_valid(board.turn_manager):
		return true
	var turn_manager = board.turn_manager
	return turn_manager.game_over or turn_manager.active_player != player_id


func _run_play_phase() -> void:
	yield(_wait_action_delay(), "timeout")
	if not _can_take_turn():
		return
	if board.turn_manager.current_phase != TurnManager.Phase.PLAY_PHASE:
		return
	while not _turn_is_over():
		if not _play_one_card():
			return
		yield(_wait_action_delay(), "timeout")


func _run_action_phase() -> void:
	yield(_wait_action_delay(), "timeout")
	if not _can_take_turn():
		return
	if board.turn_manager.current_phase != TurnManager.Phase.ACTION_PHASE:
		return
	var planned = _use_planned_control()
	if planned is GDScriptFunctionState:
		planned = yield(planned, "completed")
	yield(_wait_action_delay(), "timeout")
	while not _turn_is_over():
		var used = _use_one_action()
		if used is GDScriptFunctionState:
			used = yield(used, "completed")
		if not used:
			return
		yield(_wait_action_delay(), "timeout")


# Performs the control action we reserved a slot for during the play phase.
func _use_planned_control() -> bool:
	if _control_plan.empty():
		return false
	var controller = _control_plan.get("controller")
	var target = _control_plan.get("target")
	_control_plan = {}
	if not is_instance_valid(controller) or not is_instance_valid(target):
		return false
	for move in MoveRules.get_legal_moves(controller, player_id, board):
		if move.action_type != "Control" or not target in move.targets:
			continue
		board.show_battle_arrow(controller, target,
					TargetingArrow.color_for_action("Control"))
		yield(get_tree().create_timer(1.0), "timeout")
		board.hide_battle_arrow()
		if board.turn_manager.execute_control(controller, target):
			controller.has_acted_this_turn = true
			return true
		return false
	return false


func _play_one_card() -> bool:
	var turn_manager = board.turn_manager
	var hand = board.get_player_hand(player_id)
	var zone = board.get_player_zone(player_id)
	if not is_instance_valid(hand) or not is_instance_valid(zone):
		return false
	var options := _play_options(hand, zone, turn_manager)
	if options.empty():
		return false
	var choice: Dictionary = _preferred_option(options)
	if choice.empty():
		return false
	if not bool(choice.get("stack", false)) \
			and zone.count_available_slots() <= 0:
		# The board is full. Only replace a board card if the new card is
		# strictly better, so the AI never trades down.
		var discard_slot = _lowest_discard_slot(zone, options)
		if not is_instance_valid(discard_slot):
			return false
		var threshold := _card_score(discard_slot.occupying_card)
		var eligible := []
		for option in options:
			if bool(option.get("stack", false)) \
					or int(option.get("score", 0)) > threshold:
				eligible.append(option)
		if eligible.empty():
			return false
		choice = _best_option(eligible)
		if bool(choice.get("stack", false)):
			return _play_card(choice, choice.get("slot"))
		_discard_slot(discard_slot)
		var room = zone.find_available_slot()
		if not is_instance_valid(room):
			return false
		return _play_card(choice, room)
	if bool(choice.get("stack", false)):
		return _play_card(choice, choice.get("slot"))
	var drop_slot = zone.find_available_slot()
	if not is_instance_valid(drop_slot):
		return false
	return _play_card(choice, drop_slot)


# Builds every affordable play, using the best board card below each hand card
# (a merge target or a tag-cost reduction target).
func _play_options(hand, zone, turn_manager) -> Array:
	var options := []
	for card in hand.get_all_cards():
		if not is_instance_valid(card):
			continue
		var best := _best_affordable_target(card, zone, turn_manager)
		if best.empty():
			continue
		best["card"] = card
		best["score"] = _card_score(card)
		options.append(best)
	return options


func _best_affordable_target(card, zone, turn_manager) -> Dictionary:
	var candidates := []
	for slot in zone.get_all_slots():
		if not is_instance_valid(slot):
			continue
		var below = slot.occupying_card
		if not is_instance_valid(below) or below == card:
			continue
		var can_stack: bool = card.can_stack_on(below)
		var can_adjust: bool = card.can_use_for_cost_adjustment(below)
		if not can_stack and not can_adjust:
			continue
		candidates.append({
			"slot": slot,
			"below": below,
			"stack": can_stack,
			"cost": _card_cost(card, below),
		})
	candidates.sort_custom(self, "_candidate_before")
	for candidate in candidates:
		if turn_manager.can_player_afford(player_id, int(candidate["cost"])):
			return candidate
	var base_cost := _card_cost(card)
	if turn_manager.can_player_afford(player_id, base_cost):
		return {"slot": null, "below": null, "stack": false, "cost": base_cost}
	return {}


# Stacks are preferred over cost-only targets, then the cheapest play wins.
func _candidate_before(first: Dictionary, second: Dictionary) -> bool:
	if bool(first["stack"]) != bool(second["stack"]):
		return bool(first["stack"])
	return int(first["cost"]) < int(second["cost"])


func _preferred_option(options: Array) -> Dictionary:
	var stacks := _stack_options(options)
	if not stacks.empty():
		return _cheapest_option(stacks)
	return _cheapest_option(options)


func _stack_options(options: Array) -> Array:
	var stacks := []
	for option in options:
		if bool(option.get("stack", false)):
			stacks.append(option)
	return stacks


func _cheapest_option(options: Array) -> Dictionary:
	if options.empty():
		return {}
	var cheapest := int(options[0]["cost"])
	for option in options:
		var cost := int(option["cost"])
		if cost < cheapest:
			cheapest = cost
	var best := []
	for option in options:
		if int(option["cost"]) == cheapest:
			best.append(option)
	return best[_random_index(best.size())]


# Lowest-scoring board card (and its stack) that is not a target for a play we
# might make this turn and was not just played.
func _lowest_discard_slot(zone, options):
	var required := []
	for option in options:
		if is_instance_valid(option.get("below")):
			required.append(option["below"])
	var best_slot = null
	var best_score := 0
	var found := false
	for slot in zone.get_all_slots():
		if not is_instance_valid(slot):
			continue
		var card = slot.occupying_card
		if not is_instance_valid(card):
			continue
		if required.has(card) or _played_this_turn.has(card):
			continue
		# Do not discard cards stolen from the opponent.
		if "original_owner" in card and card.original_owner != player_id:
			continue
		var score := _card_score(card)
		if not found or score < best_score:
			found = true
			best_score = score
			best_slot = slot
	return best_slot if found else null


# Highest-scoring eligible play, preferring stacks and then cheaper cards.
func _best_option(options: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0
	var best_cost := 0
	var best_is_stack := false
	for option in options:
		var score := int(option.get("score", 0))
		var cost := int(option.get("cost", 0))
		var is_stack := bool(option.get("stack", false))
		if best.empty() or score > best_score:
			best = option
			best_score = score
			best_cost = cost
			best_is_stack = is_stack
			continue
		if score < best_score:
			continue
		if is_stack and not best_is_stack:
			best = option
			best_cost = cost
			best_is_stack = true
			continue
		if is_stack == best_is_stack and cost < best_cost:
			best = option
			best_cost = cost
	return best


func _discard_slot(slot) -> void:
	var card = slot.occupying_card
	if not is_instance_valid(card):
		return
	var discard = _discard_pile()
	if not is_instance_valid(discard):
		return
	_clear_highlights(board.get_player_zone(player_id))
	var stack : Array = card.get_stack_cards()
	# Top first, so each card detaches cleanly from the one below it.
	for i in range(stack.size() - 1, -1, -1):
		var stacked_card = stack[i]
		if is_instance_valid(stacked_card):
			stacked_card.move_to(discard, -1)


func _discard_pile():
	return board.get_player_discard(player_id)


# If the AI can steal an enemy card that is better than one of its own, free a
# slot for the control action during the action phase.
func _prepare_control_room() -> void:
	var zone = board.get_player_zone(player_id)
	if not is_instance_valid(zone):
		return
	if zone.count_available_slots() > 0:
		return
	var best_target = null
	var best_controller = null
	var best_score := -1
	for card in zone.get_all_cards():
		if not is_instance_valid(card):
			continue
		if not MoveRules.is_card_available(card, player_id):
			continue
		if MoveRules.action_power(card, "Control") <= 0:
			continue
		for target in MoveRules.get_control_targets(
				card, player_id, board, true):
			var score := _card_score(target)
			if score > best_score:
				best_score = score
				best_target = target
				best_controller = card
	if not is_instance_valid(best_target):
		return
	var slot = _control_discard_slot(zone)
	if not is_instance_valid(slot):
		return
	if _card_score(slot.occupying_card) >= best_score:
		return
	_discard_slot(slot)
	_control_plan = {"controller": best_controller, "target": best_target}


func _control_discard_slot(zone):
	var best_slot = null
	var best_score := 0
	var found := false
	for slot in zone.get_all_slots():
		if not is_instance_valid(slot):
			continue
		var card = slot.occupying_card
		if not is_instance_valid(card):
			continue
		# Keep cards that are themselves able to control.
		if MoveRules.action_power(card, "Control") > 0:
			continue
		if "original_owner" in card and card.original_owner != player_id:
			continue
		var score := _card_score(card)
		if not found or score < best_score:
			found = true
			best_score = score
			best_slot = slot
	return best_slot if found else null


# Objective-aware card ranking: level dominates, objective cost reduction breaks
# ties (cards that make the format's objective cards cheaper are more useful).
func _card_score(card) -> int:
	if not is_instance_valid(card):
		return 0
	var score := _card_lv(card) * 100
	if not _objectives.empty():
		score += int(FormatScoring.score(_objectives, [card]))
	return score


func _load_objectives() -> Array:
	if not is_instance_valid(board) or not "format_tracker" in board:
		return []
	var tracker = board.format_tracker
	if not is_instance_valid(tracker) or not "objective_cards" in tracker:
		return []
	return tracker.objective_cards


func _play_card(choice: Dictionary, drop_slot) -> bool:
	var card = choice.get("card")
	if not is_instance_valid(card):
		return false
	yield(_wait_for_card_animation(card), "completed")
	if not is_instance_valid(card) \
			or card.get_parent() != board.get_player_hand(player_id):
		return false
	var zone = board.get_player_zone(player_id)
	if not is_instance_valid(zone):
		return false
	_clear_highlights(zone)
	# The card logic reads the highlighted slot: highlight the card we want to
	# stack on / take a cost reduction from, but place cost-only plays in a
	# free slot.
	var highlight_slot = choice.get("slot")
	if not is_instance_valid(highlight_slot):
		highlight_slot = drop_slot
	if is_instance_valid(highlight_slot):
		highlight_slot.set_highlight(true)
	card.move_to(board, -1, drop_slot)
	_clear_highlights(zone)
	if card.get_parent() != board:
		return false
	_played_this_turn.append(card)
	yield(_wait_for_card_animation(card), "completed")
	_force_card_visible(card)
	return true


func _clear_highlights(zone) -> void:
	if not is_instance_valid(zone):
		return
	for slot in zone.get_all_slots():
		if is_instance_valid(slot):
			slot.set_highlight(false)


func _card_cost(card, below_card = null) -> int:
	if not is_instance_valid(card):
		return 0
	return int(card.get_calculated_cost(below_card))


func _card_lv(card) -> int:
	if not is_instance_valid(card):
		return 0
	return int(card.get_lv())


func _force_card_visible(card) -> void:
	if not is_instance_valid(card):
		return
	card.visible = true
	card.modulate = Color(1, 1, 1, 1)
	card.set_is_faceup(true, true)
	if card.state != Card.CardState.ON_PLAY_BOARD:
		card.set_state(Card.CardState.ON_PLAY_BOARD)


func _use_one_action() -> bool:
	var turn_manager = board.turn_manager
	var zone = board.get_player_zone(player_id)
	if not is_instance_valid(zone):
		return false
	for card in zone.get_all_cards():
		if _turn_is_over():
			return false
		if not is_instance_valid(card):
			continue
		if card.current_owner != player_id:
			continue
		if card.has_acted_this_turn or card.knocked_out_turns > 0:
			continue
		var moves = MoveRules.get_legal_moves(card, player_id, board)
		if moves.empty():
			continue
		var move = moves[_random_index(moves.size())]
		var target
		if move.action_type == "Control":
			target = _best_scored_target(move.targets)
		else:
			target = MoveRules.choose_target(
					move.action_type, move.targets, player_id, _get_rng())
		if not is_instance_valid(target):
			continue
		board.show_battle_arrow(card, target,
				TargetingArrow.color_for_action(move.action_type))
		yield(get_tree().create_timer(1.0), "timeout")
		board.hide_battle_arrow()
		if _turn_is_over():
			return false
		var succeeded := true
		match move.action_type:
			"Attack":
				turn_manager.execute_attack(card, target)
			"Control":
				succeeded = turn_manager.execute_control(card, target)
			"Spare":
				turn_manager.execute_spare(card, target)
			"Equip":
				succeeded = turn_manager.execute_equip(card, target)
		card.has_acted_this_turn = true
		if succeeded:
			return true
	# No more usable actions remain.
	return false


func _best_scored_target(targets: Array):
	var best = null
	var best_score := -1
	for target in targets:
		var score := _card_score(target)
		if score > best_score:
			best_score = score
			best = target
	return best


func _wait_for_card_animation(card) -> void:
	var step := 0.05
	yield(get_tree().create_timer(step), "timeout")
	var tween = null
	if is_instance_valid(card):
		tween = card.get_node_or_null("Tween")
	var waited := step
	while is_instance_valid(card) and is_instance_valid(tween) and tween.is_active():
		if waited >= MAX_ANIMATION_WAIT:
			break
		yield(get_tree().create_timer(step), "timeout")
		waited += step


func _wait_action_delay():
	return get_tree().create_timer(action_delay)


func _random_index(size: int) -> int:
	return _get_rng().randi_range(0, size - 1)


func _get_rng():
	if rng != null:
		return rng
	return cfc.game_rng
