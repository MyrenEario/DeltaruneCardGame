extends Control

signal match_requested(format_id, player1_deck, player2_deck, ai_player_id)
signal deckbuilder_requested
signal back_requested

const GameFormat = preload("res://src/custom/formats/GameFormat.gd")
const DeckLoaderScript = preload(
		"res://src/core/CardViewer/DeckBuilder/DeckLoader.gd")
const DEFAULT_FORMAT_ID := "three_heroes"

var board = null
var formats := {}
var format_ids := []
var decks := []

onready var _format_select := $Center/Panel/Margin/VBox/FormatSelect
onready var _player1_select := $Center/Panel/Margin/VBox/Player1Select
onready var _player2_select := $Center/Panel/Margin/VBox/Player2Select
onready var _player2_mode_check := $Center/Panel/Margin/VBox/Player2ModeCheck
onready var _status_label := $Center/Panel/Margin/VBox/StatusLabel
onready var _start_button := $Center/Panel/Margin/VBox/Buttons/Start
onready var _deckbuilder_button := $Center/Panel/Margin/VBox/Buttons/DeckBuilder
onready var _back_button := $Center/Panel/Margin/VBox/Buttons/Back


func _ready() -> void:
	_format_select.connect("item_selected", self, "_on_format_selected")
	_start_button.connect("pressed", self, "_on_start_pressed")
	_deckbuilder_button.connect("pressed", self, "_on_deckbuilder_pressed")
	_back_button.connect("pressed", self, "_on_back_pressed")


func open(board_ref) -> void:
	board = board_ref
	_reload()
	visible = true
	cfc.game_paused = true


func close() -> void:
	visible = false


func _reload() -> void:
	_load_formats()
	_load_decks()


func _load_formats() -> void:
	var previous_id := _selected_format_id()
	formats = GameFormat.load_all()
	format_ids = formats.keys()
	format_ids.sort()
	_format_select.clear()
	if format_ids.empty():
		_format_select.add_item("No formats available")
		_format_select.disabled = true
		_player1_select.disabled = true
		_player2_select.disabled = true
		_start_button.disabled = true
		_set_status("Create a format before starting a game.",
				Color(1, 0.6, 0.3))
		return
	for format_id in format_ids:
		_format_select.add_item(
				str(formats[format_id].get("name", format_id)))
	var selected_index := format_ids.find(previous_id)
	if selected_index < 0:
		selected_index = format_ids.find(DEFAULT_FORMAT_ID)
	if selected_index < 0:
		selected_index = 0
	_format_select.select(selected_index)
	_refresh_decks()


func _refresh_decks() -> void:
	_load_decks()
	var deck_count := decks.size()
	_player1_select.clear()
	_player2_select.clear()
	for deck in decks:
		var label := "%s (%d cards)" % [
			str(deck.get("name", "Unnamed Deck")),
			GameFormat.deck_total(deck),
		]
		_player1_select.add_item(label)
		_player2_select.add_item(label)
	_player1_select.disabled = deck_count == 0
	_player2_select.disabled = deck_count == 0
	_start_button.disabled = deck_count == 0
	if deck_count == 0:
		_set_status("No saved decks for this format. Build one first.",
				Color(1, 0.6, 0.3))
	else:
		_set_status("Each player selects their own saved deck.",
				Color(0.8, 0.9, 0.8))


func _load_decks() -> void:
	decks = []
	var format_id := _selected_format_id()
	if format_id.empty():
		return
	for deck in DeckLoaderScript.load_all_decks():
		if typeof(deck) != TYPE_DICTIONARY:
			continue
		if str(deck.get("format_id", "")) != format_id:
			continue
		if typeof(deck.get("cards", null)) != TYPE_DICTIONARY:
			continue
		decks.append(deck)
	decks.sort_custom(self, "_sort_decks")


func _sort_decks(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("name", "")).to_lower() \
			< str(second.get("name", "")).to_lower()


func _selected_format_id() -> String:
	if format_ids.empty() or _format_select == null:
		return ""
	var index: int = _format_select.selected
	if index < 0 or index >= format_ids.size():
		return ""
	return format_ids[index]


func _on_format_selected(_index: int) -> void:
	_refresh_decks()


func _on_start_pressed() -> void:
	if decks.empty():
		return
	var format_id := _selected_format_id()
	if format_id.empty() or not formats.has(format_id):
		_set_status("Select a format.", Color(1, 0.6, 0.3))
		return
	var player1_index: int = _player1_select.selected
	var player2_index: int = _player2_select.selected
	if player1_index < 0 or player1_index >= decks.size() \
			or player2_index < 0 or player2_index >= decks.size():
		_set_status("Select a deck for both players.", Color(1, 0.6, 0.3))
		return
	var format: Dictionary = formats[format_id]
	var player1_deck: Dictionary = decks[player1_index]
	var player2_deck: Dictionary = decks[player2_index]
	var error := _validate_deck(player1_deck, format, "Player 1")
	if not error.empty():
		_set_status(error, Color(1, 0.4, 0.4))
		return
	error = _validate_deck(player2_deck, format, "Player 2")
	if not error.empty():
		_set_status(error, Color(1, 0.4, 0.4))
		return
	var ai_player_id: int = 1 if is_instance_valid(_player2_mode_check) and _player2_mode_check.pressed else -1
	emit_signal("match_requested", format_id, player1_deck, player2_deck, ai_player_id)


func _validate_deck(deck: Dictionary, format: Dictionary,
		player_label: String) -> String:
	var errors := GameFormat.validate_deck(
			deck, format, cfc.card_definitions)
	if errors.empty():
		return ""
	return player_label + ": " + str(errors[0].message)


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.set("custom_colors/font_color", color)


func _on_deckbuilder_pressed() -> void:
	emit_signal("deckbuilder_requested")


func _on_back_pressed() -> void:
	emit_signal("back_requested")
