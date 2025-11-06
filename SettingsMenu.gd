extends Control

# SettingsMenu - Touch-friendly FPS settings menu for Android with gamepad support

@onready var fps_30_button: Button = $VBoxContainer/FPS30Button
@onready var fps_60_button: Button = $VBoxContainer/FPS60Button
@onready var fps_120_button: Button = $VBoxContainer/FPS120Button
@onready var button_mapper_button: Button = $VBoxContainer/ButtonMapperButton
@onready var close_button: Button = $VBoxContainer/CloseButton
@onready var current_fps_label: Label = $VBoxContainer/CurrentFPSLabel
@onready var button_mapper: Control = $ButtonMapper

func _ready():
	# Connect buttons
	fps_30_button.pressed.connect(_on_fps_30_pressed)
	fps_60_button.pressed.connect(_on_fps_60_pressed)
	fps_120_button.pressed.connect(_on_fps_120_pressed)
	button_mapper_button.pressed.connect(_on_button_mapper_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	# Setup button mapper
	if button_mapper:
		button_mapper.visible = false
		button_mapper.mapping_complete.connect(_on_mapping_complete)
		# Load saved button mappings
		button_mapper.load_button_mappings()
	
	# Enable gamepad navigation
	fps_30_button.focus_mode = Control.FOCUS_ALL
	fps_60_button.focus_mode = Control.FOCUS_ALL
	fps_120_button.focus_mode = Control.FOCUS_ALL
	button_mapper_button.focus_mode = Control.FOCUS_ALL
	close_button.focus_mode = Control.FOCUS_ALL
	
	# Set up gamepad navigation (D-pad/arrow keys navigate between buttons)
	fps_30_button.focus_neighbor_top = close_button.get_path()
	fps_30_button.focus_neighbor_bottom = fps_60_button.get_path()
	fps_60_button.focus_neighbor_top = fps_30_button.get_path()
	fps_60_button.focus_neighbor_bottom = fps_120_button.get_path()
	fps_120_button.focus_neighbor_top = fps_60_button.get_path()
	fps_120_button.focus_neighbor_bottom = button_mapper_button.get_path()
	button_mapper_button.focus_neighbor_top = fps_120_button.get_path()
	button_mapper_button.focus_neighbor_bottom = close_button.get_path()
	close_button.focus_neighbor_top = button_mapper_button.get_path()
	close_button.focus_neighbor_bottom = fps_30_button.get_path()
	
	# Update current FPS display
	update_fps_display()
	
	# Listen for FPS changes
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.fps_changed.connect(_on_fps_changed)

func _input(event):
	# Handle gamepad B button or start button to close menu
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_settings")):
		if event is InputEventJoypadButton:
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			# Focus first button when menu opens
			fps_30_button.grab_focus()

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

func _on_button_mapper_pressed():
	if button_mapper:
		button_mapper.visible = true
		button_mapper.focus_mode = Control.FOCUS_ALL

func _on_mapping_complete():
	# Button mapper was closed
	pass

func _on_close_pressed():
	visible = false

func _on_fps_changed(_new_fps: int):
	update_fps_display()

