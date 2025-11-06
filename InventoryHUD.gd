extends Control

# InventoryHUD - Displays hotbar at bottom of screen

const SLOT_SIZE = 64
const SLOT_SPACING = 4
const HOTBAR_HEIGHT = 80

@onready var hotbar_container: HBoxContainer = $HotbarContainer

var slot_labels: Array[Label] = []
var slot_containers: Array[Control] = []

func _ready():
	setup_hotbar()
	
	# Connect to inventory signals
	var inventory = get_node_or_null("/root/Inventory")
	if inventory:
		inventory.inventory_changed.connect(_on_inventory_changed)
		inventory.selected_slot_changed.connect(_on_selected_slot_changed)
		# Initial update
		update_all_slots()

func setup_hotbar():
	# Create 9 slots
	for i in range(9):
		var slot_container = Control.new()
		slot_container.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot_container.name = "Slot" + str(i)
		
		# Background panel
		var panel = Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_container.add_child(panel)
		
		# Item label (shows block name or count)
		var label = Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = ""
		slot_container.add_child(label)
		
		# Count label (bottom right)
		var count_label = Label.new()
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.text = ""
		count_label.add_theme_font_size_override("font_size", 16)
		slot_container.add_child(count_label)
		
		hotbar_container.add_child(slot_container)
		slot_containers.append(slot_container)
		slot_labels.append(label)
	
	# Update initial display
	update_all_slots()

func update_slot(slot: int):
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		return
	
	if slot < 0 or slot >= slot_containers.size():
		return
	
	var slot_data = inventory.get_slot(slot)
	var container = slot_containers[slot]
	var label = slot_labels[slot]
	var count_label = container.get_child(2) as Label
	
	# Update appearance based on selection
	var panel = container.get_child(0) as Panel
	var is_selected = inventory.selected_slot == slot
	
	if is_selected:
		panel.modulate = Color(1.2, 1.2, 1.2)  # Highlight selected
	else:
		panel.modulate = Color.WHITE
	
	# Update content
	if slot_data["type"] != null:
		var block_type = slot_data["type"] as BlockManager.BlockType
		var block_name = BlockManager.block_type_to_file.get(block_type, "grass")
		label.text = block_name.capitalize()
		if slot_data["count"] > 1:
			count_label.text = str(slot_data["count"])
		else:
			count_label.text = ""
	else:
		label.text = ""
		count_label.text = ""

func update_all_slots():
	for i in range(9):
		update_slot(i)

func _on_inventory_changed(slot: int):
	update_slot(slot)

func _on_selected_slot_changed(slot: int):
	# Update all slots to refresh highlighting
	update_all_slots()

