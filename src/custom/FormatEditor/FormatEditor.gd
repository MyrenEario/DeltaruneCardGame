extends Panel

const GameFormat = preload("res://src/custom/formats/GameFormat.gd")

var _formats := {}
var _format_ids := []
var _format := {}
var _picker_cards := []
var _picker_target := ""

onready var back_button := $Margin/VBox/Header/Back
onready var _format_list := $Margin/VBox/Content/FormatColumn/FormatList
onready var _id_edit := $Margin/VBox/Content/EditorColumn/Fields/IdEdit
onready var _name_edit := $Margin/VBox/Content/EditorColumn/Fields/NameEdit
onready var _min_deck_spin := $Margin/VBox/Content/EditorColumn/Fields/MinDeckSpin
onready var _max_deck_spin := $Margin/VBox/Content/EditorColumn/Fields/MaxDeckSpin
onready var _max_copies_spin := $Margin/VBox/Content/EditorColumn/Fields/MaxCopiesSpin
onready var _objective_list := $Margin/VBox/Content/EditorColumn/Lists/Objectives/ObjectiveList
onready var _banned_list := $Margin/VBox/Content/EditorColumn/Lists/Banned/BannedList
onready var _validation_label := $Margin/VBox/Content/EditorColumn/ValidationLabel
onready var _card_picker := $CardPicker
onready var _card_search := $CardPicker/Margin/VBox/Search
onready var _card_picker_list := $CardPicker/Margin/VBox/CardList


func _ready() -> void:
	_format_list.connect("item_selected", self, "_on_format_selected")
	_card_search.connect("text_changed", self, "_on_card_search_changed")
	_card_picker_list.connect("item_activated", self, "_on_card_picker_activated")
	_reload_formats()


func _reload_formats(select_id := "") -> void:
	_formats = GameFormat.load_all()
	_format_ids = _formats.keys()
	_format_ids.sort()
	_format_list.clear()
	for format_id in _format_ids:
		_format_list.add_item(str(_formats[format_id].name)
				+ " [" + format_id + "]")
	if select_id in _format_ids:
		_format_list.select(_format_ids.find(select_id))
		_on_format_selected(_format_list.get_selected_items()[0])
	elif not _format_ids.empty():
		_format_list.select(0)
		_on_format_selected(0)
	else:
		_new_format()


func _on_format_selected(index: int) -> void:
	if index < 0 or index >= _format_ids.size():
		return
	_format = _formats[_format_ids[index]].duplicate(true)
	_populate_fields()
	_set_validation("")


func _populate_fields() -> void:
	_id_edit.text = str(_format.get("id", ""))
	_name_edit.text = str(_format.get("name", ""))
	_min_deck_spin.value = int(_format.get(
			"min_deck_size", GameFormat.DEFAULT_MIN_DECK_SIZE))
	_max_deck_spin.value = int(_format.get(
			"max_deck_size", GameFormat.DEFAULT_MAX_DECK_SIZE))
	_max_copies_spin.value = int(_format.get(
			"max_copies", GameFormat.DEFAULT_MAX_COPIES))
	_fill_card_list(_objective_list,
			GameFormat._string_array(_format.get("objective_cards", [])))
	_fill_card_list(_banned_list,
			GameFormat._string_array(_format.get("banned_cards", [])))


func _fill_card_list(item_list: ItemList, card_names: Array) -> void:
	item_list.clear()
	for card_name in card_names:
		item_list.add_item(card_name)


func _on_New_pressed() -> void:
	_new_format()


func _new_format() -> void:
	_format = GameFormat.new_format(_next_format_id(), "New Format")
	_format_list.unselect_all()
	_populate_fields()
	_set_validation("Enter a format name and add objective cards")


func _next_format_id() -> String:
	var index := 1
	var candidate := "custom_format"
	while candidate in _format_ids:
		index += 1
		candidate = "custom_format_" + str(index)
	return candidate


func _on_Delete_pressed() -> void:
	if _format.empty():
		return
	var format_id := str(_format.get("id", ""))
	var dir := Directory.new()
	if not dir.file_exists(CFConst.FORMATS_PATH + format_id + ".json"):
		_set_validation("Built-in formats cannot be deleted", true)
		return
	var result := GameFormat.delete_format(format_id)
	if result != OK:
		_set_validation("Unable to delete format", true)
		return
	_reload_formats()


func _on_Save_pressed() -> void:
	var format := _build_format()
	var errors := GameFormat.validate_format(format, cfc.card_definitions)
	if not errors.empty():
		var messages := []
		for format_error in errors:
			messages.append(format_error.message)
		_set_validation("\n".join(messages), true)
		return
	var result := GameFormat.save_format(format)
	if result != OK:
		_set_validation("Unable to save format", true)
		return
	_format = format
	_reload_formats(str(format.id))
	_set_validation("Format saved")


func _build_format() -> Dictionary:
	var format := GameFormat.new_format(
			_id_edit.text.strip_edges(),
			_name_edit.text.strip_edges())
	format.objective_cards = _item_list_cards(_objective_list)
	format.banned_cards = _item_list_cards(_banned_list)
	format.min_deck_size = int(_min_deck_spin.value)
	format.max_deck_size = int(_max_deck_spin.value)
	format.max_copies = int(_max_copies_spin.value)
	return format


func _item_list_cards(item_list: ItemList) -> Array:
	var cards := []
	for index in range(item_list.get_item_count()):
		cards.append(item_list.get_item_text(index))
	return cards


func _on_AddObjective_pressed() -> void:
	_open_card_picker("objective_cards")


func _on_RemoveObjective_pressed() -> void:
	_remove_selected_cards(_objective_list, "objective_cards")


func _on_AddBanned_pressed() -> void:
	_open_card_picker("banned_cards")


func _on_RemoveBanned_pressed() -> void:
	_remove_selected_cards(_banned_list, "banned_cards")


func _open_card_picker(target: String) -> void:
	if _format.empty():
		_format = _build_format()
	_picker_target = target
	_card_search.text = ""
	_filter_card_picker("")
	_card_picker.popup_centered_ratio(0.65)
	_card_search.grab_focus()


func _on_card_search_changed(text: String) -> void:
	_filter_card_picker(text)


func _filter_card_picker(search_text: String) -> void:
	_card_picker_list.clear()
	_picker_cards = []
	var needle := search_text.strip_edges().to_lower()
	var card_names := []
	for card_name in cfc.card_definitions:
		if not needle.empty() and not needle in card_name.to_lower():
			continue
		var card_definition: Dictionary = cfc.card_definitions[card_name]
		if card_definition.get(CardConfig.BOOL_PROPERTY_TO_HIDE_IN_CARDVIEWER):
			continue
		if card_definition.get(CardConfig.SCENE_PROPERTY)\
				in CardConfig.TYPES_TO_HIDE_IN_CARDVIEWER:
			continue
		card_names.append(card_name)
	card_names.sort()
	for card_name in card_names:
		_picker_cards.append(card_name)
		_card_picker_list.add_item(card_name)


func _on_CardPickerAdd_pressed() -> void:
	_add_picker_selection()


func _on_card_picker_activated(index: int) -> void:
	_card_picker_list.select(index)
	_add_picker_selection()


func _add_picker_selection() -> void:
	var selected: PoolIntArray = _card_picker_list.get_selected_items()
	if selected.empty():
		return
	if _format.empty():
		_format = _build_format()
	var cards: Array = _format[_picker_target]
	for index in selected:
		var card_name: String = _picker_cards[index]
		if not card_name in cards:
			cards.append(card_name)
	_format[_picker_target] = cards
	_fill_card_list(_objective_list,
			GameFormat._string_array(_format.get("objective_cards", [])))
	_fill_card_list(_banned_list,
			GameFormat._string_array(_format.get("banned_cards", [])))
	_set_validation("")


func _remove_selected_cards(item_list: ItemList, target: String) -> void:
	var selected: PoolIntArray = item_list.get_selected_items()
	if selected.empty():
		return
	if _format.empty():
		_format = _build_format()
	var cards: Array = _format.get(target, [])
	for index in selected:
		cards.erase(item_list.get_item_text(index))
	_format[target] = cards
	_fill_card_list(_objective_list,
			GameFormat._string_array(_format.get("objective_cards", [])))
	_fill_card_list(_banned_list,
			GameFormat._string_array(_format.get("banned_cards", [])))
	_set_validation("")


func _on_CardPickerClose_pressed() -> void:
	_card_picker.hide()


func _set_validation(text: String, is_error := false) -> void:
	_validation_label.text = text
	if is_error:
		_validation_label.modulate = Color(1, 0.35, 0.35)
	else:
		_validation_label.modulate = Color(0.55, 1, 0.55)
