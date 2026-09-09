extends StaticBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var bounce_light = $BounceLight

# The strength of the launch force
@export var bounce_force: float = 600.0
@export_range(0.0, 1.0, 0.01) var force_multiplier: float = 0.99

func _ready():
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	bounce_light.enabled = false

func _on_animation_finished():
	print("Setting bounce light false")
	if animated_sprite_2d.animation == "Bounce":
		animated_sprite_2d.play("Default")
		bounce_light.enabled = false

func bounce(body: CharacterBody2D, impact_velocity: Vector2) -> Vector2:
	animated_sprite_2d.play("Bounce")
	bounce_light.enabled = true
	
	# Launch direction follows the mushroom's local top, regardless of contact resolution.
	var launch_direction = -global_transform.y.normalized()
	var impact_speed = absf(impact_velocity.dot(-launch_direction))

	# Preserve a minimum bounce while allowing stronger impacts in the same axis to scale it.
	var launch_speed = maxf(bounce_force, impact_speed * force_multiplier)
	var tangential_velocity = impact_velocity - launch_direction * impact_velocity.dot(launch_direction)
	body.velocity = tangential_velocity + launch_direction * launch_speed
	return launch_direction
