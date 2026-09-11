@tool
extends ConditionLeaf


func tick(actor, blackboard: Blackboard):
	var has_player = blackboard.get_value("is_player_in_pursuit_range", false)

	if has_player:
		return SUCCESS
		
	return FAILURE
