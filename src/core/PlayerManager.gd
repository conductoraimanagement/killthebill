extends Node

# Manages the player's archetype, inventory, and current state.

enum ClassSeed { WHITE_COLLAR, BLUE_COLLAR }

var current_class: ClassSeed = ClassSeed.BLUE_COLLAR

# Player State Variables
var credits: int = 0
var intel_level: int = 0
var social_capital: int = 0

func _ready():
	print("PlayerManager initialized.")

func initialize_run(seed: ClassSeed):
	current_class = seed
	match current_class:
		ClassSeed.WHITE_COLLAR:
			_setup_white_collar()
		ClassSeed.BLUE_COLLAR:
			_setup_blue_collar()
			
	print("Run initialized as: ", "White Collar" if current_class == ClassSeed.WHITE_COLLAR else "Blue Collar")
	print("Credits: ", credits, " | Intel: ", intel_level, " | Social Capital: ", social_capital)

func _setup_white_collar():
	credits = 5000
	intel_level = 100
	social_capital = -50
	# TODO: Initialize Compliance AI Hunter

func _setup_blue_collar():
	credits = 100
	intel_level = 10
	social_capital = 80
	# TODO: Initialize Resource Squeeze Timer
