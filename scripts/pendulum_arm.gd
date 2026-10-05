@tool # Must match the parent script to run inside the editor
extends RigidBody2D

@onready var head_collision_shape: CollisionShape2D = $PendulumHead
@onready var damage_area: Area2D = $DamageArea

## Print activation, impact, and swing-state diagnostics to the Output panel.
@export var debug_diagnostics := true

# These will be set automatically by the parent Node2D script
var swing_angle: float = 45.0
var swing_speed: float = 2.0
var use_physics_simulation := false
var reset_speed_threshold := 0.25
var reset_angle_tolerance := deg_to_rad(8.0)
var reset_slow_duration := 0.4
var reset_return_duration := 0.6
var damage_angular_speed_threshold := 1.0
var slow_push_speed := 220.0
var slow_push_lift := 80.0
var start_rotation := 0.0
var slow_motion_timer := 0.0
var has_started_physics_swing := false
var is_returning_to_start := false
var is_activation_pending := false

# Current deflection from vertical (radians) and its rate of change, integrated each
# frame via the real (nonlinear) pendulum equation rather than a fixed sine curve, so
# the arm naturally hangs near the top of each swing and accelerates back through the bottom.
var angle: float = 0.0
var swing_angular_velocity: float = 0.0
var diagnostic_time_remaining := 0.0
var diagnostic_sample_time := 0.0
# Tracked separately from a property setter so changes are picked up on the next physics
# frame instead of during construction, when sibling vars may not be initialized yet.
var _last_swing_angle: float = 0.0

func _ready() -> void:
	_reset_swing()
	if not Engine.is_editor_hint():
		freeze = true
		contact_monitor = true
		max_contacts_reported = 4
		damage_area.body_entered.connect(_on_damage_area_body_entered)

func configure_swing(initial_angle: float, configured_speed: float, physics_mode_enabled: bool, configured_angular_damp: float, configured_reset_speed_threshold: float, configured_reset_angle_tolerance_degrees: float, configured_reset_slow_duration: float, configured_reset_return_duration: float, configured_damage_angular_speed_threshold: float, configured_slow_push_speed: float, configured_slow_push_lift: float) -> void:
	swing_angle = initial_angle
	swing_speed = configured_speed
	use_physics_simulation = physics_mode_enabled
	reset_speed_threshold = maxf(configured_reset_speed_threshold, 0.0)
	reset_angle_tolerance = deg_to_rad(maxf(configured_reset_angle_tolerance_degrees, 0.0))
	reset_slow_duration = maxf(configured_reset_slow_duration, 0.0)
	reset_return_duration = maxf(configured_reset_return_duration, 0.01)
	damage_angular_speed_threshold = maxf(configured_damage_angular_speed_threshold, 0.0)
	slow_push_speed = maxf(configured_slow_push_speed, 0.0)
	slow_push_lift = maxf(configured_slow_push_lift, 0.0)
	has_started_physics_swing = false
	is_returning_to_start = false
	is_activation_pending = false
	slow_motion_timer = 0.0
	if use_physics_simulation:
		angular_damp_mode = 1
		angular_damp = configured_angular_damp
	_reset_swing()
	if debug_diagnostics:
		print("[PendulumArm:%s] configured physics=%s frozen=%s angle=%.1f angular_damp=%.2f" % [name, use_physics_simulation, freeze, initial_angle, angular_damp])

func _reset_swing() -> void:
	angle = deg_to_rad(swing_angle)
	start_rotation = angle
	swing_angular_velocity = 0.0
	rotation = angle
	_last_swing_angle = swing_angle

func _physics_process(delta: float) -> void:
	if use_physics_simulation:
		if not freeze and has_started_physics_swing and not is_returning_to_start:
			_check_for_slow_swing(delta)
		if debug_diagnostics and diagnostic_time_remaining > 0.0:
			diagnostic_time_remaining = maxf(diagnostic_time_remaining - delta, 0.0)
			diagnostic_sample_time += delta
			if diagnostic_sample_time >= 0.25:
				diagnostic_sample_time = 0.0
				print("[PendulumArm:%s] sample angle=%.1f angular_velocity=%.3f linear_velocity=%s frozen=%s sleeping=%s contacts=%d" % [name, rad_to_deg(global_rotation), angular_velocity, linear_velocity, freeze, sleeping, get_contact_count()])
		return

	if not is_equal_approx(swing_angle, _last_swing_angle):
		_reset_swing()

	var angular_acceleration = -pow(swing_speed, 2.0) * sin(angle)
	swing_angular_velocity += angular_acceleration * delta
	angle += swing_angular_velocity * delta
	rotation = angle

func _check_for_slow_swing(delta: float) -> void:
	var near_hanging_position := absf(wrapf(rotation, -PI, PI)) <= reset_angle_tolerance
	if absf(angular_velocity) <= reset_speed_threshold and near_hanging_position:
		slow_motion_timer += delta
		if slow_motion_timer >= reset_slow_duration:
			is_returning_to_start = true
			if debug_diagnostics:
				print("[PendulumArm:%s] settled near vertical; returning to %.1f degrees" % [name, rad_to_deg(start_rotation)])
			call_deferred("_begin_return_to_start")
	else:
		slow_motion_timer = 0.0

func trigger_physics_swing(impulse: Vector2) -> bool:
	if debug_diagnostics:
		print("[PendulumArm:%s] trigger received physics=%s frozen=%s active=%s returning=%s pending=%s impulse=%s" % [name, use_physics_simulation, freeze, has_started_physics_swing, is_returning_to_start, is_activation_pending, impulse])
	if not use_physics_simulation:
		return false
	if has_started_physics_swing or is_returning_to_start or is_activation_pending:
		if debug_diagnostics:
			print("[PendulumArm:%s] trigger ignored: swing is already active or resetting" % name)
		return true

	is_activation_pending = true
	call_deferred("_activate_physics_swing", impulse)
	return true

func _activate_physics_swing(impulse: Vector2) -> void:
	if not use_physics_simulation or is_returning_to_start:
		is_activation_pending = false
		if debug_diagnostics:
			print("[PendulumArm:%s] deferred activation cancelled" % name)
		return

	is_activation_pending = false
	var impulse_offset := head_collision_shape.position.rotated(global_rotation)
	if debug_diagnostics:
		print("[PendulumArm:%s] activating rotation=%.1f offset=%s contacts=%d" % [name, rad_to_deg(global_rotation), impulse_offset, get_contact_count()])
	freeze = false
	sleeping = false
	has_started_physics_swing = true
	slow_motion_timer = 0.0
	if not impulse.is_zero_approx():
		apply_impulse(impulse, impulse_offset)
	diagnostic_time_remaining = 3.0
	diagnostic_sample_time = 0.0
	if debug_diagnostics:
		print("[PendulumArm:%s] activated frozen=%s angular_velocity=%.3f linear_velocity=%s" % [name, freeze, angular_velocity, linear_velocity])

func _begin_return_to_start() -> void:
	if not is_returning_to_start or not use_physics_simulation:
		return

	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = true
	var return_tween := create_tween()
	return_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(self, "rotation", start_rotation, reset_return_duration)
	return_tween.finished.connect(_finish_return_to_start, CONNECT_ONE_SHOT)

func _finish_return_to_start() -> void:
	rotation = start_rotation
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = true
	freeze = true
	has_started_physics_swing = false
	is_returning_to_start = false
	slow_motion_timer = 0.0
	if debug_diagnostics:
		print("[PendulumArm:%s] reset complete frozen at %.1f degrees" % [name, rad_to_deg(rotation)])

func _on_damage_area_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage") and not body.has_method("apply_attack_push") and not body is CharacterBody2D:
		return

	var impact_speed := absf(angular_velocity)
	var should_damage := impact_speed >= damage_angular_speed_threshold and body.has_method("take_damage")
	if debug_diagnostics:
		print("[PendulumArm:%s] impact body=%s groups=%s angular_speed=%.3f threshold=%.3f action=%s" % [name, body.name, body.get_groups(), impact_speed, damage_angular_speed_threshold, "damage" if should_damage else "push"])
	if should_damage:
		body.call_deferred("take_damage")
		return

	var head_offset := head_collision_shape.global_position - global_position
	var tangent_velocity := Vector2(-angular_velocity * head_offset.y, angular_velocity * head_offset.x)
	var push_direction := signf(tangent_velocity.x)
	if is_zero_approx(push_direction):
		push_direction = signf(body.global_position.x - global_position.x)
	if is_zero_approx(push_direction):
		push_direction = 1.0
	var push_velocity := Vector2(push_direction * slow_push_speed, -slow_push_lift)
	if body.has_method("apply_attack_push"):
		body.call_deferred("apply_attack_push", push_velocity)
	elif body is CharacterBody2D:
		body.call_deferred("set", "velocity", push_velocity)
