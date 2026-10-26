# Extends the deck builder's Load menu with the campaign decks stored under
# res://src/custom/campaign/decks/. Campaign decks are tagged with the path
# they were loaded from, so Save writes changes back to the campaign file.
extends DeckLoader

const CAMPAIGN_DECKS_PATH := "res://src/custom/campaign/decks/"


func _on_about_to_show() -> void:
	get_popup().clear()
	_load_decks_list = []
	for deck in DeckLoader.load_all_decks():
		deck["_menu_label"] = str(deck.get("name", "Unnamed Deck"))
		_load_decks_list.append(deck)
	for file_name in CFUtils.list_files_in_directory(CAMPAIGN_DECKS_PATH):
		if not file_name.ends_with(".json"):
			continue
		var path: String = CAMPAIGN_DECKS_PATH + file_name
		var file := File.new()
		if file.open(path, File.READ) != OK:
			continue
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
			continue
		var deck: Dictionary = DeckLoader.from_stored_deck(parsed.result)
		deck["_source_path"] = path
		deck["_menu_label"] = "Campaign: " + str(deck.get("name", file_name))
		_load_decks_list.append(deck)
	for deck in _load_decks_list:
		get_popup().add_item(
				str(deck.get("_menu_label", deck.get("name", "")))
				+ ' (' + str(deck.get("total", 0)) + ' cards)')
	if get_popup().get_item_count() == 0:
		get_popup().add_item("No decks found. Please create a deck and try again")
