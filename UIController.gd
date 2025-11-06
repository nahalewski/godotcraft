extends Control

# UI Controller - Handles UI interactions including settings menu

@onready var settings_button: Button = $SettingsButton
@onready var settings_menu: Control = $SettingsMenu

func _ready():
	settings_button.pressed.connect(_on_settings_button_pressed)

func _input(event):
	# Handle gamepad start/options button to open settings
	if event.is_action_pressed("open_settings"):
		toggle_settings_menu()

func _on_settings_button_pressed():
	toggle_settings_menu()

func toggle_settings_menu():
	settings_menu.visible = not settings_menu.visible
	# If opening menu, focus first button for gamepad navigation
	if settings_menu.visible:
		var first_button = settings_menu.get_node_or_null("VBoxContainer/FPS30Button")
		if first_button:
			first_button.grab_focus()

