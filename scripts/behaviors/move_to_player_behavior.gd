extends ActionLeaf


func tick(actor, blackboard: Blackboard):
	var player = blackboard.get_value("player")

	if not is_instance_valid(player):
		return FAILURE

	actor.chase_player(player)
	return RUNNING
