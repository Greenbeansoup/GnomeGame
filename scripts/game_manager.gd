extends Node2D

# Preload your scenes for easy swapping
@export var level_1_scene: PackedScene
@export var test_arena_scene: PackedScene
@export var main_menu_scene: PackedScene

@onready var pause_menu = $UI/PauseMenu
@onready var menu_holder = $UI/MenuHolder
@onready var ui_layer = $UI
@onready var current_scene_holder = $CurrentScene

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Start by showing the main menu
	show_main_menu()
	
	# Hide the pause menu immediately when the game boots up
	pause_menu.hide()
	
	# Connect the buttons from inside your pause menu scene
	pause_menu.resume_pressed.connect(_on_resume_pressed)
	pause_menu.main_menu_pressed.connect(_on_main_menu_pressed)
	pause_menu.exit_pressed.connect(_on_exit_pressed)

func _unhandled_input(event: InputEvent):
	# 1. Check if the event is your pause action
	# 2. Make sure it's a down-press, not a release
	# 3. CRUCIAL: Make sure it's not an "echo" repeat from holding the key!
	if event.is_action_pressed("pause") and not event.is_echo():
		
		# 4. Stop the input from passing to any other nodes this frame
		get_viewport().set_input_as_handled()
		toggle_pause()

func show_main_menu():
	# Clear out the temporary menus, but the PauseMenu is safe!
	_clear_children(menu_holder) 
	_clear_children(current_scene_holder)
	
	var menu = main_menu_scene.instantiate()
	menu_holder.add_child(menu) # Put it inside the holder
	menu.start_game_pressed.connect(start_level.bind(level_1_scene))
	menu.start_test_arena_pressed.connect(start_level.bind(test_arena_scene))
	menu.exit_pressed.connect(_on_exit_pressed)

func _on_exit_pressed():
	get_tree().quit()
		
func toggle_pause():
	if get_tree().paused:
		get_tree().paused = false
		pause_menu.hide()
	else:
		get_tree().paused = true
		pause_menu.show()

func _on_resume_pressed():
	toggle_pause() # Unpauses and hides the menu

func _on_main_menu_pressed():
	toggle_pause() # Must unpause the tree first so things process normally!
	show_main_menu() # Run your existing function to load the main menu

func start_level(level_scene: PackedScene):
	# Remove the main menu
	_clear_children(menu_holder)
	
	# Load the actual game level
	var level = level_scene.instantiate()
	current_scene_holder.add_child(level)

func _clear_children(target_node: Node):
	for child in target_node.get_children():
		child.queue_free()
