extends Node2D

## Node path to the neighboring pendulum that this plate activates.
@export_node_path("Node2D") var pendulum_path: NodePath = ^"../Pendulum"
## Optional world-space impulse override. A zero vector uses the pendulum's default impulse.
@export var trigger_impulse := Vector2(180.0, 0.0)
## Trigger once and disable monitoring after the pendulum accepts the activation.
@export var one_shot := true
## Print body entries and trigger routing to the Output panel.
@export var debug_diagnostics := true

@onready var detection_area: Area2D = $Area2D
@onready var animated_sprite_2d = $AnimatedSprite2D

var has_triggered := false

func _ready() -> void:
	animated_sprite_2d.play("standing")
	animated_sprite_2d.sprite_frames.set_animation_speed("pressing", 0.5)
	detection_area.body_entered.connect(_on_body_entered)
	if debug_diagnostics:
		print("[PressurePlate:%s] ready pos=%s mask=%d target=%s impulse=%s one_shot=%s" % [name, global_position, detection_area.collision_mask, pendulum_path, trigger_impulse, one_shot])

func _on_body_entered(body: Node2D) -> void:
	if debug_diagnostics:
		print("[PressurePlate:%s] body_entered body=%s class=%s groups=%s trap_activator=%s" % [name, body.name, body.get_class(), body.get_groups(), body.is_in_group("trap_activators")])
	if body.is_in_group("trap_activators"):
		animated_sprite_2d.play("pressing")
		_trigger_pendulum()

func _trigger_pendulum() -> void:
	if one_shot and has_triggered:
		if debug_diagnostics:
			print("[PressurePlate:%s] ignored: one-shot already spent" % name)
		return

	var pendulum := get_node_or_null(pendulum_path)
	if not is_instance_valid(pendulum) or not pendulum.has_method("trigger_physics_swing"):
		push_warning("PressurePlate '%s' can't find a pendulum at '%s'." % [name, pendulum_path])
		return

	var accepted: bool = pendulum.call("trigger_physics_swing", trigger_impulse)
	if debug_diagnostics:
		print("[PressurePlate:%s] target=%s accepted=%s" % [name, pendulum.get_path(), accepted])
	if not accepted:
		push_warning("Pendulum '%s' rejected the pressure plate trigger. Enable physics simulation on it." % pendulum.name)
		return

	if one_shot:
		has_triggered = true
		detection_area.set_deferred("monitoring", false)
