extends Area2D


func _ready():
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D):
	if body.has_method("request_level_restart"):
		body.request_level_restart()
