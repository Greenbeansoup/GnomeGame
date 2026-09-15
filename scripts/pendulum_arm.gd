@tool # Must match the parent script to run inside the editor
extends RigidBody2D

# These will be set automatically by the parent Node2D script
var swing_angle: float = 45.0
var swing_speed: float = 2.0

# Current deflection from vertical (radians) and its rate of change, integrated each
# frame via the real (nonlinear) pendulum equation rather than a fixed sine curve, so
# the arm naturally hangs near the top of each swing and accelerates back through the bottom.
var angle: float = 0.0
var swing_angular_velocity: float = 0.0
# Tracked separately from a property setter so changes are picked up on the next physics
# frame instead of during construction, when sibling vars may not be initialized yet.
var _last_swing_angle: float = 0.0

func _ready() -> void:
	_reset_swing()
	if not Engine.is_editor_hint():
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_body_entered)

func _reset_swing() -> void:
	angle = deg_to_rad(swing_angle)
	swing_angular_velocity = 0.0
	rotation = angle
	_last_swing_angle = swing_angle

func _physics_process(delta: float) -> void:
	if not is_equal_approx(swing_angle, _last_swing_angle):
		_reset_swing()

	var angular_acceleration = -pow(swing_speed, 2.0) * sin(angle)
	swing_angular_velocity += angular_acceleration * delta
	angle += swing_angular_velocity * delta
	rotation = angle

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage()
