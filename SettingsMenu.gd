extends Control

# SettingsMenu - Touch-friendly FPS settings menu for Android with gamepad support

@onready var fps_30_button: Button = $ScrollContainer/VBoxContainer/FPS30Button
@onready var fps_60_button: Button = $ScrollContainer/VBoxContainer/FPS60Button
@onready var fps_120_button: Button = $ScrollContainer/VBoxContainer/FPS120Button
@onready var button_mapper_button: Button = $ScrollContainer/VBoxContainer/ButtonMapperButton
@onready var close_button: Button = $ScrollContainer/VBoxContainer/CloseButton
@onready var current_fps_label: Label = $ScrollContainer/VBoxContainer/CurrentFPSLabel
@onready var button_mapper: Control = $ButtonMapper

# Performance options
@onready var fsr_low_button: Button = $ScrollContainer/VBoxContainer/PerformanceOptions/FSRLowButton
@onready var fsr_medium_button: Button = $ScrollContainer/VBoxContainer/PerformanceOptions/FSRMediumButton
@onready var fsr_high_button: Button = $ScrollContainer/VBoxContainer/PerformanceOptions/FSRHighButton
@onready var occlusion_culling_checkbox: CheckBox = $ScrollContainer/VBoxContainer/PerformanceOptions/OcclusionCullingCheckbox
@onready var adaptive_quality_checkbox: CheckBox = $ScrollContainer/VBoxContainer/PerformanceOptions/AdaptiveQualityCheckbox
@onready var render_distance_slider: HSlider = $ScrollContainer/VBoxContainer/PerformanceOptions/RenderDistanceSlider
@onready var render_distance_label: Label = $ScrollContainer/VBoxContainer/PerformanceOptions/RenderDistanceLabel

func _ready():
	# Connect buttons (with null checks)
	if fps_30_button:
		fps_30_button.pressed.connect(_on_fps_30_pressed)
	if fps_60_button:
		fps_60_button.pressed.connect(_on_fps_60_pressed)
	if fps_120_button:
		fps_120_button.pressed.connect(_on_fps_120_pressed)
	if button_mapper_button:
		button_mapper_button.pressed.connect(_on_button_mapper_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	# Connect performance options (with null checks)
	if fsr_low_button:
		fsr_low_button.pressed.connect(_on_fsr_low_pressed)
	if fsr_medium_button:
		fsr_medium_button.pressed.connect(_on_fsr_medium_pressed)
	if fsr_high_button:
		fsr_high_button.pressed.connect(_on_fsr_high_pressed)
	if occlusion_culling_checkbox:
		occlusion_culling_checkbox.toggled.connect(_on_occlusion_culling_toggled)
	if adaptive_quality_checkbox:
		adaptive_quality_checkbox.toggled.connect(_on_adaptive_quality_toggled)
	if render_distance_slider:
		render_distance_slider.value_changed.connect(_on_render_distance_changed)
	
	# Setup button mapper
	if button_mapper:
		button_mapper.visible = false
		button_mapper.mapping_complete.connect(_on_mapping_complete)
		button_mapper.load_button_mappings()
	
	# Enable gamepad navigation for all buttons
	_setup_gamepad_navigation()
	
	# Update displays
	update_fps_display()
	update_performance_settings()
	
	# Listen for changes
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.fps_changed.connect(_on_fps_changed)
		settings_manager.performance_settings_changed.connect(_on_performance_settings_changed)

func _setup_gamepad_navigation():
	var buttons = [
		fps_30_button, fps_60_button, fps_120_button,
		fsr_low_button, fsr_medium_button, fsr_high_button,
		occlusion_culling_checkbox, adaptive_quality_checkbox,
		button_mapper_button, close_button
	]
	
	for button in buttons:
		if button:
			button.focus_mode = Control.FOCUS_ALL
	
	# Setup focus neighbors (with null checks)
	if fps_30_button and fps_60_button:
		fps_30_button.focus_neighbor_bottom = fps_60_button.get_path()
	if fps_60_button and fps_30_button:
		fps_60_button.focus_neighbor_top = fps_30_button.get_path()
	if fps_60_button and fps_120_button:
		fps_60_button.focus_neighbor_bottom = fps_120_button.get_path()
	if fps_120_button and fps_60_button:
		fps_120_button.focus_neighbor_top = fps_60_button.get_path()
	if fps_120_button and fsr_low_button:
		fps_120_button.focus_neighbor_bottom = fsr_low_button.get_path()
	if fsr_low_button and fps_120_button:
		fsr_low_button.focus_neighbor_top = fps_120_button.get_path()
	if fsr_low_button and fsr_medium_button:
		fsr_low_button.focus_neighbor_bottom = fsr_medium_button.get_path()
	if fsr_medium_button and fsr_low_button:
		fsr_medium_button.focus_neighbor_top = fsr_low_button.get_path()
	if fsr_medium_button and fsr_high_button:
		fsr_medium_button.focus_neighbor_bottom = fsr_high_button.get_path()
	if fsr_high_button and fsr_medium_button:
		fsr_high_button.focus_neighbor_top = fsr_medium_button.get_path()
	if fsr_high_button and occlusion_culling_checkbox:
		fsr_high_button.focus_neighbor_bottom = occlusion_culling_checkbox.get_path()
	if occlusion_culling_checkbox and fsr_high_button:
		occlusion_culling_checkbox.focus_neighbor_top = fsr_high_button.get_path()
	if occlusion_culling_checkbox and adaptive_quality_checkbox:
		occlusion_culling_checkbox.focus_neighbor_bottom = adaptive_quality_checkbox.get_path()
	if adaptive_quality_checkbox and occlusion_culling_checkbox:
		adaptive_quality_checkbox.focus_neighbor_top = occlusion_culling_checkbox.get_path()
	if adaptive_quality_checkbox and button_mapper_button:
		adaptive_quality_checkbox.focus_neighbor_bottom = button_mapper_button.get_path()
	if button_mapper_button and adaptive_quality_checkbox:
		button_mapper_button.focus_neighbor_top = adaptive_quality_checkbox.get_path()
	if button_mapper_button and close_button:
		button_mapper_button.focus_neighbor_bottom = close_button.get_path()
	if close_button and button_mapper_button:
		close_button.focus_neighbor_top = button_mapper_button.get_path()
	if close_button and fps_30_button:
		close_button.focus_neighbor_bottom = fps_30_button.get_path()

func _input(event):
	# Handle gamepad B button or start button to close menu
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_settings")):
		if event is InputEventJoypadButton:
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			if fps_30_button:
				fps_30_button.grab_focus()
			update_performance_settings()

func update_fps_display():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	var current_fps = settings_manager.get_target_fps() if settings_manager else 60
	if current_fps_label:
		current_fps_label.text = "Current FPS: " + str(current_fps) + " FPS"
	
	# Highlight the active button (with null checks)
	if fps_30_button:
		fps_30_button.modulate = Color.WHITE
	if fps_60_button:
		fps_60_button.modulate = Color.WHITE
	if fps_120_button:
		fps_120_button.modulate = Color.WHITE
	
	match current_fps:
		30:
			if fps_30_button:
				fps_30_button.modulate = Color.GREEN
		60:
			if fps_60_button:
				fps_60_button.modulate = Color.GREEN
		120:
			if fps_120_button:
				fps_120_button.modulate = Color.GREEN

func update_performance_settings():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if not settings_manager:
		return
	
	# Update FSR buttons (with null checks)
	if fsr_low_button:
		fsr_low_button.modulate = Color.WHITE
	if fsr_medium_button:
		fsr_medium_button.modulate = Color.WHITE
	if fsr_high_button:
		fsr_high_button.modulate = Color.WHITE
	
	match settings_manager.fsr_quality:
		0:
			if fsr_low_button:
				fsr_low_button.modulate = Color.GREEN
		1:
			if fsr_medium_button:
				fsr_medium_button.modulate = Color.GREEN
		2:
			if fsr_high_button:
				fsr_high_button.modulate = Color.GREEN
	
	# Update checkboxes (with null checks)
	if occlusion_culling_checkbox:
		occlusion_culling_checkbox.button_pressed = settings_manager.occlusion_culling
	if adaptive_quality_checkbox:
		adaptive_quality_checkbox.button_pressed = settings_manager.adaptive_quality
	
	# Update render distance slider (with null checks)
	if render_distance_slider:
		render_distance_slider.value = settings_manager.max_render_distance
	if render_distance_label:
		render_distance_label.text = "Render Distance: " + str(int(settings_manager.max_render_distance)) + " chunks"

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

func _on_fsr_low_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_fsr_quality(0)
		update_performance_settings()

func _on_fsr_medium_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_fsr_quality(1)
		update_performance_settings()

func _on_fsr_high_pressed():
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_fsr_quality(2)
		update_performance_settings()

func _on_occlusion_culling_toggled(button_pressed: bool):
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_occlusion_culling(button_pressed)

func _on_adaptive_quality_toggled(button_pressed: bool):
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_adaptive_quality(button_pressed)

func _on_render_distance_changed(value: float):
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		settings_manager.set_max_render_distance(int(value))
		render_distance_label.text = "Render Distance: " + str(int(value)) + " chunks"

func _on_button_mapper_pressed():
	if button_mapper:
		button_mapper.visible = true
		button_mapper.focus_mode = Control.FOCUS_ALL

func _on_mapping_complete():
	pass

func _on_close_pressed():
	visible = false

func _on_fps_changed(_new_fps: int):
	update_fps_display()

func _on_performance_settings_changed():
	update_performance_settings()
