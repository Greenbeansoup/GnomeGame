extends ConditionLeaf


func tick(actor, blackboard: Blackboard):
	var player = blackboard.get_value("player")

	if is_instance_valid(player) and actor.can_attack_player(player):
		return SUCCESS

	return FAILURE
