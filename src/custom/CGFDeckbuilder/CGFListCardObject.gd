extends CLListCardObject

var abilities_label : RichTextLabel

func _ready() -> void:
	abilities_label = get_node_or_null("Abilities")
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed",self,"_on_viewport_resized")

func setup(_card_name: String) -> void:
	.setup(_card_name)
	abilities_label = get_node_or_null("Abilities")
	_resize_abilities()

# Resizes the abilities to match the window size.
# So that the abilities have the most space to show.
func _on_viewport_resized() -> void:
	_resize_abilities()

func _resize_abilities() -> void:
	# The Abilities child is only created by setup(), and the viewport can
	# resize (e.g. while in the main menu) before that ever happens.
	if not is_instance_valid(abilities_label):
		return
	abilities_label.rect_min_size.x = get_viewport().size.x / 2
	
