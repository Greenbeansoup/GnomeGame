extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func make_box(size: Vector2, location: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = location
	root.add_child(body)
	return body


func _run() -> void:
	var floor_body := make_box(Vector2(2000.0, 20.0), Vector2(0.0, 10.0))
	var player: Player = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	player.velocity = Vector2(0.0, 10.0)
	player.move_and_slide()
	check(player.is_on_floor(), "Sprint test player is grounded")
	Input.action_press("right")
	Input.action_press("sprint")
	await physics_frame

	for duration in [0.3, 0.6]:
		player.sprint_wind_up_duration = duration
		for delta in [duration / 6.0, duration / 12.0]:
			player.velocity.x = 0.0
			var steps := roundi(duration / delta)
			for step in range(steps):
				player._process_default_movement(delta)
				var expected_speed := Player.SPEED + (Player.SPRINT_SPEED - Player.SPEED) * float(step + 1) / steps
				check(is_equal_approx(player.velocity.x, expected_speed), "Sprint ramp follows configured duration regardless of timestep")
				if step < steps - 1:
					check(player.velocity.x < Player.SPRINT_SPEED, "Sprint stays below the stun threshold before wind-up completes")
			player._process_default_movement(delta)
			check(player.velocity.x == Player.SPRINT_SPEED, "Sprint caps at maximum speed")

	Input.action_release("right")
	Input.action_press("left")
	player._process_default_movement(0.1)
	check(player.velocity.x < -Player.SPEED and player.velocity.x > -Player.SPRINT_SPEED, "Reversing starts a new wind-up")
	Input.action_release("sprint")
	player._process_default_movement(0.1)
	check(player.velocity.x == -Player.SPEED, "Releasing sprint immediately returns to walking speed")
	Input.action_release("left")
	player._process_default_movement(0.1)
	check(player.velocity.x == 0.0, "Releasing direction preserves responsive grounded stopping")
	Input.action_press("right")
	Input.action_press("sprint")
	player.sprint_unlocked = false
	player._process_default_movement(0.1)
	check(player.velocity.x == Player.SPEED and not player.is_sprinting, "Locked sprint retains normal walking")
	player.sprint_unlocked = true
	player.sprint_wind_up_duration = 0.3

	var wall := make_box(Vector2(8.0, 120.0), Vector2(16.0, -50.0))
	await physics_frame
	for frame_index in range(60):
		await physics_frame
		player._physics_process(1.0 / 60.0)
		check(player.wall_smack_state == Player.WallSmackState.NONE, "Holding sprint into an adjacent wall never causes a smack")
	check(player.is_on_wall(), "Adjacent-wall test actually collides")
	wall.free()
	player.position = Vector2.ZERO
	player.velocity = Vector2(0.0, 10.0)
	wall = make_box(Vector2(8.0, 120.0), Vector2(150.0, -50.0))
	await physics_frame
	var reached_max_speed := false
	for frame_index in range(120):
		await physics_frame
		player._physics_process(1.0 / 60.0)
		reached_max_speed = reached_max_speed or player.velocity.x == Player.SPRINT_SPEED
		if player.wall_smack_state == Player.WallSmackState.SMACK:
			break
	check(reached_max_speed, "Open runway allows reaching maximum sprint speed")
	check(player.wall_smack_state == Player.WallSmackState.SMACK, "Full-speed impact still starts the wall smack")
	wall.free()

	player.wall_smack_state = Player.WallSmackState.NONE
	player.position = Vector2(0.0, -100.0)
	player.velocity = Vector2.ZERO
	player.move_and_slide()
	player._process_default_movement(1.0 / 60.0)
	check(player.velocity.x == Player.AIR_ACCELERATION, "Airborne sprint steering remains unchanged")
	Input.action_release("right")
	Input.action_release("sprint")
	player.gnome_legs.free()
	player.free()
	floor_body.free()
	print("Player sprint tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
