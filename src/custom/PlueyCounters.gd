# PlueyCounters.gd
class_name PlueyCounters
extends Counters

func _ready() -> void:
	counters_container = $VBoxContainer
	value_node = "MarginContainer/CenterContainer/Label"
	needed_counters = {
		"p1_resources": {
			value_node: 3,
			"TextureRect/Label": "P1 Resources",
		},
		"p2_resources": {
			value_node: 3,
			"TextureRect/Label": "P2 Resources",
		},
	}
	spawn_needed_counters()
