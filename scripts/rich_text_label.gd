extends RichTextLabel

@export_enum("Jump", "Dig", "Dig Out", "Dig Directional", "Sprint") var hint_type: String = "Jump"

func _ready():
	_update_hint()


func _process(_delta):
	_update_hint()


func _update_hint():
	var action = &"jump" if hint_type == "Jump" else &"sprint" if hint_type == "Sprint" else &"dig"
	var action_label = "Jump" if hint_type == "Jump" else "Dig Out" if hint_type == "Dig Out" else "Sprint" if hint_type == "Sprint" else "Dig"
	var buttons: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		buttons.append(event.as_text().split("-", false, 1)[0].strip_edges())

	var button_label = " / ".join(buttons)
	if button_label.is_empty():
		button_label = "Unassigned"

	var prompt = "%s + Direction to Dig Directionally" % button_label if hint_type == "Dig Directional" else "%s to %s" % [button_label, action_label]
	if text != prompt:
		text = prompt
