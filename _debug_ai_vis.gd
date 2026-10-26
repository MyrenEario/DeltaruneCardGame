extends SceneTree

func _init():
	var board_scene = load("res://src/custom/CGFBoard.tscn")
	var board = board_scene.instance()
	root.add_child(board)
	yield(create_timer(0.2), "timeout")
	var p1_deck = {"name": "P1", "format_id": "three_heroes", "cards": {"Dess": 20}, "total": 20}
	var p2_deck = {"name": "P2", "format_id": "three_heroes", "cards": {"Berdly": 20}, "total": 20}
	board.start_match("three_heroes", p1_deck, p2_deck, 1)
	print("Match started!")
	print("P1 hand cards: ", board.get_player_hand(0).get_card_count())
	print("P2 hand cards: ", board.get_player_hand(1).get_card_count())
	
	# End turn 1 (P1)
	board.turn_manager.end_turn()
	print("After P1 end_turn, active player: ", board.turn_manager.active_player)
	print("is_ai_turn: ", board.is_ai_turn())
	
	yield(create_timer(1.0), "timeout")
	
	var p2_zone = board.get_player_zone(1)
	var cards = p2_zone.get_all_cards()
	print("P2 zone card count: ", cards.size())
	for c in cards:
		print("Card: ", c.canonical_name)
		print("  visible: ", c.visible)
		print("  modulate: ", c.modulate)
		print("  position: ", c.position, " global_pos: ", c.global_position)
		print("  scale: ", c.scale)
		print("  z_index: ", c.z_index)
		print("  parent: ", c.get_parent().name)
		print("  is_faceup: ", c.is_faceup)
		print("  state: ", c.state)
		if c.has_node("Front"):
			print("  Front visible: ", c.get_node("Front").visible)
		if c.has_node("Back"):
			print("  Back visible: ", c.get_node("Back").visible)
	quit()
