# PlueyFolderNav.gd
# Adds a "Folder" dropdown to a CardViewer (deckbuilder / card library) which
# filters the available cards down to a single card folder.
#
# Cards carry their folder in a "Folder" property. Cards without one are
# treated as belonging to DEFAULT_FOLDER.
#
# NOTE: intentionally not a `class_name`, so it does not depend on the editor
# having registered a global class. Consumers `preload()` it by path instead.
extends Reference

const DEFAULT_FOLDER := "Uncategorized"

var _viewer
var _option : OptionButton
# The currently selected folder. "" means "All folders".
var current := ""


func setup(viewer, option: OptionButton) -> void:
	_viewer = viewer
	_option = option
	_option.clear()
	_option.add_item("All folders")
	_option.set_item_metadata(0, "")
	for f in _folders():
		_option.add_item(f)
		_option.set_item_metadata(_option.get_item_count() - 1, f)
	_option.select(0)
	# warning-ignore:return_value_discarded
	_option.connect("item_selected", self, "_on_selected")


# Every folder in use among the cards shown in the viewer, sorted.
func _folders() -> Array:
	var seen := {}
	var defs := {}
	if cfc:
		defs = cfc.card_definitions
	for key in defs.keys():
		var card_def = defs[key]
		if card_def.get(CardConfig.BOOL_PROPERTY_TO_HIDE_IN_CARDVIEWER):
			continue
		if card_def.get(CardConfig.SCENE_PROPERTY)\
				in CardConfig.TYPES_TO_HIDE_IN_CARDVIEWER:
			continue
		seen[_folder_of(card_def)] = true
	var arr := seen.keys()
	arr.sort()
	return arr


func _folder_of(card_properties: Dictionary) -> String:
	var f := str(card_properties.get("Folder", "")).strip_edges()
	if f == "":
		f = DEFAULT_FOLDER
	return f


func _on_selected(_index: int) -> void:
	current = str(_option.get_item_metadata(_option.get_selected()))
	if _viewer:
		_viewer._apply_filters(_viewer._filter_line.get_active_filters())


# Called by the viewer's _check_custom_filters() for each card.
func matches(card_properties: Dictionary) -> bool:
	if current == "":
		return true
	return _folder_of(card_properties) == current
