# The opening scene of the campaign: a deck-building ritual narrated by a
# talking voice over an endlessly-zooming background.
#
# The voice asks who each of the three heroes is. Under the objective card it
# offers a handful of candidate cards; clicking one adds it to the player's deck
# and moves on to the next hero. Later steps (choosing the remaining cards up to
# a 20-card deck) are still to come.
extends Control

const CARD_OBJECT_SCENE = preload(
		"res://src/core/CardViewer/CVGridCardObject.tscn")
const CardRecommender = preload("res://src/custom/campaign/CardRecommender.gd")
const VOICE_SPEED := 14.0  # characters per second
const OBJECTIVE_THUMB_SCALE := 1.0
const OPTION_THUMB_SCALE := 0.7
const RECOMMEND_THUMB_SCALE := 0.55
# How many cards the finished deck needs, and how many copies of one card.
const DECK_TARGET := 20
const MAX_COPIES := 3

# The three "who is this hero?" steps. "options" are card names the player can
# pick; a pick is added to their deck.
const STEPS := [
	{
		"objective": "First Hero",
		"question": "Who is\nThe First Hero,\nThe Cage with Human Soul and Parts?",
		"options": ["Kris", "Ribcage Roaring Knight", "ArachnidsGrip's Vessel"],
	},
	{
		"objective": "Second Hero",
		"question": "Who is\nThe Second Hero,\nThe Girl with Hope crossed on her heart?",
		"options": ["Susie", "Noelle", "Dess", "Aqua"],
	},
	{
		"objective": "Third Hero",
		"question": "Who is\nThe Third Hero,\nThe Prince Alone in Deepest Dark?",
		"options": ["Ralsei", "Asriel", "Lancer", "UNUSED", "Mantle Boss ERAM"],
	},
]

onready var _voice := $Voice
onready var _objective := $Objective
onready var _options := $Options
onready var _recommendations := $Recommendations
onready var _grid := $Recommendations/Grid
onready var _deck_label := $DeckLabel
onready var _skip := $Skip

var _step_index := 0
var _deck := []
var _full_text := ""
var _revealed := 0.0
var _locked := false
var _count_labels := {}


func _ready() -> void:
	_skip.connect("pressed", self, "_on_skip_pressed")
	_show_step(0)


func _show_step(index: int) -> void:
	_step_index = index
	_clear(_objective)
	_clear(_options)
	_locked = false
	if index >= STEPS.size():
		_show_recommendations()
		return
	_recommendations.visible = false
	_deck_label.visible = false
	var step: Dictionary = STEPS[index]
	_speak(str(step["question"]))
	_add_card_display(_objective, str(step["objective"]),
			OBJECTIVE_THUMB_SCALE)
	for option_name in step["options"]:
		_add_option(str(option_name))


# Adds a clickable option: a flat Button holding a rendered card. The Button is
# added to the tree first so the card preview can finish its own setup.
func _add_option(card_name: String) -> void:
	var button := Button.new()
	button.flat = true
	button.hint_tooltip = "Add " + card_name + " to your deck"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_options.add_child(button)
	var display = _add_card_display(button, card_name, OPTION_THUMB_SCALE)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.rect_min_size = display.rect_min_size
	button.connect("pressed", self, "_on_option_pressed", [card_name])


func _on_option_pressed(card_name: String) -> void:
	if _locked:
		return
	_locked = true
	_deck.append(card_name)
	_show_step(_step_index + 1)


# --- Recommended extra cards ----------------------------------------------

# Once the three heroes are picked, offer cheaper cards that share tag material
# with them; pick until the deck reaches DECK_TARGET.
func _show_recommendations() -> void:
	_clear(_objective)
	_clear(_options)
	_count_labels = {}
	_clear(_grid)
	_recommendations.visible = true
	_deck_label.visible = true
	_speak("Now choose companions to round out your deck.")
	var recommendations = CardRecommender.recommend(
			_deck, cfc.card_definitions, 30)
	for card_name in recommendations:
		_add_recommendation_entry(str(card_name))
	_refresh_deck_label()


# The box is added to the grid before the card preview is built, otherwise the
# preview has no parent to finish its own setup in.
func _add_recommendation_entry(card_name: String) -> void:
	var box := VBoxContainer.new()
	_grid.add_child(box)
	var button := Button.new()
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.hint_tooltip = "Add " + card_name + " to your deck"
	box.add_child(button)
	var display = _add_card_display(button, card_name, RECOMMEND_THUMB_SCALE)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.rect_min_size = display.rect_min_size
	var count := Label.new()
	count.align = Label.ALIGN_CENTER
	box.add_child(count)
	_count_labels[card_name] = count
	button.connect("pressed", self, "_on_recommend_pressed", [card_name])


func _on_recommend_pressed(card_name: String) -> void:
	if _deck.size() >= DECK_TARGET or _card_count(card_name) >= MAX_COPIES:
		return
	_deck.append(card_name)
	_refresh_deck_label()
	if _count_labels.has(card_name):
		_count_labels[card_name].text = "%d / %d" % [
			_card_count(card_name), MAX_COPIES]
	if _deck.size() >= DECK_TARGET:
		_finish_deck_building()


func _card_count(card_name: String) -> int:
	var total := 0
	for name in _deck:
		if name == card_name:
			total += 1
	return total


func _refresh_deck_label() -> void:
	_deck_label.text = "Deck: %d / %d" % [_deck.size(), DECK_TARGET]


func _finish_deck_building() -> void:
	_speak("Your deck is ready.")
	cfc.campaign_player_deck = _deck_counts()
	yield(get_tree().create_timer(1.2), "timeout")
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "campaign/CampaignScreen.tscn")


func _deck_counts() -> Dictionary:
	var counts := {}
	for name in _deck:
		counts[name] = int(counts.get(name, 0)) + 1
	return counts


# Renders a card into `parent` and returns the node. Cards that do not exist yet
# fall back to a simple placeholder so the scene never breaks.
func _add_card_display(parent: Node, card_name: String, thumb_scale: float):
	if cfc.card_definitions.has(card_name):
		var obj = CARD_OBJECT_SCENE.instance()
		parent.add_child(obj)
		var card = cfc.instance_card(card_name)
		card.thumbnail_scale = thumb_scale
		obj.setup(card)
		return obj
	var panel := PanelContainer.new()
	panel.rect_min_size = CFConst.CARD_SIZE * thumb_scale * cfc.curr_scale
	var label := Label.new()
	label.text = "%s\n(not yet created)" % card_name
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.autowrap = true
	label.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	panel.add_child(label)
	parent.add_child(panel)
	return panel


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _speak(text: String) -> void:
	_full_text = text
	_revealed = 0.0
	_voice.text = ""


func _process(delta: float) -> void:
	if _voice.text.length() < _full_text.length():
		_revealed += delta * VOICE_SPEED
		var count := int(min(float(_full_text.length()), floor(_revealed)))
		_voice.text = _full_text.substr(0, count)


# --- Small accessors used by tests (and the upcoming deck-building step). ---

func get_step_index() -> int:
	return _step_index


func get_objective_name() -> String:
	if _step_index < STEPS.size():
		return str(STEPS[_step_index]["objective"])
	return ""


func get_options() -> Array:
	if _step_index < STEPS.size():
		return STEPS[_step_index]["options"]
	return []


func get_deck() -> Array:
	return _deck


# Temporary escape hatch while the scene is being built.
func _on_skip_pressed() -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "campaign/CampaignScreen.tscn")
