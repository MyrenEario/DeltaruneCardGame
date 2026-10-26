extends SceneTree

func _init():
	var board_scene = load("res://src/custom/CGFBoard.tscn")
	var board = board_scene.instance()
	root.add_child(board)
	yield(create_timer(0.2), "timeout")
	var p1_deck = {"name": "P1", "format_id": "three_heroes", "cards": {"Dess": 20}, "total": 20}
	var p2_deck = {"name": "P2", "format_id": "three_heroes", "cards": {"Berdly": 20}, "total": 20}
	board.start_match("three_heroes", p1_deck, p2_deck, 1)
	
	# End turn 1 (P1)
	board.turn_manager.end_turn()
	yield(create_timer(1.0), "timeout")
	
	var p2_zone = board.get_player_zone(1)
	var cards = p2_zone.get_all_cards()
	print("P2 zone card count: ", cards.size())
	for c in cards:
		print("Card: ", c.canonical_name)
		print("  visible: ", c.visible)
		print("  Control visible: ", c.get_node("Control").visible)
		print("  Front visible: ", c.get_node("Control/Front").visible)
		print("  Back visible: ", c.get_node("Control/Back").visible)
		print("  Front modulate: ", c.get_node("Control/Front").modulate)
		print("  Front self_modulate: ", c.get_node("Control/Front").self_modulate)
		print("  Control rect_size: ", c.get_node("Control").rect_size)
		print("  Control rect_scale: ", c.get_node("Control").rect_scale)
	quit()
