extends "res://tests/UTcommon.gd"

const LIST_OBJECT = preload(
		"res://src/custom/CGFDeckbuilder/CGFListCardObject.tscn")


func test_resize_before_setup_does_not_crash():
	var obj = LIST_OBJECT.instance()
	assert_null(obj.abilities_label,
			"No abilities label exists before setup")
	# This used to raise "Invalid get index 'rect_min_size'".
	obj._on_viewport_resized()
	assert_true(true, "Resizing before setup is safe")
	obj.free()
