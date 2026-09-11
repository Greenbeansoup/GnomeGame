extends CharacterBody2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var beehave_tree = $BeehaveTree
@onready var detect_area = $DetectArea
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hammer_collider: Area2D = $HammerCollider
@onready var hammer_collision_shape: CollisionShape2D = $HammerCollider/CollisionShape2D

@export_range(1.0, 200.0, 1.0) var attack_range := 65.0
@export_range(1.0, 1000.0, 1.0) var pursuit_range := 150.0
@export_range(0.0, 1000.0, 1.0) var chase_speed := 195.0
@export var attack_push_velocity := Vector2(320.0, -180.0)
@export_range(0.0, 5.0, 0.05) var attack_recovery_time := 0.4

var forget_timer: Timer

const SPEED = 100.0
const JUMP_VELOCITY = -400.0
# Extra space beyond the boss body where it stops instead of changing direction.
const FACING_FLIP_BUFFER = 8.0
# Extra detection distance behind the boss body, rather than behind its center.
const DETECTION_REAR_BUFFER = 16.0
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

const DEBUG_AI := false

func log_ai(msg: String) -> void:
	if DEBUG_AI:
		print("[AI %s] %s" % [name, msg])

func _ready():
	play_idle_animation()
	animation_player.animation_finished.connect(_on_animation_finished)
	
	detect_area.body_entered.connect(_on_player_entered_detect_area)
	detect_area.body_exited.connect(_on_player_exited_detect_area)
	
	forget_timer = Timer.new()
	forget_timer.wait_time = 5.0
	forget_timer.one_shot = true
	add_child(forget_timer)
	
	# Connect the timer's timeout signal to our cleanup function
	forget_timer.timeout.connect(_on_forget_timer_timeout)

func _physics_process(delta):
	attack_recovery_timer = maxf(attack_recovery_timer - delta, 0.0)

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	_refresh_player_detection()
	_update_pursuit_range()
	_process_attack_hits()

	move_and_slide()

func can_attack_player(player: Node2D) -> bool:
	if not is_instance_valid(player):
		return false

	var offset := player.global_position - global_position
	return attack_recovery_timer <= 0.0 \
		and detect_area.overlaps_body(player) \
		and offset.length() <= attack_range \
		and offset.x * facing_direction > 0.0

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

func _refresh_player_detection() -> void:
	var player := _get_overlapping_player()
	if is_instance_valid(player) and _is_player_in_detection_view(player):
		_set_detected_player(player)
	elif not beehave_tree.blackboard.get_value("is_player_in_pursuit_range", false):
		_clear_detected_player()

func _get_overlapping_player() -> Node2D:
	for body in detect_area.get_overlapping_bodies():
		if body is Node2D and body.is_in_group("player"):
			return body
	return null

func _is_player_in_detection_view(player: Node2D) -> bool:
	var horizontal_offset := player.global_position.x - global_position.x
	return horizontal_offset * facing_direction >= -(_get_body_half_width() + DETECTION_REAR_BUFFER)

func _get_body_half_width() -> float:
	return body_collision_shape.shape.get_rect().size.x * 0.5

func _set_detected_player(player: Node2D) -> void:
	var was_detected = beehave_tree.blackboard.get_value("is_player_in_detect_area", false)
	beehave_tree.blackboard.set_value("is_player_in_detect_area", true)
	beehave_tree.blackboard.set_value("player", player)
	if not was_detected:
		log_ai("DETECT ENTER player=%s" % player.name)

func _clear_detected_player() -> void:
	var had_target = beehave_tree.blackboard.get_value("is_player_in_detect_area", false) \
		or beehave_tree.blackboard.get_value("is_player_in_pursuit_range", false) \
		or is_instance_valid(beehave_tree.blackboard.get_value("player"))
	if not had_target:
		return

	beehave_tree.blackboard.set_value("is_player_in_detect_area", false)
	beehave_tree.blackboard.set_value("is_player_in_pursuit_range", false)
	beehave_tree.blackboard.set_value("player", null)
	forget_timer.stop()
	attack_recovery_timer = 0.0
	spotted_animation_finished = false
	windup_animation_finished = false
	attack_animation_finished = false
	velocity.x = 0.0
	play_idle_animation()
	log_ai("DETECT CLEARED (player outside facing view)")

func _update_pursuit_range() -> void:
	# Pursuit is a distance check against the single DetectArea's tracked
	# player, rather than a second (easy to desync) Area2D.
	if not beehave_tree.blackboard.get_value("is_player_in_detect_area", false):
		return

	var player = beehave_tree.blackboard.get_value("player")
	if not is_instance_valid(player):
		return

	var distance = absf(player.global_position.x - global_position.x)
	var was_in_pursuit_range = beehave_tree.blackboard.get_value("is_player_in_pursuit_range", false)
	# X-distance alone isn't enough: the player can be horizontally close but have
	# dropped out of DetectArea's actual (vertically limited) shape entirely.
	var in_range = distance <= pursuit_range and detect_area.overlaps_body(player)

	if in_range:
		if not was_in_pursuit_range:
			log_ai("PURSUIT RANGE ENTER distance=%.1f" % distance)
		forget_timer.stop()
		beehave_tree.blackboard.set_value("is_player_in_pursuit_range", true)
	elif was_in_pursuit_range and forget_timer.is_stopped():
		# Out of range but still detected: start the 5-second grace period before giving up
		# the chase, instead of dropping it the instant they step outside pursuit_range.
		log_ai("PURSUIT RANGE EXIT distance=%.1f (forget_timer started)" % distance)
		forget_timer.start()

func _on_player_entered_detect_area(body: Node2D) -> void:
	if body.is_in_group("player") and _is_player_in_detection_view(body):
		_set_detected_player(body)

func _on_player_exited_detect_area(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	log_ai("DETECT EXIT raw self=%s player=%s diff=%s" % [global_position, body.global_position, body.global_position - global_position])

	if beehave_tree.blackboard.get_value("is_player_in_pursuit_range", false):
		# A chase is active: don't clear the player just because they left this outer
		# sensor, let the attack-range grace timer decide when to give up instead.
		log_ai("DETECT EXIT player=%s but chase active, deferring to grace timer" % body.name)
		return

	_clear_detected_player()
	log_ai("DETECT EXIT player=%s (player cleared)" % body.name)

func _on_forget_timer_timeout() -> void:
	# 5 seconds outside pursuit_range without closing back in. Drop back to detecting
	# (still tracked via DetectArea) instead of abandoning the chase outright.
	var player = beehave_tree.blackboard.get_value("player")
	if not is_instance_valid(player) or not detect_area.overlaps_body(player):
		_clear_detected_player()
		log_ai("FORGET_TIMER finalized deferred DETECT EXIT")
		return

	beehave_tree.blackboard.set_value("is_player_in_pursuit_range", false)
	velocity.x = 0.0
	log_ai("FORGET_TIMER timeout (attack flag cleared)")

func play_animation(anim_name: String, speed_scale: float = 1.0) -> void:
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

	var dx := player.global_position.x - global_position.x
	var underfoot_buffer := _get_body_half_width() + FACING_FLIP_BUFFER
	if dx * facing_direction < -underfoot_buffer:
		facing_direction = signf(dx)

	velocity.x = 0.0 if absf(dx) <= underfoot_buffer else facing_direction * chase_speed
	if current_animation != "running":
		play_animation("running")
	_apply_facing(facing_direction)

func _apply_facing(direction: float) -> void:
	sprite.flip_h = direction > 0
	hammer_collider.scale.x = -1.0 if direction > 0 else 1.0
