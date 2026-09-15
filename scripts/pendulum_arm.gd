@tool # Must match the parent script to run inside the editor
extends RigidBody2D

# These will be set automatically by the parent Node2D script
var swing_angle: float = 45.0
var swing_speed: float = 2.0

var time_passed: float = 0.0

func _physics_process(delta: float) -> void:
	time_passed += delta * swing_speed
	
	var target_angle_degrees = sin(time_passed) * swing_angle
	rotation = deg_to_rad(target_angle_degrees)
