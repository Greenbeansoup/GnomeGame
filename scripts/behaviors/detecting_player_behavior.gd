extends ActionLeaf


func tick(actor, blackboard: Blackboard):
	# Sequence caches a passed condition and won't re-tick it while this action keeps
	# running, so re-check here for a hard stop the instant the player leaves the area.
	if not blackboard.get_value("is_player_in_detect_area", false) || blackboard.get_value("is_player_in_attack_area", false):
		actor.play_idle_animation()
		return FAILURE

	if actor.has_finished_detecting_animation():
		return SUCCESS

	if not actor.is_playing_detecting_animation():
		actor.play_detecting_animation()

	return RUNNING
