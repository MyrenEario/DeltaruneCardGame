# This file contains card definitions for PlueyPoker Gen3
#
# The actual card data lives in a plain-text JSON file so that it can be
# read (and later written) by a card editor. This script simply loads that
# file whenever it is instantiated.
extends Reference

const SET := "PlueyPoker Gen3"
const DATA_FILE := "res://src/custom/cards/sets/PlueyPokerGen3.json"

# Populated in _init() from DATA_FILE
var CARDS : Dictionary = {}


func _init() -> void:
	CARDS = _load_cards()


func _load_cards() -> Dictionary:
	var file := File.new()
	if not file.file_exists(DATA_FILE):
		printerr("PlueyPoker: card data file not found: " + DATA_FILE)
		return {}
	var err := file.open(DATA_FILE, File.READ)
	if err != OK:
		printerr("PlueyPoker: failed to open card data file: " + DATA_FILE)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = parse_json(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("PlueyPoker: invalid JSON in card data file: " + DATA_FILE)
		return {}
	return parsed
