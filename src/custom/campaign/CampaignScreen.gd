extends Control

const CampaignDataScript = preload("res://src/custom/campaign/CampaignData.gd")
const CampaignProgressScript = preload(
		"res://src/custom/campaign/CampaignProgress.gd")
const DeckLoaderScript = preload(
		"res://src/core/CardViewer/DeckBuilder/DeckLoader.gd")
const GameFormat = preload("res://src/custom/formats/GameFormat.gd")
const DECK_BUILDER_SCENE = preload(
		"res://src/custom/CGFDeckbuilder/CGFDeckBuilder.tscn")
const CAMPAIGN_DECK_PREFIX := "campaign_player_deck"

var campaign := {}
var progress := {}
var player_decks := []
var selected_opponent_id := ""
var _deck_builder = null
var _starter_deck_name := ""

onready var _opponent_list := $Center/Panel/Margin/VBox/OpponentList
onready var _portrait := $Center/Panel/Margin/VBox/DetailRow/Portrait
onready var _detail_label := $Center/Panel/Margin/VBox/DetailRow/DetailLabel
onready var _deck_select := $Center/Panel/Margin/VBox/DeckRow/DeckSelect
onready var _status_label := $Center/Panel/Margin/VBox/StatusLabel
onready var _start_button := $Center/Panel/Margin/VBox/Buttons/Start
onready var _deckbuilder_button := \
		$Center/Panel/Margin/VBox/Buttons/DeckBuilder
onready var _back_button := $Center/Panel/Margin/VBox/Buttons/Back


func _ready() -> void:
	_start_button.connect("pressed", self, "_on_start_pressed")
	_deckbuilder_button.connect("pressed", self, "_on_deck_builder_pressed")
	_back_button.connect("pressed", self, "_on_back_pressed")
	_deck_select.connect("item_selected", self, "_on_deck_selected")
	_load()


func _load() -> void:
	campaign = CampaignDataScript.load_campaign()
	progress = CampaignProgressScript.load_progress()
	player_decks = _load_player_decks()
	_build_deck_selector()
	_build_opponent_list()
	selected_opponent_id = CampaignProgressScript.first_incomplete_id(
			campaign, progress)
	if selected_opponent_id.empty():
		selected_opponent_id = _first_opponent_id()
	_select_opponent(selected_opponent_id)


func _first_opponent_id() -> String:
	for opponent in CampaignDataScript.get_opponents(campaign):
		var opponent_id := str(opponent.get("id", ""))
		if not opponent_id.empty():
			return opponent_id
	return ""


func _load_player_decks() -> Array:
	var format_id := str(campaign.get("format_id", "three_heroes"))
	var result := []
	var starter := _load_starter_deck()
	_starter_deck_name = str(starter.get("name", ""))
	if not starter.empty():
		result.append(starter)
	for deck in DeckLoaderScript.load_all_decks():
		if typeof(deck) != TYPE_DICTIONARY:
			continue
		if str(deck.get("format_id", "")) != format_id:
			continue
		if typeof(deck.get("cards", null)) != TYPE_DICTIONARY:
			continue
		result.append(deck)
	result.sort_custom(self, "_sort_decks_starter_first")
	return result


func _load_starter_deck() -> Dictionary:
	var path := str(campaign.get("player_deck_path", ""))
	if path.empty():
		return {}
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	# The starter deck is stored with permanent ids; use the name-keyed form.
	return DeckLoaderScript.from_stored_deck(parsed.result)


func _sort_decks_starter_first(first: Dictionary, second: Dictionary) -> bool:
	var first_is_starter := str(first.get("name", "")) == _starter_deck_name
	var second_is_starter := str(second.get("name", "")) == _starter_deck_name
	if first_is_starter != second_is_starter:
		return first_is_starter
	return str(first.get("name", "")).to_lower() \
			< str(second.get("name", "")).to_lower()


func _sort_decks(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("name", "")).to_lower() \
			< str(second.get("name", "")).to_lower()


func _build_deck_selector() -> void:
	_deck_select.clear()
	for deck in player_decks:
		_deck_select.add_item("%s (%d cards)" % [
			str(deck.get("name", "Unnamed Deck")),
			GameFormat.deck_total(deck),
		])
	_deck_select.disabled = player_decks.empty()
	var default_index := _default_deck_index()
	if default_index >= 0:
		_deck_select.selected = default_index
	if player_decks.empty():
		_start_button.disabled = true
		_set_status("Build a deck for this format before starting.",
				Color(1, 0.6, 0.3))


# The deck just built at the campaign start is selected automatically. If that
# name is unavailable (e.g. a fresh session), the newest campaign deck wins.
func _default_deck_index() -> int:
	var preferred := str(cfc.campaign_player_deck_name)
	if not preferred.empty():
		for i in range(player_decks.size()):
			if str(player_decks[i].get("name", "")) == preferred:
				return i
	var best_index := -1
	var best_number := 0
	for i in range(player_decks.size()):
		var number := _campaign_deck_number(
				str(player_decks[i].get("name", "")))
		if number > best_number:
			best_number = number
			best_index = i
	return best_index


func _campaign_deck_number(deck_name: String) -> int:
	if not deck_name.begins_with(CAMPAIGN_DECK_PREFIX):
		return 0
	var suffix := deck_name.substr(CAMPAIGN_DECK_PREFIX.length())
	if suffix.is_valid_integer():
		return int(suffix)
	return 0


func _build_opponent_list() -> void:
	for child in _opponent_list.get_children():
		_opponent_list.remove_child(child)
		child.queue_free()
	for opponent in CampaignDataScript.get_opponents(campaign):
		if typeof(opponent) != TYPE_DICTIONARY:
			continue
		var opponent_id := str(opponent.get("id", ""))
		var completed := CampaignProgressScript.is_completed(
				progress, opponent_id)
		var unlocked := CampaignProgressScript.is_unlocked(
				campaign, progress, opponent_id)
		var button := Button.new()
		button.text = _opponent_button_text(opponent, completed, unlocked)
		button.disabled = not unlocked
		button.connect("pressed", self, "_on_opponent_pressed", [opponent_id])
		_opponent_list.add_child(button)


func _opponent_button_text(opponent: Dictionary, completed: bool,
		unlocked: bool) -> String:
	var prefix := "  "
	if completed:
		prefix = "[Done] "
	elif not unlocked:
		prefix = "[Locked] "
	return prefix + str(opponent.get("name", opponent.get("id", "")))


func _on_opponent_pressed(opponent_id: String) -> void:
	_select_opponent(opponent_id)


func _select_opponent(opponent_id: String) -> void:
	if not CampaignProgressScript.is_unlocked(campaign, progress, opponent_id):
		return
	selected_opponent_id = opponent_id
	var opponent := CampaignDataScript.find_opponent(campaign, opponent_id)
	if opponent.empty():
		return
	_load_portrait(str(opponent.get("portrait", "")))
	var deck := CampaignDataScript.load_opponent_deck(opponent)
	_detail_label.text = "%s\nDifficulty: %d\nDeck size: %d" % [
		str(opponent.get("name", opponent_id)),
		int(opponent.get("difficulty", 0)),
		int(deck.get("total", 0)),
	]
	_refresh_start_button()


func _load_portrait(path: String) -> void:
	if path.empty() or not ResourceLoader.exists(path):
		_portrait.texture = null
		return
	_portrait.texture = load(path)


func _on_deck_selected(_index: int) -> void:
	_refresh_start_button()


func _refresh_start_button() -> void:
	var can_start := not player_decks.empty() and not selected_opponent_id.empty()
	_start_button.disabled = not can_start
	if can_start:
		_set_status("Ready to challenge "
				+ str(CampaignDataScript.find_opponent(campaign,
						selected_opponent_id).get("name", selected_opponent_id))
				+ ".", Color(0.8, 0.9, 0.8))


func _on_start_pressed() -> void:
	if selected_opponent_id.empty() or player_decks.empty():
		return
	var deck_index: int = _deck_select.selected
	if deck_index < 0 or deck_index >= player_decks.size():
		return
	var opponent := CampaignDataScript.find_opponent(
			campaign, selected_opponent_id)
	if opponent.empty():
		return
	cfc.pending_campaign_match = {
		"opponent_id": selected_opponent_id,
		"format_id": str(campaign.get("format_id", "three_heroes")),
		"player_deck": player_decks[deck_index],
		"opponent_deck": CampaignDataScript.load_opponent_deck(opponent),
	}
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + 'CGFMain.tscn')


func _on_deck_builder_pressed() -> void:
	if is_instance_valid(_deck_builder):
		return
	_deck_builder = DECK_BUILDER_SCENE.instance()
	add_child(_deck_builder)
	if "back_button" in _deck_builder:
		_deck_builder.back_button.connect(
				"pressed", self, "_on_deck_builder_back")


func _on_deck_builder_back() -> void:
	if is_instance_valid(_deck_builder):
		_deck_builder.queue_free()
	_deck_builder = null
	_reload_decks()


func _reload_decks() -> void:
	player_decks = _load_player_decks()
	_build_deck_selector()
	_refresh_start_button()


func _on_back_pressed() -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene("res://src/custom/MainMenu.tscn")


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.set("custom_colors/font_color", color)


