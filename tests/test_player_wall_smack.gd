extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var floor_body := StaticBody2D.new()
	var floor_collision := CollisionShape2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(2000.0, 20.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position.y = 10.0
	root.add_child(floor_body)

	var player: Player = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame

	for trigger in [Player.SmackTrigger.WALL, Player.SmackTrigger.WALL_FORWARD]:
		player.position = Vector2(0.0, -100.0)
		player.velocity = Vector2(40.0, -20.0)
		player.move_and_slide()
		check(not player.is_on_floor(), "Test player is airborne")
		player.smack_trigger = trigger
		player.wall_smack_state = Player.WallSmackState.SMACK
		player._update_wall_smack_landing()
		player._update_animations(1.0)
		check(player.animated_sprite_2d.animation == player._get_smack_animation(), "Initial impact animation is preserved")

		# The rise ends before the impact animation finishes.
		player.velocity.y = 0.0
		player._on_animation_finished()
		player._update_wall_smack_landing()
		player._update_animations(1.0)
		check(player.animated_sprite_2d.animation == &"spinningclock", "Short upward smack spins at the apex")
		player.velocity.y = 80.0
		player._update_wall_smack_landing()
		player._update_animations(1.0)
		check(player.animated_sprite_2d.animation == &"spinningclock", "Spin continues throughout descent")

		player.position = Vector2.ZERO
		player.velocity = Vector2(40.0, 10.0)
		await physics_frame
		player.move_and_slide()
		check(player.is_on_floor(), "Test player lands")
		player._update_wall_smack_landing()
		var stunned_animation := &"stunnedfacedownextended" if trigger == Player.SmackTrigger.WALL_FORWARD else &"stunnedextended"
		player._update_animations(0.0)
		check(player.wall_smack_state == Player.WallSmackState.STUNNED, "Landing without input preserves the stun despite residual momentum")
		check(player.animated_sprite_2d.animation == stunned_animation, "Landing without input plays the matching stunned animation")
		check(not player.wall_smack_spin_until_landing, "Landing resets the spin latch")
		for frame_index in range(3):
			player._update_wall_smack_landing()
			player._update_animations(0.0)
			check(player.animated_sprite_2d.animation == stunned_animation, "Stun persists while no input is held")
		Input.action_press("right")
		player._update_wall_smack_landing()
		check(player.wall_smack_state == Player.WallSmackState.NONE, "Active input cancels the grounded stun")
		player.is_sprinting = true
		player._update_animations(1.0)
		check(player.animated_sprite_2d.animation == &"sprinting", "Landing restores sprinting with continued movement")
		player.is_sprinting = false
		player._update_animations(1.0)
		check(player.animated_sprite_2d.animation == &"walking", "Landing restores walking without sprint")
		player._update_animations(0.0)
		check(player.animated_sprite_2d.animation == &"default", "Landing restores normal idle without movement")
		Input.action_release("right")

		# A subsequent non-spinning impact must not inherit the spin latch.
		player.position.y = -100.0
		player.velocity = Vector2(0.0, 80.0)
		player.move_and_slide()
		player.wall_smack_state = Player.WallSmackState.FALL
		player._update_wall_smack_landing()
		player._update_animations(0.0)
		var fall_animation := &"fallafterwallsmackforward" if trigger == Player.SmackTrigger.WALL_FORWARD else &"fallafterwallsmack"
		check(player.animated_sprite_2d.animation == fall_animation, "Non-spinning impacts retain their falling animation")
		player.position = Vector2.ZERO
		player.velocity = Vector2(0.0, 10.0)
		await physics_frame
		player.move_and_slide()
		player._update_wall_smack_landing()
		player._update_animations(0.0)
		check(player.animated_sprite_2d.animation == stunned_animation, "Non-spinning impacts retain their stunned animation")
		player.wall_smack_state = Player.WallSmackState.NONE

		# Landing can also interrupt the initial impact before it finishes.
		player.position.y = -100.0
		player.velocity = Vector2(40.0, -20.0)
		player.move_and_slide()
		player.wall_smack_state = Player.WallSmackState.SMACK
		player._update_wall_smack_landing()
		player._update_animations(1.0)
		player.position = Vector2.ZERO
		player.velocity = Vector2(40.0, 10.0)
		Input.action_press("right")
		await physics_frame
		player.move_and_slide()
		player._update_wall_smack_landing()
		player._on_animation_finished()
		player._update_animations(1.0)
		check(player.wall_smack_state == Player.WallSmackState.NONE, "Early landing and late animation completion cannot restart the smack")
		check(player.animated_sprite_2d.animation == &"walking", "Early landing restores movement animation")
		Input.action_release("right")

		player.wall_smack_state = Player.WallSmackState.STUNNED
		Input.action_press("sprint")
		player._update_wall_smack_landing()
		check(player.wall_smack_state == Player.WallSmackState.NONE, "Non-directional gameplay input also cancels grounded stun")
		Input.action_release("sprint")

	# Exercise a real wall collision and continued held input through the full physics flow.
	var wall := StaticBody2D.new()
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(8.0, 120.0)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	wall.position = Vector2(16.0, -100.0)
	root.add_child(wall)
	player.position = Vector2(0.0, -100.0)
	player.velocity = Vector2(Player.SPRINT_SPEED, -120.0)
	Input.action_press("right")
	Input.action_press("sprint")
	await physics_frame
	for frame_index in range(10):
		player._physics_process(1.0 / 60.0)
		if player.wall_smack_state == Player.WallSmackState.SMACK:
			break
		await physics_frame
	check(player.wall_smack_state == Player.WallSmackState.SMACK, "Sprint-speed wall collision starts a smack")
	check(player.wall_smack_spin_until_landing, "Real wall collision captures the remaining upward momentum")
	wall.free()
	player._on_animation_finished()
	var saw_descending_spin := false
	for frame_index in range(120):
		await physics_frame
		player._physics_process(1.0 / 60.0)
		if player.is_on_floor():
			break
		if player.velocity.y > 0.0:
			saw_descending_spin = true
			check(player.animated_sprite_2d.animation == &"spinningclock", "Held sprint input preserves the descending spin")
	check(saw_descending_spin, "Physics integration reaches the descending spin")
	check(player.is_on_floor(), "Physics integration reaches the floor")
	check(player.wall_smack_state == Player.WallSmackState.NONE, "Physics landing clears the smack with held input")
	check(player.animated_sprite_2d.animation == &"sprinting", "Physics landing immediately resumes sprinting")
	Input.action_release("right")
	Input.action_release("sprint")
	await physics_frame

	player.wall_smack_state = Player.WallSmackState.FALL
	player.wall_smack_spin_until_landing = true
	Input.action_press("left")
	await physics_frame
	player._process_default_movement(1.0 / 60.0)
	check(player.wall_smack_state == Player.WallSmackState.NONE and not player.wall_smack_spin_until_landing, "Fresh input still cancels the smack and spin latch")
	Input.action_release("left")

	for trigger in [Player.SmackTrigger.WALL, Player.SmackTrigger.WALL_FORWARD]:
		player.smack_trigger = trigger
		player.wall_smack_state = Player.WallSmackState.STUNNED
		player.wall_smack_spin_until_landing = true
		player.is_digging = true
		player.is_digging_out = false
		player.dig_in_direction = Vector2i.DOWN
		player._update_animations(0.0)
		check(player.wall_smack_state == Player.WallSmackState.NONE and not player.wall_smack_spin_until_landing, "Digging permanently cancels the stun and spin latch")
		check(player.animated_sprite_2d.animation == &"dig", "Digging replaces the stunned animation")
		player._on_animation_finished()
		player.is_earthwalking = true
		player._update_animations(0.0)
		check(player.animated_sprite_2d.animation == &"earthwalk", "Stun does not return after the dig animation finishes")
		player.is_earthwalking = false

		player.wall_smack_state = Player.WallSmackState.STUNNED
		player.wall_smack_spin_until_landing = true
		player.enter_long_legs_mode()
		player._update_animations(0.0)
		check(player.is_long_legs, "Grounded player enters long legs mode")
		check(player.wall_smack_state == Player.WallSmackState.NONE and not player.wall_smack_spin_until_landing, "Entering long legs permanently cancels the stun and spin latch")
		check(player.animated_sprite_2d.animation == &"stretchup", "Long legs replaces the stunned animation")
		player.exit_long_legs_mode()
		player._update_animations(0.0)
		check(player.animated_sprite_2d.animation == &"default", "Stun does not return after exiting long legs")

	player.wall_smack_state = Player.WallSmackState.FALL
	player.wall_smack_spin_until_landing = true
	player.respawn_at(Vector2.ZERO)
	check(player.wall_smack_state == Player.WallSmackState.NONE and not player.wall_smack_spin_until_landing, "Respawn resets the smack and spin latch")

	player.gnome_legs.free()
	player.free()
	floor_body.free()
	print("Player wall smack tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
