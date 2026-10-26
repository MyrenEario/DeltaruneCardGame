# TurnManager.gd
class_name TurnManager
extends Node

enum Phase {
	PLAY_PHASE,
	ACTION_PHASE,
}

var active_player: int = 0
var current_turn: int = 1
var current_phase: int = Phase.PLAY_PHASE
var player_resources: Array = [3, 3]
var selected_action_card = null
var selected_action_type: String = ""
var game_over := false

signal turn_started(player_id, turn_number)
signal phase_changed(new_phase)
signal resources_updated(p1_res, p2_res)

func _ready() -> void:
	pass

func start_game() -> void:
	active_player = 0
	current_turn = 1
	current_phase = Phase.PLAY_PHASE
	game_over = false
	player_resources[0] = get_turn_resource_amount(current_turn)
	player_resources[1] = get_turn_resource_amount(current_turn)
	_update_counters()
	emit_signal("turn_started", active_player, current_turn)
	emit_signal("phase_changed", current_phase)

func get_turn_resource_amount(turn_num: int) -> int:
	return 2 + turn_num

func can_player_afford(p_id: int, amount: int) -> bool:
	return player_resources[p_id] >= amount

func deduct_player_resource(p_id: int, amount: int) -> void:
	player_resources[p_id] = max(0, player_resources[p_id] - amount)
	_update_counters()

func _update_counters() -> void:
	emit_signal("resources_updated", player_resources[0], player_resources[1])
	if cfc.NMAP.has("board") and "counters" in cfc.NMAP.board and cfc.NMAP.board.counters:
		cfc.NMAP.board.counters.mod_counter("p1_resources", player_resources[0], true)
		cfc.NMAP.board.counters.mod_counter("p2_resources", player_resources[1], true)

func next_phase() -> void:
	if game_over:
		return
	if current_phase == Phase.PLAY_PHASE:
		current_phase = Phase.ACTION_PHASE
		emit_signal("phase_changed", current_phase)
	elif current_phase == Phase.ACTION_PHASE:
		end_turn()

func end_turn() -> void:
	if game_over:
		return
	active_player = 1 if active_player == 0 else 0
	if active_player == 0:
		current_turn += 1
	current_phase = Phase.PLAY_PHASE
	player_resources[active_player] = get_turn_resource_amount(current_turn)
	_update_counters()
	var active_zone = _get_active_zone()
	if active_zone and active_zone.has_method("get_all_cards"):
		for card in active_zone.get_all_cards():
			if "has_acted_this_turn" in card:
				card.has_acted_this_turn = false
			if "tick_knockout" in card:
				card.tick_knockout()
	emit_signal("turn_started", active_player, current_turn)
	emit_signal("phase_changed", current_phase)

func _get_active_zone():
	var key = "player" + str(active_player + 1) + "zone"
	if cfc.NMAP.has(key):
		return cfc.NMAP[key]
	return null

func _get_inactive_zone():
	var inactive_p = 1 if active_player == 0 else 0
	var key = "player" + str(inactive_p + 1) + "zone"
	if cfc.NMAP.has(key):
		return cfc.NMAP[key]
	return null

func request_action(card, action_type: String) -> void:
	if game_over or current_phase != Phase.ACTION_PHASE:
		return
	if "has_acted_this_turn" in card and card.has_acted_this_turn:
		return
	if "knocked_out_turns" in card and card.knocked_out_turns > 0:
		return
	var card_is_item = card.has_method("is_item") and card.is_item()
	if action_type == "Equip":
		if not card_is_item:
			return
	elif card_is_item:
		return
	if action_type in ["Attack", "Control", "Spare"] \
			and card.has_method("get_action_value") \
			and card.get_action_value(action_type) <= 0:
		return
	selected_action_card = card
	selected_action_type = action_type
	card.targeting_arrow.initiate_targeting()
	if not card.targeting_arrow.is_connected("target_selected", self, "_on_target_selected"):
		card.targeting_arrow.connect("target_selected", self, "_on_target_selected", [card, action_type], CONNECT_ONESHOT)

func _on_target_selected(target, source_card, action_type: String) -> void:
	if not is_instance_valid(target) or not target is Card:
		return
	var succeeded := true
	match action_type:
		"Attack":
			execute_attack(source_card, target)
		"Control":
			succeeded = execute_control(source_card, target)
		"Spare":
			execute_spare(source_card, target)
		"Equip":
			succeeded = execute_equip(source_card, target)
	# A failed action (e.g. Control with no room in the zone) does not consume
	# the card's action for this turn.
	if succeeded:
		source_card.has_acted_this_turn = true

func execute_attack(attacker, defender) -> void:
	if attacker.has_method("get_action_value") and attacker.get_action_value("Attack") <= 0:
		return
	var inactive_p = 1 if active_player == 0 else 0
	if defender.current_owner != inactive_p:
		return
	if not attacker.can_attack_player(inactive_p):
		return
	if defender.knocked_out_turns > 0:
		return
	var attack_target = defender
	if defender.has_method("get_controlled_shield"):
		var shield = defender.get_controlled_shield()
		if shield:
			attack_target = shield
	var was_knocked_out = attack_target.knocked_out_turns > 0
	var atk_power: int = 1
	if attacker.has_method("get_attack_value"):
		atk_power = attacker.get_attack_value()
	else:
		atk_power = attacker.properties.get("AT", 1)
	if attacker.has_method("get_opposite_tag_attack_bonus"):
		atk_power += attacker.get_opposite_tag_attack_bonus(attack_target)
	attack_target.accumulated_attack += atk_power
	var def_lv: int = attack_target.properties.get("LV", 1)
	if attack_target.has_method("get_lv"):
		def_lv = attack_target.get_lv()
	# A Fight weakness makes the attack always knock the card out.
	var weakness_knockout = attack_target.has_method("is_weak_to") \
			and attack_target.is_weak_to("Fight", attacker)
	if weakness_knockout or attack_target.accumulated_attack > def_lv:
		var knockout_turns = attack_target.accumulated_attack - def_lv
		if weakness_knockout:
			knockout_turns = int(max(1, knockout_turns))
		attack_target.set_knocked_out(knockout_turns)
		attack_target.accumulated_attack = 0
		if not was_knocked_out and attacker.has_method("gain_lv"):
			attacker.gain_lv(1)

func execute_equip(item, target) -> bool:
	if not item.has_method("is_item") or not item.is_item():
		return false
	if item.current_owner != active_player:
		return false
	if not target.has_method("is_character") or not target.is_character():
		return false
	if target == item or target.knocked_out_turns > 0:
		return false
	return target.equip_item(item)

# Takes control of an opponent's card, moving it into the active player's zone.
#
# Returns false (and changes nothing) if the target is not a valid, non-knocked
# out opponent card, or if there is no free space left in the controller's zone.
func execute_control(controller, target) -> bool:
	if controller.has_method("get_action_value") \
			and controller.get_action_value("Control") <= 0:
		return false
	var inactive_p = 1 if active_player == 0 else 0
	if target.current_owner != inactive_p:
		return false
	if target.knocked_out_turns > 0:
		return false
	# A card with a Control weakness to this controller can always be controlled
	# by it, as if the controller had infinitely high control strength.
	var weakens = target.has_method("is_weak_to") \
			and target.is_weak_to("Control", controller)
	var previous_controller = target.controlling_card \
			if "controlling_card" in target else null
	# If someone else already controls it, only a higher control strength can
	# take it over.
	if not weakens and is_instance_valid(previous_controller) \
			and previous_controller != controller \
			and _control_strength(controller) <= _control_strength(previous_controller):
		return false
	# Releasing the card we already control frees a slot in our own zone,
	# so a player can always swap what they are controlling.
	if controller.controlled_card and is_instance_valid(controller.controlled_card):
		controller.controlled_card.return_to_owner()
	# The zone has no room for another card, so the control simply fails.
	if not target.move_to_player_zone(active_player):
		return false
	if is_instance_valid(previous_controller) and previous_controller != controller \
			and "controlled_card" in previous_controller \
			and previous_controller.controlled_card == target:
		previous_controller.controlled_card = null
	controller.controlled_card = target
	target.controlling_card = controller
	target.current_owner = active_player
	return true


func _control_strength(card) -> int:
	if is_instance_valid(card) and card.has_method("get_control_value"):
		return card.get_control_value()
	return 0

func execute_spare(sparer, target) -> void:
	if sparer.has_method("get_action_value") \
			and sparer.get_action_value("Spare") <= 0:
		return
	if target.original_owner == active_player and target.controlling_card != null:
		target.return_to_owner()
		if not active_player in target.spared_for_players:
			target.spared_for_players.append(active_player)
	else:
		if not active_player in target.spared_for_players:
			target.spared_for_players.append(active_player)
