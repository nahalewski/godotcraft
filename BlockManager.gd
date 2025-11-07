extends Node

# BlockManager - Manages loading and caching of block models
# Note: This is an autoload singleton, so we don't use class_name
# Loads GLTF block models from Assets/gltf/ folder

var block_cache: Dictionary = {}
var block_scenes: Dictionary = {}
# Cache for mesh scale factors per block type (calculated once per block type)
var block_mesh_scales: Dictionary = {}  # BlockType -> Array of scale data: [{mesh_path: String, scale: Vector3, offset: Vector3}, ...]
# Cache for fully-prepared template StaticBody3D nodes (ready to duplicate)
var block_templates: Dictionary = {}  # BlockType -> StaticBody3D (template node)

# Common block types for terrain generation
enum BlockType {
	GRASS,
	DIRT,
	STONE,
	BEDROCK,
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
	BlockType.BEDROCK: "stone",  # Use stone model for bedrock (or create separate bedrock model later)
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
	# Preload the most commonly used blocks and pre-calculate their scales
	var common_blocks = [
		BlockType.GRASS,
		BlockType.DIRT,
		BlockType.STONE,
		BlockType.SAND,
		BlockType.WOOD
	]
	
	for block_type in common_blocks:
		var block_scene = load_block(block_type)
		if block_scene:
			# Pre-calculate scales during preload
			if not block_mesh_scales.has(block_type):
				var temp_instance = block_scene.instantiate()
				if temp_instance:
					remove_physics_bodies(temp_instance)
					calculate_and_cache_mesh_scales(temp_instance, block_type)
					temp_instance.queue_free()
			
			# Pre-create template StaticBody3D for fast duplication
			create_block_template(block_type)

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

func create_block_template(block_type: BlockType) -> StaticBody3D:
	# Create a fully-prepared template StaticBody3D that can be duplicated quickly
	# This avoids expensive instantiation and setup for every block
	if block_templates.has(block_type):
		return block_templates[block_type]
	
	# Load the block scene if not already loaded
	var block_scene = load_block(block_type)
	if block_scene == null:
		print("Error: Failed to load block scene for type: ", block_type)
		return null
	
	# Pre-calculate scales if not already cached
	if not block_mesh_scales.has(block_type):
		var temp_instance = block_scene.instantiate()
		if temp_instance:
			remove_physics_bodies(temp_instance)
			calculate_and_cache_mesh_scales(temp_instance, block_type)
			temp_instance.queue_free()
	
	# Create template using the existing method
	var block_instance = get_block_instance_slow(block_type)
	if block_instance == null:
		return null
	
	# Create StaticBody3D wrapper at origin (template position)
	var template = create_block_with_physics(block_instance, Vector3.ZERO)
	
	# Manually create collision shape for template (needed for proper duplication)
	# Create collision shape directly without needing scene tree
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 1.0)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, 0.5, 0)
	collision_shape.disabled = false
	template.add_child(collision_shape)
	
	# Store template for fast duplication
	# Note: Template doesn't need to be in scene tree for duplication to work
	# Collision shapes will be properly duplicated when we duplicate the template
	block_templates[block_type] = template
	
	return template

func get_block_instance_slow(block_type: BlockType) -> Node3D:
	# Slow path: Full instantiation and setup (used for creating templates)
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
	if instance is RigidBody3D:
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
	elif instance is CharacterBody3D or instance is Area3D:
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
	
	# Remove any physics bodies
	remove_physics_bodies(instance)
	
	# Apply texture
	apply_texture_to_block(instance)
	
	return instance

func get_block_instance(block_type: BlockType) -> Node3D:
	# Fast path: Use template if available, otherwise fall back to slow path
	# Note: This returns a Node3D, but templates are StaticBody3D
	# We'll handle this in create_block_with_physics_fast
	
	# Ensure template exists
	if not block_templates.has(block_type):
		create_block_template(block_type)
	
	# Return null here - we'll use get_block_fast() instead which returns StaticBody3D
	return null

func get_block_fast(block_type: BlockType, position: Vector3) -> StaticBody3D:
	# Fast path: Duplicate from template (much faster than instantiating)
	if not block_templates.has(block_type):
		create_block_template(block_type)  # Create template synchronously
	
	var template = block_templates.get(block_type)
	if template == null:
		# Fallback to slow path
		var block_instance = get_block_instance_slow(block_type)
		if block_instance == null:
			return null
		return create_block_with_physics(block_instance, position)
	
	# Duplicate the template (fast operation - copies structure without full instantiation)
	# Use regular duplicate (DUPLICATE_USE_INSTANCING might not work properly for StaticBody3D)
	var duplicate = template.duplicate(0) as StaticBody3D
	if duplicate == null:
		# Fallback to slow path if duplication fails
		var block_instance = get_block_instance_slow(block_type)
		if block_instance == null:
			return null
		return create_block_with_physics(block_instance, position)
	
	# Set position and metadata
	duplicate.position = position
	if template.has_meta("block_type"):
		duplicate.set_meta("block_type", template.get_meta("block_type"))
	
	# Reset name (will be set by caller)
	duplicate.name = "Block_Template"
	
	# Ensure collision layers are set correctly
	duplicate.collision_layer = 1
	duplicate.collision_mask = 0
	
	# Ensure all collision shapes are properly configured
	for child in duplicate.get_children():
		if child is CollisionShape3D:
			child.disabled = false
	
	return duplicate

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
	# Ensure exact integer positioning to prevent z-fighting (best practice)
	# Blocks are positioned at integer grid coordinates: Vector3i * BLOCK_SIZE
	# The collision box is 1x1x1 and positioned at (0, 0.5, 0) relative to the block
	# This means a block at (x, y, z) has collision from (x, y, z) to (x+1, y+1, z+1)
	# Snap position to grid to ensure exact integer coordinates (prevents float drift)
	const BLOCK_SIZE = 1.0
	static_body.position = position.snapped(Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE))
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
	
	# Apply cached mesh scales (fast - no recalculation)
	apply_cached_scales_fast(static_body, block_node.get_meta("block_type") if block_node.has_meta("block_type") else BlockType.GRASS)
	
	# Clean up the old node
	block_node.queue_free()
	
	return static_body

func apply_cached_scales_fast(node: Node, block_type: BlockType):
	# Fast scaling using pre-calculated cache - no expensive AABB calculations
	# Scales are pre-calculated when blocks are first loaded, so this is just applying cached values
	var scale_data_array = block_mesh_scales.get(block_type, [])
	if scale_data_array.is_empty():
		# Fallback: should never happen if pre-caching works, but handle gracefully
		print("Warning: No cached scales for block type ", block_type, ", calculating now (slow!)")
		calculate_and_cache_mesh_scales(node, block_type)
		scale_data_array = block_mesh_scales.get(block_type, [])
	
	# Apply cached scales using index-based traversal (fast - just setting values)
	var mesh_index = 0
	apply_scales_by_index_recursive(node, scale_data_array, mesh_index)
	
func apply_scales_by_index_recursive(node: Node, scale_data_array: Array, mesh_index: int) -> int:
	# Apply cached scales by traversing in the same order they were calculated
	if node is MeshInstance3D:
		if mesh_index < scale_data_array.size():
			var scale_data = scale_data_array[mesh_index]
			if scale_data.has("scale") and scale_data.has("offset"):
				node.scale = scale_data.scale
				node.position = scale_data.offset
			mesh_index += 1
	
	# Recursively process all children
	for child in node.get_children():
		mesh_index = apply_scales_by_index_recursive(child, scale_data_array, mesh_index)
	
	return mesh_index

func calculate_and_cache_mesh_scales(node: Node, block_type: BlockType):
	# Calculate scales once per block type and cache them
	var scale_data_array: Array = []
	collect_mesh_scales_recursive(node, scale_data_array)
	block_mesh_scales[block_type] = scale_data_array

func collect_mesh_scales_recursive(node: Node, scale_data_array: Array):
	# Collect scale data for all meshes (called once per block type)
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			# Get AABB from the mesh resource directly
			var aabb = mesh_instance.mesh.get_aabb()
			if aabb.size.length() > 0.001:  # Avoid division by zero
				# Calculate scale needed to fit mesh in 1.0x1.0x1.0 box
				var mesh_size = aabb.size
				
				# Use uniform scale based on largest dimension to ensure it fits perfectly
				var max_dimension = max(mesh_size.x, mesh_size.y, mesh_size.z)
				if max_dimension > 0.001:
					var uniform_scale = 1.0 / max_dimension
					var scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
					
					# Center the mesh at origin (compensate for AABB center offset)
					var aabb_center = aabb.get_center()
					var offset = -aabb_center * uniform_scale
					
					# Cache the scale data
					scale_data_array.append({"scale": scale, "offset": offset})
				else:
					scale_data_array.append({"scale": Vector3.ONE, "offset": Vector3.ZERO})
			else:
				scale_data_array.append({"scale": Vector3.ONE, "offset": Vector3.ZERO})
	
	# Recursively process all children
	for child in node.get_children():
		collect_mesh_scales_recursive(child, scale_data_array)

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


func get_texture_for_block_type(block_type: BlockType) -> Texture2D:
	# Get the texture for a block type (used for mesh merging)
	var texture_path = "res://Textures/block_bits_texture.png"
	if ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		return texture
	return null

func apply_texture_to_block(block_instance: Node3D):
	# Try to load and apply the block texture
	var texture = get_texture_for_block_type(BlockType.STONE)  # Use default texture
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
