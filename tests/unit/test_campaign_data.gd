extends "res://addons/gut/test.gd"

const CAMPAIGN_DATA = preload("res://src/custom/campaign/CampaignData.gd")
const GameFormat = preload("res://src/custom/formats/GameFormat.gd")
const DeckLoader = preload("res://src/core/CardViewer/DeckBuilder/DeckLoader.gd")
const CARD_SET_PATH := "res://src/custom/cards/sets/PlueyPokerGen3.json"
const FORMAT_PATH := "res://src/custom/formats/three_heroes.json"

var campaign: Dictionary
var card_definitions: Dictionary


func before_each() -> void:
	cfc.is_testing = true
	cfc._setup()
	campaign = CAMPAIGN_DATA.load_campaign()
	card_definitions = cfc.card_definitions
	assert_false(campaign.empty(), "Campaign data should load")
	assert_false(card_definitions.empty(), "Card definitions should load")


func test_campaign_has_six_ordered_opponents() -> void:
	var opponents := CAMPAIGN_DATA.get_opponents(campaign)
	assert_eq(opponents.size(), 6)
	var expected_ids := [
		"king",
		"queen",
		"roaring_knight",
		"flowery",
		"ralsei",
		"eram",
	]
	for index in range(expected_ids.size()):
		assert_eq(str(opponents[index].get("id", "")), expected_ids[index])


func test_campaign_unlock_chain_is_sequential() -> void:
	var opponents := CAMPAIGN_DATA.get_opponents(campaign)
	assert_true(opponents[0].get("unlock_after") == null)
	for index in range(1, opponents.size()):
		assert_eq(
				str(opponents[index].get("unlock_after", "")),
				str(opponents[index - 1].get("id", "")))


func test_campaign_portraits_exist() -> void:
	var file := File.new()
	for opponent in CAMPAIGN_DATA.get_opponents(campaign):
		var path := str(opponent.get("portrait", ""))
		assert_eq(file.open(path, File.READ), OK, "Missing portrait: " + path)
		file.close()


func test_all_opponent_decks_load() -> void:
	for opponent in CAMPAIGN_DATA.get_opponents(campaign):
		var deck := CAMPAIGN_DATA.load_opponent_deck(opponent)
		assert_false(deck.empty(), "Missing deck for " + str(opponent.get("id", "")))
		for card_name in deck.get("cards", {}):
			assert_true(card_definitions.has(str(card_name)),
					"Unknown card in deck %s: %s" % [
						opponent.get("id", ""), card_name,
					])


func test_starter_player_deck_is_valid_for_format() -> void:
	var path := str(campaign.get("player_deck_path", ""))
	assert_false(path.empty(), "Campaign defines a starter player deck")
	var deck := DeckLoader.from_stored_deck(_load_json(path))
	assert_false(deck.empty(), "Starter deck loads")
	var format := GameFormat.load_format(FORMAT_PATH)
	var errors := GameFormat.validate_deck(deck, format, card_definitions)
	assert_eq(errors.size(), 0,
			"Starter deck must be legal: " + str(errors))


func test_campaign_rules_match_deck_decisions() -> void:
	var rules: Dictionary = campaign.get("rules", {})
	assert_eq(int(rules.get("player_deck_min", 0)), 20)
	assert_eq(int(rules.get("player_deck_max", 0)), 30)
	assert_true(bool(rules.get("allow_incomplete_opponent_decks", false)))


func _load_json(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	return parsed.result
