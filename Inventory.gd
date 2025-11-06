extends Node

# Inventory - Manages player inventory with hotbar slots

const MAX_SLOTS = 9
const MAX_STACK_SIZE = 64

signal inventory_changed(slot: int)
signal selected_slot_changed(slot: int)

var slots: Array[Dictionary] = []
var selected_slot: int = 0

func _ready():
	# Initialize empty inventory slots
	for i in range(MAX_SLOTS):
		slots.append({"type": null, "count": 0})

func add_item(block_type: BlockManager.BlockType, count: int = 1) -> int:
	# Try to add to existing stacks first
	for i in range(MAX_SLOTS):
		if slots[i]["type"] == block_type and slots[i]["count"] < MAX_STACK_SIZE:
			var space_available = MAX_STACK_SIZE - slots[i]["count"]
			var to_add = min(count, space_available)
			slots[i]["count"] += to_add
			inventory_changed.emit(i)
			count -= to_add
			if count <= 0:
				return 0
	
	# Add to empty slots
	for i in range(MAX_SLOTS):
		if slots[i]["type"] == null:
			var to_add = min(count, MAX_STACK_SIZE)
			slots[i]["type"] = block_type
			slots[i]["count"] = to_add
			inventory_changed.emit(i)
			count -= to_add
			if count <= 0:
				return 0
	
	# Return remaining count if inventory is full
	return count

func remove_item(slot: int, count: int = 1) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	
	if slots[slot]["type"] == null or slots[slot]["count"] < count:
		return false
	
	slots[slot]["count"] -= count
	if slots[slot]["count"] <= 0:
		slots[slot]["type"] = null
		slots[slot]["count"] = 0
	
	inventory_changed.emit(slot)
	return true

func get_selected_item() -> Dictionary:
	if selected_slot >= 0 and selected_slot < MAX_SLOTS:
		return slots[selected_slot].duplicate()
	return {"type": null, "count": 0}

func has_item_in_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	return slots[slot]["type"] != null and slots[slot]["count"] > 0

func set_selected_slot(slot: int):
	if slot >= 0 and slot < MAX_SLOTS:
		selected_slot = slot
		selected_slot_changed.emit(selected_slot)

func get_slot(slot: int) -> Dictionary:
	if slot >= 0 and slot < MAX_SLOTS:
		return slots[slot].duplicate()
	return {"type": null, "count": 0}

func get_block_type_from_name(block_name: String) -> BlockManager.BlockType:
	# Convert block name to BlockType
	var name_lower = block_name.to_lower()
	if name_lower.contains("grass"):
		return BlockManager.BlockType.GRASS
	elif name_lower.contains("dirt"):
		return BlockManager.BlockType.DIRT
	elif name_lower.contains("stone"):
		return BlockManager.BlockType.STONE
	elif name_lower.contains("sand"):
		return BlockManager.BlockType.SAND
	elif name_lower.contains("gravel"):
		return BlockManager.BlockType.GRAVEL
	elif name_lower.contains("wood"):
		return BlockManager.BlockType.WOOD
	elif name_lower.contains("snow"):
		return BlockManager.BlockType.SNOW
	elif name_lower.contains("water"):
		return BlockManager.BlockType.WATER
	elif name_lower.contains("lava"):
		return BlockManager.BlockType.LAVA
	elif name_lower.contains("glass"):
		return BlockManager.BlockType.GLASS
	elif name_lower.contains("metal"):
		return BlockManager.BlockType.METAL
	return BlockManager.BlockType.GRASS  # Default fallback

