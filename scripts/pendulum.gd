@tool # Allows the pendulum to swing live inside the Godot editor view
extends Node2D

## Starting angle in degrees from the hanging-down position.
@export var swing_angle: float = 89.0
## Swing speed used by the scripted animation mode.
@export var swing_speed: float = 2.0
## Use gravity and the pin joint instead of scripted rotation. The pressure plate only activates this mode.
@export var physics_simulation_enabled := true
## World-space impulse used when the swing is triggered without an override.
@export var physics_trigger_impulse := Vector2(180.0, 0.0)
## Angular damping applied only in physics simulation mode. Higher values make the swing settle sooner.
@export_range(0.0, 10.0, 0.1) var physics_angular_damp := 2.0
## Impacts at or above this angular speed damage targets. Measured in radians per second.
@export_range(0.0, 20.0, 0.1) var damage_angular_speed_threshold := 2.5
## Horizontal speed applied to targets when the pendulum is below the damage threshold.
@export_range(0.0, 1000.0, 10.0) var slow_push_speed := 220.0
## Upward component of the push applied below the damage threshold.
@export_range(0.0, 500.0, 10.0) var slow_push_lift := 80.0
## The arm must stay below this angular speed before returning to its starting angle.
@export_range(0.0, 5.0, 0.05) var reset_speed_threshold := 2.3
## The arm must also be within this many degrees of vertical to avoid resetting at normal turning points.
@export_range(0.0, 30.0, 1.0) var reset_angle_tolerance_degrees := 12.0
## How long the arm must remain slow and near vertical before returning.
@export_range(0.0, 2.0, 0.05) var reset_slow_duration := 0.4
## Duration of the return to the configured starting angle.
@export_range(0.1, 3.0, 0.1) var reset_return_duration := 0.6
## Print diagnostic startup, trigger, and swing-state information to the Output panel.
@export var debug_diagnostics := true

@onready var pendulum_arm: RigidBody2D = $PendulumArm

func _ready() -> void:
	# Pass the custom settings down to the physics body when the game starts
	if not Engine.is_editor_hint() and pendulum_arm:
		pendulum_arm.call("configure_swing", swing_angle, swing_speed, physics_simulation_enabled, physics_angular_damp, reset_speed_threshold, reset_angle_tolerance_degrees, reset_slow_duration, reset_return_duration, damage_angular_speed_threshold, slow_push_speed, slow_push_lift)
		if debug_diagnostics:
			print("[Pendulum:%s] ready physics_enabled=%s arm_physics=%s frozen=%s angle=%.1f impulse=%s angular_damp=%.2f reset_speed=%.2f" % [name, physics_simulation_enabled, pendulum_arm.get("use_physics_simulation"), pendulum_arm.freeze, swing_angle, physics_trigger_impulse, physics_angular_damp, reset_speed_threshold])

func _process(_delta: float) -> void:
	# Keeps the editor view updated if you tweak variables while designing
	if Engine.is_editor_hint() and pendulum_arm:
		pendulum_arm.swing_angle = swing_angle
		pendulum_arm.swing_speed = swing_speed

func trigger_physics_swing(impulse_override: Vector2 = Vector2.ZERO) -> bool:
	if debug_diagnostics:
		print("[Pendulum:%s] trigger requested enabled=%s arm_valid=%s override=%s" % [name, physics_simulation_enabled, is_instance_valid(pendulum_arm), impulse_override])
	if not physics_simulation_enabled or not is_instance_valid(pendulum_arm):
		if debug_diagnostics:
			print("[Pendulum:%s] trigger rejected" % name)
		return false

	var impulse := physics_trigger_impulse
	if not impulse_override.is_zero_approx():
		impulse = impulse_override
	var accepted: bool = pendulum_arm.call("trigger_physics_swing", impulse)
	if debug_diagnostics:
		print("[Pendulum:%s] arm accepted=%s arm_physics=%s frozen=%s applied_impulse=%s" % [name, accepted, pendulum_arm.get("use_physics_simulation"), pendulum_arm.freeze, impulse])
	return accepted
