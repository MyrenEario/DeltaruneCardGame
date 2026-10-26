extends Reference

const SCHEMA_VERSION := CFConst.FORMAT_SCHEMA_VERSION
const DEFAULT_MIN_DECK_SIZE := 52
const DEFAULT_MAX_DECK_SIZE := 60
const DEFAULT_MAX_COPIES := 3
const BUILTIN_PATH := CFConst.BUILTIN_FORMATS_PATH
const USER_PATH := CFConst.FORMATS_PATH


static func new_format(id := "", name := "") -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"name": name,
		"objective_cards": [],
		"banned_cards": [],
		"min_deck_size": DEFAULT_MIN_DECK_SIZE,
		"max_deck_size": DEFAULT_MAX_DECK_SIZE,
		"max_copies": DEFAULT_MAX_COPIES,
	}


static func normalize(data: Dictionary) -> Dictionary:
	var format := data.duplicate(true)
	format["schema_version"] = int(format.get(
			"schema_version", SCHEMA_VERSION))
	format["id"] = str(format.get("id", "")).strip_edges()
	format["name"] = str(format.get("name", "")).strip_edges()
	format["objective_cards"] = _resolve_refs_to_names(
			_string_array(format.get("objective_cards", [])))
	format["banned_cards"] = _resolve_refs_to_names(
			_string_array(format.get("banned_cards", [])))
	format["min_deck_size"] = int(format.get(
			"min_deck_size", DEFAULT_MIN_DECK_SIZE))
	format["max_deck_size"] = int(format.get(
			"max_deck_size", DEFAULT_MAX_DECK_SIZE))
	format["max_copies"] = int(format.get("max_copies", DEFAULT_MAX_COPIES))
	return format


static func load_all(include_user := true) -> Dictionary:
	var formats := {}
	_load_directory(BUILTIN_PATH, formats)
	if include_user:
		_load_directory(USER_PATH, formats)
	return formats


static func load_format(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	var format: Dictionary = normalize(parsed.result)
	if format.id.empty():
		format.id = path.get_file().get_basename()
	return format


static func save_format(format: Dictionary) -> int:
	var normalized := normalize(format)
	if not is_valid_id(str(normalized.id)):
		return ERR_INVALID_PARAMETER
	var dir := Directory.new()
	if not dir.dir_exists(USER_PATH):
		dir.make_dir_recursive(USER_PATH)
	var file := File.new()
	var path: String = USER_PATH + str(normalized.id) + ".json"
	if file.open(path, File.WRITE) != OK:
		return ERR_CANT_CREATE
	# Formats are persisted with permanent card ids so a rename never breaks
	# them; in memory they stay name-based (see normalize()).
	var stored := normalized.duplicate(true)
	stored["objective_cards"] = _refs_to_ids(
			_string_array(normalized.get("objective_cards", [])))
	stored["banned_cards"] = _refs_to_ids(
			_string_array(normalized.get("banned_cards", [])))
	file.store_string(JSON.print(stored, "\t"))
	file.close()
	return OK


static func delete_format(format_id: String) -> int:
	if not is_valid_id(format_id):
		return ERR_INVALID_PARAMETER
	var path := USER_PATH + format_id + ".json"
	var dir := Directory.new()
	if not dir.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return dir.remove(path)


static func effective_banned(format: Dictionary) -> Array:
	var banned := []
	for card_name in _string_array(format.get("objective_cards", [])):
		if not card_name in banned:
			banned.append(card_name)
	for card_name in _string_array(format.get("banned_cards", [])):
		if not card_name in banned:
			banned.append(card_name)
	return banned


static func validate_format(format: Dictionary, definitions = null) -> Array:
	if definitions == null:
		definitions = cfc.card_definitions
	var errors := []
	if format.empty():
		errors.append(_error("format_empty", "Format is empty"))
		return errors
	var format_id := str(format.get("id", ""))
	if not is_valid_id(format_id):
		errors.append(_error(
				"invalid_id",
				"Format ID must use lowercase letters, numbers, '-' or '_'"))
	if str(format.get("name", "")).strip_edges().empty():
		errors.append(_error("empty_name", "Format name is required"))
	var objectives := _string_array(format.get("objective_cards", []))
	if objectives.empty():
		errors.append(_error(
				"no_objectives", "At least one objective card is required"))
	var min_size := int(format.get("min_deck_size", 0))
	var max_size := int(format.get("max_deck_size", 0))
	var max_copies := int(format.get("max_copies", 0))
	if min_size < 0:
		errors.append(_error(
				"invalid_min_size", "Minimum deck size cannot be negative"))
	if max_size < 0:
		errors.append(_error(
				"invalid_max_size", "Maximum deck size cannot be negative"))
	if min_size > 0 and max_size > 0 and min_size > max_size:
		errors.append(_error(
				"invalid_size_range",
				"Minimum deck size cannot exceed maximum deck size"))
	if max_copies < 1:
		errors.append(_error(
				"invalid_max_copies",
				"Maximum copies must be at least 1"))
	for card_name in effective_banned(format):
		if not definitions.has(card_name):
			errors.append(_error(
					"unknown_card",
					"Unknown card: " + card_name,
					card_name))
	return errors


static func validate_deck(
		deck: Dictionary,
		format: Dictionary,
		definitions = null) -> Array:
	if definitions == null:
		definitions = cfc.card_definitions
	var errors := []
	if format.empty():
		errors.append(_error("no_format", "Select a format"))
		return errors
	if not deck.has("cards") or typeof(deck.cards) != TYPE_DICTIONARY:
		errors.append(_error("invalid_deck", "Deck has no card list"))
		return errors
	var banned := effective_banned(format)
	var max_copies := int(format.get("max_copies", DEFAULT_MAX_COPIES))
	var total := 0
	for card_name in deck.cards:
		var quantity := int(deck.cards[card_name])
		if quantity <= 0:
			continue
		total += quantity
		if not definitions.has(card_name):
			errors.append(_error(
					"unknown_card",
					"Unknown card: " + card_name,
					card_name))
		elif card_name in banned:
			errors.append(_error(
					"banned_card",
					"Banned card: " + card_name,
					card_name))
		if max_copies > 0 and quantity > max_copies:
			errors.append(_error(
					"too_many_copies",
					card_name + " exceeds the " + str(max_copies)
							+ " copy limit",
					card_name))
	var min_size := int(format.get("min_deck_size", 0))
	var max_size := int(format.get("max_deck_size", 0))
	if min_size > 0 and total < min_size:
		errors.append(_error(
				"too_few_cards",
				"Deck has " + str(total) + " cards; minimum is "
						+ str(min_size)))
	if max_size > 0 and total > max_size:
		errors.append(_error(
				"too_many_cards",
				"Deck has " + str(total) + " cards; maximum is "
						+ str(max_size)))
	return errors


static func deck_total(deck: Dictionary) -> int:
	var total := 0
	if not deck.has("cards") or typeof(deck.cards) != TYPE_DICTIONARY:
		return total
	for card_name in deck.cards:
		total += max(0, int(deck.cards[card_name]))
	return total


static func is_valid_id(format_id: String) -> bool:
	var regex := RegEx.new()
	if regex.compile("^[a-z0-9][a-z0-9_-]*$") != OK:
		return false
	return regex.search(format_id) != null


static func _load_directory(path: String, formats: Dictionary) -> void:
	for file_name in CFUtils.list_files_in_directory(path):
		if not file_name.ends_with(".json"):
			continue
		var format := load_format(path + file_name)
		if format.empty() or str(format.id).empty():
			continue
		formats[format.id] = format


static func _string_array(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.empty() and not text in result:
			result.append(text)
	return result


# Formats are stored on disk with permanent card ids but used in memory with
# names. These translate at the boundary. Unknown refs are kept as-is so that
# validation can still report them.
static func _resolve_refs_to_names(refs: Array) -> Array:
	var out := []
	for ref in refs:
		var card_name = cfc.resolve_card_name(str(ref))
		var value := str(ref) if str(card_name) == "" else str(card_name)
		if not value in out:
			out.append(value)
	return out


static func _refs_to_ids(refs: Array) -> Array:
	var out := []
	for ref in refs:
		var card_name = cfc.resolve_card_name(str(ref))
		var card_id = cfc.card_id_for_name(str(card_name))
		var value := str(ref) if str(card_id) == "" else str(card_id)
		if not value in out:
			out.append(value)
	return out


static func _error(code: String, message: String, card_name := "") -> Dictionary:
	return {
		"code": code,
		"message": message,
		"card": card_name,
	}
