extends Node3D

# MiningEffect - Visual effect when a block is mined (shrinks and spins before pickup)

var block_type: BlockManager.BlockType
var target_position: Vector3
var pickup_distance: float = 2.0
var shrink_duration: float = 0.5
var spin_speed: float = 5.0

var elapsed_time: float = 0.0
var initial_scale: Vector3 = Vector3.ONE
var player: CharacterBody3D

func _ready():
	# Find player
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	
	# Start animation
	initial_scale = scale
	create_block_visual()

func create_block_visual():
	# Create a visual representation of the block
	var block_instance = BlockManager.get_block_instance(block_type)
	if block_instance == null:
		queue_free()
		return
	
	# CRITICAL: Recursively remove ALL physics bodies and collision shapes
	# This ensures no collision remains on the mining effect
	remove_all_physics_recursive(block_instance)
	
	# Reset transforms on mesh children
	for child in block_instance.get_children():
		if child is MeshInstance3D:
			child.position = Vector3.ZERO
			child.rotation = Vector3.ZERO
			child.scale = Vector3.ONE
	
	# Add as child
	add_child(block_instance)
	block_instance.position = Vector3.ZERO
	block_instance.rotation = Vector3.ZERO
	block_instance.scale = Vector3.ONE
	
	# Note: No collision_layer/mask needed - Node3D doesn't have these properties
	# All physics bodies have been removed recursively, so no collision exists

func remove_all_physics_recursive(node: Node):
	# Remove physics bodies and collision shapes recursively
	var to_remove = []
	for child in node.get_children():
		if child is CollisionShape3D or child is StaticBody3D or child is RigidBody3D or child is CharacterBody3D or child is Area3D:
			to_remove.append(child)
		else:
			# Recursively check children
			remove_all_physics_recursive(child)
	
	for child in to_remove:
		node.remove_child(child)
		child.queue_free()

func _process(delta):
	elapsed_time += delta
	
	# Spin the block
	rotate_y(delta * spin_speed)
	
	# Shrink the block
	var progress = elapsed_time / shrink_duration
	if progress >= 1.0:
		progress = 1.0
	
	var scale_factor = 1.0 - progress
	scale = initial_scale * scale_factor
	
	# Move towards player if close enough
	if player:
		var distance_to_player = global_position.distance_to(player.global_position)
		if distance_to_player < pickup_distance:
			# Move towards player
			var direction = (player.global_position - global_position).normalized()
			global_position += direction * delta * 3.0
			
			# If very close, collect it
			if distance_to_player < 0.5:
				collect_block()
				return
	
	# Remove if fully shrunk
	if progress >= 1.0:
		# Wait a bit before removing
		await get_tree().create_timer(0.1).timeout
		queue_free()

func collect_block():
	# Add to inventory
	var inventory = get_node_or_null("/root/Inventory")
	if inventory:
		inventory.add_item(block_type, 1)
	
	queue_free()

