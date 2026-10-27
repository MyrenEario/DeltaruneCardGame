class_name AIMoveRules
extends Reference

const ACTION_TYPES := ["Attack", "Control", "Spare"]


static func get_player_zone(board, player_id: int):
	return board.get_player_zone(player_id)


static func action_power(card, action_type: String) -> int:
	if not is_instance_valid(card):
		return 0
	return int(card.get_action_value(action_type))


static func is_card_available(card, active_player: int) -> bool:
	if not is_instance_valid(card):
		return false
	if "current_owner" in card and card.current_owner != active_player:
		return false
	if "has_acted_this_turn" in card and card.has_acted_this_turn:
		return false
	if "knocked_out_turns" in card and card.knocked_out_turns > 0:
		return false
	return true


static func get_attack_targets(card, active_player: int, board) -> Array:
	if action_power(card, "Attack") <= 0:
		return []
	var opponent := 1 - active_player
	if not card.can_attack_player(opponent):
		return []
	var targets := []
	for target in get_zone_cards(board, opponent):
		if not is_instance_valid(target):
			continue
		if "current_owner" in target and target.current_owner != opponent:
			continue
		if "knocked_out_turns" in target and target.knocked_out_turns > 0:
			continue
		targets.append(target)
	return targets


static func get_control_targets(card, active_player: int, board,
		ignore_room := false) -> Array:
	var control_power := action_power(card, "Control")
	if control_power <= 0:
		return []
	var opponent := 1 - active_player
	var active_zone = get_player_zone(board, active_player)
	var has_room = active_zone != null and active_zone.count_available_slots() > 0
	var controlled = card.controlled_card if "controlled_card" in card else null
	if not ignore_room and not has_room and not is_instance_valid(controlled):
		return []
	var targets := []
	for target in get_zone_cards(board, opponent):
		if not is_instance_valid(target):
			continue
		if "current_owner" in target and target.current_owner != opponent:
			continue
		if "knocked_out_turns" in target and target.knocked_out_turns > 0:
			continue
		var weakens = target.is_weak_to("Control", card)
		var current_controller = target.controlling_card \
				if "controlling_card" in target else null
		if is_instance_valid(current_controller) and current_controller != card:
			# Already controlled: only a Control weakness or a stronger
			# controller wins.
			if weakens or control_power > _control_strength(current_controller):
				targets.append(target)
			continue
		# Uncontrolled: a Control weakness always works, otherwise the usual
		# LV limit.
		if weakens or target.get_lv() <= control_power:
			targets.append(target)
	return targets


static func _control_strength(card) -> int:
	if not is_instance_valid(card):
		return 0
	return card.get_control_value()


static func get_spare_targets(card, active_player: int, board) -> Array:
	if action_power(card, "Spare") <= 0:
		return []
	var controlled := []
	for target in get_zone_cards(board, active_player):
		if not is_instance_valid(target):
			continue
		if "current_owner" in target and target.current_owner != active_player:
			continue
		if not ("controlling_card" in target) or target.controlling_card == null:
			continue
		if "knocked_out_turns" in target and target.knocked_out_turns > 0:
			continue
		controlled.append(target)
	if not controlled.empty():
		return controlled
	var opponent := 1 - active_player
	var candidates := []
	for target in get_zone_cards(board, opponent):
		if not is_instance_valid(target):
			continue
		if "current_owner" in target and target.current_owner != opponent:
			continue
		if "knocked_out_turns" in target and target.knocked_out_turns > 0:
			continue
		if "spared_for_players" in target and active_player in target.spared_for_players:
			continue
		candidates.append(target)
	return _highest_attack_targets(candidates)


static func get_equip_targets(card, active_player: int, board) -> Array:
	if not is_instance_valid(card) or not card.is_item():
		return []
	if not is_card_available(card, active_player):
		return []
	var targets := []
	for target in get_zone_cards(board, active_player):
		if not is_instance_valid(target):
			continue
		if not target.is_character():
			continue
		if "knocked_out_turns" in target and target.knocked_out_turns > 0:
			continue
		if target == card:
			continue
		if "equipped_to" in card and card.equipped_to == target:
			continue
		targets.append(target)
	return targets


static func get_action_targets(card, action_type: String, active_player: int, board) -> Array:
	match action_type:
		"Attack":
			return get_attack_targets(card, active_player, board)
		"Control":
			return get_control_targets(card, active_player, board)
		"Spare":
			return get_spare_targets(card, active_player, board)
		"Equip":
			return get_equip_targets(card, active_player, board)
	return []


static func get_legal_moves(card, active_player: int, board) -> Array:
	if not is_card_available(card, active_player):
		return []
	if card.is_item():
		var equip_targets := get_equip_targets(card, active_player, board)
		if not equip_targets.empty():
			return [{"action_type": "Equip", "targets": equip_targets}]
		return []
	var moves := []
	for action_type in ACTION_TYPES:
		if action_power(card, action_type) <= 0:
			continue
		var targets := get_action_targets(card, action_type, active_player, board)
		if not targets.empty():
			moves.append({"action_type": action_type, "targets": targets})
	return moves


static func choose_target(action_type: String, targets: Array, active_player: int,
		rng = null):
	if targets.empty():
		return null
	var generator = rng
	if generator == null:
		generator = cfc.game_rng
	match action_type:
		"Control":
			return _pick_highest_lv(targets, generator)
		"Spare":
			var controlled := []
			for target in targets:
				if "current_owner" in target and target.current_owner == active_player \
						and "controlling_card" in target and target.controlling_card != null:
					controlled.append(target)
			if not controlled.empty():
				return controlled[generator.randi_range(0, controlled.size() - 1)]
			return _pick_highest_attack(targets, generator)
	return targets[generator.randi_range(0, targets.size() - 1)]


static func get_zone_cards(board, player_id: int) -> Array:
	var zone = get_player_zone(board, player_id)
	if not is_instance_valid(zone):
		return []
	return zone.get_all_cards()


static func _highest_attack_targets(targets: Array) -> Array:
	var highest := -1
	var best := []
	for target in targets:
		var attack := _attack_value(target)
		if attack > highest:
			highest = attack
			best = [target]
		elif attack == highest:
			best.append(target)
	return best


static func _pick_highest_attack(targets: Array, generator):
	var highest := -1
	for target in targets:
		highest = max(highest, _attack_value(target))
	var best := []
	for target in targets:
		if _attack_value(target) == highest:
			best.append(target)
	if best.empty():
		return null
	return best[generator.randi_range(0, best.size() - 1)]


static func _pick_highest_lv(targets: Array, generator):
	var highest := -1
	for target in targets:
		highest = max(highest, _lv_value(target))
	var best := []
	for target in targets:
		if _lv_value(target) == highest:
			best.append(target)
	if best.empty():
		return null
	return best[generator.randi_range(0, best.size() - 1)]


static func _attack_value(card) -> int:
	if not is_instance_valid(card):
		return 0
	return card.get_attack_value()


static func _lv_value(card) -> int:
	if not is_instance_valid(card):
		return 0
	return card.get_lv()
