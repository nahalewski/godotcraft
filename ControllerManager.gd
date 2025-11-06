extends Node

# ControllerManager - Detects controller type and applies appropriate button mappings
# Supports: Razer Kishi, PS5 (DualSense), Xbox controllers

signal controller_detected(controller_name: String, controller_type: String)

enum ControllerType {
	UNKNOWN,
	RAZER_KISHI,
	PS5_DUALSENSE,
	XBOX,
	GENERIC
}

var current_controller_type: ControllerType = ControllerType.UNKNOWN
var controller_name: String = ""

func _ready():
	# Wait a frame for controllers to be detected
	await get_tree().process_frame
	detect_controller()

func detect_controller():
	# Check for controllers periodically (they might connect after game starts)
	var joypads = Input.get_connected_joypads()
	if joypads.is_empty():
		# Try again after a delay
		await get_tree().create_timer(1.0).timeout
		joypads = Input.get_connected_joypads()
		if joypads.is_empty():
			return
	
	var device_id = joypads[0]
	var original_name = Input.get_joy_name(device_id)
	var guid = Input.get_joy_guid(device_id)
	
	# Store original name for display
	controller_name = original_name
	
	# Detect controller type by name and GUID (use lowercase for detection)
	var name_lower = original_name.to_lower()
	var guid_lower = guid.to_lower()
	
	if "razer" in name_lower or "kishi" in name_lower:
		current_controller_type = ControllerType.RAZER_KISHI
		apply_razer_kishi_mappings()
	elif "playstation" in name_lower or "dualsense" in name_lower or "ps5" in name_lower or "054c" in guid_lower:
		current_controller_type = ControllerType.PS5_DUALSENSE
		apply_ps5_mappings()
	elif "xbox" in name_lower or "xinput" in name_lower or "045e" in guid_lower:
		current_controller_type = ControllerType.XBOX
		apply_xbox_mappings()
	else:
		current_controller_type = ControllerType.GENERIC
		apply_generic_mappings()
	
	controller_detected.emit(controller_name, ControllerType.keys()[current_controller_type])
	print("Controller detected: ", controller_name, " (", ControllerType.keys()[current_controller_type], ")")

func apply_razer_kishi_mappings():
	# Razer Kishi mappings (already set in project.godot)
	# R2 = mine (button 7, axis 7)
	# L2 = place (button 6, axis 6)
	pass  # Defaults are already correct

func apply_ps5_mappings():
	# PS5 DualSense mappings
	# R2 = mine (button 7, axis 7)
	# L2 = place (button 6, axis 6)
	# These are the same as Razer Kishi, so no changes needed
	# But we can verify/add if needed
	ensure_mapping("mine", 7, 7)  # R2
	ensure_mapping("place", 6, 6)  # L2
	ensure_mapping("jump", 0, -1)  # X button
	ensure_mapping("open_settings", 9, -1)  # Options button

func apply_xbox_mappings():
	# Xbox controller mappings
	# RT = mine (button 7, axis 7)
	# LT = place (button 6, axis 6)
	ensure_mapping("mine", 7, 7)  # RT
	ensure_mapping("place", 6, 6)  # LT
	ensure_mapping("jump", 0, -1)  # A button
	ensure_mapping("open_settings", 9, -1)  # Menu button

func apply_generic_mappings():
	# Generic controller - use standard mappings
	ensure_mapping("mine", 7, 7)  # Right trigger
	ensure_mapping("place", 6, 6)  # Left trigger
	ensure_mapping("jump", 0, -1)  # Button 0
	ensure_mapping("open_settings", 9, -1)  # Button 9

func ensure_mapping(action: String, button: int, axis: int):
	# Check if action already has the mapping, if not add it
	var has_button = false
	var has_axis = false
	
	var events = InputMap.action_get_events(action)
	for event in events:
		if event is InputEventJoypadButton and event.button_index == button:
			has_button = true
		if event is InputEventJoypadMotion and axis >= 0 and event.axis == axis:
			has_axis = true
	
	# Add button mapping if missing
	if not has_button and button >= 0:
		var button_event = InputEventJoypadButton.new()
		button_event.button_index = button
		InputMap.action_add_event(action, button_event)
	
	# Add axis mapping if missing
	if not has_axis and axis >= 0:
		var axis_event = InputEventJoypadMotion.new()
		axis_event.axis = axis
		axis_event.axis_value = 1.0
		InputMap.action_add_event(action, axis_event)

func get_controller_type() -> ControllerType:
	return current_controller_type

func get_controller_name() -> String:
	return controller_name

func get_controller_type_name() -> String:
	match current_controller_type:
		ControllerType.RAZER_KISHI:
			return "RAZER_KISHI"
		ControllerType.PS5_DUALSENSE:
			return "PS5_DUALSENSE"
		ControllerType.XBOX:
			return "XBOX"
		ControllerType.GENERIC:
			return "GENERIC"
		_:
			return "UNKNOWN"

