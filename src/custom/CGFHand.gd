extends Hand

export var paired_discard_name := "Discard"

func _ready() -> void:
	# warning-ignore:return_value_discarded
	$Control/ManipulationButtons/DiscardRandom.connect("pressed",self,'_on_DiscardRandom_Button_pressed')

func _on_DiscardRandom_Button_pressed() -> void:
	var card = get_random_card()
	if card:
		var discard_pile = cfc.NMAP.get(paired_discard_name.to_lower())
		if discard_pile:
			card.move_to(discard_pile)
