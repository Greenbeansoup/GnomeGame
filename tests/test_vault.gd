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
	var floor_body := make_box(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	var enemy := CharacterBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16.0, 16.0)
	collision.shape = shape
	collision.position.y = -8.0
	enemy.add_child(collision)
	var vault = load("res://scenes/vault_behavior.tscn").instantiate()
	vault.body_shape = collision
	enemy.add_child(vault)
	root.add_child(enemy)
	await physics_frame
	enemy.velocity = Vector2(0.0, 10.0)
	enemy.move_and_slide()
	check(enemy.is_on_floor(), "Test actor is grounded")
	var obstacle := make_box(Vector2(8.0, 8.0), Vector2(16.0, -4.0))
	await physics_frame
	await physics_frame
	check(vault.has_low_obstacle_ahead(1.0), "Low obstacle is detected ahead")
	check(not vault.has_low_obstacle_ahead(-1.0), "Probe follows movement direction")
	enemy.velocity.x = 100.0
	vault.update()
	check(enemy.velocity.y == vault.jump_velocity and vault.jump_attempts == 1, "First grounded attempt uses normal jump")
	vault.update()
	check(enemy.velocity.y == vault.retry_jump_velocity and vault.jump_attempts == 2, "Blocked retry uses stronger jump")
	enemy.velocity.y = 0.0
	vault.update()
	check(enemy.velocity.y == 0.0, "Attempt limit prevents endless jumps without progress")
	enemy.velocity.x = 0.0
	vault.update()
	check(vault.jump_attempts == 0 and not vault.jump_pending, "Stopping resets vault state")
	obstacle.free()
	var wall := make_box(Vector2(8.0, 80.0), Vector2(16.0, -40.0))
	await physics_frame
	await physics_frame
	check(not vault.has_low_obstacle_ahead(1.0), "Tall walls are not vaultable")
	enemy.velocity = Vector2(100.0, 0.0)
	vault.update()
	check(enemy.velocity.y == 0.0, "Tall wall does not trigger jump")
	vault.enabled = false
	vault.jump_pending = true
	vault.update()
	check(not vault.jump_pending, "Disabled vault clears pending jumps")
	wall.free()
	enemy.free()
	for enemy_scene in ["res://scenes/explode_gnome.tscn", "res://scenes/sprinter_boss.tscn"]:
		var placed_enemy = load(enemy_scene).instantiate()
		placed_enemy.start_facing = 1
		root.add_child(placed_enemy)
		placed_enemy.set_physics_process(false)
		var body_shape: CollisionShape2D = placed_enemy.vault.body_shape
		var body_rect := body_shape.shape.get_rect()
		placed_enemy.position.y -= body_shape.to_global(Vector2(body_rect.get_center().x, body_rect.end.y)).y
		await physics_frame
		placed_enemy.velocity = Vector2(0.0, 10.0)
		placed_enemy.move_and_slide()
		check(placed_enemy.is_on_floor(), "Enemy scene is grounded: %s" % enemy_scene)
		var low_step := make_box(Vector2(8.0, 8.0), Vector2(body_rect.size.x * 0.5 + 8.0, -4.0))
		var destination := Node2D.new()
		destination.position = Vector2(150.0, placed_enemy.position.y)
		root.add_child(destination)
		await physics_frame
		await physics_frame
		placed_enemy.pursuit.observe_target(destination)
		placed_enemy.pursuit._preparation_step = 2
		placed_enemy._physics_process(0.016)
		check(placed_enemy.velocity.y < 0.0 and placed_enemy.vault.jump_attempts == 1, "Pursuing enemy vaults a low obstacle: %s" % enemy_scene)
		low_step.free()
		destination.free()
		placed_enemy.free()
	floor_body.free()
	print("Vault tests: %d failure(s)" % failures)
	quit(1 if failures else 0)