extends ConditionLeaf


func tick(actor, blackboard: Blackboard):
	var has_player = blackboard.get_value("is_player_in_detect_area", false)
	
	if has_player:
		return SUCCESS
		
	return FAILURE
