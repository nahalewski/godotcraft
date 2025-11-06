extends Control

# UI Controller - Handles UI interactions including settings menu

@onready var settings_button: Button = $SettingsButton
@onready var settings_menu: Control = $SettingsMenu

func _ready():
	settings_button.pressed.connect(_on_settings_button_pressed)

func _on_settings_button_pressed():
	settings_menu.visible = true

