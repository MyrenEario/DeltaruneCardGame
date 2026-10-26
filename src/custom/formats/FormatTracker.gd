class_name FormatTracker
extends PanelContainer

const GameFormat = preload("res://src/custom/formats/GameFormat.gd")
const FormatScoring = preload("res://src/custom/formats/FormatScoring.gd")
const CARD_OBJECT_SCENE = preload(
		"res://src/core/CardViewer/CVGridCardObject.tscn")
const DEFAULT_FORMAT_ID := "three_heroes"
const SCORE_REFRESH_INTERVAL := 0.25

var formats := {}
var format_ids := []
var current_format := {}
var objective_cards := []
var scores := [0, 0]
var costs := [0, 0]
var finished := false
var turn_manager = null
var _refresh_accum := 0.0

onready var _format_select := $Margin/VBox/Header/FormatSelect
onready var _score_label := $Margin/VBox/Header/ScoreLabel
onready var _objective_row := $Margin/VBox/Objectives
onready var _need_label := $Margin/VBox/NeedLabel
onready var _game_over := $GameOver
onready var _game_over_title := \
		$GameOver/GameOverMargin/GameOverVBox/GameOverTitle
onready var _game_over_detail := \
		$GameOver/GameOverMargin/GameOverVBox/GameOverDetail
onready var _back_button := \
		$GameOver/GameOverMargin/GameOverVBox/BackToMain


func _ready() -> void:
	_format_select.connect("item_selected", self, "_on_format_selected")
	_back_button.connect("pressed", self, "_on_back_to_main_pressed")
	_load_formats()
	if turn_manager == null:
		turn_manager = cfc.NMAP.get("turnmanager")
	if is_instance_valid(turn_manager):
		if not turn_manager.is_connected(
				"turn_started", self, "_on_turn_started"):
			turn_manager.connect(
					"turn_started", self, "_on_turn_started")
	_select_default_format()


func _process(delta: float) -> void:
	if finished or objective_cards.empty():
		return
	_refresh_accum += delta
	if _refresh_accum < SCORE_REFRESH_INTERVAL:
		return
	_refresh_accum = 0.0
	_refresh_scores()


func _load_formats() -> void:
	formats = GameFormat.load_all()
	format_ids = formats.keys()
	format_ids.sort()
	_format_select.clear()
	for format_id in format_ids:
		_format_select.add_item(
				str(formats[format_id].get("name", format_id)))


func _select_default_format() -> void:
	if format_ids.empty():
		_format_select.add_item("No formats available")
		_format_select.disabled = true
		_need_label.text = "Create a format before starting a game."
		return
	var default_index := format_ids.find(DEFAULT_FORMAT_ID)
	if default_index < 0:
		default_index = 0
	_format_select.select(default_index)
	_on_format_selected(default_index)


func set_format(format_id: String) -> bool:
	var index := format_ids.find(format_id)
	if index < 0:
		return false
	_format_select.select(index)
	_on_format_selected(index)
	return true


func lock_format() -> void:
	_format_select.disabled = true


func _on_format_selected(index: int) -> void:
	if finished or index < 0 or index >= format_ids.size():
		return
	current_format = formats[format_ids[index]]
	_build_objectives()
	scores = [0, 0]
	costs = [0, 0]
	_refresh_scores()


func _build_objectives() -> void:
	for child in _objective_row.get_children():
		_objective_row.remove_child(child)
		child.queue_free()
	objective_cards.clear()
	for card_name in current_format.get("objective_cards", []):
		var card_name_text := str(card_name)
		if not cfc.card_definitions.has(card_name_text):
			var missing := Label.new()
			missing.text = "Missing: " + card_name_text
			_objective_row.add_child(missing)
			continue
		var card = cfc.instance_card(card_name_text)
		var display = CARD_OBJECT_SCENE.instance()
		_objective_row.add_child(display)
		display.setup(card)
		objective_cards.append(card)


func _refresh_scores() -> void:
	for player_id in [0, 1]:
		var result := FormatScoring.evaluate(
				objective_cards, _zone_for(player_id))
		scores[player_id] = int(result.score)
		costs[player_id] = int(result.cost)
	_update_labels()


func _zone_for(player_id: int):
	return cfc.NMAP.get("player" + str(player_id + 1) + "zone")


func _update_labels() -> void:
	_score_label.text = "P1 score %d  |  P2 score %d" % [
		scores[0], scores[1]]
	_need_label.text = \
			"Best total cost  P1: %d  |  P2: %d" % [costs[0], costs[1]]


func _on_turn_started(player_id: int, _turn_number: int) -> void:
	if finished or objective_cards.empty():
		return
	if not is_instance_valid(turn_manager):
		return
	_refresh_scores()
	if turn_manager.player_resources[player_id] >= costs[player_id]:
		_finish_game(player_id)


func _finish_game(player_id: int) -> void:
	finished = true
	_format_select.disabled = true
	turn_manager.game_over = true
	var winner := -1
	if scores[0] > scores[1]:
		winner = 0
	elif scores[1] > scores[0]:
		winner = 1
	var board = cfc.NMAP.get("board")
	var campaign = is_instance_valid(board) and "campaign_match" in board \
			and board.campaign_match
	var title := "Draw!"
	if campaign:
		if winner == 0:
			title = "Victory!"
		elif winner == 1:
			title = "Defeat!"
		_back_button.text = "Return to Campaign"
	else:
		if winner == 0:
			title = "Player 1 wins!"
		elif winner == 1:
			title = "Player 2 wins!"
	_game_over_title.text = title
	_game_over_detail.text = (
			"Player 1 score: %d\nPlayer 2 score: %d\n"
			+ "Player %d can play every objective for %d resources."
	) % [scores[0], scores[1], player_id + 1, costs[player_id]]
	if is_instance_valid(board) and board.has_method("on_match_finished"):
		board.on_match_finished(winner)
	if not cfc.ut:
		cfc.game_paused = true
		_game_over.popup_centered_minsize()


func _on_back_to_main_pressed() -> void:
	cfc.game_paused = false
	cfc.quit_game()
	var board = cfc.NMAP.get("board")
	if is_instance_valid(board) and "campaign_match" in board \
			and board.campaign_match:
		# warning-ignore:return_value_discarded
		get_tree().change_scene(
				CFConst.PATH_CUSTOM + 'campaign/CampaignScreen.tscn')
		return
	get_tree().change_scene("res://src/custom/MainMenu.tscn")
