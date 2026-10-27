extends Reference


static func evaluate(objectives: Array, zone) -> Dictionary:
	var result := {
		"score": 0,
		"cost": 0,
		"base_cost": 0,
	}
	for objective in objectives:
		if not is_instance_valid(objective):
			continue
		var base_cost := int(objective.get_calculated_cost())
		var best_cost := base_cost
		for card in _occupied_cards(zone):
			best_cost = int(min(best_cost,
					int(objective.get_calculated_cost(card))))
		result.base_cost += base_cost
		result.cost += best_cost
		result.score += base_cost - best_cost
	return result


static func score(objectives: Array, zone) -> int:
	return int(evaluate(objectives, zone).score)


static func best_cost(objectives: Array, zone) -> int:
	return int(evaluate(objectives, zone).cost)


static func _occupied_cards(zone) -> Array:
	var cards := []
	if typeof(zone) == TYPE_ARRAY:
		for card in zone:
			if is_instance_valid(card):
				cards.append(card)
		return cards
	if not is_instance_valid(zone):
		return cards
	if zone.has_method("get_all_slots"):
		for slot in zone.get_all_slots():
			if is_instance_valid(slot.occupying_card):
				cards.append(slot.occupying_card)
	elif zone.has_method("get_all_cards"):
		for card in zone.get_all_cards():
			if is_instance_valid(card):
				cards.append(card)
	return cards
