# Code for a sample playspace, you're expected to provide your own ;)
extends Board

const FORMAT_TRACKER_SCENE = preload(
		"res://src/custom/formats/FormatTracker.tscn")
const MATCH_SETUP_SCENE = preload("res://src/custom/MatchSetup.tscn")
const AI_CONTROLLER_SCRIPT = preload("res://src/custom/ai/AIController.gd")
const CAMPAIGN_DATA_SCRIPT = preload("res://src/custom/campaign/CampaignData.gd")
const CAMPAIGN_PROGRESS_SCRIPT = preload(
		"res://src/custom/campaign/CampaignProgress.gd")
const BATTLE_ARROW_SCENE = preload("res://src/core/Card/TargetingArrow.tscn")

var turn_manager: TurnManager = null
var selected_card_for_action = null
var format_tracker = null
var match_setup = null
var ai_controller = null
var match_started := false
var _opening_deckbuilder := false
var campaign_match := false
var campaign_opponent_id := ""
var campaign_save_path := CAMPAIGN_PROGRESS_SCRIPT.SAVE_PATH
var battle_log_messages := []
var _battle_arrow = null
var _arrow_timer = null

onready var _battle_log_scroll = get_node_or_null("BattleLog/VBox/Scroll")
onready var _battle_log_messages = get_node_or_null(
		"BattleLog/VBox/Scroll/Messages")

func _ready() -> void:
	counters = $Counters
	cfc.map_node(self)
	cfc.NMAP["player1deck"] = cfc.NMAP.get("deck")
	cfc.NMAP["player1discard"] = cfc.NMAP.get("discard")
	cfc.NMAP["player1hand"] = cfc.NMAP.get("hand")
	
	turn_manager = TurnManager.new()
	turn_manager.name = "TurnManager"
	add_child(turn_manager)
	cfc.NMAP["turnmanager"] = turn_manager
	
	if has_node("Player1Zone"):
		cfc.NMAP["player1zone"] = $Player1Zone
	if has_node("Player2Zone"):
		cfc.NMAP["player2zone"] = $Player2Zone
		
	turn_manager.connect("turn_started", self, "_on_turn_started")
	turn_manager.connect("phase_changed", self, "_on_phase_changed")
	
	$FancyMovementToggle.pressed = cfc.game_settings.fancy_movement
	$OvalHandToggle.pressed = cfc.game_settings.hand_use_oval_shape
	$ScalingFocusOptions.selected = cfc.game_settings.focus_style
	$Debug.pressed = cfc._debug
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
		if cfc.pending_campaign_match.empty():
			_create_match_setup()
		else:
			call_deferred("_start_pending_campaign_match")
	$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')
	_battle_arrow = BATTLE_ARROW_SCENE.instance()
	_battle_arrow.name = "BattleArrow"
	add_child(_battle_arrow)
	_battle_arrow.visible = false
	_arrow_timer = Timer.new()
	_arrow_timer.one_shot = true
	add_child(_arrow_timer)
	_arrow_timer.connect("timeout", self, "_hide_battle_arrow")

func _create_format_tracker() -> void:
	format_tracker = FORMAT_TRACKER_SCENE.instance()
	format_tracker.turn_manager = turn_manager
	format_tracker.rect_position = Vector2(220, 150)
	format_tracker.rect_size = Vector2(540, 300)
	add_child(format_tracker)


func _create_match_setup() -> void:
	match_setup = MATCH_SETUP_SCENE.instance()
	add_child(match_setup)
	match_setup.connect("match_requested", self, "_on_match_requested")
	match_setup.connect("deckbuilder_requested", self, "_on_match_setup_deckbuilder")
	match_setup.connect("back_requested", self, "_on_BackToMain_pressed")
	match_setup.open(self)


func _on_match_requested(format_id: String, player1_deck: Dictionary,
		player2_deck: Dictionary, ai_player_id := -1) -> void:
	start_match(format_id, player1_deck, player2_deck, ai_player_id)


func start_match(format_id: String, player1_deck: Dictionary,
		player2_deck: Dictionary, ai_player_id := -1) -> void:
	if match_started:
		return
	# A fresh seed for every match, so rematches/replays are never predictable.
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		if has_node("SeedLabel"):
			$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
	_clear_deck($Deck)
	_clear_deck($Discard)
	_clear_deck($Hand)
	_clear_deck($Player2Deck)
	_clear_deck($Player2Discard)
	_clear_deck($Player2Hand)
	_load_deck_into($Deck, player1_deck)
	_load_deck_into($Player2Deck, player2_deck)
	match_started = true
	if is_instance_valid(match_setup):
		match_setup.close()
	if not is_instance_valid(format_tracker):
		_create_format_tracker()
	format_tracker.set_format(format_id)
	format_tracker.lock_format()
	if ai_player_id >= 0:
		set_ai_player(ai_player_id)
	else:
		if is_instance_valid(ai_controller):
			ai_controller.queue_free()
			ai_controller = null
	cfc.game_paused = false
	turn_manager.start_game()


func set_ai_player(player_id: int) -> void:
	if is_instance_valid(ai_controller):
		ai_controller.queue_free()
	ai_controller = AI_CONTROLLER_SCRIPT.new()
	ai_controller.name = "AIController"
	ai_controller.board = self
	ai_controller.player_id = player_id
	add_child(ai_controller)


func _start_pending_campaign_match() -> void:
	var pending: Dictionary = cfc.pending_campaign_match
	cfc.pending_campaign_match = {}
	if pending.empty():
		_create_match_setup()
		return
	var campaign: Dictionary = CAMPAIGN_DATA_SCRIPT.load_campaign()
	var opponent_id := str(pending.get("opponent_id", ""))
	var opponent := CAMPAIGN_DATA_SCRIPT.find_opponent(campaign, opponent_id)
	var opponent_deck: Dictionary = pending.get("opponent_deck", {})
	if opponent_deck.empty() and not opponent.empty():
		opponent_deck = CAMPAIGN_DATA_SCRIPT.load_opponent_deck(opponent)
	var player_deck: Dictionary = pending.get("player_deck", {})
	if player_deck.empty() or opponent_deck.empty():
		_create_match_setup()
		return
	campaign_match = true
	campaign_opponent_id = opponent_id
	var format_id := str(pending.get("format_id",
			campaign.get("format_id", "three_heroes")))
	start_match(format_id, player_deck, opponent_deck, 1)


func on_match_finished(winner_player_id: int) -> void:
	if not campaign_match or campaign_opponent_id.empty():
		return
	if winner_player_id != 0:
		return
	var campaign: Dictionary = CAMPAIGN_DATA_SCRIPT.load_campaign()
	var progress: Dictionary = CAMPAIGN_PROGRESS_SCRIPT.load_progress(
			campaign_save_path)
	progress = CAMPAIGN_PROGRESS_SCRIPT.record_completion(
			campaign, progress, campaign_opponent_id)
	CAMPAIGN_PROGRESS_SCRIPT.save_progress(progress, campaign_save_path)


func _clear_deck(container: CardContainer) -> void:
	for child in container.get_children():
		if child is Card:
			container.remove_child(child)
			child.queue_free()


func _load_deck_into(pile: Pile, deck: Dictionary) -> void:
	if not deck.has("cards") or typeof(deck.cards) != TYPE_DICTIONARY:
		return
	for card_name in deck.cards:
		var quantity := max(0, int(deck.cards[card_name]))
		for _copy in range(quantity):
			var card: Card = cfc.instance_card(str(card_name))
			if not is_instance_valid(card):
				continue
			pile.add_child(card)
			card._determine_idle_state()
	# Synchronous shuffle: the opening hand is drawn immediately after
	# start_match(), so the animated shuffle (which reorders later) would let
	# the draw use the deck file's insertion order.
	pile.shuffle_cards(false)


func _on_match_setup_deckbuilder() -> void:
	if is_instance_valid(match_setup):
		match_setup.close()
	_opening_deckbuilder = true
	_on_DeckBuilder_pressed()


func _on_turn_started(player_id: int, turn_num: int) -> void:
	var is_ai := is_ai_turn()
	set_input_locked(is_ai)
	if has_node("TurnInfo/TurnLabel"):
		if is_ai:
			$TurnInfo/TurnLabel.text = "Player %d's Turn [AI]" % [player_id + 1]
		else:
			$TurnInfo/TurnLabel.text = "Player %d's Turn (Turn %d)" % [player_id + 1, turn_num]
	_set_active_player_containers(player_id)
	if match_started:
		draw_cards_for_turn(player_id)
	_hide_actions()
	if is_instance_valid(ai_controller) and player_id == ai_controller.player_id:
		call_deferred("_start_ai_turn")


func set_input_locked(locked: bool) -> void:
	if has_node("AIInputBlocker"):
		$AIInputBlocker.visible = locked
	if is_instance_valid(mouse_pointer):
		if locked:
			mouse_pointer.disable()
		else:
			mouse_pointer.enable()
	if has_node("TurnInfo/NextPhaseBtn"):
		$TurnInfo/NextPhaseBtn.disabled = locked
		if locked:
			$TurnInfo/NextPhaseBtn.text = "AI Turn..."
		elif turn_manager:
			var p_name = "Next Phase" if turn_manager.current_phase == TurnManager.Phase.PLAY_PHASE else "End Turn"
			$TurnInfo/NextPhaseBtn.text = p_name


func draw_cards_for_turn(player_id: int) -> int:
	var hand = get_player_hand(player_id)
	var deck = get_player_deck(player_id)
	if not is_instance_valid(hand) or not is_instance_valid(deck):
		return 0
	var hand_count = hand.get_card_count()
	var draw_count = 1 if hand_count >= 5 else 5 - hand_count
	var drawn := 0
	for _draw in range(draw_count):
		if deck.get_card_count() <= 0:
			break
		if not hand.draw_card(deck):
			break
		drawn += 1
	return drawn


func _start_ai_turn() -> void:
	if not cfc.ut:
		yield(get_tree().create_timer(0.4), "timeout")
	if not is_instance_valid(ai_controller):
		return
	var result = ai_controller.take_turn()
	if result is GDScriptFunctionState:
		yield(result, "completed")


func is_ai_turn() -> bool:
	if not is_instance_valid(ai_controller) or not is_instance_valid(turn_manager):
		return false
	return turn_manager.active_player == ai_controller.player_id


func get_player_zone(player_id: int):
	var key := "player" + str(player_id + 1) + "zone"
	return cfc.NMAP.get(key)


func _set_active_player_containers(player_id: int) -> void:
	if not has_node("Player2Deck"):
		return
	var show_player1 := player_id == 0
	for node_name in ["Deck", "Discard", "Hand"]:
		if has_node(node_name):
			get_node(node_name).visible = show_player1
	for node_name in ["Player2Deck", "Player2Discard", "Player2Hand"]:
		if has_node(node_name):
			get_node(node_name).visible = not show_player1
	for container in get_tree().get_nodes_in_group("card_containers"):
		if is_instance_valid(container):
			container.re_place()


func get_player_deck(player_id: int):
	if player_id == 0 or not has_node("Player2Deck"):
		return $Deck
	return $Player2Deck


func get_player_discard(player_id: int):
	if player_id == 0 or not has_node("Player2Discard"):
		return $Discard
	return $Player2Discard


func get_player_hand(player_id: int):
	if player_id == 0 or not has_node("Player2Hand"):
		return $Hand
	return $Player2Hand


func get_active_deck():
	return get_player_deck(turn_manager.active_player)


func get_active_discard():
	return get_player_discard(turn_manager.active_player)


func get_active_hand():
	return get_player_hand(turn_manager.active_player)

func _on_phase_changed(phase: int) -> void:
	if has_node("TurnInfo/PhaseLabel"):
		var p_name = "Play Phase" if phase == TurnManager.Phase.PLAY_PHASE else "Action Phase"
		$TurnInfo/PhaseLabel.text = p_name
	if has_node("TurnInfo/NextPhaseBtn"):
		if is_ai_turn():
			$TurnInfo/NextPhaseBtn.text = "AI Turn..."
			$TurnInfo/NextPhaseBtn.disabled = true
		else:
			$TurnInfo/NextPhaseBtn.text = "Next Phase" if phase == TurnManager.Phase.PLAY_PHASE else "End Turn"
			$TurnInfo/NextPhaseBtn.disabled = false
	_hide_actions()

func _on_NextPhaseBtn_pressed() -> void:
	if turn_manager and not is_ai_turn():
		turn_manager.next_phase()

func _hide_actions() -> void:
	if has_node("ActionContainer"):
		$ActionContainer.visible = false
	selected_card_for_action = null

func select_card_for_action(card) -> void:
	if not turn_manager or is_ai_turn():
		return
	if turn_manager.current_phase != TurnManager.Phase.ACTION_PHASE:
		return
	if card.current_owner != turn_manager.active_player:
		return
	if card.has_acted_this_turn or card.knocked_out_turns > 0:
		return
	selected_card_for_action = card
	if has_node("ActionContainer"):
		var card_is_item = card.is_item()
		var attack_visible = not card_is_item and _card_action_power(card, "Attack") > 0
		var control_visible = not card_is_item and _card_action_power(card, "Control") > 0
		var spare_visible = not card_is_item and _card_action_power(card, "Spare") > 0
		var equip_visible = card_is_item
		$ActionContainer/AttackBtn.visible = attack_visible
		$ActionContainer/ControlBtn.visible = control_visible
		$ActionContainer/SpareBtn.visible = spare_visible
		$ActionContainer/EquipBtn.visible = equip_visible
		$ActionContainer.visible = attack_visible or control_visible \
				or spare_visible or equip_visible


func _card_action_power(card, action_type: String) -> int:
	if not is_instance_valid(card):
		return 0
	return card.get_action_value(action_type)

func _on_AttackBtn_pressed() -> void:
	if is_ai_turn():
		return
	if selected_card_for_action and turn_manager:
		turn_manager.request_action(selected_card_for_action, "Attack")
		_hide_actions()

func _on_ControlBtn_pressed() -> void:
	if is_ai_turn():
		return
	if selected_card_for_action and turn_manager:
		turn_manager.request_action(selected_card_for_action, "Control")
		_hide_actions()

func _on_SpareBtn_pressed() -> void:
	if is_ai_turn():
		return
	if selected_card_for_action and turn_manager:
		turn_manager.request_action(selected_card_for_action, "Spare")
		_hide_actions()

func _on_EquipBtn_pressed() -> void:
	if is_ai_turn():
		return
	if selected_card_for_action and turn_manager:
		turn_manager.request_action(selected_card_for_action, "Equip")
		_hide_actions()

func _on_FancyMovementToggle_toggled(_button_pressed) -> void:
	cfc.set_setting('fancy_movement', $FancyMovementToggle.pressed)

func _on_OvalHandToggle_toggled(_button_pressed: bool) -> void:
	cfc.set_setting("hand_use_oval_shape", $OvalHandToggle.pressed)
	for hand in get_tree().get_nodes_in_group("hands"):
		for c in hand.get_all_cards():
			c.reorganize_self()

func _on_ReshuffleAllDeck_pressed() -> void:
	reshuffle_all_in_pile(get_active_deck())

func _on_ReshuffleAllDiscard_pressed() -> void:
	reshuffle_all_in_pile(get_active_discard())

func reshuffle_all_in_pile(pile: Pile = null):
	if not is_instance_valid(pile):
		pile = get_active_deck()
	var active_player = turn_manager.active_player
	var active_hand = get_player_hand(active_player)
	var active_discard = get_player_discard(active_player)
	for c in get_tree().get_nodes_in_group("cards"):
		if c.get_parent() == pile or c.state == Card.CardState.DECKBUILDER_GRID:
			continue
		if c.get_parent() == active_hand or c.get_parent() == active_discard \
				or c.current_owner == active_player:
			c.move_to(pile)
			yield(get_tree().create_timer(0.1), "timeout")
	var last_card : Card = pile.get_top_card()
	if last_card and last_card._tween.is_active():
		yield(last_card._tween, "tween_all_completed")
	yield(get_tree().create_timer(0.2), "timeout")
	pile.shuffle_cards()

func _on_ScalingFocusOptions_item_selected(index) -> void:
	cfc.set_setting('focus_style', index)

func _on_EnableAttach_toggled(button_pressed: bool) -> void:
	for c in get_tree().get_nodes_in_group("cards"):
		if button_pressed:
			c.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		else:
			c.attachment_mode = Card.AttachmentMode.DO_NOT_ATTACH

func _on_Debug_toggled(button_pressed: bool) -> void:
	cfc._debug = button_pressed

func load_test_cards(gut := true) -> void:
	var test_card_array := []
	for card_name in cfc.card_definitions.keys():
		if card_name != "Spawn Card":
			test_card_array.append(cfc.instance_card(card_name))
	for card in test_card_array:
		cfc.NMAP.deck.add_child(card)
		card._determine_idle_state()
	if turn_manager:
		turn_manager.start_game()

func _on_DeckBuilder_pressed() -> void:
	cfc.game_paused = true
	$DeckBuilderPopup.popup_centered_minsize()

func _on_DeckBuilder_hide() -> void:
	cfc.game_paused = false
	if _opening_deckbuilder and not match_started \
			and is_instance_valid(match_setup):
		_opening_deckbuilder = false
		match_setup.open(self)

func _on_BackToMain_pressed() -> void:
	cfc.quit_game()
	get_tree().change_scene("res://src/custom/MainMenu.tscn")


# --- Battle log -----------------------------------------------------------

func add_log_message(message: String) -> void:
	battle_log_messages.append(message)
	if not is_instance_valid(_battle_log_messages):
		return
	var label := Label.new()
	label.text = message
	label.autowrap = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_log_messages.add_child(label)
	call_deferred("_scroll_log_bottom")


func _scroll_log_bottom() -> void:
	if is_instance_valid(_battle_log_scroll):
		_battle_log_scroll.scroll_vertical = 1000000


func get_player_name(player_id: int) -> String:
	if campaign_match:
		var campaign = CAMPAIGN_DATA_SCRIPT.load_campaign()
		var opponent = CAMPAIGN_DATA_SCRIPT.find_opponent(
				campaign, campaign_opponent_id)
		if player_id == 1 and not opponent.empty():
			return str(opponent.get("name", "Opponent"))
	return "Player " + str(player_id + 1)


func log_card_played(card) -> void:
	if not is_instance_valid(card):
		return
	add_log_message("%s played %s" % [
			get_player_name(card.original_owner), card.canonical_name])


# --- Battle arrows --------------------------------------------------------

func _card_center(card) -> Vector2:
	if not is_instance_valid(card):
		return Vector2.ZERO
	# Board cards use their placement slot, so a card that is still tweening
	# from the hand (or its previous slot) does not skew the arrow.
	if card.get_parent() == self and is_instance_valid(card._placement_slot):
		return card._placement_slot.rect_global_position \
				+ card._placement_slot.rect_size / 2
	return card.targeting_arrow.card_center()


func show_battle_arrow(card, target, color: Color) -> void:
	if not is_instance_valid(_battle_arrow):
		return
	if is_instance_valid(_arrow_timer):
		_arrow_timer.stop()
	_battle_arrow.draw_between(_card_center(card), _card_center(target), color)


func hide_battle_arrow() -> void:
	if is_instance_valid(_arrow_timer):
		_arrow_timer.stop()
	if is_instance_valid(_battle_arrow):
		_battle_arrow.hide_arrow()


func _hide_battle_arrow() -> void:
	hide_battle_arrow()


func show_cost_arrow(source, played) -> void:
	if not is_instance_valid(_battle_arrow):
		return
	if not is_instance_valid(source) or not is_instance_valid(played):
		return
	_battle_arrow.draw_between(_card_center(source), _card_center(played),
			Color(1, 1, 1, 1))
	if is_instance_valid(_arrow_timer):
		var is_ai_play: bool = is_instance_valid(ai_controller) \
				and played.original_owner == ai_controller.player_id
		_arrow_timer.start(0.5 if is_ai_play else 1.0)
