extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var enemy := CharacterBody2D.new()
	var area := Area2D.new()
	enemy.add_child(area)
	var pursuit = load("res://scenes/pursuit_behavior.tscn").instantiate()
	pursuit.detect_area = area
	pursuit.automatic_update = false
	enemy.add_child(pursuit)
	root.add_child(enemy)
	var target := Node2D.new()
	root.add_child(target)
	target.position.x = -300.0
	pursuit.tick_behavior()
	check(pursuit.state == PursuitBehavior.State.IDLE, "Enemy begins idle")
	pursuit.observe_target(target)
	check(pursuit.state == PursuitBehavior.State.DETECTION, "Distant visible target triggers detection")
	target.position.x = -100.0
	pursuit.observe_target(target)
	pursuit.beehave_tree.tick()
	check(pursuit.state == PursuitBehavior.State.PURSUIT and enemy.velocity.x < 0.0, "Beehave drives pursuit without enemy-specific methods or animations")
	pursuit.lose_sight()
	pursuit.beehave_tree.tick()
	check(enemy.velocity.x < 0.0, "Lost target is pursued at last known position")
	enemy.position = target.position
	pursuit.beehave_tree.tick()
	check(pursuit.state == PursuitBehavior.State.IDLE_ACTIVE, "Reaching last known position enters active idle")
	pursuit.observe_target(target)
	check(pursuit.state == PursuitBehavior.State.PURSUIT, "Active idle can reacquire target")
	pursuit.lose_sight()
	pursuit.beehave_tree.tick()
	pursuit.update(pursuit.forget_time + 0.1)
	check(pursuit.state == PursuitBehavior.State.IDLE, "Active idle expires to idle")
	target.position.x = -400.0
	pursuit.pursuit_range = 500.0
	pursuit.observe_target(target)
	pursuit.beehave_tree.tick()
	pursuit.lose_sight()
	pursuit.update(pursuit.stuck_timeout + 0.1)
	check(pursuit.state == PursuitBehavior.State.IDLE_ACTIVE, "Stalled blind pursuit enters active idle")
	pursuit.stop()
	check(not pursuit.enabled and enemy.velocity.x == 0.0, "Stopping pursuit clears movement")
	pursuit.enabled = true
	var animations := AnimationPlayer.new()
	enemy.add_child(animations)
	var library := AnimationLibrary.new()
	for animation_name in [&"spotted", &"windup"]:
		var animation := Animation.new()
		animation.length = 0.1
		library.add_animation(animation_name, animation)
	animations.add_animation_library(&"", library)
	pursuit.animation_player = animations
	pursuit.observe_target(target)
	pursuit.tick_behavior()
	check(animations.current_animation == &"spotted" and enemy.velocity.x == 0.0, "Spotted animation gates movement")
	animations.advance(0.2)
	pursuit.tick_behavior()
	check(animations.current_animation == &"windup", "Windup follows completed spotted animation")
	animations.advance(0.2)
	pursuit.tick_behavior()
	check(enemy.velocity.x < 0.0, "Pursuit starts after preparation animations finish")
	pursuit.animation_player = null
	pursuit.reset()
	pursuit.pursuit_range = 150.0
	var area_shape := CollisionShape2D.new()
	var detection_shape := RectangleShape2D.new()
	detection_shape.size = Vector2(300.0, 100.0)
	area_shape.shape = detection_shape
	area.add_child(area_shape)
	var sensed_target := CharacterBody2D.new()
	sensed_target.add_to_group("player")
	var target_shape := CollisionShape2D.new()
	target_shape.shape = CircleShape2D.new()
	sensed_target.add_child(target_shape)
	sensed_target.position = enemy.position + Vector2(-80.0, 0.0)
	root.add_child(sensed_target)
	await physics_frame
	await physics_frame
	pursuit.update(0.016)
	check(pursuit.target == sensed_target, "Area2D sensing acquires a player in front")
	pursuit.reset()
	sensed_target.position = enemy.position + Vector2(80.0, 0.0)
	await physics_frame
	await physics_frame
	pursuit.update(0.016)
	check(pursuit.target == null, "Idle sensing rejects a player behind the enemy")
	sensed_target.free()
	enemy.free()
	target.free()
	for enemy_scene in ["res://scenes/sprinter_boss.tscn", "res://scenes/explode_gnome.tscn"]:
		for direction in [-1, 1]:
			var placed_enemy = load(enemy_scene).instantiate()
			placed_enemy.start_facing = direction
			var placed_sprite = placed_enemy.get_node("Sprite2D" if placed_enemy.has_node("Sprite2D") else "AnimatedSprite2D")
			var authored_transform: Transform2D = placed_sprite.transform
			if placed_enemy.has_node("AnimatedSprite2D") and direction > 0:
				authored_transform.origin.x = -authored_transform.origin.x
			root.add_child(placed_enemy)
			placed_enemy.set_physics_process(false)
			check(placed_sprite.transform.is_equal_approx(authored_transform), "Startup preserves authored sprite size and position: %s" % enemy_scene)
			check(placed_enemy.pursuit.facing_direction == float(direction), "Root start-facing setting initializes pursuit: %s" % enemy_scene)
			check(placed_enemy.sprite.flip_h == (direction > 0), "Root start-facing setting initializes sprite: %s" % enemy_scene)
			check(placed_enemy.pursuit.aggro_sight.scale.x == -float(direction), "Root start-facing setting initializes cone: %s" % enemy_scene)
			placed_enemy._physics_process(0.016)
			if placed_enemy.has_node("AnimationPlayer"):
				placed_enemy.get_node("AnimationPlayer").advance(0.1)
			check(placed_sprite.transform.is_equal_approx(authored_transform), "Idle playback preserves authored sprite size and position: %s" % enemy_scene)
			check(placed_enemy.pursuit.facing_direction == float(direction), "Initial facing survives the first physics tick: %s" % enemy_scene)
			if placed_enemy.has_node("AnimatedSprite2D"):
				placed_enemy._on_facing_changed(-float(direction))
				check(is_equal_approx(placed_sprite.position.x, -authored_transform.origin.x), "Turning mirrors the sprite offset around the enemy origin")
				placed_enemy._on_facing_changed(float(direction))
				check(placed_sprite.transform.is_equal_approx(authored_transform), "Turning back restores sprite alignment without drift")
			placed_enemy.free()
	var boss = load("res://scenes/sprinter_boss.tscn").instantiate()
	boss.chase_speed = 184.0
	root.add_child(boss)
	boss.set_physics_process(false)
	check(boss.pursuit.chase_speed == 184.0, "Chunk chase-speed override survives migration")
	var player := CharacterBody2D.new()
	root.add_child(player)
	player.position.x = -40.0
	boss.pursuit.observe_target(player)
	boss.pursuit.beehave_tree.tick()
	check(boss.current_animation == "attack", "Sprinter combat hook retains attack priority")
	boss.apply_attack_push(Vector2(100.0, -100.0))
	check(not boss.pursuit.enabled, "Push suspends pursuit")
	boss._physics_process(boss.pendulum_push_control_duration + 0.1)
	check(boss.pursuit.enabled, "Pursuit resumes after push")
	boss.die_from_pendulum()
	check(not boss.pursuit.enabled and boss.is_dead, "Death stops pursuit")
	boss.free()
	player.free()
	var gnome = load("res://scenes/explode_gnome.tscn").instantiate()
	root.add_child(gnome)
	gnome.set_physics_process(false)
	var gnome_target := CharacterBody2D.new()
	gnome_target.add_to_group("player")
	var gnome_target_shape := CollisionShape2D.new()
	gnome_target_shape.shape = CircleShape2D.new()
	gnome_target.add_child(gnome_target_shape)
	gnome_target.position = Vector2(-100.0, -8.0)
	root.add_child(gnome_target)
	await physics_frame
	await physics_frame
	gnome._physics_process(0.016)
	check(gnome.pursuit.target == gnome_target, "Explode gnome senses the player through its attached detection area")
	check(gnome.pursuit.state == PursuitBehavior.State.PURSUIT, "Explode gnome enters pursuit without sprinter hooks")
	check(gnome.position.x < 0.0 and gnome.velocity.x == -gnome.pursuit.chase_speed, "Explode gnome applies the component's horizontal movement")
	check(gnome.velocity.y > 0.0, "Explode gnome applies gravity")
	check(gnome.sprite.transform.x.x < 0.0, "Explode gnome sprite is cosmetically mirrored in its scene")
	check(not gnome.sprite.flip_h, "Explode gnome faces left while chasing left")
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == gnome_target, "Explode gnome tracks a visible player through its pursuit cone")
	var wall := StaticBody2D.new()
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(8.0, 80.0)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	wall.position = Vector2(-50.0, -8.0)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == null, "Explode gnome loses sight of a player behind a wall")
	wall.free()
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == gnome_target, "Explode gnome reacquires a player when the wall is removed")
	gnome_target.position = Vector2(100.0, -8.0)
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == gnome_target, "Explode gnome nearby awareness retains a player crossing behind it")
	check(gnome.sprite.flip_h and gnome.velocity.x > 0.0, "Explode gnome turns its sprite when pursuit changes direction")
	gnome.pursuit.update(0.016)
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.aggro_sight.scale.x < 0.0 and gnome.pursuit.target == gnome_target, "Explode gnome mirrors its pursuit cone to track a player on the right")
	for direction in [-1.0, 1.0, -1.0, 1.0]:
		gnome_target.position = gnome.position + Vector2(direction * 90.0, -8.0)
		await physics_frame
		await physics_frame
		for step in range(5):
			gnome.pursuit.update(0.016)
			check(gnome.pursuit.target == gnome_target and gnome.pursuit.state == PursuitBehavior.State.PURSUIT, "Nearby crossover does not interrupt pursuit")
			check(gnome.velocity.x == direction * gnome.pursuit.chase_speed, "Nearby crossover maintains movement toward the player")
	gnome_target.position = gnome.position + Vector2(10.0, -8.0)
	await physics_frame
	await physics_frame
	for step in range(5):
		gnome.pursuit.update(0.016)
		check(gnome.pursuit.target == gnome_target and gnome.velocity.x == 0.0, "Nearby player is tracked without stop-start jitter")
	gnome.pursuit.reset()
	check(gnome.pursuit.state == PursuitBehavior.State.IDLE and gnome.velocity.x == 0.0, "Explode gnome returns to stationary idle")
	gnome.pursuit.facing_direction = -1.0
	gnome_target.position = gnome.position + Vector2(90.0, -8.0)
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == gnome_target and gnome.velocity.x > 0.0, "Idle explode gnome notices a nearby player behind it")
	gnome.pursuit.reset()
	gnome.pursuit.facing_direction = -1.0
	gnome_target.position = gnome.position + Vector2(200.0, -8.0)
	await physics_frame
	await physics_frame
	gnome.pursuit.update(0.016)
	check(gnome.pursuit.target == null, "Rear awareness does not grant unlimited detection behind the enemy")
	gnome.free()
	gnome_target.free()
	print("Pursuit tests: %d failure(s)" % failures)
	quit(1 if failures else 0)