@tool
extends ActionLeaf


func tick(actor, blackboard: Blackboard):
	# Sequence caches PlayerSpotted's success and won't re-tick it while this action
	# keeps running, so re-check the pursuit flag directly for a hard stop the instant
	# the grace timer clears it - otherwise the chase never actually ends.
	if not blackboard.get_value("is_player_in_pursuit_range", false):
		actor.log_ai("MoveToPlayer tick -> FAILURE (pursuit flag cleared)")
		actor.velocity.x = 0.0
		if not blackboard.get_value("is_player_in_detect_area", false):
			actor.play_idle_animation()
		return FAILURE

	if blackboard.get_value("is_player_in_detect_area", false):
		var player = blackboard.get_value("player")
		if not is_instance_valid(player):
			actor.log_ai("MoveToPlayer tick -> FAILURE (player=%s)" % str(player))
			actor.velocity.x = 0.0
			return FAILURE
		actor.chase_player(player)
	elif blackboard.get_value("has_last_known_player_position", false):
		actor.chase_position(blackboard.get_value("last_known_player_position"))
	else:
		actor.log_ai("MoveToPlayer tick -> FAILURE (no last known position)")
		actor.velocity.x = 0.0
		return FAILURE

	return RUNNING
