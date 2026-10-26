extends "res://tests/UTcommon.gd"

const CARD_EDITOR = preload("res://src/custom/CardEditor/CardEditor.tscn")
const PlueyCardFrontScript = preload(
		"res://src/custom/cards/PlueyCardFront.gd")


func before_each():
	cfc.is_testing = true
	cfc._setup()


func test_editor_renders_a_full_card_instance():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.3), YIELD)

	editor._populate("Dess")
	yield(yield_for(0.3), YIELD)

	assert_true(is_instance_valid(editor._preview_card_obj),
			"Preview widget is created")
	var card = editor._preview_card_obj.display_card
	assert_true(is_instance_valid(card), "Preview holds a card instance")
	assert_eq(card.canonical_name, "Dess", "Preview shows the selected card")
	assert_true(card.card_front != null, "Preview card has a front side")
	assert_eq(card.state, Card.CardState.DECKBUILDER_GRID)


func test_editor_preview_reflects_unsaved_edits():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.3), YIELD)

	editor._populate("Dess")
	yield(yield_for(0.3), YIELD)

	# Change a value in the form without saving, then rebuild the preview.
	editor.field_controls["AT"].value = 7
	editor._update_preview()
	yield(yield_for(0.2), YIELD)

	assert_eq(int(editor._preview_card_obj.display_card.properties.get("AT", -1)),
			7, "Preview reflects the edited Attack value")


func test_editor_preview_tracks_name_edits():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.3), YIELD)

	editor._populate("Dess")
	yield(yield_for(0.3), YIELD)

	editor.name_edit.text = "Dess Edited"
	editor._update_preview()
	yield(yield_for(0.2), YIELD)

	assert_eq(editor._preview_card_obj.display_card.canonical_name,
			"Dess Edited", "Preview updates the displayed card name")

func test_editor_preview_is_display_only():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.3), YIELD)
	editor._populate("Dess")
	yield(yield_for(0.3), YIELD)
	assert_eq(editor._preview_card_obj.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"Preview ignores the mouse so its hover popup cannot fire")


func test_preview_popup_ignores_unknown_card():
	var popup = add_child_autofree(
			load("res://src/core/CardViewer/CVPreviewPopup.tscn").instance())
	popup.show_preview_card("Totally Unknown Card")
	assert_false(popup.has_preview_card(),
			"Unknown card names are ignored instead of crashing")


func test_cards_sort_by_base_name_then_prefix():
	var editor = add_child_autofree(CARD_EDITOR.instance())
	yield(yield_for(0.3), YIELD)
	editor.data = {
		"Zed": {"Prefix": "", "Folder": "Uncategorized"},
		"Alpha Zed": {"Prefix": "Alpha", "Folder": "Uncategorized"},
		"Beta Alpha": {"Prefix": "Beta", "Folder": "Uncategorized"},
		"Aaron": {"Prefix": "", "Folder": "Uncategorized"},
	}
	editor._refresh_folders()
	editor._refresh_list("")
	var order := []
	for i in range(editor.list.get_item_count()):
		order.append(editor.list.get_item_text(i))
	var expected := ["Aaron", "Beta Alpha", "Zed", "Alpha Zed"]
	assert_eq(order.size(), expected.size())
	for i in range(expected.size()):
		assert_eq(str(order[i]), expected[i],
				"Cards are ordered by base name, then prefix")


func test_refresh_texture_cache_replaces_cached_texture():
	var path := "res://assets/cardimages/King.png"
	assert_true(ResourceLoader.exists(path), "King illustration exists")
	cfc.set_meta("pluey_texture_cache", {})
	PlueyCardFrontScript.refresh_texture_cache(path)
	var before = cfc.get_meta("pluey_texture_cache").get(path)
	assert_true(before is Texture, "Texture was cached")
	PlueyCardFrontScript.refresh_texture_cache(path)
	var after = cfc.get_meta("pluey_texture_cache").get(path)
	assert_true(after is Texture)
	assert_ne(after, before, "Overwrite refresh replaces the cached texture")
