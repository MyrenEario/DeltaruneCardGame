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


func test_campaign_hero_cards_exist() -> void:
	for opponent in CAMPAIGN_DATA.get_opponents(campaign):
		for hero_card in opponent.get("hero_cards", []):
			assert_true(
					card_definitions.has(str(hero_card)),
					"Unknown hero card for %s: %s" % [
						opponent.get("name", ""),
						hero_card,
					])


func test_king_deck_contains_three_hero_cards() -> void:
	var king := CAMPAIGN_DATA.find_opponent(campaign, "king")
	assert_false(king.empty())
	var deck := CAMPAIGN_DATA.load_opponent_deck(king)
	assert_false(deck.empty())
	assert_eq(int(deck.get("total", 0)), 3)
	assert_eq(deck.get("cards", {}).size(), 3)
	for hero_card in king.get("hero_cards", []):
		assert_eq(int(deck.cards.get(str(hero_card), 0)), 1)


func test_all_opponent_decks_load_and_contain_hero_cards() -> void:
	for opponent in CAMPAIGN_DATA.get_opponents(campaign):
		var deck := CAMPAIGN_DATA.load_opponent_deck(opponent)
		assert_false(deck.empty(), "Missing deck for " + str(opponent.get("id", "")))
		var cards: Dictionary = deck.get("cards", {})
		for hero_card in opponent.get("hero_cards", []):
			assert_true(cards.has(str(hero_card)),
					"Deck %s missing hero card %s" % [
						opponent.get("id", ""),
						hero_card,
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
