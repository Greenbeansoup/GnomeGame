extends Control

@onready var continue_button = $VBoxContainer/Continue
@onready var return_to_main_menu = $VBoxContainer/ReturnToMainMenu
@onready var exit_game = $VBoxContainer/ExitGame

signal main_menu_pressed
signal resume_pressed
signal exit_pressed

func _ready():
	continue_button.pressed.connect(_on_continue_pressed)
	return_to_main_menu.pressed.connect(_on_return_to_main_menue_pressed)
	exit_game.pressed.connect(_on_exit_game_pressed)


func _on_continue_pressed():
	resume_pressed.emit()
	
func _on_return_to_main_menue_pressed():
	main_menu_pressed.emit()

func _on_exit_game_pressed():
	exit_pressed.emit()
