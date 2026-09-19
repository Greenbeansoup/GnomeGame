extends Node2D

@export var player: CharacterBody2D
@onready var sprite: Sprite2D = $LegsSprite

const PLAYER_OVERLAP_PIXELS = 3.0

var is_active: bool = false
var anchor_y: float = 0.0

func _ready() -> void:
	_align_sprite_to_bottom()
	visible = false
	set_process(false)


func _align_sprite_to_bottom() -> void:
	if not sprite or not sprite.texture:
		return

	sprite.position = Vector2.ZERO
	sprite.offset.y = -sprite.texture.get_height()

## Call this from the player when the mode starts
func activate_tether(ground_position: Vector2) -> void:
	_align_sprite_to_bottom()
	sprite.show()
	anchor_y = ground_position.y
	
	# Initial positioning
	global_position.x = player.global_position.x
	global_position.y = anchor_y
	
	visible = true
	is_active = true
	set_process(true)

## Call this from the player when the mode ends
func deactivate_tether() -> void:
	sprite.hide()
	visible = false
	is_active = false
	set_process(false)
	if sprite:
		sprite.scale = Vector2.ONE

func _process(_delta: float) -> void:
	if not player or not sprite or not is_active:
		return
		
	# 1. Follow the player horizontally, keep the anchor vertically
	global_position.x = player.global_position.x
	global_position.y = anchor_y
	
	# 2. Calculate height between the parent node (ground) and player
	var vertical_distance = global_position.y - player.global_position.y + PLAYER_OVERLAP_PIXELS
	
	# 3. Stretch only the child sprite asset
	if sprite.texture and vertical_distance > 0:
		sprite.scale.y = vertical_distance / sprite.texture.get_height()
	else:
		sprite.scale.y = 0.0
