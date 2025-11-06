extends Node

# BlockManager - Manages loading and caching of block models
# Loads GLTF block models from Assets/gltf/ folder

var block_cache: Dictionary = {}
var block_scenes: Dictionary = {}

# Common block types for terrain generation
enum BlockType {
	GRASS,
	DIRT,
	STONE,
	SAND,
	GRAVEL,
	WOOD,
	SNOW,
	WATER,
	LAVA,
	GLASS,
	METAL
}

# Map block types to GLTF file names
var block_type_to_file: Dictionary = {
	BlockType.GRASS: "grass",
	BlockType.DIRT: "dirt",
	BlockType.STONE: "stone",
	BlockType.SAND: "sand_A",
	BlockType.GRAVEL: "gravel",
	BlockType.WOOD: "wood",
	BlockType.SNOW: "snow",
	BlockType.WATER: "water",
	BlockType.LAVA: "lava",
	BlockType.GLASS: "glass",
	BlockType.METAL: "metal"
}

func _ready():
	# Preload common block types for better performance
	preload_common_blocks()

func preload_common_blocks():
	# Preload the most commonly used blocks
	var common_blocks = [
		BlockType.GRASS,
		BlockType.DIRT,
		BlockType.STONE,
		BlockType.SAND,
		BlockType.WOOD
	]
	
	for block_type in common_blocks:
		load_block(block_type)

func load_block(block_type: BlockType) -> PackedScene:
	# Check if already cached
	if block_scenes.has(block_type):
		return block_scenes[block_type]
	
	# Get the file name for this block type
	var file_name = block_type_to_file.get(block_type, "grass")
	var gltf_path = "res://Assets/gltf/" + file_name + ".gltf"
	
	# Check if file exists
	if not ResourceLoader.exists(gltf_path):
		print("Warning: Block model not found: ", gltf_path)
		# Fallback to grass if file doesn't exist
		if block_type != BlockType.GRASS:
			return load_block(BlockType.GRASS)
		return null
	
	# Load the GLTF scene
	var gltf_scene = load(gltf_path) as PackedScene
	if gltf_scene == null:
		print("Error: Failed to load block model: ", gltf_path)
		return null
	
	# Cache the scene
	block_scenes[block_type] = gltf_scene
	return gltf_scene

func get_block_instance(block_type: BlockType) -> Node3D:
	# Load the block scene if not already loaded
	var block_scene = load_block(block_type)
	if block_scene == null:
		print("Error: Failed to load block scene for type: ", block_type)
		return null
	
	# Instantiate the block
	var instance = block_scene.instantiate()
	if instance == null:
		print("Error: Failed to instantiate block for type: ", block_type)
		return null
	
	# CRITICAL: Check if the root node itself is a physics body
	# GLTF imports might create RigidBody3D as the root
	if instance is RigidBody3D:
		print("ERROR: Block root is RigidBody3D! Converting to Node3D...")
		# Create a new Node3D to replace it
		var new_root = Node3D.new()
		new_root.name = instance.name
		new_root.transform = instance.transform
		# Move all children
		var children = []
		for child in instance.get_children():
			children.append(child)
		for child in children:
			instance.remove_child(child)
			new_root.add_child(child)
			child.owner = new_root
		instance.queue_free()
		instance = new_root
	elif instance is CharacterBody3D or instance is Area3D:
		print("ERROR: Block root is ", instance.get_class(), "! Converting to Node3D...")
		var new_root = Node3D.new()
		new_root.name = instance.name
		new_root.transform = instance.transform
		var children = []
		for child in instance.get_children():
			children.append(child)
		for child in children:
			instance.remove_child(child)
			new_root.add_child(child)
			child.owner = new_root
		instance.queue_free()
		instance = new_root
	
	# Remove any physics bodies that might cause blocks to fall
	remove_physics_bodies(instance)
	
	# Apply texture if available
	apply_texture_to_block(instance)
	
	# Return the instance - physics will be set up after adding to scene
	return instance

func remove_physics_bodies(node: Node):
	# Remove any RigidBody3D, CharacterBody3D, or Area3D that might cause physics
	# Check recursively through all children
	var to_remove = []
	for child in node.get_children():
		if child is RigidBody3D:
			to_remove.append(child)
			print("Warning: Found RigidBody3D in block, removing: ", child.name)
		elif child is CharacterBody3D:
			to_remove.append(child)
			print("Warning: Found CharacterBody3D in block, removing: ", child.name)
		elif child is Area3D:
			to_remove.append(child)
			print("Warning: Found Area3D in block, removing: ", child.name)
		else:
			# Recursively check children
			remove_physics_bodies(child)
	
	for child in to_remove:
		node.remove_child(child)
		child.queue_free()
	

func ensure_block_collision(static_body: StaticBody3D):
	# Ensure the StaticBody3D has a valid collision shape
	# This is called after the block is added to the scene tree
	if not static_body.is_inside_tree():
		return
	
	# Remove any existing collision shapes first (in case they were added incorrectly)
	var existing_collision_shapes = []
	for child in static_body.get_children():
		if child is CollisionShape3D:
			existing_collision_shapes.append(child)
	for shape in existing_collision_shapes:
		static_body.remove_child(shape)
		shape.queue_free()
	
	# Add collision shape AFTER node is in tree - this ensures physics server registers it
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	# Standard 1x1x1 collision box
	# The collision box should be exactly 1.0 to match block size
	box_shape.size = Vector3(1.0, 1.0, 1.0)
	collision_shape.shape = box_shape
	# Position at (0, 0.5, 0) so the 1x1x1 box extends from y=0 to y=1
	collision_shape.position = Vector3(0, 0.5, 0)
	
	# Add as first child to ensure it's processed first
	static_body.add_child(collision_shape)
	collision_shape.owner = static_body
	
	# CRITICAL: Ensure the collision shape is properly registered
	# Set disabled to false explicitly (should be default, but be sure)
	collision_shape.disabled = false
	
	# Force physics update - this ensures the physics server sees the shape
	collision_shape.set_notify_transform(true)
	
	# Ensure collision layers are set
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	# Force the physics server to update the StaticBody3D
	static_body.set_notify_transform(true)
	
	# Note: Physics server will register the collision shape automatically
	# The physics frames we wait for in World.gd ensure proper registration

func create_block_with_physics(block_node: Node3D, position: Vector3) -> StaticBody3D:
	# Create a StaticBody3D wrapper for the block
	# This ensures collision works properly from the start
	var static_body = StaticBody3D.new()
	static_body.name = block_node.name
	# Ensure exact integer positioning to prevent z-fighting
	# Blocks are positioned at integer coordinates (x, y, z)
	# The collision box is 1x1x1 and positioned at (0, 0.5, 0) relative to the block
	# This means a block at (x, y, z) has collision from (x, y, z) to (x+1, y+1, z+1)
	# Use consistent position calculation: position should already be exact integers from World.gd
	# But ensure it's exactly at integer coordinates
	var exact_x = float(int(round(position.x)))
	var exact_y = float(int(round(position.y)))
	var exact_z = float(int(round(position.z)))
	static_body.position = Vector3(exact_x, exact_y, exact_z)
	static_body.rotation = Vector3.ZERO  # No rotation to prevent alignment issues
	static_body.scale = Vector3.ONE  # No scaling to prevent size mismatches
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	# Copy metadata from block_node to static_body
	if block_node.has_meta("block_type"):
		static_body.set_meta("block_type", block_node.get_meta("block_type"))
	
	# NOTE: Do NOT add collision shape here - it will be added after the node is in the scene tree
	# This ensures the physics server properly registers it
	
	# Remove any physics bodies from the block (but keep mesh children)
	remove_physics_bodies(block_node)
	
	# Move all remaining children (mesh, etc.) to static_body
	# CRITICAL: Reset transforms to prevent overlap/positioning issues
	var children = []
	for child in block_node.get_children():
		# Skip any collision shapes that might be in the GLTF (we have our own)
		if child is CollisionShape3D:
			continue
		children.append(child)
	for child in children:
		block_node.remove_child(child)
		
		# CRITICAL: Unset owner before adding to new parent to avoid owner inconsistency warning
		if child.owner != null:
			child.owner = null
		
		static_body.add_child(child)
		child.owner = static_body
		
		# Reset transform to origin - the StaticBody3D's position handles world positioning
		# This prevents blocks from overlapping due to inherited transforms from GLTF models
		child.position = Vector3.ZERO
		child.rotation = Vector3.ZERO
		child.scale = Vector3.ONE
		
		# Also reset the transform matrix to ensure no inherited transforms
		child.transform = Transform3D.IDENTITY
		
		# For MeshInstance3D nodes, ensure they're properly centered
		# Some GLTF models might have mesh geometry offset from origin
		if child is MeshInstance3D:
			var mesh_instance = child as MeshInstance3D
			# Ensure mesh is centered at origin (0,0,0)
			mesh_instance.position = Vector3.ZERO
			mesh_instance.rotation = Vector3.ZERO
			mesh_instance.scale = Vector3.ONE
			mesh_instance.transform = Transform3D.IDENTITY
			
			# CRITICAL: Also check if the mesh itself has offset geometry
			# If the mesh has geometry offset, we may need to adjust or ensure it's centered
			# For now, we ensure the transform is at origin - the mesh geometry offset
			# should be handled by the GLTF import settings, but we can't fix it here
	
	# Clean up the old node
	block_node.queue_free()
	
	return static_body

func setup_block_physics(block_node: Node3D):
	# If the root is already a StaticBody3D with collision, we're done
	if block_node is StaticBody3D:
		ensure_collision_shape(block_node)
		block_node.collision_layer = 1
		block_node.collision_mask = 0
		return
	
	# Check if there's already a StaticBody3D child with collision
	for child in block_node.get_children():
		if child is StaticBody3D:
			var has_collision = false
			for grandchild in child.get_children():
				if grandchild is CollisionShape3D and grandchild.shape != null:
					has_collision = true
					break
			if has_collision:
				child.collision_layer = 1
				child.collision_mask = 0
				return
	
	# Create StaticBody3D wrapper at root level by replacing the node
	var parent = block_node.get_parent()
	if parent == null:
		# Not in scene tree yet - add as child (will be replaced later)
		var temp_static_body = StaticBody3D.new()
		temp_static_body.name = "BlockCollision"
		temp_static_body.collision_layer = 1
		temp_static_body.collision_mask = 0
		
		var temp_collision_shape = CollisionShape3D.new()
		var temp_box_shape = BoxShape3D.new()
		temp_box_shape.size = Vector3(1.0, 1.0, 1.0)
		temp_collision_shape.shape = temp_box_shape
		temp_collision_shape.position = Vector3(0, 0.5, 0)
		temp_static_body.add_child(temp_collision_shape)
		temp_static_body.owner = block_node
		
		block_node.add_child(temp_static_body)
		block_node.move_child(temp_static_body, 0)
		return
	
	# Block is in scene tree - wrap it in StaticBody3D
	# Save transform and name
	var saved_position = block_node.position
	var saved_rotation = block_node.rotation
	var saved_scale = block_node.scale
	var saved_name = block_node.name
	
	# Create StaticBody3D wrapper
	var static_body = StaticBody3D.new()
	static_body.name = saved_name
	static_body.position = saved_position
	static_body.rotation = saved_rotation
	static_body.scale = saved_scale
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	# Remove any existing physics bodies
	var to_remove = []
	for child in block_node.get_children():
		if child is RigidBody3D or child is CharacterBody3D or child is Area3D or child is StaticBody3D:
			to_remove.append(child)
		else:
			remove_physics_bodies(child)
	for child in to_remove:
		block_node.remove_child(child)
		child.queue_free()
	
	# Move all mesh children to static_body
	var children = []
	for child in block_node.get_children():
		children.append(child)
	for child in children:
		block_node.remove_child(child)
		static_body.add_child(child)
		child.owner = static_body
	
	# Add collision shape at origin
	# BoxShape3D with size (1,1,1) centered at origin extends from -0.5 to +0.5
	# We want collision from y=0 to y=1, so we position it at (0, 0.5, 0)
	# This makes it extend from y=0 to y=1
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 1.0)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, 0.5, 0)
	static_body.add_child(collision_shape)
	collision_shape.owner = static_body
	
	# CRITICAL: Ensure the collision shape is properly set up
	# Force the shape to be recognized by physics server
	if static_body.is_inside_tree():
		# Force update the physics body
		static_body.set_notify_transform(true)
	
	# Replace block_node with static_body in parent
	var block_index = block_node.get_index()
	parent.remove_child(block_node)
	parent.add_child(static_body)
	if block_index < parent.get_child_count() - 1:
		parent.move_child(static_body, block_index)
	static_body.owner = parent
	
	block_node.queue_free()

func ensure_collision_shape(static_body: StaticBody3D):
	# Check if it already has a valid CollisionShape3D
	var has_valid_collision = false
	for child in static_body.get_children():
		if child is CollisionShape3D:
			if child.shape != null:
				has_valid_collision = true
				break
			else:
				# Remove invalid collision shape
				child.queue_free()
	
	# Add a box collision shape if none exists
	if not has_valid_collision:
		var collision_shape = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		# Standard 1x1x1 block - size is the full dimensions
		box_shape.size = Vector3(1.0, 1.0, 1.0)
		collision_shape.shape = box_shape
		# Position at origin - box extends from -0.5 to +0.5 in all axes
		# But we want bottom at y=0, so center at y=0.5
		collision_shape.position = Vector3(0, 0.5, 0)
		static_body.add_child(collision_shape)
		collision_shape.owner = static_body
		
		# Ensure collision layers are set correctly (default layer 1)
		static_body.collision_layer = 1
		static_body.collision_mask = 0


func apply_texture_to_block(block_instance: Node3D):
	# Try to load and apply the block texture
	var texture_path = "res://Textures/block_bits_texture.png"
	if ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		if texture != null:
			# Apply texture to all MeshInstance3D nodes in the block
			apply_texture_recursive(block_instance, texture)

func apply_texture_recursive(node: Node, texture: Texture2D):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		# Depth testing is enabled by default in Godot 4
		# Set depth draw mode to always to ensure proper rendering
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		# Add polygon offset to prevent z-fighting between adjacent blocks
		# This pushes the geometry slightly away from the camera to prevent flickering
		material.depth_bias_enabled = true
		material.depth_bias = 0.0001  # Increased bias to better prevent z-fighting
		# Use polygon offset mode to push geometry away from camera
		material.depth_bias_slope_scale = 1.0
		# Use backface culling to improve performance and reduce rendering artifacts
		material.cull_mode = BaseMaterial3D.CULL_BACK
		# Disable transparency to prevent edge artifacts
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh_instance.material_override = material
	
	for child in node.get_children():
		apply_texture_recursive(child, texture)

func get_block_by_name(block_name: String) -> Node3D:
	# Load a block by its file name (without extension)
	var gltf_path = "res://Assets/gltf/" + block_name + ".gltf"
	
	if not ResourceLoader.exists(gltf_path):
		print("Warning: Block model not found: ", gltf_path)
		return null
	
	var gltf_scene = load(gltf_path) as PackedScene
	if gltf_scene == null:
		print("Error: Failed to load block model: ", gltf_path)
		return null
	
	var instance = gltf_scene.instantiate()
	setup_block_physics(instance)
	apply_texture_to_block(instance)
	return instance
