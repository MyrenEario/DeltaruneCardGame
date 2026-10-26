extends DeckBuilder

const PlueyFolderNav = preload("res://src/custom/CGFDeckbuilder/PlueyFolderNav.gd")

onready var back_button := $VBC/HBC/DeckMC/CurrentDeck/Buttons/Back

# Filters the available cards by the card "Folder" property
var folder_nav


func _ready() -> void:
	folder_nav = PlueyFolderNav.new()
	var opt := OptionButton.new()
	opt.name = "FolderFilter"
	opt.rect_min_size = Vector2(150, 0)
	var settings := $VBC/HBC/MC/AvailableCards/Settings
	settings.add_child(opt)
	settings.move_child(opt, 0)
	folder_nav.setup(self, opt)
	var headers = $VBC/HBC/MC/AvailableCards/CardListHeaders
	headers.visible = not cfc.game_settings.get('deckbuilder_gridstyle', true)


func _check_custom_filters(_card_object: CVListCardObject) -> bool:
	if folder_nav == null:
		return true
	return folder_nav.matches(_card_object.card_properties)
