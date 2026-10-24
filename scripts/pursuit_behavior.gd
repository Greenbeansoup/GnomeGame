class_name PursuitBehavior
extends Node

signal state_changed(previous: State, current: State)
signal pursuit_changed(active: bool)
signal target_changed(target: Node2D)
signal facing_changed(direction: float)

enum State { IDLE, DETECTION, PURSUIT, IDLE_ACTIVE }

@export var actor: CharacterBody2D
@export var animation_player: AnimationPlayer
@export var detect_area: Area2D
@export var aggro_sight: Area2D
@export var line_of_sight: RayCast2D
@export var body_shape: CollisionShape2D
@export var target_group: StringName = &"player"
@export var enabled := true
@export var automatic_update := true
@export_group("Pursuit")
@export var pursuit_range := 150.0
@export var chase_speed := 195.0
@export var stop_distance := 18.0
@export var resume_distance := 48.0
@export var rear_detection_buffer := 16.0
@export_range(0.0, 500.0, 1.0) var rear_awareness_range := 0.0
@export var facing_direction := -1.0
@export var flip_detection := false
@export var forget_time := 5.0
@export var stuck_timeout := 2.0
@export var stuck_progress_distance := 4.0
@export_group("Animations")
@export var idle_animation: StringName = &"idle"
@export var detection_animation: StringName = &"detecting"
@export var spotted_animation: StringName = &"spotted"
@export var windup_animation: StringName = &"windup"
@export var pursuit_animation: StringName = &"running"
@export var idle_active_animation: StringName = &"idleactive"
@export var idle_speed := 1.0
@export var detection_speed := 1.0
@export var idle_active_speed := 1.0

@onready var beehave_tree: BeehaveTree = $BeehaveTree

var state := State.IDLE
var target: Node2D
var holding_position := false
var _watch_time := 0.0
var _stuck_time := 0.0
var _progress_position := Vector2.ZERO
var _tracking_progress := false
var _preparation_step := 0
var _preparation_started := false
var _requested_animation: StringName
var _pursuit_active := false


func _ready() -> void:
	if actor == null:
		actor = get_parent() as CharacterBody2D
	assert(actor != null, "PursuitBehavior needs a CharacterBody2D actor")
	assert(detect_area != null, "PursuitBehavior needs a detection Area2D")
	beehave_tree.set_physics_process(false)
	beehave_tree.set_process(false)
	_progress_position = actor.global_position


func _physics_process(delta: float) -> void:
	if automatic_update:
		update(delta)


func update(delta: float) -> void:
	if not enabled:
		return
	_refresh_detection()
	_update_stuck(delta)
	if state == State.IDLE_ACTIVE and target == null:
		_watch_time += delta
		if _watch_time >= forget_time:
			reset()
	beehave_tree.tick()


func tick_behavior() -> int:
	if not enabled:
		return BeehaveTree.FAILURE
	if state == State.PURSUIT:
		if actor.has_method("tick_pursuit_combat") and actor.tick_pursuit_combat():
			_preparation_step = 2
			_preparation_started = false
			return BeehaveTree.RUNNING
		if not _prepare_pursuit():
			return BeehaveTree.RUNNING
		var blackboard := beehave_tree.blackboard
		if not blackboard.get_value("has_last_known_player_position", false):
			_enter_watch()
		else:
			var destination: Vector2 = target.global_position if is_instance_valid(target) else blackboard.get_value("last_known_player_position")
			_chase(destination)
	elif state == State.DETECTION:
		actor.velocity.x = 0.0
		_play(detection_animation, detection_speed)
	elif state == State.IDLE_ACTIVE:
		actor.velocity.x = 0.0
		_play(idle_active_animation, idle_active_speed)
	else:
		actor.velocity.x = 0.0
		_play(idle_animation, idle_speed)
	return BeehaveTree.RUNNING


func _refresh_detection() -> void:
	var use_aggro := state == State.PURSUIT or state == State.IDLE_ACTIVE
	var watching := state == State.IDLE_ACTIVE or holding_position
	var direction := -facing_direction if watching and flip_detection else facing_direction
	if aggro_sight:
		aggro_sight.scale.x = -direction
	var sight_area := aggro_sight if use_aggro and aggro_sight else detect_area
	for candidate in sight_area.get_overlapping_bodies():
		if candidate is not Node2D or not candidate.is_in_group(target_group):
			continue
		if not use_aggro and (candidate.global_position.x - actor.global_position.x) * direction < -(_body_half_width() + rear_detection_buffer):
			continue
		if use_aggro and not _has_line_of_sight(candidate):
			continue
		observe_target(candidate)
		return
	if rear_awareness_range > 0.0:
		for candidate in detect_area.get_overlapping_bodies():
			if candidate is not Node2D or not candidate.is_in_group(target_group):
				continue
			if actor.global_position.distance_to(candidate.global_position) > rear_awareness_range:
				continue
			if not _has_line_of_sight(candidate):
				continue
			observe_target(candidate)
			return
	lose_sight()


func _has_line_of_sight(candidate: Node2D) -> bool:
	if line_of_sight == null:
		return true
	var aim := candidate.global_position
	var collision := candidate.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		aim = collision.global_position
	line_of_sight.target_position = line_of_sight.to_local(aim)
	line_of_sight.force_raycast_update()
	return line_of_sight.is_colliding() and line_of_sight.get_collider() == candidate


func observe_target(candidate: Node2D) -> void:
	if not is_instance_valid(candidate):
		return
	var blackboard := beehave_tree.blackboard
	if target != candidate:
		target = candidate
		target_changed.emit(target)
	blackboard.set_value("player", target)
	blackboard.set_value("is_player_in_detect_area", true)
	blackboard.set_value("last_known_player_position", target.global_position)
	blackboard.set_value("has_last_known_player_position", true)
	_watch_time = 0.0
	if state == State.PURSUIT or state == State.IDLE_ACTIVE or absf(target.global_position.x - actor.global_position.x) <= pursuit_range:
		blackboard.set_value("is_player_in_pursuit_range", true)
		_set_state(State.PURSUIT)
		_set_pursuit_active(true)
	else:
		_set_state(State.DETECTION)


func lose_sight() -> void:
	if target != null:
		target = null
		target_changed.emit(null)
	beehave_tree.blackboard.set_value("player", null)
	beehave_tree.blackboard.set_value("is_player_in_detect_area", false)
	if state == State.DETECTION:
		reset()


func _prepare_pursuit() -> bool:
	var animations: Array[StringName] = [spotted_animation, windup_animation]
	while _preparation_step < animations.size():
		var animation := animations[_preparation_step]
		if animation_player == null or animation.is_empty() or not animation_player.has_animation(animation):
			_preparation_step += 1
			continue
		if not _preparation_started:
			actor.velocity.x = 0.0
			if actor.has_method("face_player") and is_instance_valid(target):
				actor.face_player(target)
			_play(animation)
			_preparation_started = true
			return false
		if animation_player.is_playing():
			return false
		_preparation_step += 1
		_preparation_started = false
	return true


func _chase(destination: Vector2) -> void:
	var previous_facing := facing_direction
	if actor.has_method("chase_position"):
		holding_position = actor.chase_position(destination)
		if not is_zero_approx(actor.velocity.x):
			facing_direction = signf(actor.velocity.x)
	else:
		var distance := destination.x - actor.global_position.x
		if holding_position:
			holding_position = absf(distance) < maxf(resume_distance, stop_distance)
		else:
			holding_position = absf(distance) <= stop_distance
		if not holding_position:
			facing_direction = signf(distance)
		actor.velocity.x = 0.0 if holding_position else facing_direction * chase_speed
		_play(idle_active_animation if holding_position else pursuit_animation, idle_active_speed if holding_position else 1.0)
	if facing_direction != previous_facing:
		facing_changed.emit(facing_direction)
	if holding_position and not is_instance_valid(target):
		_enter_watch()


func _update_stuck(delta: float) -> void:
	if state != State.PURSUIT or is_instance_valid(target) or holding_position or _preparation_step < 2:
		_tracking_progress = false
		_stuck_time = 0.0
		return
	if not _tracking_progress:
		_progress_position = actor.global_position
		_tracking_progress = true
	if actor.global_position.distance_to(_progress_position) >= stuck_progress_distance:
		_progress_position = actor.global_position
		_stuck_time = 0.0
	else:
		_stuck_time += delta
	if _stuck_time >= stuck_timeout:
		_enter_watch()


func _enter_watch() -> void:
	beehave_tree.blackboard.set_value("has_last_known_player_position", false)
	actor.velocity.x = 0.0
	_watch_time = 0.0
	_set_state(State.IDLE_ACTIVE)
	_set_pursuit_active(false)
	_play(idle_active_animation, idle_active_speed)


func reset() -> void:
	lose_target()
	beehave_tree.blackboard.set_value("is_player_in_pursuit_range", false)
	beehave_tree.blackboard.set_value("has_last_known_player_position", false)
	holding_position = false
	_preparation_step = 0
	_preparation_started = false
	_tracking_progress = false
	_stuck_time = 0.0
	_watch_time = 0.0
	actor.velocity.x = 0.0
	_set_state(State.IDLE)
	_set_pursuit_active(false)
	_play(idle_animation, idle_speed)


func lose_target() -> void:
	target = null
	beehave_tree.blackboard.set_value("player", null)
	beehave_tree.blackboard.set_value("is_player_in_detect_area", false)
	target_changed.emit(null)


func stop() -> void:
	reset()
	enabled = false
	beehave_tree.enabled = false


func _set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_changed.emit(previous, state)


func _set_pursuit_active(active: bool) -> void:
	if _pursuit_active == active:
		return
	_pursuit_active = active
	pursuit_changed.emit(active)


func _body_half_width() -> float:
	return body_shape.shape.get_rect().size.x * 0.5 if body_shape and body_shape.shape else stop_distance


func _play(animation: StringName, speed: float = 1.0) -> void:
	if _requested_animation == animation:
		return
	_requested_animation = animation
	if animation_player == null or animation.is_empty() or not animation_player.has_animation(animation):
		return
	if actor.has_method("play_animation"):
		actor.play_animation(String(animation), speed)
	else:
		animation_player.play(animation, -1.0, speed)
