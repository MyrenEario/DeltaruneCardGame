extends Reference

const OPPOSITES_FILE := "res://src/custom/cards/tag_opposites.json"
const MATCH_IGNORED_CHARS := "𝅘𝅥𝅮"

var tags := []
var _index := {}
var _opposites := {}
var _words := 0
var _reach := []
var _related := []


static func parse_equalities(entries) -> Array:
	return _parse_pairs(entries, "=")


static func parse_opposites(entries) -> Array:
	return _parse_pairs(entries, "=")


static func load_opposite_pairs(path: String = "") -> Array:
	if path == "":
		path = OPPOSITES_FILE
	var file := File.new()
	if not file.file_exists(path) or file.open(path, File.READ) != OK:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = parse_json(text)
	var entries = parsed
	if typeof(parsed) == TYPE_DICTIONARY:
		entries = parsed.get("TagOpposites", [])
	if typeof(entries) != TYPE_ARRAY:
		return []
	return parse_opposites(entries)


static func parse_implications(entries) -> Array:
	var pairs := []
	if typeof(entries) != TYPE_ARRAY:
		return pairs
	for entry in entries:
		var pair = _parse_implication_one(entry)
		if pair.size() == 2:
			pairs.append(pair)
	return pairs


static func _parse_pairs(entries, separator: String) -> Array:
	var pairs := []
	if typeof(entries) != TYPE_ARRAY:
		return pairs
	for entry in entries:
		var pair = _parse_pair_one(entry, separator)
		if pair.size() == 2:
			pairs.append(pair)
	return pairs


static func _parse_pair_one(entry, separator: String) -> Array:
	if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
		return [_clean(entry[0]), _clean(entry[1])]
	var text := str(entry)
	var idx := text.find(separator)
	if idx <= 0:
		return []
	var left := _clean(text.substr(0, idx))
	var right := _clean(text.substr(idx + separator.length()))
	if left == "" or right == "":
		return []
	return [left, right]


static func _parse_implication_one(entry) -> Array:
	if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
		return [_clean(entry[0]), _clean(entry[1])]
	var text := str(entry)
	var idx := text.find("->")
	if idx <= 0:
		return []
	var left := _clean(text.substr(0, idx))
	var right := _clean(text.substr(idx + 2))
	if left == "" or right == "":
		return []
	return [left, right]


static func normalize_tag(value) -> String:
	var text := str(value)
	for ch in MATCH_IGNORED_CHARS:
		text = text.replace(ch, "")
	return text.strip_edges()


static func _clean(value) -> String:
	return normalize_tag(value)


func setup(equality_pairs: Array, implication_pairs: Array, extra_tags: Array = [],
		opposite_pairs: Array = []) -> void:
	var seen := {}
	for pair in equality_pairs:
		if pair.size() >= 2:
			seen[_clean(pair[0])] = true
			seen[_clean(pair[1])] = true
	for pair in implication_pairs:
		if pair.size() >= 2:
			seen[_clean(pair[0])] = true
			seen[_clean(pair[1])] = true
	for pair in opposite_pairs:
		if pair.size() >= 2:
			seen[_clean(pair[0])] = true
			seen[_clean(pair[1])] = true
	for tag in extra_tags:
		seen[_clean(tag)] = true
	seen.erase("")
	tags = seen.keys()
	tags.sort()
	_index = {}
	for i in range(tags.size()):
		_index[tags[i]] = i
	_opposites = {}
	for pair in opposite_pairs:
		if pair.size() < 2:
			continue
		var clean_a := _clean(pair[0])
		var clean_b := _clean(pair[1])
		if clean_a == "" or clean_b == "" or clean_a == clean_b:
			continue
		if not _opposites.has(clean_a):
			_opposites[clean_a] = {}
		_opposites[clean_a][clean_b] = true
		if not _opposites.has(clean_b):
			_opposites[clean_b] = {}
		_opposites[clean_b][clean_a] = true
	_words = (tags.size() + 63) >> 6
	_reach = []
	for i in range(tags.size()):
		var row = _empty_row(_words)
		_set_bit(row, i)
		_reach.append(row)
	for pair in equality_pairs:
		if pair.size() >= 2:
			_add_edge(pair[0], pair[1])
			_add_edge(pair[1], pair[0])
	for pair in implication_pairs:
		if pair.size() >= 2:
			_add_edge(pair[0], pair[1])
	for k in range(tags.size()):
		var row_k = _reach[k]
		for i in range(tags.size()):
			var row_i = _reach[i]
			if _get_bit(row_i, k):
				_or_rows(row_i, row_k)
	var reverse := []
	for i in range(tags.size()):
		reverse.append(_empty_row(_words))
	for u in range(tags.size()):
		var row_u = _reach[u]
		for v in range(tags.size()):
			if _get_bit(row_u, v):
				_set_bit(reverse[v], u)
	_related = []
	for i in range(tags.size()):
		var row = _reach[i].duplicate()
		_set_bit(row, i)
		_or_rows(row, reverse[i])
		_related.append(row)


func has_tag(tag: String) -> bool:
	return _index.has(_clean(tag))


func implies(a: String, b: String) -> bool:
	var clean_a := _clean(a)
	var clean_b := _clean(b)
	if clean_a == clean_b:
		return true
	var ia = _index.get(clean_a, -1)
	var ib = _index.get(clean_b, -1)
	if ia < 0 or ib < 0:
		return false
	return _get_bit(_reach[ia], ib)


func related(a: String, b: String) -> bool:
	var clean_a := _clean(a)
	var clean_b := _clean(b)
	if clean_a == clean_b:
		return true
	var ia = _index.get(clean_a, -1)
	var ib = _index.get(clean_b, -1)
	if ia < 0 or ib < 0:
		return false
	return _get_bit(_related[ia], ib)


func are_opposites(a: String, b: String) -> bool:
	var clean_a := _clean(a)
	var clean_b := _clean(b)
	if clean_a == "" or clean_b == "":
		return false
	var row = _opposites.get(clean_a, null)
	return row != null and row.has(clean_b)


func count_opposites(my_tags: Array, other_tags: Array) -> int:
	var matching := 0
	var seen := {}
	for t in my_tags:
		var clean_t := _clean(t)
		if clean_t == "" or seen.has(clean_t):
			continue
		seen[clean_t] = true
		for o in other_tags:
			if are_opposites(clean_t, str(o)):
				matching += 1
				break
	return matching


func count_matches(my_tags: Array, ally_tags: Array) -> int:
	var matching := 0
	var seen := {}
	for t in my_tags:
		var clean_t := _clean(t)
		if seen.has(clean_t):
			continue
		seen[clean_t] = true
		for a in ally_tags:
			if related(clean_t, str(a)):
				matching += 1
				break
	return matching


func _add_edge(a: String, b: String) -> void:
	var ia = _index.get(_clean(a), -1)
	var ib = _index.get(_clean(b), -1)
	if ia < 0 or ib < 0:
		return
	_set_bit(_reach[ia], ib)


static func _empty_row(words: int) -> Array:
	var row := []
	for i in range(words):
		row.append(0)
	return row


static func _set_bit(row: Array, index: int) -> void:
	var word := index >> 6
	if word < 0 or word >= row.size():
		return
	row[word] = row[word] | (1 << (index & 63))


static func _get_bit(row: Array, index: int) -> bool:
	var word := index >> 6
	if word < 0 or word >= row.size():
		return false
	return (row[word] & (1 << (index & 63))) != 0


static func _or_rows(target: Array, source: Array) -> void:
	for i in range(target.size()):
		target[i] = target[i] | source[i]
