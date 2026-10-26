# TagEditor.gd
# In-game tag authoring tool for PlueyPoker.
#
# Lists every tag that appears on any card (across both the "Tags" and
# "SpecificTags" fields). Selecting a tag shows which cards have it as a normal
# tag and which have it as a specific tag, and lets you add/remove cards from
# each list. Every change is written straight back to the card data JSON and
# the running game is kept in sync, so there is no separate save step.
#
# Cards with a "TagEqualities" or "TagImplications" law involving the selected
# tag are shown with the matching law(s) in brackets. Cards that have such a
# law but do not actually carry the tag are listed in a read-only section below
# the two membership lists.
#
# The selected tag can also be marked as the opposite of any other tag. These
# pairs are stored separately in tag_opposites.json so they apply globally.
#
# Only intended to be used while running from the Godot editor (res:// is
# read-only in exports).
extends Control

const TagRelations = preload("res://src/custom/cards/TagRelations.gd")

# Kept as vars (rather than consts) so tests can point them at scratch files.
var DATA_FILE := "res://src/custom/cards/sets/PlueyPokerGen3.json"
var OPPOSITES_FILE := "res://src/custom/cards/tag_opposites.json"

# Canonical property order used when saving, so the JSON stays stable/readable
const FIELD_ORDER := [
	"Type", "Prefix", "Cost", "LV", "AT", "HP", "Score", "GroupSize",
	"Gender", "Darkness", "Color1", "Color2", "ActionType", "DefenseType",
	"WeaknessType", "Weakness", "Group", "Tags", "SpecificTags",
	"TagEqualities", "TagImplications", "Abilities", "_keep_aspect",
]

var data := {}
var all_tags := []
var card_names := []
var opposite_pairs := []
var current_tag := ""

var tag_title : Label
var tag_search : LineEdit
var new_tag_edit : LineEdit
var tag_list : ItemList
var normal_list : ItemList
var specific_list : ItemList
var related_title : Label
var related_list : ItemList
var opposite_title : Label
var opposite_list : ItemList
var opposite_picker : OptionButton
var normal_picker : OptionButton
var specific_picker : OptionButton
var title_label : Label
var status_label : Label


func _ready() -> void:
	_build_ui()
	_load_data()
	_fill_pickers()
	_refresh_tag_list("")


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := PanelContainer.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(root)

	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hb)

	# --- Left: tag list ---
	var left := VBoxContainer.new()
	left.rect_min_size = Vector2(280, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(left)

	tag_title = Label.new()
	tag_title.text = "Tags"
	left.add_child(tag_title)

	tag_search = LineEdit.new()
	tag_search.placeholder_text = "Search tags..."
	tag_search.connect("text_changed", self, "_on_tag_search_changed")
	left.add_child(tag_search)

	tag_list = ItemList.new()
	tag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tag_list.connect("item_selected", self, "_on_tag_selected")
	left.add_child(tag_list)

	# Create a tag that does not exist on any card yet, so it can then be
	# added to cards below.
	var new_tag_row := HBoxContainer.new()
	left.add_child(new_tag_row)
	new_tag_edit = LineEdit.new()
	new_tag_edit.placeholder_text = "New tag name..."
	new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_tag_edit.connect("text_entered", self, "_on_create_tag_pressed")
	new_tag_row.add_child(new_tag_edit)
	var create_tag_btn := Button.new()
	create_tag_btn.text = "Create tag"
	create_tag_btn.connect("pressed", self, "_on_create_tag_pressed")
	new_tag_row.add_child(create_tag_btn)

	var vsplit := VSeparator.new()
	hb.add_child(vsplit)

	# --- Right: membership editing ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(right)

	title_label = Label.new()
	title_label.text = "Select a tag"
	right.add_child(title_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)

	# Normal tags column
	var col_normal := VBoxContainer.new()
	col_normal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_normal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(col_normal)
	var n_lbl := Label.new()
	n_lbl.text = "Cards with tag"
	col_normal.add_child(n_lbl)
	normal_list = ItemList.new()
	normal_list.select_mode = ItemList.SELECT_MULTI
	normal_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_normal.add_child(normal_list)
	var n_row := HBoxContainer.new()
	col_normal.add_child(n_row)
	normal_picker = OptionButton.new()
	normal_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n_row.add_child(normal_picker)
	var n_add := Button.new()
	n_add.text = "Add"
	n_add.connect("pressed", self, "_on_add_normal_pressed")
	n_row.add_child(n_add)
	var n_rem := Button.new()
	n_rem.text = "Remove"
	n_rem.connect("pressed", self, "_on_remove_normal_pressed")
	n_row.add_child(n_rem)
	var n_move := Button.new()
	n_move.text = "To specific"
	n_move.hint_tooltip = "Move the selected cards' tag to specific tags"
	n_move.connect("pressed", self, "_on_move_normal_to_specific_pressed")
	n_row.add_child(n_move)

	var vsplit2 := VSeparator.new()
	body.add_child(vsplit2)

	# Specific tags column
	var col_specific := VBoxContainer.new()
	col_specific.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_specific.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(col_specific)
	var s_lbl := Label.new()
	s_lbl.text = "Cards with specific tag"
	col_specific.add_child(s_lbl)
	specific_list = ItemList.new()
	specific_list.select_mode = ItemList.SELECT_MULTI
	specific_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_specific.add_child(specific_list)
	var s_row := HBoxContainer.new()
	col_specific.add_child(s_row)
	specific_picker = OptionButton.new()
	specific_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_row.add_child(specific_picker)
	var s_add := Button.new()
	s_add.text = "Add"
	s_add.connect("pressed", self, "_on_add_specific_pressed")
	s_row.add_child(s_add)
	var s_rem := Button.new()
	s_rem.text = "Remove"
	s_rem.connect("pressed", self, "_on_remove_specific_pressed")
	s_row.add_child(s_rem)
	var s_move := Button.new()
	s_move.text = "To normal"
	s_move.hint_tooltip = "Move the selected cards' tag to normal tags"
	s_move.connect("pressed", self, "_on_move_specific_to_normal_pressed")
	s_row.add_child(s_move)

	related_title = Label.new()
	related_title.text = "Other cards with laws involving this tag"
	right.add_child(related_title)

	related_list = ItemList.new()
	related_list.rect_min_size = Vector2(0, 120)
	related_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(related_list)

	opposite_title = Label.new()
	opposite_title.text = "Opposite tags"
	right.add_child(opposite_title)

	opposite_list = ItemList.new()
	opposite_list.rect_min_size = Vector2(0, 100)
	opposite_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(opposite_list)

	var opposite_row := HBoxContainer.new()
	right.add_child(opposite_row)
	opposite_picker = OptionButton.new()
	opposite_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opposite_row.add_child(opposite_picker)
	var opposite_add := Button.new()
	opposite_add.text = "Add opposite"
	opposite_add.connect("pressed", self, "_on_add_opposite_pressed")
	opposite_row.add_child(opposite_add)
	var opposite_remove := Button.new()
	opposite_remove.text = "Remove"
	opposite_remove.connect("pressed", self, "_on_remove_opposite_pressed")
	opposite_row.add_child(opposite_remove)

	# --- Bottom bar ---
	var bottom := HBoxContainer.new()
	right.add_child(bottom)
	var reload_btn := Button.new()
	reload_btn.text = "Reload from disk"
	reload_btn.connect("pressed", self, "_on_reload_pressed")
	bottom.add_child(reload_btn)
	var back_btn := Button.new()
	back_btn.text = "Back to menu"
	back_btn.connect("pressed", self, "_on_back_pressed")
	bottom.add_child(back_btn)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.align = Label.ALIGN_RIGHT
	bottom.add_child(status_label)


# ---------------------------------------------------------------------------
# Data loading / saving
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var f := File.new()
	if not f.file_exists(DATA_FILE):
		_set_status("Data file not found: " + DATA_FILE)
		return
	if f.open(DATA_FILE, File.READ) != OK:
		_set_status("Could not open " + DATA_FILE)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = parse_json(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Invalid JSON in " + DATA_FILE)
		return
	data = parsed
	card_names = data.keys()
	card_names.sort()
	_load_opposites()


func _write_data() -> bool:
	var f := File.new()
	if f.open(DATA_FILE, File.WRITE) != OK:
		_set_status("Failed to write " + DATA_FILE)
		return false
	f.store_string(_serialize(data))
	f.close()
	# Keep the running game in sync so the deckbuilder/game show the changes
	var cfc = get_node_or_null("/root/cfc")
	if cfc:
		cfc.card_definitions = data
	return true


func _load_opposites() -> void:
	opposite_pairs = []
	var f := File.new()
	if not f.file_exists(OPPOSITES_FILE):
		return
	if f.open(OPPOSITES_FILE, File.READ) != OK:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = parse_json(text)
	var entries = parsed
	if typeof(parsed) == TYPE_DICTIONARY:
		entries = parsed.get("TagOpposites", [])
	if typeof(entries) == TYPE_ARRAY:
		opposite_pairs = TagRelations.parse_opposites(entries)


func _write_opposites() -> bool:
	var f := File.new()
	if f.open(OPPOSITES_FILE, File.WRITE) != OK:
		_set_status("Failed to write " + OPPOSITES_FILE)
		return false
	f.store_string(_serialize_opposites())
	f.close()
	return true


func _serialize_opposites() -> String:
	var seen := {}
	for pair in opposite_pairs:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		var a := TagRelations.normalize_tag(pair[0])
		var b := TagRelations.normalize_tag(pair[1])
		if a == "" or b == "" or a == b:
			continue
		if a > b:
			var swap := a
			a = b
			b = swap
		seen[a + "\n" + b] = [a, b]
	var keys := seen.keys()
	keys.sort()
	var lines := ["{", "\t\"TagOpposites\": ["]
	for i in range(keys.size()):
		var pair = seen[keys[i]]
		var comma := "," if i < keys.size() - 1 else ""
		lines.append("\t\t[" + _esc(pair[0]) + ", " + _esc(pair[1]) + "]" + comma)
	lines.append("\t]")
	lines.append("}")
	return "\n".join(PoolStringArray(lines)) + "\n"


func _serialize(source: Dictionary) -> String:
	var lines := ["{"]
	var keys := source.keys()
	keys.sort()
	for i in range(keys.size()):
		var key = keys[i]
		lines.append("\t" + _esc(key) + ": {")
		var card = source[key]
		var props := []
		for f in FIELD_ORDER:
			if card.has(f):
				props.append(f)
		for f in card.keys():
			if not f in FIELD_ORDER:
				props.append(f)
		for j in range(props.size()):
			var p = props[j]
			var comma := "," if j < props.size() - 1 else ""
			lines.append("\t\t" + _esc(p) + ": " + _json_value(card[p]) + comma)
		lines.append("\t}" + ("," if i < keys.size() - 1 else ""))
	lines.append("}")
	return "\n".join(PoolStringArray(lines)) + "\n"


func _json_value(v) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_REAL:
			return str(v)
		TYPE_STRING:
			return _esc(v)
		TYPE_ARRAY:
			var parts := []
			for it in v:
				parts.append(_json_value(it))
			return "[" + ", ".join(PoolStringArray(parts)) + "]"
	return "null"


func _esc(s: String) -> String:
	var r := s.replace("\\", "\\\\")
	r = r.replace("\"", "\\\"")
	r = r.replace("\n", "\\n")
	r = r.replace("\r", "")
	r = r.replace("\t", "\\t")
	return "\"" + r + "\""


# ---------------------------------------------------------------------------
# Tag list
# ---------------------------------------------------------------------------

func _collect_tags() -> Array:
	var seen := {}
	for cname in data:
		var card = data[cname]
		for t in _read_array(card, "SpecificTags"):
			seen[t] = true
		for t in _read_array(card, "Tags"):
			seen[t] = true
	var out = seen.keys()
	out.sort()
	return out


func _refresh_tag_list(filter: String) -> void:
	all_tags = _collect_tags()
	# Keep showing the tag currently being edited even if it is not on any card
	# (newly created, or its last card membership was just removed), so editing
	# is not interrupted.
	var display_tags := all_tags.duplicate()
	if current_tag != "" and not display_tags.has(current_tag):
		display_tags.append(current_tag)
		display_tags.sort()
	tag_list.clear()
	var normalized_filter := TagRelations.normalize_tag(filter).to_lower()
	for t in display_tags:
		if normalized_filter == "" or TagRelations.normalize_tag(t).to_lower().find(normalized_filter) != -1:
			tag_list.add_item(t)
	tag_title.text = "Tags (%d)" % all_tags.size()
	if current_tag != "":
		for i in range(tag_list.get_item_count()):
			if tag_list.get_item_text(i) == current_tag:
				tag_list.select(i)
				break


func _fill_pickers() -> void:
	normal_picker.clear()
	specific_picker.clear()
	for cname in card_names:
		normal_picker.add_item(cname)
		specific_picker.add_item(cname)


func _on_tag_search_changed(new_text: String) -> void:
	_refresh_tag_list(new_text)


# Creates/selects a tag name that may not exist on any card yet.
func _on_create_tag_pressed(_text := "") -> void:
	var tag_name := new_tag_edit.text.strip_edges()
	if tag_name == "":
		_set_status("Type a tag name first")
		return
	current_tag = tag_name
	new_tag_edit.text = ""
	_refresh_tag_list(tag_search.text)
	_populate_lists()
	_set_status("Editing tag '%s' - add it to cards below" % tag_name)


func _on_tag_selected(index: int) -> void:
	current_tag = tag_list.get_item_text(index)
	_populate_lists()


func _populate_lists() -> void:
	normal_list.clear()
	specific_list.clear()
	related_list.clear()
	related_title.text = "Other cards with laws involving this tag"
	if current_tag == "":
		title_label.text = "Select a tag"
		_populate_opposites()
		return
	title_label.text = "Tag: " + current_tag
	_populate_opposites()
	var related: Array = []
	for cname in card_names:
		var card = data[cname]
		var laws := _laws_involving_tag(card, current_tag)
		var has_normal := current_tag in _read_array(card, "Tags")
		var has_specific := current_tag in _read_array(card, "SpecificTags")
		var label := _card_label(cname, laws)
		if has_normal:
			_add_card_item(normal_list, cname, label)
		if has_specific:
			_add_card_item(specific_list, cname, label)
		if not has_normal and not has_specific and not laws.empty():
			related.append([cname, laws])
	for entry in related:
		var laws_text := ", ".join(PoolStringArray(entry[1]))
		related_list.add_item(entry[0] + " [" + laws_text + "]")
	related_title.text = "Other cards with laws involving '%s' (%d)" % [current_tag, related.size()]


func _populate_opposites() -> void:
	opposite_list.clear()
	opposite_title.text = "Opposite tags"
	if current_tag == "":
		_fill_opposite_picker()
		return
	var normalized := TagRelations.normalize_tag(current_tag)
	var count := 0
	for pair in opposite_pairs:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		var a := TagRelations.normalize_tag(pair[0])
		var b := TagRelations.normalize_tag(pair[1])
		var other := ""
		if a == normalized:
			other = b
		elif b == normalized:
			other = a
		if other == "":
			continue
		opposite_list.add_item(other)
		opposite_list.set_item_metadata(opposite_list.get_item_count() - 1, other)
		count += 1
	opposite_title.text = "Opposite tags for '%s' (%d)" % [current_tag, count]
	_fill_opposite_picker()


func _fill_opposite_picker() -> void:
	var previous := _picker_value(opposite_picker)
	opposite_picker.clear()
	var normalized := TagRelations.normalize_tag(current_tag)
	var known := _known_tags()
	for tag in known:
		if TagRelations.normalize_tag(tag) == normalized:
			continue
		opposite_picker.add_item(tag)
		if tag == previous:
			opposite_picker.select(opposite_picker.get_item_count() - 1)


func _known_tags() -> Array:
	var known := []
	var seen := {}
	for tag in all_tags:
		_append_known_tag(known, seen, tag)
	for pair in opposite_pairs:
		if typeof(pair) != TYPE_ARRAY:
			continue
		for tag in pair:
			_append_known_tag(known, seen, tag)
	_append_known_tag(known, seen, current_tag)
	known.sort()
	return known


func _append_known_tag(known: Array, seen: Dictionary, tag) -> void:
	var clean := TagRelations.normalize_tag(tag)
	if clean == "" or seen.has(clean):
		return
	seen[clean] = true
	known.append(clean)


func _on_add_opposite_pressed() -> void:
	if current_tag == "":
		_set_status("Select a tag first")
		return
	var other = _picker_value(opposite_picker)
	if other == "":
		_set_status("Select an opposite tag first")
		return
	var a := TagRelations.normalize_tag(current_tag)
	var b := TagRelations.normalize_tag(other)
	if a == "" or b == "" or a == b:
		_set_status("A tag cannot be opposite to itself")
		return
	if _has_opposite_pair(a, b):
		_set_status("'%s' and '%s' are already opposites" % [a, b])
		return
	opposite_pairs.append([a, b])
	if _write_opposites():
		_after_edit()
		_set_status("'%s' is now opposite to '%s'" % [a, b])


func _on_remove_opposite_pressed() -> void:
	if current_tag == "":
		return
	var selection = opposite_list.get_selected_items()
	if selection.empty():
		_set_status("Select an opposite tag to remove")
		return
	var remove := {}
	for index in selection:
		var other = opposite_list.get_item_metadata(index)
		if other != null:
			remove[TagRelations.normalize_tag(other)] = true
	var normalized := TagRelations.normalize_tag(current_tag)
	var kept := []
	for pair in opposite_pairs:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		var a := TagRelations.normalize_tag(pair[0])
		var b := TagRelations.normalize_tag(pair[1])
		var is_current := a == normalized or b == normalized
		var other := b if a == normalized else a
		if is_current and remove.has(other):
			continue
		kept.append(pair)
	if kept.size() == opposite_pairs.size():
		_set_status("No matching opposite pair to remove")
		return
	opposite_pairs = kept
	if _write_opposites():
		_after_edit()
		_set_status("Removed opposite tag from '%s'" % current_tag)


func _has_opposite_pair(a: String, b: String) -> bool:
	for pair in opposite_pairs:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		var left := TagRelations.normalize_tag(pair[0])
		var right := TagRelations.normalize_tag(pair[1])
		if (left == a and right == b) or (left == b and right == a):
			return true
	return false


func _card_label(cname: String, laws: Array) -> String:
	if laws.empty():
		return cname
	return cname + " [" + ", ".join(PoolStringArray(laws)) + "]"


func _add_card_item(list: ItemList, cname: String, label: String) -> void:
	list.add_item(label)
	var index := list.get_item_count() - 1
	list.set_item_metadata(index, cname)


# Returns the laws on this card which mention the given tag, formatted for
# display. Both direct sides of a law count as "involving" the tag.
func _laws_involving_tag(card, tag: String) -> Array:
	var out: Array = []
	var normalized_tag := TagRelations.normalize_tag(tag)
	for field in ["TagEqualities", "TagImplications"]:
		for entry in _read_array(card, field):
			var parsed := _law_sides(entry, field)
			if parsed.size() != 2:
				continue
			if TagRelations.normalize_tag(parsed[0]) != normalized_tag\
					and TagRelations.normalize_tag(parsed[1]) != normalized_tag:
				continue
			var law = parsed[0] + (" = " if field == "TagEqualities" else " -> ") + parsed[1]
			if not law in out:
				out.append(law)
	return out


func _law_sides(entry, field: String) -> Array:
	var separator := "=" if field == "TagEqualities" else "->"
	if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
		var a := str(entry[0]).strip_edges()
		var b := str(entry[1]).strip_edges()
		if a != "" and b != "":
			return [a, b]
		return []
	var text := str(entry).strip_edges()
	var index := text.find(separator)
	if index <= 0:
		return []
	var left := text.substr(0, index).strip_edges()
	var right := text.substr(index + separator.length()).strip_edges()
	if left == "" or right == "":
		return []
	return [left, right]


# ---------------------------------------------------------------------------
# Array helpers
# ---------------------------------------------------------------------------

func _read_array(card, field: String) -> Array:
	if typeof(card) == TYPE_DICTIONARY and card.has(field) and typeof(card[field]) == TYPE_ARRAY:
		return card[field]
	return []


func _mutable_array(card, field: String) -> Array:
	if not card.has(field) or typeof(card[field]) != TYPE_ARRAY:
		card[field] = []
	return card[field]


# ---------------------------------------------------------------------------
# Membership edits
# ---------------------------------------------------------------------------

func _on_add_normal_pressed() -> void:
	_add_membership("Tags", normal_picker, "tag")
	# Refresh the tag list so a brand new tag shows up
	_after_edit()


func _on_add_specific_pressed() -> void:
	_add_membership("SpecificTags", specific_picker, "specific tag")
	_after_edit()


func _add_membership(field: String, picker: OptionButton, kind: String) -> void:
	if current_tag == "":
		_set_status("Select a tag first")
		return
	var cname = _picker_value(picker)
	if cname == "":
		return
	var arr = _mutable_array(data[cname], field)
	if current_tag in arr:
		_set_status("'%s' is already a %s on '%s'" % [current_tag, kind, cname])
		return
	arr.append(current_tag)
	if _write_data():
		_set_status("Added '%s' as a %s on '%s'" % [current_tag, kind, cname])


func _on_remove_normal_pressed() -> void:
	_remove_membership("Tags", normal_list)
	_after_edit()


func _on_remove_specific_pressed() -> void:
	_remove_membership("SpecificTags", specific_list)
	_after_edit()


func _remove_membership(field: String, list: ItemList) -> void:
	if current_tag == "":
		return
	var selection = list.get_selected_items()
	if selection.empty():
		_set_status("Select card(s) to remove")
		return
	var names := []
	for i in selection:
		names.append(_item_card_name(list, i))
	for cname in names:
		var arr = _mutable_array(data[cname], field)
		arr.erase(current_tag)
	if _write_data():
		_set_status("Removed '%s' from %d card(s)" % [current_tag, names.size()])


func _on_move_normal_to_specific_pressed() -> void:
	_move_membership("Tags", "SpecificTags", normal_list)
	_after_edit()


func _on_move_specific_to_normal_pressed() -> void:
	_move_membership("SpecificTags", "Tags", specific_list)
	_after_edit()


# Moves the current tag for the selected cards from one field to the other,
# i.e. converts it between a normal tag and a specific tag.
func _move_membership(from_field: String, to_field: String, list: ItemList) -> void:
	if current_tag == "":
		return
	var selection = list.get_selected_items()
	if selection.empty():
		_set_status("Select card(s) to move")
		return
	var names := []
	for i in selection:
		names.append(_item_card_name(list, i))
	for cname in names:
		var from_arr = _mutable_array(data[cname], from_field)
		from_arr.erase(current_tag)
		var to_arr = _mutable_array(data[cname], to_field)
		if not current_tag in to_arr:
			to_arr.append(current_tag)
	if _write_data():
		var dest := "specific" if to_field == "SpecificTags" else "normal"
		_set_status("Moved '%s' to %s tags on %d card(s)" % [current_tag, dest, names.size()])


func _after_edit() -> void:
	# The tag may have appeared or disappeared, and the card lists may have
	# changed, so refresh both.
	_refresh_tag_list(tag_search.text)
	_populate_lists()


func _item_card_name(list: ItemList, index: int) -> String:
	var metadata = list.get_item_metadata(index)
	if metadata != null:
		return str(metadata)
	return list.get_item_text(index)


func _picker_value(picker: OptionButton) -> String:
	var i = picker.get_selected()
	if i < 0:
		return ""
	return picker.get_item_text(i)


func _on_reload_pressed() -> void:
	_load_data()
	_fill_pickers()
	_refresh_tag_list(tag_search.text)
	_populate_lists()


func _on_back_pressed() -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene("res://src/custom/MainMenu.tscn")


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
