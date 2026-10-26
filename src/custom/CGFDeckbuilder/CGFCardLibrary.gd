extends CardLibrary

const PlueyFolderNav = preload("res://src/custom/CGFDeckbuilder/PlueyFolderNav.gd")

onready var back_button := $VBC/HBC/MC/AvailableCards/Settings/Back
var abilities_header : RichTextLabel
# Filters the available cards by the card "Folder" property
var folder_nav

func _ready() -> void:
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed",self,"_on_viewport_resized")
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

# Populates the list of available cards, with all defined cards in the game
func populate_available_cards() -> void:
	.populate_available_cards()
	abilities_header = _card_headers.get_node("Abilities")
	abilities_header.rect_min_size.x = get_viewport().size.x / 2

# Resizes the abilities header to match the window size.
# So that the abilities have the most space to show.
func _on_viewport_resized() -> void:
	# On resize down, for some reason, the name doesn't automatically resize properly
	# Only manually tweaking the window size fixes it. I haven't found a proper solution yet
	abilities_header.rect_min_size.x = get_viewport().size.x / 2

	
