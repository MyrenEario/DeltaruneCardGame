# PlueyCardFront.gd
extends CardFront

# Colours used for the combined tag list. Specific tags are shown first and in
# a more saturated colour, followed by normal tags in a slightly less
# saturated colour.
const TAG_COLOR_SPECIFIC := "#6ec6ff"
const TAG_COLOR_NORMAL := "#8b93a8"
const TAG_SEPARATOR := ", "

# Action-type ("action strength", bottom-left) and defence-type
# ("resistances", bottom-right) icons, mirroring PlueyPoker1.
const ACTION_ICONS := {
	"Fight": "res://assets/icons/fight.png",
	"Mercy": "res://assets/icons/spare.png",
	"Control": "res://assets/icons/control.png",
}
const DEFENSE_ICONS := {
	"Fight": "res://assets/icons/defend_fight.png",
	"Mercy": "res://assets/icons/defend_spare.png",
	"Control": "res://assets/icons/defend_control.png",
}
const ACTION_COLORS := {
	"Fight": Color(1.0, 0.35, 0.35, 1),
	"Mercy": Color(0.4, 0.9, 0.4, 1),
	"Control": Color(0.4, 0.7, 1.0, 1),
}
const ICON_NEUTRAL_COLOR := Color(0.9, 0.3, 0.3, 1)

# Horizontal space (px) taken up in the prefix row by the Cost column
# (icon + value), the LV column, the spacer between them and the HBox
# separations. The Prefix label is narrowed by this much so the row totals the
# card width while an always-present expanding spacer keeps LV pinned to the
# top-right even when there is no prefix.
const HEADER_SIDE_WIDTH := 60

# Tag layout. Tags are packed into explicit lines, breaking only between tags,
# so a tag is never split across lines. The font is left untouched while the
# list fits in five lines and only shrinks beyond that.
const TAG_FONT_SIZE := 9
const TAG_LINE_COUNT := 5
const TAG_LINE_HEIGHT := 14
const TAG_AREA_HEIGHT := TAG_LINE_COUNT * TAG_LINE_HEIGHT
const TAG_RELATION_FONT_SIZE := 9
const TAG_RELATION_LINE_SPACING := 1
const ABILITIES_MIN_HEIGHT := 18
const CARD_VBOX_SEPARATION := 2
const HEADER_MIN_HEIGHT := 46
const TYPE_MIN_HEIGHT := 13
const FOOTER_MIN_HEIGHT := 19
const ILLUSTRATION_MIN_HEIGHT := 20

func _ready() -> void:
	_card_text = find_node("CardText")
	card_labels["Prefix"] = find_node("Prefix")
	card_labels["Name"] = find_node("Name")
	card_labels["Type"] = find_node("Type")
	card_labels["Weakness"] = find_node("Weakness")
	card_labels["Tags"] = find_node("Tags")
	card_labels["Abilities"] = find_node("Abilities")
	card_labels["TagRelations"] = find_node("TagRelations")
	card_labels["Cost"] = find_node("Cost")
	card_labels["LV"] = find_node("LV")
	card_labels["AT"] = find_node("AT")
	card_labels["HP"] = find_node("HP")

	card_label_min_sizes["Prefix"] = Vector2(CFConst.CARD_SIZE.x - 4 - HEADER_SIDE_WIDTH, 13)
	card_label_min_sizes["Name"] = Vector2(CFConst.CARD_SIZE.x - 4, 19)
	card_label_min_sizes["Type"] = Vector2(CFConst.CARD_SIZE.x - 4, 13)
	card_label_min_sizes["Tags"] = Vector2(CFConst.CARD_SIZE.x - 4, TAG_AREA_HEIGHT)
	card_label_min_sizes["Abilities"] = Vector2(CFConst.CARD_SIZE.x - 4, ABILITIES_MIN_HEIGHT)
	card_label_min_sizes["TagRelations"] = Vector2(CFConst.CARD_SIZE.x - 4, 11)
	card_label_min_sizes["Weakness"] = Vector2(CFConst.CARD_SIZE.x - 4, 10)
	card_label_min_sizes["Cost"] = Vector2(18, 16)
	card_label_min_sizes["LV"] = Vector2(20, 16)
	card_label_min_sizes["AT"] = Vector2(20, 16)
	card_label_min_sizes["HP"] = Vector2(20, 16)

	for l in card_label_min_sizes:
		if card_labels.has(l) and is_instance_valid(card_labels[l]):
			card_labels[l].rect_min_size = card_label_min_sizes[l]

	# The header row must span the card's content width. VBoxContainer does not
	# always re-stretch it after the labels are populated, which left a no-prefix
	# card's LV floating in the middle (the row collapsed to its minimum width).
	# An explicit min width is scaled by resize_recursively() for previews.
	var header_row = find_node("HeaderRow")
	if header_row:
		header_row.rect_min_size = Vector2(CFConst.CARD_SIZE.x - 8, 0)

	for label in card_labels:
		match label:
			"Cost", "LV", "AT", "HP":
				original_font_sizes[label] = 14
			"Prefix":
				original_font_sizes[label] = 9
			"Tags":
				original_font_sizes[label] = TAG_FONT_SIZE
			"Abilities":
				original_font_sizes[label] = 12
			"TagRelations":
				original_font_sizes[label] = TAG_RELATION_FONT_SIZE
			"Weakness":
				original_font_sizes[label] = 8
			_:
				original_font_sizes[label] = 14

	_setup_vertical_flow()
	var illustration = find_node("Illustration")
	if illustration and not illustration.is_connected(
			"resized", self, "_position_type_label"):
		illustration.connect("resized", self, "_position_type_label")
	call_deferred("_position_type_label")
	call_deferred("_load_visuals")


# The illustration is the only element that grows, so it absorbs all the
# vertical space left over after the header/type/tags/abilities/relations/
# footer. This means a card with few tags (or no abilities text) gets a bigger
# picture instead of leaving a gap. (Previously the Abilities box expanded
# instead, which kept the art pinned to its minimum height.)
func _setup_vertical_flow() -> void:
	var illustration = find_node("Illustration")
	if illustration:
		illustration.size_flags_vertical = Control.SIZE_EXPAND_FILL
		illustration.rect_min_size.y = ILLUSTRATION_MIN_HEIGHT
	var abilities = card_labels.get("Abilities")
	if abilities:
		abilities.size_flags_vertical = Control.SIZE_FILL


# Keeps the Type tag in the illustration's bottom-right while the image grows
# or shrinks (the image is the only element that expands vertically).
func _position_type_label() -> void:
	var illustration = find_node("Illustration")
	var type_label = card_labels.get("Type")
	if not is_instance_valid(illustration) or not is_instance_valid(type_label):
		return
	type_label.rect_size = type_label.rect_min_size
	var scaled_size: Vector2 = type_label.rect_size * type_label.rect_scale
	type_label.rect_position = Vector2(
			illustration.rect_size.x - scaled_size.x - 2,
			illustration.rect_size.y - scaled_size.y - 2)

# We override the framework's setter so we can:
# * strip the prefix from the Name (it is shown in its own Prefix label)
# * hide the Prefix label whenever it is empty
#
# The tag list is handled separately (see _apply_tags and PlueyCard.gd's
# refresh_property_label) because it needs a RichTextLabel.
func set_label_text(node: Label, value, scale: float = 1):
	if node == card_labels.get("Name"):
		value = _strip_prefix(value)
	elif node == card_labels.get("Prefix"):
		node.visible = (str(value) != "")
	.set_label_text(node, value, scale)


func _strip_prefix(value) -> String:
	var text := str(value)
	if not card_owner or not "properties" in card_owner:
		return text
	var prefix = card_owner.properties.get("Prefix", "")
	if prefix != "" and text.begins_with(prefix + " "):
		return text.substr(prefix.length() + 1)
	return text


func _tag_relation_height(lines: int, font_size: int) -> int:
	if lines <= 0:
		return 0
	var font = get_card_label_font(card_labels["TagRelations"])
	font.size = font_size
	return int(lines * (font.get_height() + TAG_RELATION_LINE_SPACING) - TAG_RELATION_LINE_SPACING)


func _card_scale() -> float:
	return float(scaled_fonts.get("Tags", 1.0))


func _base_label_width() -> float:
	return CFConst.CARD_SIZE.x - 8


func _tag_entry(value, color: String) -> Dictionary:
	var text := str(value)
	return {"plain": text, "bbcode": "[color=%s]%s[/color]" % [color, text]}


func _pack_tag_lines(entries: Array, font: Font, width: float) -> Dictionary:
	var lines := []
	var current := ""
	var current_width := 0.0
	var separator_width: float = font.get_string_size(TAG_SEPARATOR).x
	var widest_tag := 0.0
	for entry in entries:
		var tag_width: float = font.get_string_size(entry["plain"]).x
		widest_tag = max(widest_tag, tag_width)
		if current == "":
			current = entry["bbcode"]
			current_width = tag_width
		elif current_width + separator_width + tag_width <= width:
			current += TAG_SEPARATOR + entry["bbcode"]
			current_width += separator_width + tag_width
		else:
			lines.append(current)
			current = entry["bbcode"]
			current_width = tag_width
	if current != "":
		lines.append(current)
	return {"lines": lines, "widest_tag": widest_tag}


func _pack_tags(entries: Array, node: RichTextLabel) -> Dictionary:
	var fonts := _get_card_rtl_fonts(node)
	var font = fonts.get("normal_font")
	if not font:
		return {"text": "", "font_size": TAG_FONT_SIZE, "lines": 0}
	var width := _base_label_width()
	var font_size := TAG_FONT_SIZE
	var chosen_size := font_size
	var packed := {}
	while font_size >= 5:
		font.size = font_size
		chosen_size = font_size
		packed = _pack_tag_lines(entries, font, width)
		if packed["lines"].size() <= TAG_LINE_COUNT and packed["widest_tag"] <= width:
			break
		font_size -= 1
	return {
		"text": "\n".join(PoolStringArray(packed["lines"])),
		"font_size": chosen_size,
		"lines": packed["lines"].size(),
	}


func _fit_relation_font(parts: Array, node: Label) -> int:
	var font = get_card_label_font(node)
	var width := _base_label_width()
	var font_size := TAG_RELATION_FONT_SIZE
	while font_size > 5:
		font.size = font_size
		var widest := 0.0
		for part in parts:
			widest = max(widest, font.get_string_size(str(part)).x)
		if widest <= width:
			break
		font_size -= 1
	return font_size


func _load_visuals() -> void:
	if not card_owner or not "properties" in card_owner:
		return
	var props = card_owner.properties
	var cname = card_owner.canonical_name
	var prefix = props.get("Prefix", "")
	_load_illustration(prefix, cname)
	_apply_prefix(prefix, cname)
	_apply_tags()
	_apply_abilities()
	_apply_weakness()
	_apply_action_icons(props.get("ActionType", "None"), props.get("DefenseType", "None"))


# Shows the card's weakness line ("Obeys: X", "Weakness: X" or "Likes: X").
func _apply_weakness() -> void:
	var node = card_labels.get("Weakness")
	if not node:
		return
	var text := _weakness_text()
	node.visible = text != ""
	set_label_text(node, text)


func _weakness_text() -> String:
	if not card_owner or not "properties" in card_owner:
		return ""
	var props = card_owner.properties
	var weakness_type := str(props.get("WeaknessType", "")).strip_edges()
	var prefix := ""
	match weakness_type:
		"Control":
			prefix = "Obeys: "
		"Fight":
			prefix = "Weakness: "
		"Mercy":
			prefix = "Likes: "
		_:
			return ""
	var names := []
	var raw = props.get("Weakness", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			var tag := str(entry).strip_edges()
			if not tag.empty():
				names.append(tag)
	if names.empty():
		return ""
	return prefix + ", ".join(PoolStringArray(names))


# Hides the abilities box when a card has no ability text, so it does not take
# up space (and the picture can grow).
#
# Only visibility is toggled here - never the min size. Setting a RichTextLabel's
# rect_min_size.y to 0 makes the framework's font-shrinking loop spin forever
# (it can never satisfy "content height <= 0"), which leaves the whole card
# front stuck at modulate alpha 0, i.e. invisible.
func _apply_abilities() -> void:
	var node = card_labels.get("Abilities")
	if not node:
		return
	var text := ""
	if card_owner and "properties" in card_owner:
		text = str(card_owner.properties.get("Abilities", "")).strip_edges()
	node.visible = text != ""


# Sets the bottom-left action strength symbol (fight/mercy/control) and the
# bottom-right resistance symbol (their matching defend icons), and tints the
# AT/HP values to match.
func _apply_action_icons(action_type, defense_type) -> void:
	var action := str(action_type)
	var defense := str(defense_type)
	_apply_type_icon("ActionIcon", action, ACTION_ICONS)
	_apply_type_icon("DefenseIcon", defense, DEFENSE_ICONS)
	var at_label = card_labels.get("AT")
	if at_label:
		at_label.add_color_override("font_color", ACTION_COLORS.get(action, ICON_NEUTRAL_COLOR))
	var hp_label = card_labels.get("HP")
	if hp_label:
		hp_label.add_color_override("font_color", ACTION_COLORS.get(defense, ICON_NEUTRAL_COLOR))


func _apply_type_icon(node_name: String, type_name: String, icons: Dictionary) -> void:
	var rect: TextureRect = find_node(node_name)
	if not rect:
		return
	var path = icons.get(type_name, "")
	var tex = _load_texture_cached(path)
	if tex:
		rect.texture = tex
		rect.visible = true
	else:
		rect.visible = false
		rect.texture = null


# Loads a texture once and caches it (shared across every card and viewer), with
# point filtering applied. This avoids re-creating ImageTextures (a CPU copy of
# the image data) for every card, which is by far the biggest cost when
# instancing the grid. The cache lives on the "cfc" singleton via metadata so we
# do not have to touch the framework's core scripts.
func _load_texture_cached(path: String) -> Texture:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var cfc_node = get_node_or_null("/root/cfc")
	var cache = null
	if cfc_node:
		if not cfc_node.has_meta("pluey_texture_cache"):
			cfc_node.set_meta("pluey_texture_cache", {})
		cache = cfc_node.get_meta("pluey_texture_cache")
		if cache.has(path):
			return cache[path]
	var tex = load(path)
	if tex is Texture:
		tex.flags = tex.flags & ~Texture.FLAG_FILTER
		if cache != null:
			cache[path] = tex
		return tex
	return null


# Re-reads an image from disk into the shared texture cache. Used after the card
# editor overwrites an illustration: otherwise both this cache and Godot's
# resource cache would keep serving the old picture.
static func refresh_texture_cache(path: String) -> void:
	if path.empty() or not ResourceLoader.exists(path):
		return
	var image := Image.new()
	if image.load(path) != OK:
		return
	var texture := ImageTexture.new()
	texture.create_from_image(image)
	texture.flags = texture.flags & ~Texture.FLAG_FILTER
	if not cfc.has_meta("pluey_texture_cache"):
		cfc.set_meta("pluey_texture_cache", {})
	var cache = cfc.get_meta("pluey_texture_cache")
	cache[path] = texture


func _apply_prefix(prefix: String, cname: String) -> void:
	var prefix_label = card_labels.get("Prefix")
	if prefix_label:
		prefix_label.visible = (prefix != "")
	var name_label = card_labels.get("Name")
	if name_label:
		var base = cname
		if prefix != "" and base.begins_with(prefix + " "):
			base = base.substr(prefix.length() + 1)
		set_label_text(name_label, base)


# Builds the combined tag list (specific tags first, then normal tags), each
# coloured differently, and pushes it into the Tags RichTextLabel.
func _apply_tags() -> void:
	var tags_node = card_labels.get("Tags")
	if not tags_node or not card_owner or not "properties" in card_owner:
		return
	var specific = card_owner.properties.get("SpecificTags", [])
	var normal = card_owner.properties.get("Tags", [])
	var entries := []
	if typeof(specific) == TYPE_ARRAY:
		for t in specific:
			entries.append(_tag_entry(t, TAG_COLOR_SPECIFIC))
	if typeof(normal) == TYPE_ARRAY:
		for t in normal:
			entries.append(_tag_entry(t, TAG_COLOR_NORMAL))
	# set_rich_label_text() resizes over the course of several frames. During
	# setup it can be triggered repeatedly (once per tag property) so we wait
	# for any in-progress resize to finish, ensuring the final, complete list
	# is the one that ends up displayed.
	var _waits := 0
	while tags_node in resizing_labels and _waits < 60:
		_waits += 1
		yield(get_tree(), "idle_frame")
	if entries.empty():
		bbcode_texts[tags_node] = ""
		tags_node.visible = false
		return
	tags_node.visible = true
	var card_scale := _card_scale()
	var packed := _pack_tags(entries, tags_node)
	var text: String = packed["text"]
	# Only reserve as many lines as the tags actually need, so short tag lists
	# do not leave a big gap before the tag equalities (and the picture gets
	# the reclaimed space).
	var lines := int(max(1, int(packed["lines"])))
	tags_node.rect_min_size = Vector2(
			(float(CFConst.CARD_SIZE.x) - 4.0) * card_scale,
			float(lines * TAG_LINE_HEIGHT) * card_scale)
	font_sizes["Tags"] = packed["font_size"] * card_scale
	# Keep the cached bbcode in sync so scale_to() (used by the card viewer)
	# re-renders the current tags rather than a stale copy.
	bbcode_texts[tags_node] = text
	set_rich_label_text(tags_node, text, false, card_scale)


func _apply_tag_relations() -> void:
	var node = card_labels.get("TagRelations")
	if not node or not is_instance_valid(node):
		return
	var card_scale := _card_scale()
	if not card_owner or not "properties" in card_owner:
		node.visible = false
		return
	var parts := []
	for field in ["TagEqualities", "TagImplications"]:
		var raw = card_owner.properties.get(field, [])
		if typeof(raw) == TYPE_ARRAY:
			for e in raw:
				var s = str(e).strip_edges()
				if s != "":
					parts.append(s)
	if parts.empty():
		node.visible = false
		node.text = ""
		node.rect_min_size.y = 0
		return
	var relation_font_size := _fit_relation_font(parts, node)
	var relation_height := _tag_relation_height(parts.size(), relation_font_size)
	node.rect_min_size = Vector2((CFConst.CARD_SIZE.x - 4) * card_scale, \
			max(1, int(round(relation_height * card_scale))))
	font_sizes["TagRelations"] = relation_font_size * card_scale
	node.visible = true
	set_label_text(node, "\n".join(PoolStringArray(parts)), card_scale)


func _load_illustration(prefix: String, cname: String) -> void:
	var rect: TextureRect = find_node("Illustration")
	if not rect:
		return
	var name = cname;
	if(prefix != ""):
		name.erase(0,prefix.length() + 1);
		name = prefix + name;
	name = name + ".png";
	
	var user_dir = "res://assets/cardimages/"
	var full_path = user_dir + name
	var tex = _load_texture_cached(full_path)
	if tex:
		rect.texture = tex
		rect.visible = true
	else:
		rect.visible = false
