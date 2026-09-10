extends CharacterBody2D
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var beehave_tree = $BeehaveTree
@onready var detect_area = $DetectArea
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

var forget_timer: Timer

const SPEED = 100.0
const JUMP_VELOCITY = -400.0
const CHASE_SPEED = 195.0
# Extra space beyond the boss body where it stops instead of changing direction.
const FACING_FLIP_BUFFER = 8.0
# Extra detection distance behind the boss body, rather than behind its center.
const DETECTION_REAR_BUFFER = 16.0
# How close the player must be (in pixels) to escalate from detecting to attack pursuit.
const ATTACK_RANGE = 200.0

# Facing left (unflipped) by default; positive means facing right.
var facing_direction := -1.0
# Tracked explicitly instead of via is_playing(), since that can't be relied on to flip
# false the instant a non-looping animation completes.
var spotted_animation_finished := false

const DEBUG_AI := true

func log_ai(msg: String) -> void:
	if DEBUG_AI:
		print("[AI %s] %s" % [name, msg])

func _ready():
	animated_sprite_2d.sprite_frames.set_animation_speed("idle", 1)
	play_idle_animation()
	animated_sprite_2d.animation_finished.connect(_on_animated_sprite_animation_finished)
	
	detect_area.body_entered.connect(_on_player_entered_detect_area)
	detect_area.body_exited.connect(_on_player_exited_detect_area)
	
	forget_timer = Timer.new()
	forget_timer.wait_time = 5.0
	forget_timer.one_shot = true
	add_child(forget_timer)
	
	# Connect the timer's timeout signal to our cleanup function
	forget_timer.timeout.connect(_on_forget_timer_timeout)

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	_refresh_player_detection()
	_update_attack_range()

	move_and_slide()

func _refresh_player_detection() -> void:
	var player := _get_overlapping_player()
	if is_instance_valid(player) and _is_player_in_detection_view(player):
		_set_detected_player(player)
	elif not beehave_tree.blackboard.get_value("is_player_in_attack_area", false):
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
	if not beehave_tree.blackboard.get_value("is_player_in_detect_area", false):
		return

	beehave_tree.blackboard.set_value("is_player_in_detect_area", false)
	beehave_tree.blackboard.set_value("player", null)
	velocity.x = 0
	play_idle_animation()
	log_ai("DETECT CLEARED (player outside facing view)")

func _update_attack_range() -> void:
	# Attack pursuit is now a distance check against the single DetectArea's tracked
	# player, rather than a second (easy to desync) Area2D.
	if not beehave_tree.blackboard.get_value("is_player_in_detect_area", false):
		return

	var player = beehave_tree.blackboard.get_value("player")
	if not is_instance_valid(player):
		return

	var distance = absf(player.global_position.x - global_position.x)
	var was_in_attack_range = beehave_tree.blackboard.get_value("is_player_in_attack_area", false)
	# X-distance alone isn't enough: the player can be horizontally close but have
	# dropped out of DetectArea's actual (vertically limited) shape entirely.
	var in_range = distance <= ATTACK_RANGE and detect_area.overlaps_body(player)

	if in_range:
		if not was_in_attack_range:
			log_ai("ATTACK RANGE ENTER distance=%.1f" % distance)
		forget_timer.stop()
		beehave_tree.blackboard.set_value("is_player_in_attack_area", true)
	elif was_in_attack_range and forget_timer.is_stopped():
		# Out of range but still detected: start the 5-second grace period before giving up
		# the chase, instead of dropping it the instant they step outside ATTACK_RANGE.
		log_ai("ATTACK RANGE EXIT distance=%.1f (forget_timer started)" % distance)
		forget_timer.start()

func _on_player_entered_detect_area(body: Node2D) -> void:
	if body.is_in_group("player") and _is_player_in_detection_view(body):
		_set_detected_player(body)

func _on_player_exited_detect_area(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	log_ai("DETECT EXIT raw self=%s player=%s diff=%s" % [global_position, body.global_position, body.global_position - global_position])

	if beehave_tree.blackboard.get_value("is_player_in_attack_area", false):
		# A chase is active: don't clear the player just because they left this outer
		# sensor, let the attack-range grace timer decide when to give up instead.
		log_ai("DETECT EXIT player=%s but chase active, deferring to grace timer" % body.name)
		return

	_clear_detected_player()
	log_ai("DETECT EXIT player=%s (player cleared)" % body.name)

func _on_forget_timer_timeout() -> void:
	# 5 seconds outside ATTACK_RANGE without closing back in. Drop back to detecting
	# (still tracked via DetectArea) instead of abandoning the chase outright.
	beehave_tree.blackboard.set_value("is_player_in_attack_area", false)
	velocity.x = 0
	log_ai("FORGET_TIMER timeout (attack flag cleared)")

	# The player may have already physically left DetectArea while the grace period was
	# running (that exit was deferred above); finish it now if they're still outside.
	var player = beehave_tree.blackboard.get_value("player")
	if is_instance_valid(player) and not detect_area.get_overlapping_bodies().has(player):
		beehave_tree.blackboard.set_value("is_player_in_detect_area", false)
		beehave_tree.blackboard.set_value("player", null)
		play_idle_animation()
		log_ai("FORGET_TIMER finalized deferred DETECT EXIT")

func play_detecting_animation() -> void:
	animated_sprite_2d.play("detecting")

func play_idle_animation() -> void:
	animated_sprite_2d.play("idle")

func is_playing_detecting_animation() -> bool:
	return animated_sprite_2d.animation == "detecting" and animated_sprite_2d.is_playing()


func has_finished_detecting_animation() -> bool:
	return animated_sprite_2d.animation == "detecting" and not animated_sprite_2d.is_playing()

func play_spotted_animation() -> void:
	spotted_animation_finished = false
	animated_sprite_2d.play("spotted")

func _on_animated_sprite_animation_finished() -> void:
	if animated_sprite_2d.animation == "spotted":
		spotted_animation_finished = true

func is_playing_spotted_animation() -> bool:
	return animated_sprite_2d.animation == "spotted" and not spotted_animation_finished


func has_finished_spotted_animation() -> bool:
	return animated_sprite_2d.animation == "spotted" and spotted_animation_finished

func chase_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return

	var dx := player.global_position.x - global_position.x
	var underfoot_buffer := _get_body_half_width() + FACING_FLIP_BUFFER
	if dx * facing_direction < -underfoot_buffer:
		facing_direction = signf(dx)

	velocity.x = 0.0 if absf(dx) <= underfoot_buffer else facing_direction * CHASE_SPEED
	_apply_facing(facing_direction)

func _apply_facing(direction: float) -> void:
	animated_sprite_2d.flip_h = direction > 0
