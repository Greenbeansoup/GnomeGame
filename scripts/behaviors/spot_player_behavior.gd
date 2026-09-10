extends ActionLeaf


func tick(actor, blackboard: Blackboard):
	if actor.has_finished_spotted_animation():
		return SUCCESS

	if not actor.is_playing_spotted_animation():
		actor.play_spotted_animation()

	return RUNNING
