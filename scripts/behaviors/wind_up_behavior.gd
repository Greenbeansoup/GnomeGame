extends ActionLeaf



func tick(actor, blackboard: Blackboard):
	if actor.has_finished_windup_animation():
		return SUCCESS

	if not actor.is_playing_windup_animation():
		actor.play_windup_animation()

	return RUNNING
