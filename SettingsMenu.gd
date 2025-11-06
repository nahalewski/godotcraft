extends Control

# SettingsMenu - Touch-friendly FPS settings menu for Android

@onready var fps_30_button: Button = $VBoxContainer/FPS30Button
@onready var fps_60_button: Button = $VBoxContainer/FPS60Button
@onready var fps_120_button: Button = $VBoxContainer/FPS120Button
@onready var close_button: Button = $VBoxContainer/CloseButton
@onready var current_fps_label: Label = $VBoxContainer/CurrentFPSLabel

func _ready():
	# Connect buttons
	fps_30_button.pressed.connect(_on_fps_30_pressed)
	fps_60_button.pressed.connect(_on_fps_60_pressed)
	fps_120_button.pressed.connect(_on_fps_120_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	# Update current FPS display
	update_fps_display()
	
	# Listen for FPS changes
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.fps_changed.connect(_on_fps_changed)

func update_fps_display():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	var current_fps = settings_manager.get_target_fps() if settings_manager else 60
	current_fps_label.text = "Current FPS: " + str(current_fps) + " FPS"
	
	# Highlight the active button
	fps_30_button.modulate = Color.WHITE
	fps_60_button.modulate = Color.WHITE
	fps_120_button.modulate = Color.WHITE
	
	match current_fps:
		30:
			fps_30_button.modulate = Color.GREEN
		60:
			fps_60_button.modulate = Color.GREEN
		120:
			fps_120_button.modulate = Color.GREEN

func _on_fps_30_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_target_fps(30)
		update_fps_display()

func _on_fps_60_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_target_fps(60)
		update_fps_display()

func _on_fps_120_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_target_fps(120)
		update_fps_display()

func _on_close_pressed():
	visible = false

func _on_fps_changed(new_fps: int):
	update_fps_display()

