extends Control

# ButtonMapper - Allows users to remap gamepad buttons

signal mapping_complete

var current_action: String = ""
var waiting_for_input: bool = false
var action_to_remap: String = ""

@onready var action_list: ItemList = $VBoxContainer/ActionList
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var controller_label: Label = $VBoxContainer/ControllerLabel
@onready var remap_button: Button = $VBoxContainer/RemapButton
@onready var reset_button: Button = $VBoxContainer/ResetButton
@onready var close_button: Button = $VBoxContainer/CloseButton

var actions = [
	{"name": "Mine", "action": "mine"},
	{"name": "Place Block", "action": "place"},
	{"name": "Jump", "action": "jump"},
	{"name": "Open Settings", "action": "open_settings"},
	{"name": "Inventory Left", "action": "inventory_left"},
	{"name": "Inventory Right", "action": "inventory_right"}
]

func _ready():
	# Populate action list
	for action_data in actions:
		action_list.add_item(action_data["name"])
	
	remap_button.pressed.connect(_on_remap_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)
	action_list.item_selected.connect(_on_action_selected)
	
	# Enable gamepad navigation
	remap_button.focus_mode = Control.FOCUS_ALL
	reset_button.focus_mode = Control.FOCUS_ALL
	close_button.focus_mode = Control.FOCUS_ALL
	
	# Load saved mappings on startup
	load_button_mappings()
	
	# Display detected controller
	update_controller_display()
	
	update_status("Select an action to remap")

func _on_action_selected(index: int):
	if index >= 0 and index < actions.size():
		current_action = actions[index]["action"]
		update_status("Selected: " + actions[index]["name"] + " - Click 'Start Remap' to begin")

func _on_remap_pressed():
	if current_action == "":
		update_status("Please select an action first")
		return
	
	action_to_remap = current_action
	waiting_for_input = true
	update_status("Press any gamepad button or move any stick/trigger...")

func _on_reset_pressed():
	if current_action == "":
		update_status("Please select an action first")
		return
	
	# Reset to default mappings
	var defaults = {
		"mine": [7, 7],  # R2 button and axis
		"place": [6, 6],  # L2 button and axis
		"jump": [0, 1],  # A and B buttons
		"open_settings": [9],  # Start button
		"inventory_left": [14],  # D-pad left
		"inventory_right": [15]  # D-pad right
	}
	
	if defaults.has(current_action):
		InputMap.action_erase_events(current_action)
		# Re-add default events (this is simplified - full implementation would restore all defaults)
		update_status("Reset " + current_action + " to defaults (rebuild APK to fully apply)")

func _on_close_pressed():
	mapping_complete.emit()
	visible = false

func _input(event):
	# Handle gamepad B button to close mapper (when not waiting for input)
	if visible and not waiting_for_input:
		if event.is_action_pressed("ui_cancel"):
			if event is InputEventJoypadButton:
				_on_close_pressed()
				get_viewport().set_input_as_handled()
		return
	
	# Handle input for remapping
	if not waiting_for_input:
		return
	
	if event is InputEventJoypadButton:
		if event.pressed:
			remap_action_button(event.button_index)
			waiting_for_input = false
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		# Check if it's a significant movement (not just drift)
		if abs(event.axis_value) > 0.5:
			remap_action_axis(event.axis, event.axis_value > 0)
			waiting_for_input = false
			get_viewport().set_input_as_handled()

func remap_action_button(button_index: int):
	if action_to_remap == "":
		return
	
	# Remove existing gamepad button mappings for this action
	var action_events = InputMap.action_get_events(action_to_remap)
	for event in action_events:
		if event is InputEventJoypadButton:
			InputMap.action_erase_event(action_to_remap, event)
	
	# Add new mapping
	var new_event = InputEventJoypadButton.new()
	new_event.button_index = button_index
	InputMap.action_add_event(action_to_remap, new_event)
	
	# Save mapping
	save_button_mapping(action_to_remap, "button", button_index)
	
	var action_name = ""
	for action_data in actions:
		if action_data["action"] == action_to_remap:
			action_name = action_data["name"]
			break
	
	update_status("Mapped " + action_name + " to button " + str(button_index))
	action_to_remap = ""

func remap_action_axis(axis: int, positive: bool):
	if action_to_remap == "":
		return
	
	# Remove existing gamepad axis mappings for this action
	var action_events = InputMap.action_get_events(action_to_remap)
	for event in action_events:
		if event is InputEventJoypadMotion and event.axis == axis:
			InputMap.action_erase_event(action_to_remap, event)
	
	# Add new mapping
	var new_event = InputEventJoypadMotion.new()
	new_event.axis = axis
	new_event.axis_value = 1.0 if positive else -1.0
	InputMap.action_add_event(action_to_remap, new_event)
	
	# Save mapping
	save_button_mapping(action_to_remap, "axis", axis, positive)
	
	var action_name = ""
	for action_data in actions:
		if action_data["action"] == action_to_remap:
			action_name = action_data["name"]
			break
	
	update_status("Mapped " + action_name + " to axis " + str(axis) + ("+" if positive else "-"))
	action_to_remap = ""

func save_button_mapping(action: String, type: String, value: int, positive: bool = true):
	var config = ConfigFile.new()
	var config_path = "user://button_mappings.cfg"
	
	# Load existing mappings
	var err = config.load(config_path)
	if err != OK:
		config = ConfigFile.new()
	
	# Save mapping
	config.set_value(action, "type", type)
	config.set_value(action, "value", value)
	if type == "axis":
		config.set_value(action, "positive", positive)
	
	config.save(config_path)

func load_button_mappings():
	var config = ConfigFile.new()
	var config_path = "user://button_mappings.cfg"
	
	var err = config.load(config_path)
	if err != OK:
		return  # No saved mappings
	
	# Load and apply mappings
	for action_data in actions:
		var action = action_data["action"]
		if config.has_section_key(action, "type"):
			var type = config.get_value(action, "type")
			var value = config.get_value(action, "value")
			
			# Remove existing gamepad events for this action first
			var action_events = InputMap.action_get_events(action)
			for event in action_events:
				if event is InputEventJoypadButton or event is InputEventJoypadMotion:
					InputMap.action_erase_event(action, event)
			
			# Add saved mapping
			if type == "button":
				var event = InputEventJoypadButton.new()
				event.button_index = value
				InputMap.action_add_event(action, event)
			elif type == "axis":
				var positive = config.get_value(action, "positive", true)
				var event = InputEventJoypadMotion.new()
				event.axis = value
				event.axis_value = 1.0 if positive else -1.0
				InputMap.action_add_event(action, event)

func update_status(text: String):
	status_label.text = text

func update_controller_display():
	if not controller_label:
		return
	var controller_manager = get_node_or_null("/root/ControllerManager")
	if controller_manager:
		var ctrl_name = controller_manager.get_controller_name()
		if ctrl_name != "":
			# Get type name from ControllerManager
			var type_name = controller_manager.get_controller_type_name()
			controller_label.text = "Controller: " + ctrl_name + " (" + type_name + ")"
		else:
			controller_label.text = "Controller: Not detected"
	else:
		controller_label.text = "Controller: Not detected"
