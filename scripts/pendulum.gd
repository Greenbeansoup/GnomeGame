@tool # Allows the pendulum to swing live inside the Godot editor view
extends Node2D

# Expose settings directly on the top-level parent node
@export var swing_angle: float = 45.0
@export var swing_speed: float = 2.0

@onready var pendulum_arm: RigidBody2D = $PendulumArm

func _ready() -> void:
	# Pass the custom settings down to the physics body when the game starts
	if not Engine.is_editor_hint() and pendulum_arm:
		pendulum_arm.swing_angle = swing_angle
		pendulum_arm.swing_speed = swing_speed

func _process(_delta: float) -> void:
	# Keeps the editor view updated if you tweak variables while designing
	if Engine.is_editor_hint() and pendulum_arm:
		pendulum_arm.swing_angle = swing_angle
		pendulum_arm.swing_speed = swing_speed
