# Suggests extra cards to round out a deck around the chosen hero candidates.
#
# Rule of thumb: a recommended card must be *cheaper* than the chosen heroes and
# must share tag material with them - i.e. it has tags that appear on the heroes
# (directly, or through a tag equality/implication the heroes define), or it has
# its own tag equalities/implications that involve a hero tag. Cards that share
# more such material are ranked higher, with cheaper cards breaking ties.
class_name CardRecommender
extends Reference


static func recommend(seed_names: Array, definitions: Dictionary,
		limit := 40) -> Array:
	var seed_tags := expanded_seed_tags(seed_names, definitions)
	if seed_tags.empty():
		return []
	var ceiling := seed_cost_ceiling(seed_names, definitions)
	var scored := []
	for name in definitions.keys():
		var card_name := str(name)
		if card_name in seed_names:
			continue
		var card = definitions[card_name]
		if typeof(card) != TYPE_DICTIONARY:
			continue
		if not is_recommendable(card):
			continue
		var cost := cost_of(card)
		if cost >= ceiling:
			continue
		var score := relevance(card, seed_tags)
		if score <= 0:
			continue
		scored.append({"name": card_name, "score": score, "cost": cost})
	_sort_scored(scored)
	var result := []
	for entry in scored:
		result.append(str(entry["name"]))
		if result.size() >= limit:
			break
	return result


static func cost_of(card) -> int:
	if typeof(card) != TYPE_DICTIONARY:
		return 0
	var value = card.get("Cost", 0)
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_REAL:
			return int(value)
		TYPE_STRING:
			return int(value) if value.is_valid_integer() else 0
	return 0


# The cost a recommended card has to stay under: it must be cheaper than the
# most expensive hero candidate (so it is cheaper than the heroes).
static func seed_cost_ceiling(seed_names: Array, definitions: Dictionary) -> int:
	var ceiling := 0
	for name in seed_names:
		ceiling = int(max(ceiling, cost_of(definitions.get(name, {}))))
	return int(max(1, ceiling))


# A card is not recommended if it is a token, or one of the three hero objective
# cards (which are banned anyway).
static func is_recommendable(card) -> bool:
	if typeof(card) != TYPE_DICTIONARY:
		return false
	if str(card.get("Type", "")) == "Token":
		return false
	if str(card.get("Group", "")) == "Hero":
		return false
	return true


# The set of tag labels the heroes care about. Starts from their Tags and
# SpecificTags, then grows through the tag equalities (both directions) and
# implications (forward only) the heroes define, so e.g. a hero that says
# "Depths = Hell" also brings in "Depths" if it lists "Hell".
static func expanded_seed_tags(seed_names: Array, definitions: Dictionary) -> Dictionary:
	var tags := {}
	var equalities := []
	var implications := []
	for name in seed_names:
		var card = definitions.get(name, {})
		if typeof(card) != TYPE_DICTIONARY:
			continue
		_add_tags(tags, string_array(card.get("Tags", [])))
		_add_tags(tags, string_array(card.get("SpecificTags", [])))
		_append_all(equalities, string_array(card.get("TagEqualities", [])))
		_append_all(implications, string_array(card.get("TagImplications", [])))
	var changed := true
	var guard := 0
	while changed and guard < 16:
		changed = false
		guard += 1
		for equality in equalities:
			var pair := split_equality(str(equality))
			if pair.size() == 2:
				if tags.has(pair[0]) and not tags.has(pair[1]):
					tags[pair[1]] = true
					changed = true
				if tags.has(pair[1]) and not tags.has(pair[0]):
					tags[pair[0]] = true
					changed = true
		for implication in implications:
			var pair := split_implication(str(implication))
			if pair.size() == 2 and tags.has(pair[0]) and not tags.has(pair[1]):
				tags[pair[1]] = true
				changed = true
	return tags


# How much tag material a card shares with the heroes.
static func relevance(card, seed_tags: Dictionary) -> int:
	var score := 0
	for tag in string_array(card.get("Tags", [])):
		if seed_tags.has(tag):
			score += 1
	for tag in string_array(card.get("SpecificTags", [])):
		if seed_tags.has(tag):
			score += 1
	for entry in string_array(card.get("TagEqualities", [])):
		var pair := split_equality(str(entry))
		if pair.size() == 2 and (seed_tags.has(pair[0]) or seed_tags.has(pair[1])):
			score += 1
	for entry in string_array(card.get("TagImplications", [])):
		var pair := split_implication(str(entry))
		if pair.size() == 2 and (seed_tags.has(pair[0]) or seed_tags.has(pair[1])):
			score += 1
	return score


# --- helpers ---------------------------------------------------------------

static func split_equality(entry: String) -> Array:
	var index := entry.find("=")
	if index <= 0:
		return []
	var left := entry.substr(0, index).strip_edges()
	var right := entry.substr(index + 1).strip_edges()
	if left.empty() or right.empty():
		return []
	return [left, right]


static func split_implication(entry: String) -> Array:
	var index := entry.find("->")
	if index <= 0:
		return []
	var left := entry.substr(0, index).strip_edges()
	var right := entry.substr(index + 2).strip_edges()
	if left.empty() or right.empty():
		return []
	return [left, right]


static func string_array(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		var text := str(entry)
		if not text.empty():
			result.append(text)
	return result


static func _add_tags(target: Dictionary, values: Array) -> void:
	for value in values:
		target[value] = true


static func _append_all(target: Array, values: Array) -> void:
	for value in values:
		if not value in target:
			target.append(value)


static func _sort_scored(scored: Array) -> void:
	# Simple insertion sort by: score desc, then cost asc, then name asc.
	for i in range(1, scored.size()):
		var current = scored[i]
		var j := i - 1
		while j >= 0 and _comes_before(current, scored[j]):
			scored[j + 1] = scored[j]
			j -= 1
		scored[j + 1] = current


static func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	if int(a["cost"]) != int(b["cost"]):
		return int(a["cost"]) < int(b["cost"])
	return str(a["name"]) < str(b["name"])
