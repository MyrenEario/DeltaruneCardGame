class_name CampaignData
extends Reference

const CAMPAIGN_PATH := "res://src/custom/campaign/campaign.json"


static func load_campaign(path := CAMPAIGN_PATH) -> Dictionary:
	return _load_json(path)


static func get_opponents(campaign: Dictionary) -> Array:
	var opponents = campaign.get("opponents", [])
	if typeof(opponents) != TYPE_ARRAY:
		return []
	var resolved := []
	for opponent in opponents:
		if typeof(opponent) != TYPE_DICTIONARY:
			continue
		resolved.append(opponent.duplicate(true))
	return resolved


static func find_opponent(campaign: Dictionary, opponent_id: String) -> Dictionary:
	for opponent in get_opponents(campaign):
		if typeof(opponent) == TYPE_DICTIONARY \
				and str(opponent.get("id", "")) == opponent_id:
			return opponent
	return {}


static func load_opponent_deck(opponent: Dictionary) -> Dictionary:
	# Decks are stored with permanent ids; the game works with names.
	var deck := _load_json(str(opponent.get("deck_path", "")))
	if deck.empty():
		return deck
	var cards = deck.get("cards", {})
	if typeof(cards) == TYPE_DICTIONARY:
		var resolved := {}
		for ref in cards:
			var card_name = cfc.resolve_card_name(str(ref))
			card_name = str(ref) if str(card_name) == "" else str(card_name)
			resolved[card_name] = int(resolved.get(card_name, 0)) + int(cards[ref])
		deck["cards"] = resolved
	return deck


static func _load_json(path: String) -> Dictionary:
	if path.empty():
		return {}
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	return parsed.result
