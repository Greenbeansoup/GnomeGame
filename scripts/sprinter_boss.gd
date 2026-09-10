extends CharacterBody2D
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var beehave_tree = $BeehaveTree
@onready var attack_area: Area2D = $AttackArea

var forget_timer: Timer

const SPEED = 100.0
const JUMP_VELOCITY = -400.0
const CHASE_SPEED = 195.0
# Player must be this far past the current facing direction before the rat flips around,
# preventing rapid flip-flopping when they're directly overhead.
const FACING_FLIP_BUFFER = 8.0

# Facing left (unflipped) by default; positive means facing right.
var facing_direction := -1.0

func _ready():
	animated_sprite_2d.sprite_frames.set_animation_speed("idle", 1)
	animated_sprite_2d.play("idle")
	
	attack_area.body_entered.connect(_on_player_entered)
	attack_area.body_exited.connect(_on_player_exited)
	
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


	move_and_slide()

func _on_player_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# If the timer was running down, stop it because the player is back!
		forget_timer.stop()
		
		# Tell the behavior tree the player is here
		beehave_tree.blackboard.set_value("is_player_in_area", true)
		beehave_tree.blackboard.set_value("player", body)

func _on_player_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Player left the view! Start the 5-second countdown clock
		forget_timer.start()

func _on_forget_timer_timeout() -> void:
	# 5 seconds have passed without seeing the player. Clear the data!
	beehave_tree.blackboard.set_value("is_player_in_area", false)
	beehave_tree.blackboard.set_value("player", null)
	velocity.x = 0
	animated_sprite_2d.play("idle")

func play_spotted_animation() -> void:
	animated_sprite_2d.play("spotted")

func is_playing_spotted_animation() -> bool:
	return animated_sprite_2d.animation == "spotted" and animated_sprite_2d.is_playing()

func has_finished_spotted_animation() -> bool:
	return animated_sprite_2d.animation == "spotted" and not animated_sprite_2d.is_playing()

func chase_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return

	var dx := player.global_position.x - global_position.x
	if absf(dx) > FACING_FLIP_BUFFER:
		facing_direction = signf(dx)

	# Standing still while the player is within the buffer avoids jittering back and
	# forth across their position, which would also cause repeated facing flips.
	velocity.x = 0.0 if absf(dx) <= FACING_FLIP_BUFFER else facing_direction * CHASE_SPEED
	_apply_facing(facing_direction)

func _apply_facing(direction: float) -> void:
	animated_sprite_2d.flip_h = direction > 0
	# AttackArea's detection shape is offset toward the default (left) facing side, so
	# mirror it whenever the rat flips to keep the bias in front of it.
	attack_area.scale.x = -1.0 if direction > 0 else 1.0
