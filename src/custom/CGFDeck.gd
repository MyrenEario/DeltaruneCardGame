# Code for a sample deck, you're expected to provide your own ;)
extends Pile

signal draw_card(deck)

export var paired_hand_name := "Hand"

var paired_hand: Hand = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	paired_hand = cfc.NMAP.get(paired_hand_name.to_lower())
	if is_instance_valid(paired_hand):
		# warning-ignore:return_value_discarded
		connect("draw_card", paired_hand, "draw_card")
