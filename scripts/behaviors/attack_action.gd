extends ActionLeaf


func tick(actor, blackboard: Blackboard):
	if actor.has_finished_attack_animation():
		actor.finish_attack()
		return SUCCESS

	if not actor.is_playing_attack_animation():
		actor.play_attack_animation()

	return RUNNING
