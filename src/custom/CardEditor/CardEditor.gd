# CardEditor.gd
# In-game card authoring tool for PlueyPoker.
#
# Reads and writes the card data JSON directly in res:// so new/changed cards
# show up in the game without any external export step. Only intended to be
# used while running from the Godot editor (res:// is read-only in exports).
extends Control

const DATA_FILE := "res://src/custom/cards/sets/PlueyPokerGen3.json"
const CardIds = preload("res://src/custom/cards/CardIds.gd")
const IMAGES_DIR := "res://assets/cardimages/"
# Optional companion file listing every folder, so a folder can exist (and be
# renamed/deleted) even before any card is placed in it. Cards themselves carry
# their folder in a "Folder" property.
const FOLDERS_FILE := "res://src/custom/cards/sets/PlueyFolders.json"
# The folder a card belongs to when it has no explicit "Folder" value.
const DEFAULT_FOLDER := "Uncategorized"
# Reused card-preview widget (same one the Deck Builder / HUD use) so the
# editor shows a real, fully-rendered card instance instead of just its art.
const CARD_PREVIEW_SCENE = preload(
		"res://src/core/CardViewer/CVGridCardObject.tscn")
const PlueyCardFrontScript = preload(
		"res://src/custom/cards/PlueyCardFront.gd")
# How big to draw the preview card relative to its canonical size.
const PREVIEW_SCALE := 1.0
# Keystroke debounce before rebuilding the preview card.
const PREVIEW_DEBOUNCE := 0.15

# Canonical property order used when saving, so the JSON stays stable/readable
const FIELD_ORDER := [
	"Version", "Type", "Folder", "Prefix", "Cost", "LV", "AT", "HP", "Score",
	"GroupSize", "Gender", "Darkness", "Color1", "Color2", "ActionType",
	"DefenseType", "WeaknessType", "Weakness", "Group", "Tags", "SpecificTags",
	"TagEqualities", "TagImplications", "Abilities", "_keep_aspect",
]
const NUMERIC_FIELDS := ["Version", "Cost", "LV", "AT", "HP", "Score", "GroupSize"]

# Version comparison modes for the list filter (index 0 disables the filter)
const VERSION_FILTER_MODES := [
	"Any", "Newer than", "Newer or equal", "Older than", "Older or equal", "Exactly",
]
const ENUM_FIELDS := {
	"Type": ["Char", "Char-Role", "Item", "Scene"],
	"Gender": ["Male", "Female", "Non-Binary", "Both", "Unknown", "None"],
	"Darkness": ["☼Light", "☾Dark", "☼☾Both", "?Unknown", "None"],
	"Color1": ["Titan", "Friend", "Red", "Green", "Blue", "Purple", "Gold", "Goner", "None"],
	"Color2": ["Titan", "Friend", "Red", "Green", "Blue", "Purple", "Gold", "Goner", "None"],
	"ActionType": ["Fight", "Mercy", "Control", "None"],
	"DefenseType": ["Fight", "Mercy", "Control", "None"],
	"WeaknessType": ["None", "Fight", "Control", "Mercy"],
}
# These enum fields default to "None" when a card has no value for them.
const NONE_DEFAULT_FIELDS := [
	"Gender", "Darkness", "Color1", "Color2", "ActionType", "DefenseType",
	"WeaknessType",
]

var data := {}
var card_keys := []
var current_key := ""

var list : ItemList
var search_edit : LineEdit
var version_mode_opt : OptionButton
var version_value_spin : SpinBox
var name_edit : LineEdit
var abil_edit : TextEdit
var preview_holder : VBoxContainer
var preview_timer : Timer
var image_label : Label
var status_label : Label
var file_dialog : FileDialog
var folder_filter_opt : OptionButton
var new_folder_edit : LineEdit
var move_to_opt : OptionButton

# The live, fully-rendered card preview (a CVGridCardObject wrapping a card)
var _preview_card_obj = null

# Folders that exist even with no cards in them (persisted to FOLDERS_FILE)
var extra_folders := []

# field name -> control
var field_controls := {}
# Only true while we are writing values into the form programmatically
var _loading := false


func _ready() -> void:
	_build_ui()
	_load_data()
	_load_folders()
	_refresh_folders()
	_refresh_list("")


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

	# --- Left: card list ---
	var left := VBoxContainer.new()
	left.rect_min_size = Vector2(280, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(left)

	var list_title := Label.new()
	list_title.text = "Cards"
	left.add_child(list_title)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search..."
	search_edit.connect("text_changed", self, "_on_search_changed")
	left.add_child(search_edit)

	# Version filter row
	var version_row := HBoxContainer.new()
	left.add_child(version_row)
	version_mode_opt = OptionButton.new()
	for mode in VERSION_FILTER_MODES:
		version_mode_opt.add_item(mode)
	version_mode_opt.select(0)
	version_mode_opt.connect("item_selected", self, "_on_version_filter_changed")
	version_row.add_child(version_mode_opt)
	version_value_spin = SpinBox.new()
	version_value_spin.min_value = -999999
	version_value_spin.max_value = 999999
	version_value_spin.step = 1
	version_value_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version_value_spin.connect("value_changed", self, "_on_version_value_changed")
	version_row.add_child(version_value_spin)

	# Folder navigation
	var folder_title := Label.new()
	folder_title.text = "Folder"
	left.add_child(folder_title)

	folder_filter_opt = OptionButton.new()
	folder_filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_filter_opt.connect("item_selected", self, "_on_folder_filter_changed")
	left.add_child(folder_filter_opt)

	var folder_new_row := HBoxContainer.new()
	left.add_child(folder_new_row)
	new_folder_edit = LineEdit.new()
	new_folder_edit.placeholder_text = "New folder name..."
	new_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_folder_edit.connect("text_entered", self, "_on_create_folder_pressed")
	folder_new_row.add_child(new_folder_edit)
	var create_folder_btn := Button.new()
	create_folder_btn.text = "Create"
	create_folder_btn.connect("pressed", self, "_on_create_folder_pressed")
	folder_new_row.add_child(create_folder_btn)

	var folder_ops_row := HBoxContainer.new()
	left.add_child(folder_ops_row)
	var rename_folder_btn := Button.new()
	rename_folder_btn.text = "Rename"
	rename_folder_btn.connect("pressed", self, "_on_rename_folder_pressed")
	folder_ops_row.add_child(rename_folder_btn)
	var delete_folder_btn := Button.new()
	delete_folder_btn.text = "Delete"
	delete_folder_btn.connect("pressed", self, "_on_delete_folder_pressed")
	folder_ops_row.add_child(delete_folder_btn)

	list = ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.connect("item_selected", self, "_on_item_selected")
	list.connect("multi_selected", self, "_on_multi_selected")
	left.add_child(list)

	var list_buttons := HBoxContainer.new()
	left.add_child(list_buttons)
	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.connect("pressed", self, "_on_new_pressed")
	list_buttons.add_child(new_btn)
	var dup_btn := Button.new()
	dup_btn.text = "Duplicate"
	dup_btn.connect("pressed", self, "_on_duplicate_pressed")
	list_buttons.add_child(dup_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.connect("pressed", self, "_on_delete_pressed")
	list_buttons.add_child(del_btn)

	# Move the selected card(s) into another folder
	var move_row := HBoxContainer.new()
	left.add_child(move_row)
	var move_lbl := Label.new()
	move_lbl.text = "Move to:"
	move_row.add_child(move_lbl)
	move_to_opt = OptionButton.new()
	move_to_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_row.add_child(move_to_opt)
	var move_btn := Button.new()
	move_btn.text = "Move"
	move_btn.connect("pressed", self, "_on_move_pressed")
	move_row.add_child(move_btn)

	var vsplit := VSeparator.new()
	hb.add_child(vsplit)

	# --- Right: form ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(right)

	# Name row
	var name_row := HBoxContainer.new()
	right.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Name"
	name_lbl.rect_min_size = Vector2(110, 0)
	name_row.add_child(name_lbl)
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)

	# Body: form (scroll) + image column
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(grid)

	for field in FIELD_ORDER:
		if field == "Abilities" or field == "Weakness" or field == "Tags" or field == "SpecificTags" or field == "TagEqualities" or field == "TagImplications":
			continue
		grid.add_child(_make_label(field))
		grid.add_child(_make_control(field))

	# Tag rows (kept in the grid for consistency)
	_add_grid_row(grid, "Weakness", _make_line_edit())
	_add_grid_row(grid, "Tags", _make_line_edit())
	_add_grid_row(grid, "SpecificTags", _make_line_edit())
	# Tag equalities: comma-separated "A = B" pairs, e.g. "Piano = Music"
	_add_grid_row(grid, "TagEqualities", _make_line_edit())
	_add_grid_row(grid, "TagImplications", _make_line_edit())

	# Abilities
	var abil_lbl := Label.new()
	abil_lbl.text = "Abilities"
	form.add_child(abil_lbl)
	abil_edit = TextEdit.new()
	abil_edit.rect_min_size = Vector2(0, 120)
	abil_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(abil_edit)
	field_controls["Abilities"] = abil_edit

	# --- Card preview column ---
	var img_box := VBoxContainer.new()
	img_box.rect_min_size = Vector2(210, 0)
	body.add_child(img_box)
	img_box.add_child(_make_label("Card"))
	preview_holder = VBoxContainer.new()
	preview_holder.rect_min_size = Vector2(200, 260)
	img_box.add_child(preview_holder)
	image_label = Label.new()
	image_label.autowrap = true
	image_label.rect_min_size = Vector2(200, 0)
	img_box.add_child(image_label)
	var import_btn := Button.new()
	import_btn.text = "Import illustration..."
	import_btn.connect("pressed", self, "_on_import_pressed")
	img_box.add_child(import_btn)

	# Debounced live rebuild of the card preview when any field changes.
	preview_timer = Timer.new()
	preview_timer.one_shot = true
	preview_timer.wait_time = PREVIEW_DEBOUNCE
	preview_timer.connect("timeout", self, "_update_preview")
	add_child(preview_timer)
	_connect_form_signals()

	# --- Bottom bar ---
	var bottom := HBoxContainer.new()
	right.add_child(bottom)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.connect("pressed", self, "_on_save_pressed")
	bottom.add_child(save_btn)
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

	# --- File dialog for importing images ---
	file_dialog = FileDialog.new()
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.png ; PNG Images")
	file_dialog.connect("file_selected", self, "_on_image_selected")
	add_child(file_dialog)


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.rect_min_size = Vector2(110, 0)
	return lbl


func _make_line_edit() -> LineEdit:
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return le


func _make_control(field: String) -> Control:
	if field == "Folder":
		# Populated dynamically by _refresh_folders() so it can list every
		# folder in the data (plus any extra/empty folders).
		var fopt := OptionButton.new()
		fopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field_controls[field] = fopt
		return fopt
	if field in ENUM_FIELDS:
		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item in ENUM_FIELDS[field]:
			opt.add_item(item)
		field_controls[field] = opt
		return opt
	elif field in NUMERIC_FIELDS:
		var spin := SpinBox.new()
		if field == "Version":
			spin.min_value = 0
			spin.max_value = 999999
		else:
			spin.min_value = -999
			spin.max_value = 999
		spin.step = 1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field_controls[field] = spin
		return spin
	elif field == "_keep_aspect":
		var cb := CheckBox.new()
		field_controls[field] = cb
		return cb
	else:
		var le := _make_line_edit()
		field_controls[field] = le
		return le


func _add_grid_row(grid: GridContainer, label_text: String, control: Control) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.rect_min_size = Vector2(110, 0)
	grid.add_child(lbl)
	grid.add_child(control)
	field_controls[label_text] = control


# Connects every editable field (plus the Name box) so the card preview updates
# live while the user types.
func _connect_form_signals() -> void:
	if name_edit:
		name_edit.connect("text_changed", self, "_on_form_changed")
	for field in field_controls.keys():
		_connect_control(field_controls[field])


func _connect_control(control) -> void:
	if control is OptionButton:
		control.connect("item_selected", self, "_on_form_changed")
	elif control is SpinBox:
		control.connect("value_changed", self, "_on_form_changed")
	elif control is CheckBox:
		control.connect("toggled", self, "_on_form_changed")
	elif control is TextEdit:
		control.connect("text_changed", self, "_on_form_changed")
	elif control is LineEdit:
		control.connect("text_changed", self, "_on_form_changed")


func _on_form_changed(_a = null, _b = null) -> void:
	if _loading:
		return
	if preview_timer:
		preview_timer.start()


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
	_set_status("Loaded %d cards" % data.size())


func _write_data() -> bool:
	var f := File.new()
	if f.open(DATA_FILE, File.WRITE) != OK:
		_set_status("Failed to write " + DATA_FILE)
		return false
	f.store_string(_serialize(data))
	f.close()
	# Keep the running game in sync so the deckbuilder/game show the changes
	if Engine.has_singleton("CFControl") or get_node_or_null("/root/cfc"):
		var cfc = get_node("/root/cfc")
		if cfc:
			cfc.card_definitions = data
			cfc.rebuild_card_id_index()
	return true


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
# List / selection
# ---------------------------------------------------------------------------

func _refresh_list(filter: String) -> void:
	list.clear()
	card_keys = data.keys()
	card_keys.sort_custom(self, "_sort_card_keys")
	var folder_filter := _selected_filter_folder()
	var shown := 0
	for k in card_keys:
		if folder_filter != "" and _folder_of(k) != folder_filter:
			continue
		if filter != "" and k.to_lower().find(filter.to_lower()) == -1:
			continue
		if not _version_matches(k):
			continue
		list.add_item(k)
		shown += 1
	_set_status("%d cards (%d shown)" % [card_keys.size(), shown])


# Cards are ordered by their base name (the name with the prefix removed).
# Only cards that share a base name are then ordered by their prefix, so all
# variants of one character sit together.
func _sort_card_keys(first: String, second: String) -> bool:
	var base_first := _base_name_of(first)
	var base_second := _base_name_of(second)
	if base_first.to_lower() != base_second.to_lower():
		return base_first.to_lower() < base_second.to_lower()
	if base_first != base_second:
		return base_first < base_second
	var prefix_first := _prefix_of(first)
	var prefix_second := _prefix_of(second)
	if prefix_first.to_lower() != prefix_second.to_lower():
		return prefix_first.to_lower() < prefix_second.to_lower()
	if prefix_first != prefix_second:
		return prefix_first < prefix_second
	return first < second


func _base_name_of(key: String) -> String:
	return _display_name(key, _prefix_of(key))


func _prefix_of(key: String) -> String:
	return str(data.get(key, {}).get("Prefix", ""))


# Returns true if the card's Version satisfies the current version filter.
func _version_matches(key: String) -> bool:
	if version_mode_opt == null:
		return true
	var mode := version_mode_opt.get_selected()
	if mode <= 0:
		return true
	var card = data.get(key, {})
	var version := int(card.get("Version", 0))
	var target := int(version_value_spin.value)
	match mode:
		1: return version > target
		2: return version >= target
		3: return version < target
		4: return version <= target
		5: return version == target
	return true


func _on_search_changed(new_text: String) -> void:
	_refresh_list(new_text)


func _on_version_filter_changed(_index: int) -> void:
	_refresh_list(search_edit.text)


func _on_version_value_changed(_value: float) -> void:
	_refresh_list(search_edit.text)


func _on_item_selected(index: int) -> void:
	var key = list.get_item_text(index)
	_populate(key)


func _on_multi_selected(index: int, selected: bool) -> void:
	if selected:
		_on_item_selected(index)


# ---------------------------------------------------------------------------
# Folders
# ---------------------------------------------------------------------------

# The folder a card belongs to. Cards with no explicit value fall back to
# DEFAULT_FOLDER so they always show up somewhere.
func _folder_of(key: String) -> String:
	var f := str(data.get(key, {}).get("Folder", "")).strip_edges()
	if f == "":
		f = DEFAULT_FOLDER
	return f


# Every folder in use, plus any extra (possibly empty) folders, sorted.
func _all_folders() -> Array:
	var seen := {}
	seen[DEFAULT_FOLDER] = true
	for k in data.keys():
		seen[_folder_of(k)] = true
	for f in extra_folders:
		var fs := str(f).strip_edges()
		if fs != "":
			seen[fs] = true
	var arr := seen.keys()
	arr.sort()
	return arr


func _selected_filter_folder() -> String:
	if folder_filter_opt == null or folder_filter_opt.get_selected() < 0:
		return ""
	return str(folder_filter_opt.get_item_metadata(folder_filter_opt.get_selected()))


func _select_meta(opt: OptionButton, value: String) -> void:
	var idx := 0
	for i in range(opt.get_item_count()):
		if str(opt.get_item_metadata(i)) == value:
			idx = i
			break
	opt.select(idx)


func _select_text(opt: OptionButton, text: String) -> void:
	var idx := 0
	for i in range(opt.get_item_count()):
		if opt.get_item_text(i) == text:
			idx = i
			break
	opt.select(idx)


# Rebuilds every folder dropdown from the current data, preserving selections.
func _refresh_folders() -> void:
	var folders := _all_folders()
	if folder_filter_opt:
		var prev := _selected_filter_folder()
		folder_filter_opt.clear()
		folder_filter_opt.add_item("All folders")
		folder_filter_opt.set_item_metadata(0, "")
		for f in folders:
			folder_filter_opt.add_item(f)
			folder_filter_opt.set_item_metadata(folder_filter_opt.get_item_count() - 1, f)
		_select_meta(folder_filter_opt, prev)
	if move_to_opt:
		var prev_move := ""
		if move_to_opt.get_selected() >= 0:
			prev_move = move_to_opt.get_item_text(move_to_opt.get_selected())
		move_to_opt.clear()
		for f in folders:
			move_to_opt.add_item(f)
		_select_text(move_to_opt, prev_move if prev_move != "" else DEFAULT_FOLDER)
	var fc = field_controls.get("Folder")
	if fc is OptionButton:
		var prev_fc := ""
		if fc.get_selected() >= 0:
			prev_fc = fc.get_item_text(fc.get_selected())
		fc.clear()
		for f in folders:
			fc.add_item(f)
		_select_text(fc, prev_fc if prev_fc != "" else DEFAULT_FOLDER)


func _load_folders() -> void:
	extra_folders = []
	var f := File.new()
	if not f.file_exists(FOLDERS_FILE):
		return
	if f.open(FOLDERS_FILE, File.READ) != OK:
		return
	var parsed = parse_json(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("folders")) == TYPE_ARRAY:
		for x in parsed["folders"]:
			var fs := str(x).strip_edges()
			if fs != "" and not fs in extra_folders:
				extra_folders.append(fs)


func _save_folders() -> void:
	var f := File.new()
	if f.open(FOLDERS_FILE, File.WRITE) != OK:
		return
	f.store_string(JSON.print({"folders": _all_folders()}, "\t"))
	f.close()


func _on_folder_filter_changed(_index: int) -> void:
	_refresh_list(search_edit.text)


func _on_create_folder_pressed(_text := "") -> void:
	var name := new_folder_edit.text.strip_edges()
	if name == "":
		name = str(_text).strip_edges()
	if name == "":
		_set_status("Type a folder name first")
		return
	if name == "All folders":
		_set_status("'All folders' is a reserved name")
		return
	if not name in extra_folders:
		extra_folders.append(name)
	_save_folders()
	_refresh_folders()
	if folder_filter_opt:
		_select_meta(folder_filter_opt, name)
	new_folder_edit.text = ""
	_refresh_list(search_edit.text)
	_set_status("Folder '%s' ready" % name)


func _on_rename_folder_pressed() -> void:
	var old := _selected_filter_folder()
	if old == "":
		_set_status("Pick a folder in the dropdown to rename")
		return
	var new_name := new_folder_edit.text.strip_edges()
	if new_name == "":
		_set_status("Type the new name in the box, then press Rename")
		return
	if new_name == old:
		return
	if new_name == "All folders":
		_set_status("'All folders' is a reserved name")
		return
	for k in data.keys():
		if _folder_of(k) == old:
			data[k]["Folder"] = new_name
	if old in extra_folders:
		extra_folders.erase(old)
	if not new_name in extra_folders:
		extra_folders.append(new_name)
	_save_folders()
	_write_data()
	_refresh_folders()
	if folder_filter_opt:
		_select_meta(folder_filter_opt, new_name)
	new_folder_edit.text = ""
	_refresh_list(search_edit.text)
	_set_status("Folder renamed to '%s'" % new_name)


func _on_delete_folder_pressed() -> void:
	var target := _selected_filter_folder()
	if target == "":
		_set_status("Pick a folder in the dropdown to delete")
		return
	var moved := 0
	for k in data.keys():
		if _folder_of(k) == target:
			data[k]["Folder"] = DEFAULT_FOLDER
			moved += 1
	extra_folders.erase(target)
	_save_folders()
	_write_data()
	_refresh_folders()
	if folder_filter_opt:
		folder_filter_opt.select(0)
	_refresh_list(search_edit.text)
	_set_status("Deleted folder '%s' (%d card(s) moved to %s)" % [target, moved, DEFAULT_FOLDER])


func _on_move_pressed() -> void:
	if move_to_opt == null or move_to_opt.get_selected() < 0:
		return
	var target := move_to_opt.get_item_text(move_to_opt.get_selected())
	var selected := list.get_selected_items()
	if selected.empty():
		_set_status("Select card(s) in the list to move")
		return
	for idx in selected:
		var k := list.get_item_text(idx)
		if data.has(k):
			data[k]["Folder"] = target
	_write_data()
	_refresh_folders()
	_refresh_list(search_edit.text)
	_set_status("Moved %d card(s) to '%s'" % [selected.size(), target])


func _populate(key: String) -> void:
	if not data.has(key):
		return
	_loading = true
	current_key = key
	var card = data[key]
	name_edit.text = _display_name(key, str(card.get("Prefix", "")))
	for field in field_controls.keys():
		var value = card.get(field, _default_for(field))
		var control = field_controls[field]
		if control is OptionButton:
			_set_option(control, str(value))
		elif control is SpinBox:
			control.value = int(value)
		elif control is CheckBox:
			control.pressed = bool(value)
		elif control is TextEdit:
			control.text = str(value)
		elif control is LineEdit:
			if control == field_controls.get("Weakness") or control == field_controls.get("Tags") or control == field_controls.get("SpecificTags") or control == field_controls.get("TagEqualities") or control == field_controls.get("TagImplications"):
				control.text = ", ".join(PoolStringArray(_to_string_array(value)))
			else:
				control.text = str(value)
	_loading = false
	_update_preview()


func _default_for(field: String):
	if field in NUMERIC_FIELDS:
		return 0
	if field == "GroupSize":
		return -1
	if field == "Weakness" or field == "Tags" or field == "SpecificTags" or field == "TagEqualities" or field == "TagImplications":
		return []
	if field == "_keep_aspect":
		return true
	if field == "Folder":
		return DEFAULT_FOLDER
	if field in ENUM_FIELDS:
		if field in NONE_DEFAULT_FIELDS:
			return "None"
		return ENUM_FIELDS[field][0]
	return ""


func _set_option(opt: OptionButton, value: String) -> void:
	var idx := -1
	for i in range(opt.get_item_count()):
		if opt.get_item_text(i) == value:
			idx = i
			break
	if idx == -1 and value != "":
		opt.add_item(value)
		idx = opt.get_item_count() - 1
	opt.select(idx if idx >= 0 else 0)


# ---------------------------------------------------------------------------
# Form reading
# ---------------------------------------------------------------------------

func _read_form() -> Dictionary:
	var card := {}
	for field in field_controls.keys():
		var control = field_controls[field]
		if control is OptionButton:
			var i = control.get_selected()
			card[field] = control.get_item_text(i) if i >= 0 else ""
		elif control is SpinBox:
			card[field] = int(control.value)
		elif control is CheckBox:
			card[field] = control.pressed
		elif control is TextEdit:
			card[field] = control.text
		elif control is LineEdit:
			if field == "Weakness" or field == "Tags" or field == "SpecificTags":
				card[field] = _parse_tags(control.text)
			elif field == "TagEqualities":
				card[field] = _parse_equalities(control.text)
			elif field == "TagImplications":
				card[field] = _parse_implications(control.text)
			else:
				card[field] = control.text
	return card


func _parse_tags(text: String) -> Array:
	var out := []
	for part in text.split(","):
		var t = part.strip_edges()
		if t != "" and not t in out:
			out.append(t)
	return out


# Parses a comma-separated list of "A = B" tag equalities, normalising each to
# "A = B" and dropping malformed entries and duplicates.
func _parse_equalities(text: String) -> Array:
	var out := []
	for part in text.split(","):
		var p = part.strip_edges()
		if p == "":
			continue
		var idx = p.find("=")
		if idx <= 0:
			continue
		var a = p.substr(0, idx).strip_edges()
		var b = p.substr(idx + 1).strip_edges()
		if a == "" or b == "":
			continue
		var norm = a + " = " + b
		if not norm in out:
			out.append(norm)
	return out


func _parse_implications(text: String) -> Array:
	var out := []
	for part in text.split(","):
		var p = part.strip_edges()
		if p == "":
			continue
		var idx = p.find("->")
		if idx <= 0:
			continue
		var a = p.substr(0, idx).strip_edges()
		var b = p.substr(idx + 2).strip_edges()
		if a == "" or b == "":
			continue
		var norm = a + " -> " + b
		if not norm in out:
			out.append(norm)
	return out


func _to_string_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	if typeof(value) == TYPE_STRING and value != "":
		return [value]
	return []


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	if current_key == "":
		_set_status("No card selected")
		return
	var new_key = _combine_name(field_controls["Prefix"].text, name_edit.text)
	if new_key == "":
		_set_status("Card name cannot be empty")
		return
	if new_key != current_key and data.has(new_key):
		_set_status("A card named '%s' already exists" % new_key)
		return
	var card = _with_id(_read_form(),
			str(data.get(current_key, {}).get("id", "")))
	if new_key != current_key:
		# The illustration filename is derived from the card's name/prefix, so
		# rename the picture too, otherwise the renamed card is left without one.
		var old_prefix := str(data[current_key].get("Prefix", ""))
		var new_prefix := str(field_controls["Prefix"].text).strip_edges()
		# warning-ignore:return_value_discarded
		_rename_card_image(current_key, new_key, old_prefix, new_prefix)
		data.erase(current_key)
	data[new_key] = card
	current_key = new_key
	if _write_data():
		_set_status("Saved '%s'" % new_key)
		_refresh_folders()
		_refresh_list(search_edit.text)
		_update_preview()


func _on_new_pressed() -> void:
	var base := "New Card"
	var key := base
	var i := 1
	while data.has(key):
		key = "%s %d" % [base, i]
		i += 1
	data[key] = _default_card()
	_refresh_list(search_edit.text)
	_populate(key)


func _on_duplicate_pressed() -> void:
	if current_key == "":
		return
	var base := current_key + " Copy"
	var key := base
	var i := 1
	while data.has(key):
		key = "%s %d" % [base, i]
		i += 1
	data[key] = data[current_key].duplicate(true)
	# A duplicate is a new card, so it gets its own identity.
	data[key]["id"] = CardIds.new_id()
	_refresh_list(search_edit.text)
	_populate(key)


func _on_delete_pressed() -> void:
	if current_key == "":
		return
	var key := current_key
	data.erase(key)
	current_key = ""
	if _write_data():
		_set_status("Deleted '%s'" % key)
	_refresh_folders()
	_refresh_list(search_edit.text)


func _on_reload_pressed() -> void:
	_load_data()
	_load_folders()
	_refresh_folders()
	_refresh_list(search_edit.text)
	if current_key != "" and data.has(current_key):
		_populate(current_key)


func _on_back_pressed() -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene("res://src/custom/MainMenu.tscn")


# Stamps the hidden permanent id onto a saved card payload: the existing id is
# kept (so renames never change it), or a fresh one is minted if there is none.
func _with_id(card: Dictionary, existing_id: String) -> Dictionary:
	var card_id := existing_id.strip_edges()
	card["id"] = card_id if card_id != "" else CardIds.new_id()
	return card


func _default_card() -> Dictionary:
	var card := {}
	for field in FIELD_ORDER:
		card[field] = _default_for(field)
	card["Type"] = "Char"
	card["id"] = CardIds.new_id()
	return card


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

func _on_import_pressed() -> void:
	if current_key == "":
		_set_status("Select a card first")
		return
	# On Windows we use the OS-native file picker (much nicer than Godot's
	# built-in dialog). Elsewhere we fall back to the built-in FileDialog.
	if _native_picker_available():
		var path := _pick_image_native()
		# Empty means the user cancelled the native dialog: do nothing.
		if path != "":
			_on_image_selected(path)
		return
	file_dialog.popup_centered_ratio(0.7)


# Godot 3.6 has no built-in native file dialog (that is a Godot 4.2+ feature),
# so on Windows we shell out to PowerShell to show the real WinForms picker.
func _native_picker_available() -> bool:
	return OS.get_name() == "Windows"


# Shows the Windows native "open file" dialog and returns the selected path,
# or "" when the user cancels. The script is run with -STA because WinForms
# dialogs require a single-threaded apartment.
func _pick_image_native() -> String:
	var script := "Add-Type -AssemblyName System.Windows.Forms;" \
			+ "$d = New-Object System.Windows.Forms.OpenFileDialog;" \
			+ "$d.Title = 'Select a card illustration';" \
			+ "$d.Filter = 'Image files|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.gif|All files|*.*';" \
			+ "$d.CheckFileExists = $true;" \
			+ "if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)"\
			+ " { Write-Output $d.FileName }"
	var output := []
	var code := OS.execute("powershell.exe",
			["-NoProfile", "-STA", "-Command", script], true, output, false)
	if code == 0 and output.size() > 0:
		return str(output[0]).strip_edges()
	return ""



func _on_image_selected(path: String) -> void:
	var fname = _image_name_for(name_edit.text.strip_edges(), field_controls["Prefix"].text.strip_edges())
	if fname == "":
		return
	var full_path: String = IMAGES_DIR + str(fname)
	if _copy_file(path, full_path):
		# Godot caches textures by path, so an overwrite would otherwise keep
		# showing the old illustration. Force a re-read from disk.
		PlueyCardFrontScript.refresh_texture_cache(full_path)
		_set_status("Imported image as " + fname)
		_update_preview()
	else:
		_set_status("Failed to import image")


func _image_name_for(base_name: String, prefix: String) -> String:
	var base := base_name.strip_edges()
	if base == "":
		return ""
	if prefix != "" and base.begins_with(prefix + " "):
		base = base.substr(prefix.length() + 1)
	return prefix + base + ".png"


# Builds the canonical (saved) card key from the separate Prefix and Name fields,
# so a variant's key is always "<prefix> <name>" (e.g. "Old Gerson").
func _combine_name(prefix: String, base_name: String) -> String:
	var base := base_name.strip_edges()
	var pre := prefix.strip_edges()
	if pre == "":
		return base
	if base.begins_with(pre + " "):
		base = base.substr(pre.length() + 1)
	if base == "":
		return ""
	return pre + " " + base


# Returns the Name field value for a card, i.e. its canonical key with the
# leading prefix removed (so prefix is not duplicated inside Name).
func _display_name(key: String, prefix: String) -> String:
	var pre := prefix.strip_edges()
	if pre != "" and key.begins_with(pre + " "):
		return key.substr(pre.length() + 1)
	return key


func _update_preview() -> void:
	_update_illustration_label()
	_rebuild_card_preview()


# Keeps the illustration filename/status label in sync (the actual art now
# shows up inside the full card preview).
func _update_illustration_label() -> void:
	var fname = _image_name_for(name_edit.text.strip_edges(), field_controls["Prefix"].text.strip_edges())
	if fname == "":
		image_label.text = "(no card selected)"
		return
	image_label.text = "File: " + fname
	var path = IMAGES_DIR + fname
	var img := Image.new()
	if img.load(path) != OK:
		image_label.text += " (missing)"


# Builds a real, fully-rendered card instance from the current form values and
# shows it in the preview column.
func _rebuild_card_preview() -> void:
	if is_instance_valid(_preview_card_obj):
		if _preview_card_obj.get_parent():
			_preview_card_obj.get_parent().remove_child(_preview_card_obj)
		_preview_card_obj.queue_free()
		_preview_card_obj = null
	if current_key == "" or not is_instance_valid(preview_holder):
		return
	var card = _make_preview_card(_read_form())
	if card == null:
		return
	_preview_card_obj = CARD_PREVIEW_SCENE.instance()
	preview_holder.add_child(_preview_card_obj)
	# The editor preview is display-only. Disable mouse handling so its hover
	# popup never tries to instance the card by name (which fails for a card
	# that has not been saved to the definitions yet, e.g. a brand-new one).
	_preview_card_obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_card_obj.setup(card)


# Instances the card template that matches the card's Type, pre-filling its
# properties from the form so the preview reflects unsaved edits too.
func _make_preview_card(form: Dictionary):
	var card_type := str(form.get("Type", "Char"))
	var scene_path := CFConst.PATH_CARDS + card_type + ".tscn"
	if not ResourceLoader.exists(scene_path):
		scene_path = CFConst.PATH_CARDS + "Char.tscn"
	var scene = load(scene_path)
	if scene == null:
		return null
	var card = scene.instance()
	var preview_name := _combine_name(
			str(field_controls["Prefix"].text), name_edit.text)
	if preview_name == "":
		preview_name = current_key
	card.canonical_name = preview_name
	card.properties = form.duplicate(true)
	card.thumbnail_scale = PREVIEW_SCALE
	return card


# Renames a card's illustration (and its Godot .import sidecar) when the card is
# renamed, so the picture follows the card instead of being orphaned under the
# old filename.
func _rename_card_image(old_key: String, new_key: String, old_prefix: String, new_prefix: String) -> bool:
	var old_name := _image_name_for(old_key, old_prefix)
	var new_name := _image_name_for(new_key, new_prefix)
	if old_name == "" or new_name == "" or old_name == new_name:
		return false
	var old_path := IMAGES_DIR + old_name
	var new_path := IMAGES_DIR + new_name
	var dir := Directory.new()
	if not dir.file_exists(old_path):
		return false
	# Never overwrite an image that already exists under the new name.
	if dir.file_exists(new_path):
		return false
	if dir.rename(old_path, new_path) != OK:
		return false
	# Move the .import sidecar as well, so the running game can still load the
	# texture immediately. We repoint its "source_file" at the new path while the
	# pre-imported .stex it references is left in place for the editor to refresh.
	var old_imp := old_path + ".import"
	var new_imp := new_path + ".import"
	if dir.file_exists(old_imp):
		var f := File.new()
		if f.open(old_imp, File.READ) == OK:
			var text := f.get_as_text()
			f.close()
			text = text.replace(old_path, new_path)
			var o := File.new()
			if o.open(new_imp, File.WRITE) == OK:
				o.store_string(text)
				o.close()
				dir.remove(old_imp)
	return true


func _copy_file(src: String, dst: String) -> bool:
	var f := File.new()
	if f.open(src, File.READ) != OK:
		return false
	var buf := f.get_buffer(f.get_len())
	f.close()
	var out := File.new()
	if out.open(dst, File.WRITE) != OK:
		return false
	out.store_buffer(buf)
	out.close()
	return true


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
