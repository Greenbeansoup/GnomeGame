extends CharacterBody2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pursuit: PursuitBehavior = $PursuitBehavior
@onready var vault = $VaultBehavior
@onready var beehave_tree: BeehaveTree = $PursuitBehavior/BeehaveTree
@onready var detect_area: Area2D = $DetectArea
@onready var aggro_sight_cone: Area2D = $AggroSightCone
@onready var line_of_sight: RayCast2D = $LineOfSight
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detect_collision_shape: CollisionShape2D = $DetectArea/CollisionShape2D
@onready var hammer_collider: Area2D = $HammerCollider
@onready var hammer_collision_shape: CollisionShape2D = $HammerCollider/CollisionShape2D
@onready var aggro_collision_polygon: CollisionPolygon2D = $AggroSightCone/CollisionPolygon2D

@export_enum("Left:-1", "Right:1") var start_facing: int = -1
@export_range(1.0, 200.0, 1.0) var attack_range := 65.0
@export_range(1.0, 1000.0, 1.0) var pursuit_range := 150.0
@export_range(0.0, 1000.0, 1.0) var chase_speed := 195.0
@export_range(1.0, 500.0, 1.0) var chase_resume_distance := 48.0
@export_range(1.0, 64.0, 1.0) var vault_obstacle_height := 16.0
@export_range(1.0, 32.0, 1.0) var vault_probe_distance := 12.0
@export_range(-600.0, -200.0, 10.0) var vault_retry_jump_velocity := -300.0
@export_range(0.5, 10.0, 0.5) var stuck_pursuit_timeout := 2.0
@export_range(1.0, 32.0, 1.0) var stuck_pursuit_progress_distance := 4.0
@export var attack_push_velocity := Vector2(420.0, -240.0)
@export_range(0.0, 5.0, 0.05) var attack_recovery_time := 0.4
## How long the boss's behavior tree stays paused while it is pushed by a slow pendulum.
@export_range(0.05, 1.0, 0.05) var pendulum_push_control_duration := 0.3
@export var keep_chunks_alive := true
@export var keep_alive_group := &"chunk_keep_alive"
@export var ignore_home_chunk_keep_alive := true

const SPEED = 100.0
const JUMP_VELOCITY = -200.0
# Extra space beyond the boss body where it stops instead of changing direction.
const FACING_FLIP_BUFFER = 8.0
# Animations are authored at the Aseprite frame rate; these slow down playback at runtime.
const IDLE_SPEED_SCALE = 0.1
const DETECTING_SPEED_SCALE = 0.5

# Facing left (unflipped) by default; positive means facing right.
var facing_direction := -1.0
# AnimationPlayer clears current_animation once a non-looping animation ends, so the
# behaviour tree needs its own record of what was last requested and whether it finished.
var current_animation := ""
var spotted_animation_finished := false
var windup_animation_finished := false
var attack_animation_finished := false
var attack_hit_players: Array[Node] = []
var attack_recovery_timer := 0.0
var pendulum_push_timer := 0.0
var is_holding_chase_position := false
var is_dead := false
var chase_music_active := false

const DEBUG_AI := false

var idle_active_playback_speed := 0.5
@export var idle_active_flip_detection := false

func log_ai(msg: String) -> void:
	if DEBUG_AI:
		print("[AI %s] %s" % [name, msg])

func _ready():
	facing_direction = float(start_facing)
	pursuit.facing_direction = facing_direction
	aggro_sight_cone.scale.x = -facing_direction
	_apply_facing(facing_direction)
	if keep_chunks_alive:
		add_to_group(keep_alive_group)

	play_idle_animation()
	animation_player.animation_finished.connect(_on_animation_finished)
	pursuit.pursuit_changed.connect(_set_chase_music_active)
	pursuit.state_changed.connect(_on_pursuit_state_changed)
	pursuit.pursuit_range = pursuit_range
	pursuit.chase_speed = chase_speed
	pursuit.resume_distance = chase_resume_distance
	pursuit.stuck_timeout = stuck_pursuit_timeout
	pursuit.stuck_progress_distance = stuck_pursuit_progress_distance
	vault.obstacle_height = vault_obstacle_height
	vault.probe_distance = vault_probe_distance
	vault.jump_velocity = JUMP_VELOCITY
	vault.retry_jump_velocity = vault_retry_jump_velocity


func _on_pursuit_state_changed(_previous: PursuitBehavior.State, state: PursuitBehavior.State) -> void:
	if state == PursuitBehavior.State.IDLE:
		attack_recovery_timer = 0.0
		spotted_animation_finished = false
		windup_animation_finished = false
		attack_animation_finished = false
		is_holding_chase_position = false


func tick_pursuit_combat() -> bool:
	if is_playing_attack_animation():
		return true
	if has_finished_attack_animation():
		finish_attack()
		return true
	if can_attack_player(pursuit.target):
		play_attack_animation()
		return true
	return false

func _exit_tree() -> void:
	_set_chase_music_active(false)


func _set_chase_music_active(active: bool) -> void:
	if chase_music_active == active:
		return
	chase_music_active = active
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("set_chase_music_active"):
		game_manager.set_chase_music_active(self, active)


func _physics_process(delta):
	attack_recovery_timer = maxf(attack_recovery_timer - delta, 0.0)
	if is_dead:
		if not is_on_floor():
			velocity += get_gravity() * delta
		else:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		move_and_slide()
		return

	if pendulum_push_timer > 0.0:
		pendulum_push_timer = maxf(pendulum_push_timer - delta, 0.0)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		if is_zero_approx(pendulum_push_timer) and not is_dead:
			pursuit.enabled = true
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	pursuit.facing_direction = facing_direction
	pursuit.flip_detection = idle_active_flip_detection
	pursuit.update(delta)
	vault.update()
	_process_attack_hits()

	move_and_slide()

func can_attack_player(player: Node2D) -> bool:
	if not is_instance_valid(player):
		return false

	var offset := player.global_position - global_position
	return attack_recovery_timer <= 0.0 \
		and beehave_tree.blackboard.get_value("is_player_in_detect_area", false) \
		and beehave_tree.blackboard.get_value("player") == player \
		and offset.length() <= attack_range \
		and offset.x * facing_direction > 0.0

func apply_attack_push(push_velocity: Vector2) -> void:
	if is_dead:
		velocity = push_velocity
		return

	pendulum_push_timer = pendulum_push_control_duration
	pursuit.enabled = false
	velocity = push_velocity

func _process_attack_hits() -> void:
	if current_animation != "attack" or hammer_collision_shape.disabled:
		return

	for body in hammer_collider.get_overlapping_bodies():
		if not body.is_in_group("player") or body in attack_hit_players:
			continue

		attack_hit_players.append(body)
		if hammer_collision_shape.get_meta("push", false):
			var push_direction := signf(body.global_position.x - global_position.x)
			if is_zero_approx(push_direction):
				push_direction = facing_direction
			var push_velocity := Vector2(push_direction * attack_push_velocity.x, attack_push_velocity.y)
			if body.has_method("apply_attack_push"):
				body.apply_attack_push(push_velocity)
			else:
				body.velocity = push_velocity
		elif body.has_method("squash"):
			body.squash()

func _get_body_half_width() -> float:
	return body_collision_shape.shape.get_rect().size.x * 0.5

func take_damage() -> void:
	die_from_pendulum()

func die_from_pendulum() -> void:
	if is_dead:
		return

	is_dead = true
	_set_chase_music_active(false)
	velocity = Vector2.ZERO
	collision_layer = 0
	pursuit.stop()

	for player in get_tree().get_nodes_in_group("player"):
		if player is PhysicsBody2D:
			add_collision_exception_with(player)
	detect_collision_shape.set_deferred("disabled", true)
	hammer_collision_shape.set_deferred("disabled", true)
	aggro_collision_polygon.set_deferred("disabled", true)
	detect_area.set_deferred("monitoring", false)
	detect_area.set_deferred("monitorable", false)
	hammer_collider.set_deferred("monitoring", false)
	hammer_collider.set_deferred("monitorable", false)
	aggro_sight_cone.set_deferred("monitoring", false)
	aggro_sight_cone.set_deferred("monitorable", false)
	line_of_sight.enabled = false
	play_animation("kill")

func play_animation(anim_name: String, speed_scale: float = 1.0) -> void:
	var watching_without_target: bool = anim_name == "idleactive" \
		and not beehave_tree.blackboard.get_value("is_player_in_detect_area", false) \
		and not beehave_tree.blackboard.get_value("has_last_known_player_position", false)
	if anim_name == "idle" or watching_without_target:
		_set_chase_music_active(false)
	current_animation = anim_name
	animation_player.play(anim_name, -1.0, speed_scale)

func play_detecting_animation() -> void:
	play_animation("detecting", DETECTING_SPEED_SCALE)

func play_idle_animation() -> void:
	play_animation("idle", IDLE_SPEED_SCALE)

func is_playing_detecting_animation() -> bool:
	return current_animation == "detecting" and animation_player.is_playing()

func play_attack_animation() -> void:
	attack_animation_finished = false
	attack_hit_players.clear()
	velocity.x = 0.0
	play_animation("attack")

func finish_attack() -> void:
	attack_animation_finished = false
	spotted_animation_finished = true
	windup_animation_finished = true
	attack_recovery_timer = attack_recovery_time
	play_animation("running")


func has_finished_detecting_animation() -> bool:
	return current_animation == "detecting" and not animation_player.is_playing()

func play_spotted_animation() -> void:
	spotted_animation_finished = false
	play_animation("spotted")

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "spotted":
		spotted_animation_finished = true
	if anim_name == "windup":
		windup_animation_finished = true
	if anim_name == "attack":
		attack_animation_finished = true

func is_playing_spotted_animation() -> bool:
	return current_animation == "spotted" and not spotted_animation_finished


func has_finished_spotted_animation() -> bool:
	return spotted_animation_finished

func is_playing_attack_animation() -> bool:
	return current_animation == "attack" and not attack_animation_finished


func has_finished_attack_animation() -> bool:
	return current_animation == "attack" and attack_animation_finished

func face_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return

	var dx := player.global_position.x - global_position.x
	if not is_zero_approx(dx):
		facing_direction = signf(dx)
	_apply_facing(facing_direction)

func play_windup_animation() -> void:
	windup_animation_finished = false
	velocity.x = 0.0
	play_animation("windup")

func is_playing_windup_animation() -> bool:
	return current_animation == "windup" and not windup_animation_finished


func has_finished_windup_animation() -> bool:
	return windup_animation_finished

func chase_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return

	chase_position(player.global_position)


func chase_position(target_position: Vector2) -> bool:
	var dx := target_position.x - global_position.x
	var underfoot_buffer := _get_body_half_width() + FACING_FLIP_BUFFER
	var resume_distance := maxf(chase_resume_distance, underfoot_buffer)
	if is_holding_chase_position:
		is_holding_chase_position = absf(dx) < resume_distance
	elif absf(dx) <= underfoot_buffer:
		is_holding_chase_position = true

	if dx * facing_direction < -underfoot_buffer:
		facing_direction = signf(dx)

	velocity.x = 0.0 if is_holding_chase_position else facing_direction * chase_speed
	if is_holding_chase_position:
		if current_animation != "idleactive":
			play_animation("idleactive", idle_active_playback_speed)
	elif current_animation != "running":
		play_animation("running")
	_apply_facing(facing_direction)
	return is_holding_chase_position

func _apply_facing(direction: float) -> void:
	sprite.flip_h = direction > 0
	hammer_collider.scale.x = -1.0 if direction > 0 else 1.0
