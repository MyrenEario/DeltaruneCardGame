# PlueyCard.gd
# Custom Card class for PlueyPoker implementing 2-player game rules
class_name PlueyCard
extends Card

const TagRelations = preload("res://src/custom/cards/TagRelations.gd")

var has_acted_this_turn: bool = false
var knocked_out_turns: int = 0
var original_owner: int = 0
var current_owner: int = 0
var controlling_card = null
var controlled_card = null
var spared_for_players: Array = []
var accumulated_attack: int = 0
var lv_bonus: int = 0
var equipped_to = null
var stack_below = null
var stack_above = null
var _pending_stack_below = null
var _pending_cost_below = null
# Card that gave a cost reduction for the current play (for the white arrow).
var _cost_arrow_source = null

const ROLE_SPLAY_OFFSET := 56.0

func _ready() -> void:
	pass

# We intercept the tag properties so that the card front can render the
# specific tags and normal tags as a single, differently-coloured list
# instead of the framework's default plain-text array label.
func refresh_property_label(property: String) -> void:
	if property == "WeaknessType" or property == "Weakness":
		card_front._apply_weakness()
		return
	if property == "Tags" or property == "SpecificTags":
		card_front._apply_tags()
		return
	if property == "TagEqualities" or property == "TagImplications":
		card_front._apply_tag_relations()
		return
	if property == "LV":
		_set_combat_label(property, get_lv())
		return
	if property == "AT":
		_set_combat_label(property, get_displayed_action_value())
		return
	if property == "HP":
		_set_combat_label(property, get_displayed_defense_value())
		return
	.refresh_property_label(property)

func _set_combat_label(property: String, value: int) -> void:
	if not is_instance_valid(card_front) or not card_front.card_labels.has(property):
		return
	var label_node = card_front.card_labels[property]
	if is_instance_valid(label_node):
		var text := str(value)
		if property == "LV":
			text = str(max(0, value))
		elif value == 0:
			text = ""
		card_front.set_label_text(label_node, text)

func _numeric_property(property: String) -> int:
	var value = properties.get(property, 0)
	if value == null:
		return 0
	var value_type = typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_REAL:
		return 0
	return int(max(0, int(value)))

# Like _numeric_property, but keeps negative modifiers (used for AT/HP).
func _raw_numeric_property(property: String) -> int:
	var value = properties.get(property, 0)
	if value == null:
		return 0
	var value_type = typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_REAL:
		return 0
	return int(value)

func _action_key(action_name) -> String:
	match str(action_name):
		"Fight", "Attack":
			return "Attack"
		"Mercy", "Spare":
			return "Spare"
		"Control":
			return "Control"
	return ""

func get_attack_value() -> int:
	return get_action_value("Attack")

func get_control_value() -> int:
	return get_action_value("Control")

func get_spare_value() -> int:
	return get_action_value("Spare")

# A stack acts as one card: each action strength is the maximum across the
# base character and every role fused on top of it.
func get_action_value(action_name) -> int:
	var key := _action_key(action_name)
	if key == "":
		return 0
	var value := 0
	var found := false
	for card in get_stack_cards():
		var own := _own_action_value(card, key)
		if not found or own > value:
			found = true
			value = own
	return value


func _own_action_value(card, key: String) -> int:
	if not is_instance_valid(card):
		return 0
	var value := 0
	if _action_key(card.properties.get("ActionType", "None")) == key:
		value = card._raw_numeric_property("AT")
	for item in card.get_equipped_items():
		value += item.get_equipment_action_bonus(key)
	return value


func get_defense_value(action_name) -> int:
	var key := _action_key(action_name)
	if key == "":
		return 0
	var value := 0
	var found := false
	for card in get_stack_cards():
		var own := _own_defense_value(card, key)
		if not found or own > value:
			found = true
			value = own
	return value


func _own_defense_value(card, key: String) -> int:
	if not is_instance_valid(card):
		return 0
	var value := 0
	if _action_key(card.properties.get("DefenseType", "None")) == key:
		value = card._raw_numeric_property("HP")
	for item in card.get_equipped_items():
		value += item.get_equipment_defense_bonus(key)
	return value

func get_equipment_action_bonus(key: String) -> int:
	if _action_key(properties.get("ActionType", "None")) == key:
		return _raw_numeric_property("AT")
	return 0

func get_equipment_defense_bonus(key: String) -> int:
	if _action_key(properties.get("DefenseType", "None")) == key:
		return _raw_numeric_property("HP")
	return 0

func get_displayed_action_value() -> int:
	var key := _action_key(properties.get("ActionType", "None"))
	if key == "":
		var value := 0
		var found := false
		for card in get_stack_cards():
			if not is_instance_valid(card):
				continue
			var own: int = card._raw_numeric_property("AT")
			if not found or own > value:
				found = true
				value = own
		return value
	return get_action_value(key)

func get_displayed_defense_value() -> int:
	var key := _action_key(properties.get("DefenseType", "None"))
	if key == "":
		var value := 0
		var found := false
		for card in get_stack_cards():
			if not is_instance_valid(card):
				continue
			var own: int = card._raw_numeric_property("HP")
			if not found or own > value:
				found = true
				value = own
		return value
	return get_defense_value(key)

# A stack's level is the highest level among the base character and its roles.
func get_lv() -> int:
	var value := 0
	for card in get_stack_cards():
		if not is_instance_valid(card):
			continue
		var own: int = card._numeric_property("LV") + card.lv_bonus
		if own > value:
			value = own
	return value

func gain_lv(amount: int = 1) -> void:
	if amount <= 0:
		return
	lv_bonus += amount
	refresh_property_label("LV")
	_check_control_break()

func _check_control_break() -> void:
	if not controlling_card or not is_instance_valid(controlling_card):
		return
	if get_lv() > controlling_card.get_control_value():
		return_to_owner()

func is_item() -> bool:
	return str(properties.get("Type", "")) == "Item"

func is_character() -> bool:
	var card_type := str(properties.get("Type", ""))
	return card_type == "Char" or card_type == "Char-Role"

func is_base_character() -> bool:
	return str(properties.get("Type", "")) == "Char"

# Only Char-Role cards can merge on top of a character stack.
func is_role_card() -> bool:
	return str(properties.get("Type", "")) == "Char-Role"

func get_stack_below():
	if not is_instance_valid(stack_below):
		stack_below = null
	return stack_below

func get_stack_above():
	if not is_instance_valid(stack_above):
		stack_above = null
	return stack_above

# Returns the cards of this stack from the bottom card to the top role.
func get_stack_cards() -> Array:
	var cards := []
	var root = self
	var guard := 0
	while is_instance_valid(root.get_stack_below()) and guard < 64:
		root = root.get_stack_below()
		guard += 1
	var card = root
	guard = 0
	while is_instance_valid(card) and guard < 64:
		cards.append(card)
		card = card.get_stack_above()
		guard += 1
	return cards

func is_stacked() -> bool:
	return is_instance_valid(get_stack_below()) or is_instance_valid(get_stack_above())

# Two base characters whose names only differ by their Prefix are variants of
# the same character and merge at no cost.
func is_same_character_variant(other) -> bool:
	if not is_base_character():
		return false
	if not is_instance_valid(other):
		return false
	if not other.is_base_character():
		return false
	var name := _name_tag(self)
	return name != "" and name == _name_tag(other)

func _stack_root():
	var cards := get_stack_cards()
	if cards.empty():
		return self
	return cards.front()

# A stack is one base Char with any number of Char-Role cards on top. Base
# characters can only merge with a same-name variant.
func can_stack_on(below_card) -> bool:
	if not is_instance_valid(below_card) or below_card == self:
		return false
	if not below_card.is_character():
		return false
	if "knocked_out_turns" in below_card and below_card.knocked_out_turns > 0:
		return false
	if is_same_character_variant(below_card):
		return true
	if not is_role_card():
		return false
	var root = below_card._stack_root()
	return root.is_base_character()

# Character tag equalities can reduce the cost when a base character is played
# onto another card, even when they will not merge.
func can_use_for_cost_reduction(below_card) -> bool:
	if not is_character() or not is_instance_valid(below_card):
		return false
	if not below_card.is_character():
		return false
	return _matching_tag_count(below_card) > 0

# Opposing tags use the same occupied-slot targeting as matching tags, but the
# resulting cost adjustment is positive instead of negative.
func can_use_for_cost_adjustment(below_card) -> bool:
	if not is_character() or not is_instance_valid(below_card):
		return false
	if not below_card.is_character():
		return false
	return _matching_tag_count(below_card) > 0 \
			or _opposite_matching_tag_count(below_card) > 0

# Hook used by the mouse pointer to decide whether an occupied placement slot
# can be highlighted as a drop target.
func can_be_placed_on_occupied_slot(slot) -> bool:
	if not is_instance_valid(slot) or not is_instance_valid(slot.occupying_card):
		return false
	if slot.occupying_card == self:
		return false
	if can_stack_on(slot.occupying_card):
		return true
	return can_use_for_cost_adjustment(slot.occupying_card)

# Places this card into the same slot as below_card and arranges the stack
# vertically, leaving each role visible below the previous card.
func stack_on(below_card) -> bool:
	if not can_stack_on(below_card):
		return false
	var old_above = get_stack_above()
	if is_instance_valid(old_above):
		old_above.stack_below = null
	stack_above = null
	stack_below = below_card
	below_card.stack_above = self
	if is_instance_valid(_placement_slot):
		_placement_slot.occupying_card = self
	_arrange_stack()
	refresh_combat_stats()
	return true

# Removes this card from its stack, keeping the remaining cards linked.
func detach_from_stack() -> void:
	var below = get_stack_below()
	var above = get_stack_above()
	if is_instance_valid(above):
		above.stack_below = below
	if is_instance_valid(below):
		below.stack_above = above
	stack_below = null
	stack_above = null
	var remaining_top = null
	if is_instance_valid(above):
		remaining_top = above.get_stack_cards().back()
	elif is_instance_valid(below):
		remaining_top = below.get_stack_cards().back()
	if is_instance_valid(_placement_slot):
		_placement_slot.occupying_card = remaining_top
	if is_instance_valid(remaining_top):
		remaining_top._arrange_stack()
		remaining_top.refresh_combat_stats()

func _arrange_stack() -> void:
	if not is_instance_valid(_placement_slot):
		return
	var slot = _placement_slot
	var cards := get_stack_cards()
	for i in range(cards.size()):
		var card = cards[i]
		if not is_instance_valid(card):
			continue
		var target = slot.rect_global_position + Vector2(0, ROLE_SPLAY_OFFSET * i)
		card._placement_slot = slot
		card._target_position = target
		if card.state != Card.CardState.DROPPING_TO_BOARD:
			card.global_position = target
		card.raise()
	slot.occupying_card = cards.back()

func get_equipped_items() -> Array:
	var items := []
	for card in attachments:
		if not is_instance_valid(card):
			continue
		if not card.is_item():
			continue
		if card.equipped_to == self:
			items.append(card)
	return items

func equip_item(item) -> bool:
	if not is_instance_valid(item) or not item.is_item():
		return false
	if not is_character():
		return false
	var previous_host = item.equipped_to
	item.attach_to_host(self)
	item.equipped_to = self
	if previous_host and is_instance_valid(previous_host) and previous_host != self:
		previous_host.refresh_combat_stats()
	refresh_combat_stats()
	return true

func unequip_item(item) -> void:
	if item.equipped_to == self:
		item.equipped_to = null
	refresh_combat_stats()

func refresh_combat_stats() -> void:
	refresh_property_label("AT")
	refresh_property_label("HP")
	refresh_property_label("LV")

func common_post_move_scripts(new_host: String, old_host: String, move_tags: Array) -> void:
	if equipped_to and is_instance_valid(equipped_to) and current_host_card != equipped_to:
		var previous_host = equipped_to
		equipped_to = null
		previous_host.refresh_combat_stats()
	if is_instance_valid(_pending_stack_below):
		var below = _pending_stack_below
		_pending_stack_below = null
		if get_parent() == cfc.NMAP.board and is_instance_valid(_placement_slot):
			stack_on(below)
	if is_instance_valid(_cost_arrow_source):
		var arrow_source = _cost_arrow_source
		_cost_arrow_source = null
		if get_parent() == cfc.NMAP.board:
			cfc.NMAP.board.show_cost_arrow(arrow_source, self)
	.common_post_move_scripts(new_host, old_host, move_tags)

# Cost rules:
# * A card played into a free slot always pays its base cost.
# * A character played onto another card gets adjustments only from the card
#   below it. Tag equalities still use the whole board.
# * Same-name character variants merge and cost zero.
# * Specific tags (including character names) are worth twice as much as a
#   normal tag match, while two normal tags are worth half as much.
# * Opposing tags increase the cost by the same amount a match would reduce it.
func get_calculated_cost(below_card = null) -> int:
	var base_cost: int = _numeric_property("Cost")
	if not is_instance_valid(below_card):
		return base_cost
	if is_same_character_variant(below_card):
		return 0
	if not can_use_for_cost_adjustment(below_card):
		return base_cost
	var adjustment := _cost_penalty_from(below_card) - _cost_reduction_from(below_card)
	return int(max(0, base_cost + adjustment))

func _cost_reduction_from(below_card) -> int:
	var below_lv := _card_lv(below_card)
	var reduction := 0
	for match_data in _matched_tags(below_card):
		reduction += _cost_adjustment_amount(match_data[2], below_lv)
	return reduction

func _cost_penalty_from(below_card) -> int:
	var below_lv := _card_lv(below_card)
	var penalty := 0
	for match_data in _opposite_matched_tags(below_card):
		penalty += _cost_adjustment_amount(match_data[2], below_lv)
	return penalty

func _card_lv(card) -> int:
	return card.get_lv()

func _cost_adjustment_amount(weight: float, below_lv: int) -> int:
	if weight == 0.5:
		return int(ceil(0.5 * below_lv))
	return int(weight * below_lv)

func _matching_tag_count(below_card) -> int:
	return _matched_tags(below_card).size()

func _opposite_matching_tag_count(below_card) -> int:
	return _opposite_matched_tags(below_card).size()

func get_opposite_tag_attack_bonus(defender) -> int:
	return _opposite_matched_tags(defender).size()

# Returns [my_tag, below_tag, weight] for each unique tag on this card that
# matches a tag on the card below. When several tags match, the most valuable
# specificity pairing is used.
func _matched_tags(below_card) -> Array:
	var matched := []
	if not is_instance_valid(below_card):
		return matched
	var my_tags := _all_tags(self)
	var below_tags := _all_tags(below_card)
	var my_specific := _specific_tag_lookup(self)
	var below_specific := _specific_tag_lookup(below_card)
	var relations = _make_tag_relations()
	var seen := {}
	for tag in my_tags:
		var clean_tag := TagRelations.normalize_tag(tag)
		if clean_tag == "" or seen.has(clean_tag):
			continue
		seen[clean_tag] = true
		var best_weight := 0.0
		var best_tag := ""
		for below_tag in below_tags:
			var clean_below := TagRelations.normalize_tag(below_tag)
			if clean_below == "" or not relations.related(clean_tag, clean_below):
				continue
			var weight := _tag_match_weight(clean_tag, clean_below,
					my_specific, below_specific)
			if weight > best_weight:
				best_weight = weight
				best_tag = clean_below
		if best_weight > 0.0:
			matched.append([clean_tag, best_tag, best_weight])
	return matched

# Returns [my_tag, below_tag, weight] for each unique tag on this card that is
# defined as an opposite of a tag on the other card.
func _opposite_matched_tags(below_card) -> Array:
	var matched := []
	if not is_instance_valid(below_card):
		return matched
	var my_tags := _all_tags(self)
	var below_tags := _all_tags(below_card)
	var my_specific := _specific_tag_lookup(self)
	var below_specific := _specific_tag_lookup(below_card)
	var relations = _make_tag_relations()
	var seen := {}
	for tag in my_tags:
		var clean_tag := TagRelations.normalize_tag(tag)
		if clean_tag == "" or seen.has(clean_tag):
			continue
		seen[clean_tag] = true
		var best_weight := 0.0
		var best_tag := ""
		for below_tag in below_tags:
			var clean_below := TagRelations.normalize_tag(below_tag)
			if clean_below == "" or not relations.are_opposites(clean_tag, clean_below):
				continue
			var weight := _tag_match_weight(clean_tag, clean_below,
					my_specific, below_specific)
			if weight > best_weight:
				best_weight = weight
				best_tag = clean_below
		if best_weight > 0.0:
			matched.append([clean_tag, best_tag, best_weight])
	return matched

func _tag_match_weight(my_tag: String, below_tag: String,
		my_specific: Dictionary, below_specific: Dictionary) -> float:
	var my_is_specific := my_specific.has(my_tag)
	var below_is_specific := below_specific.has(below_tag)
	if my_is_specific and below_is_specific:
		return 2.0
	if not my_is_specific and not below_is_specific:
		return 0.5
	return 1.0

func _specific_tag_lookup(card) -> Dictionary:
	var lookup := {}
	for tag in _all_specific_tags(card):
		var clean_tag := TagRelations.normalize_tag(tag)
		if clean_tag != "":
			lookup[clean_tag] = true
	return lookup

func _all_specific_tags(card) -> Array:
	var tags := []
	if not is_instance_valid(card):
		return tags
	for stacked in card.get_stack_cards():
		tags += _own_specific_tags(stacked)
	return tags

func _own_specific_tags(card) -> Array:
	var tags := []
	if not is_instance_valid(card):
		return tags
	var props = card.properties
	if props.has("SpecificTags") and props["SpecificTags"] is Array:
		tags += props["SpecificTags"]
	if card.is_character():
		var name_tag := _name_tag(card)
		if name_tag != "":
			tags.append(name_tag)
	return tags

func _make_tag_relations():
	var relation_data = _collect_tag_relations()
	var relations = TagRelations.new()
	relations.setup(relation_data["equalities"],
			relation_data["implications"], relation_data["tags"],
			TagRelations.load_opposite_pairs())
	return relations


# Every tag a card "has": for a stacked character this is the union of every
# card in the stack, plus their normal tags, specific tags and unprefixed names.
func _all_tags(card) -> Array:
	var tags: Array = []
	if not is_instance_valid(card):
		return tags
	for stacked in card.get_stack_cards():
		tags += _own_tags(stacked)
	return tags

func _own_tags(card) -> Array:
	var tags: Array = []
	if not is_instance_valid(card):
		return tags
	var props = card.properties
	if props.has("Tags") and props["Tags"] is Array:
		tags += props["Tags"]
	if props.has("SpecificTags") and props["SpecificTags"] is Array:
		tags += props["SpecificTags"]
	var name_tag := _name_tag(card)
	if name_tag != "":
		tags.append(name_tag)
	return tags


func _name_tag(card) -> String:
	var name := str(card.canonical_name).strip_edges()
	var prefix := str(card.properties.get("Prefix", "")).strip_edges()
	if prefix != "" and name.begins_with(prefix + " "):
		name = name.substr(prefix.length() + 1).strip_edges()
	return name


func _tag_equality_pairs(card) -> Array:
	if not is_instance_valid(card):
		return []
	return TagRelations.parse_equalities(card.properties.get("TagEqualities", []))


func _tag_implication_pairs(card) -> Array:
	if not is_instance_valid(card):
		return []
	return TagRelations.parse_implications(card.properties.get("TagImplications", []))


func _collect_tag_relations() -> Dictionary:
	var data = {
		"equalities": _tag_equality_pairs(self),
		"implications": _tag_implication_pairs(self),
		"tags": _all_tags(self),
	}
	var board = null
	if cfc.NMAP.has("board"):
		board = cfc.NMAP.board
	if board:
		for card in board.get_all_cards():
			if not is_instance_valid(card) or card == self:
				continue
			data["equalities"] += _tag_equality_pairs(card)
			data["implications"] += _tag_implication_pairs(card)
			data["tags"] += _all_tags(card)
	return data

func can_afford(below_card = null) -> bool:
	if not cfc.NMAP.has("board") or not "turn_manager" in cfc.NMAP.board or not cfc.NMAP.board.turn_manager:
		return true
	var active_p: int = cfc.NMAP.board.turn_manager.active_player
	var cost: int = get_calculated_cost(below_card)
	return cfc.NMAP.board.turn_manager.can_player_afford(active_p, cost)

func pay_play_costs(below_card = null) -> void:
	if cfc.NMAP.has("board") and "turn_manager" in cfc.NMAP.board and cfc.NMAP.board.turn_manager:
		var active_p: int = cfc.NMAP.board.turn_manager.active_player
		var cost: int = get_calculated_cost(below_card)
		cfc.NMAP.board.turn_manager.deduct_player_resource(active_p, cost)

func common_pre_move_scripts(new_host: Node, old_host: Node, move_tags: Array) -> Node:
	_pending_stack_below = null
	_pending_cost_below = null
	_cost_arrow_source = null
	if old_host == cfc.NMAP.board:
		var target_slot = get_potential_placement_slot()
		var stack_target = null
		var redirect_slot = null
		if target_slot != _placement_slot:
			if is_instance_valid(target_slot) and is_instance_valid(target_slot.occupying_card) \
					and target_slot.occupying_card != self:
				if can_stack_on(target_slot.occupying_card):
					stack_target = target_slot.occupying_card
				else:
					redirect_slot = _find_free_player_slot()
					if not is_instance_valid(redirect_slot):
						return old_host
			detach_from_stack()
			if is_instance_valid(stack_target):
				_pending_stack_below = stack_target
			if is_instance_valid(redirect_slot):
				target_slot.set_highlight(false)
				redirect_slot.set_highlight(true)
	if old_host and old_host.is_in_group("hands"):
		var is_board_target = (new_host == cfc.NMAP.board or new_host.is_in_group("placement_grids") or new_host.is_in_group("board_slots"))
		if is_board_target:
			var slot = get_potential_placement_slot()
			if is_instance_valid(slot) and is_instance_valid(slot.occupying_card) and slot.occupying_card != self:
				var target_card = slot.occupying_card
				if can_stack_on(target_card):
					_pending_stack_below = target_card
					_pending_cost_below = target_card
				elif can_use_for_cost_adjustment(target_card):
					_pending_cost_below = target_card
					_cost_arrow_source = target_card
					slot.set_highlight(false)
					slot = null
				else:
					slot.set_highlight(false)
					slot = null
			if not is_instance_valid(slot):
				slot = _find_free_player_slot()
				if not is_instance_valid(slot):
					return old_host
				slot.set_highlight(true)
			if not can_afford(_pending_cost_below):
				_pending_stack_below = null
				_pending_cost_below = null
				_cost_arrow_source = null
				slot.set_highlight(false)
				return old_host
			pay_play_costs(_pending_cost_below)
			_pending_cost_below = null
			if cfc.NMAP.has("board") and "turn_manager" in cfc.NMAP.board and cfc.NMAP.board.turn_manager:
				original_owner = cfc.NMAP.board.turn_manager.active_player
				current_owner = original_owner
				cfc.NMAP.board.log_card_played(self)
	return new_host

func _find_free_player_slot():
	if not cfc.NMAP.has("board") or not "turn_manager" in cfc.NMAP.board or not cfc.NMAP.board.turn_manager:
		return null
	var zone = _get_player_zone(cfc.NMAP.board.turn_manager.active_player)
	if not zone:
		return null
	return zone.find_available_slot()

func set_knocked_out(turns: int) -> void:
	knocked_out_turns = max(0, turns)
	if knocked_out_turns > 0:
		modulate = Color(0.5, 0.5, 0.6, 0.7)
	else:
		modulate = Color(1, 1, 1, 1)

func tick_knockout() -> void:
	if knocked_out_turns > 0:
		set_knocked_out(knocked_out_turns - 1)

func return_to_owner() -> void:
	if controlling_card and is_instance_valid(controlling_card):
		controlling_card.controlled_card = null
	controlling_card = null
	current_owner = original_owner
	move_to_player_zone(original_owner)

# Moves this card onto the board in the first free placement slot of the given
# player's zone grid.
#
# Returns true when the card was moved, or false when the player's zone has no
# available slot (the card is left untouched). Player zones are
# BoardPlacementGrids, which organise cards through BoardPlacementSlots rather
# than holding them as children, so we route through the board and pass the
# chosen slot as the board position.
func move_to_player_zone(p_id: int) -> bool:
	var zone = _get_player_zone(p_id)
	if not zone:
		return false
	var slot = zone.find_available_slot()
	if not slot:
		return false
	move_to(cfc.NMAP.board, -1, slot)
	return true

func _get_player_zone(p_id: int):
	var key = "player" + str(p_id + 1) + "zone"
	if cfc.NMAP.has(key):
		return cfc.NMAP[key]
	return null

func can_attack_player(p_id: int) -> bool:
	if knocked_out_turns > 0:
		return false
	if p_id in spared_for_players:
		return false
	return true

func get_controlled_shield():
	if not controlled_card or not is_instance_valid(controlled_card):
		return null
	if controlled_card.controlling_card != self:
		return null
	if controlled_card.knocked_out_turns > 0:
		return null
	return controlled_card

# Every tag this card has, including its unprefixed name.
func get_all_tags() -> Array:
	return _all_tags(self)


# True when an action of the given type from `source` exploits this card's
# weakness. The weakness type must match (Fight/Control/Mercy) and the source
# must have one of the weakness tags (its name counts as a tag).
func is_weak_to(action_type: String, source) -> bool:
	var weakness_type := str(properties.get("WeaknessType", "")).strip_edges()
	if not _weakness_matches_action(weakness_type, action_type):
		return false
	var weakness := []
	var raw = properties.get("Weakness", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			var tag := str(entry).strip_edges()
			if not tag.empty():
				weakness.append(tag)
	if weakness.empty() or not is_instance_valid(source):
		return false
	var source_tags = source.get_all_tags()
	for tag in weakness:
		if tag in source_tags:
			return true
	return false


func _weakness_matches_action(weakness_type: String, action_type: String) -> bool:
	match weakness_type:
		"Fight":
			return action_type == "Fight" or action_type == "Attack"
		"Control":
			return action_type == "Control"
		"Mercy":
			return action_type == "Mercy" or action_type == "Spare"
	return false


func _on_Card_gui_input(event) -> void:
	._on_Card_gui_input(event)
	if event is InputEventMouseButton:
		if event.is_pressed() and event.get_button_index() == 1:
			if cfc.NMAP.has("board"):
				cfc.NMAP.board.select_card_for_action(self)
