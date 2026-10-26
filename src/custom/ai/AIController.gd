class_name AIController
extends Node

const MoveRules = preload("res://src/custom/ai/AIMoveRules.gd")

const ACTION_DELAY := 0.5
const MAX_ANIMATION_WAIT := 1.0

var board = null
var player_id := 1
var rng = null
var action_delay := ACTION_DELAY


func take_turn() -> void:
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
	while not _turn_is_over():
		if not _use_one_action():
			return
		yield(_wait_action_delay(), "timeout")


func _play_one_card() -> bool:
	var turn_manager = board.turn_manager
	var hand = board.get_player_hand(player_id)
	var zone = board.get_player_zone(player_id)
	if not is_instance_valid(hand) or not is_instance_valid(zone):
		return false
	if zone.count_available_slots() <= 0:
		return false
	var playable := []
	for card in hand.get_all_cards():
		if not is_instance_valid(card):
			continue
		if card.has_method("get_calculated_cost"):
			var cost: int = card.get_calculated_cost()
			if turn_manager.can_player_afford(player_id, cost):
				playable.append(card)
		else:
			playable.append(card)
	if playable.empty():
		return false
	var chosen = playable[_random_index(playable.size())]
	return _play_card(chosen, zone)


func _play_card(card, zone) -> bool:
	yield(_wait_for_card_animation(card), "completed")
	if not is_instance_valid(card) or card.get_parent() != board.get_player_hand(player_id):
		return false
	var slot = zone.find_available_slot()
	if not is_instance_valid(slot):
		return false
	slot.set_highlight(true)
	card.move_to(board, -1, slot)
	slot.set_highlight(false)
	if card.get_parent() != board:
		return false
	yield(_wait_for_card_animation(card), "completed")
	_force_card_visible(card)
	return true


func _force_card_visible(card) -> void:
	if not is_instance_valid(card):
		return
	card.visible = true
	card.modulate = Color(1, 1, 1, 1)
	if card.has_method("set_is_faceup"):
		card.set_is_faceup(true, true)
	if "state" in card and card.state != Card.CardState.ON_PLAY_BOARD \
			and card.has_method("set_state"):
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
		var target = MoveRules.choose_target(
				move.action_type, move.targets, player_id, _get_rng())
		if not is_instance_valid(target):
			continue
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
