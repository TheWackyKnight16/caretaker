# MazeGenerator.gd
extends Node3D

## Generates a 3D maze with collision walls using Recursive Backtracking.
## Includes options for a 2x2 spawn room at (0,0) and random light placement.

# --- Export Variables ---
## The width of the maze in cells. Minimum 2 if spawn room is enabled.
@export var maze_width: int = 10
## The height (depth) of the maze in cells. Minimum 2 if spawn room is enabled.
@export var maze_height: int = 10
## The size of each cell (path width + wall thickness).
@export var cell_size: float = 2.5
## The thickness of the walls.
@export var wall_thickness: float = 0.5
## The height of the walls.
@export var wall_height: float = 3.0
## The PackedScene for the wall segment (StaticBody3D with MeshInstance3D and CollisionShape3D).
## IMPORTANT: This scene should have a MeshInstance3D with a BoxMesh resource
## and a CollisionShape3D with a BoxShape3D resource already assigned in the editor.
## Ensure the prefab has scale (1,1,1).
@export var wall_scene: PackedScene
## Seed for the random number generator. 0 means random seed.
@export var random_seed: int = 0
## Whether to add a floor plane beneath the maze.
@export var add_floor: bool = true
## Create a 2x2 open room at grid coordinates (0,0), (0,1), (1,0), (1,1).
@export var create_spawn_room: bool = true

# --- Light Options ---
## Optional PackedScene for lights to be randomly placed in cells.
@export var light_scene: PackedScene
## The probability (0.0 to 1.0) of a light spawning in any given cell.
@export_range(0.0, 1.0) var light_spawn_chance: float = 0.05
## Vertical offset for placing lights relative to the wall center height.
@export var light_vertical_offset: float = 0.0


# --- Internal Variables ---
# Stores removed walls. Key: canonical "first" cell. Value: Array of neighbors connected to the key cell.
var _removed_walls: Dictionary = {} # {Vector2i -> Array[Vector2i]}
var _visited: Array = [] # 2D array tracking visited cells [x][y]
var _rng := RandomNumberGenerator.new()
const MAZE_ELEMENT_GROUP = "maze_elements" # Group name for cleanup


# --- Godot Lifecycle Methods ---
func _ready() -> void:
	# Initialize random number generator
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

	# Generate and build the maze
	generate_maze()


# --- Maze Generation Logic ---
## Clears previous maze elements and generates a new one.
func generate_maze() -> void:
	# Basic validation for spawn room
	if create_spawn_room and (maze_width < 2 or maze_height < 2):
		printerr("Maze dimensions must be at least 2x2 to create a spawn room.")
		return
		
	_clear_maze() # Remove old walls, floor, and lights
	_initialize_grid()
	_prepare_spawn_room() # Handle spawn room setup before backtracking
	_perform_recursive_backtracking()
	_instantiate_walls()
	if add_floor:
		_add_floor_plane()
	_instantiate_lights() # Add lights after walls/floor

## Resets the internal grid and wall data structures.
func _initialize_grid() -> void:
	# Resize visited grid
	_visited.clear()
	_visited.resize(maze_width)
	for x in range(maze_width):
		_visited[x] = []
		_visited[x].resize(maze_height)
		for y in range(maze_height):
			_visited[x][y] = false
	# Clear the removed walls dictionary
	_removed_walls.clear()

## Pre-marks spawn room cells as visited and removes internal walls.
func _prepare_spawn_room() -> void:
	if not create_spawn_room:
		return # Do nothing if spawn room is disabled

	# Ensure dimensions are sufficient (checked in generate_maze, but good practice)
	if maze_width < 2 or maze_height < 2:
		return

	# Define the 4 cells of the spawn room
	var room_cells = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1)
	]

	# Mark these cells as visited
	for cell in room_cells:
		if _is_valid_cell(cell) and not _visited[cell.x][cell.y]: # Check validity just in case
			_visited[cell.x][cell.y] = true
			# Note: visited_count in backtracking will need to account for this

	# Remove the 4 internal walls within the 2x2 room
	_remove_wall(Vector2i(0, 0), Vector2i(1, 0)) # Wall between (0,0) and (1,0)
	_remove_wall(Vector2i(0, 0), Vector2i(0, 1)) # Wall between (0,0) and (0,1)
	_remove_wall(Vector2i(1, 0), Vector2i(1, 1)) # Wall between (1,0) and (1,1)
	_remove_wall(Vector2i(0, 1), Vector2i(1, 1)) # Wall between (0,1) and (1,1)


## The core Recursive Backtracking algorithm.
func _perform_recursive_backtracking() -> void:
	var stack: Array[Vector2i] = []
	# Ensure dimensions are valid (basic check)
	if maze_width <= 0 or maze_height <= 0:
		printerr("Maze dimensions must be positive.")
		return
		
	# Calculate initial visited count (accounts for spawn room if enabled)
	var visited_count = 0
	if create_spawn_room and maze_width >= 2 and maze_height >= 2:
		visited_count = 4 # Start with 4 visited cells for the spawn room
	
	var total_cells = maze_width * maze_height
	
	# Find a starting cell *outside* the spawn room if possible, otherwise pick any valid cell
	var start_cell := Vector2i(-1, -1) # Invalid initial value
	var potential_starts: Array[Vector2i] = []
	for x in range(maze_width):
		for y in range(maze_height):
			if not _visited[x][y]: # Find any unvisited cell
				potential_starts.append(Vector2i(x,y))
				
	if not potential_starts.is_empty():
		# Pick a random unvisited cell to start
		start_cell = potential_starts[_rng.randi() % potential_starts.size()]
	elif visited_count < total_cells:
		# This case should only happen if the grid is already fully visited (e.g., 2x2 with spawn room)
		# or if something went wrong.
		print("No unvisited cells found to start backtracking, but not all cells accounted for. Maze might be incomplete.")
		return # Nothing left to do
	else:
		# All cells were pre-visited (e.g., 2x2 grid with spawn room enabled)
		print("All cells pre-visited (likely due to spawn room in small maze). Skipping backtracking.")
		return # Maze is already 'generated' (fully open or just the room)

	# --- Start Backtracking ---
	var current_cell := start_cell
	_visited[current_cell.x][current_cell.y] = true
	visited_count += 1 # Increment for the actual starting cell

	while visited_count < total_cells:
		var neighbors = _get_unvisited_neighbors(current_cell)

		if not neighbors.is_empty():
			# Choose a random neighbor
			var next_cell = neighbors[_rng.randi() % neighbors.size()]

			# Push current cell to stack
			stack.push_back(current_cell)

			# Mark the wall between current and next cell as removed
			_remove_wall(current_cell, next_cell)

			# Move to the next cell
			current_cell = next_cell
			_visited[current_cell.x][current_cell.y] = true
			visited_count += 1
		elif not stack.is_empty():
			# Backtrack if no unvisited neighbors
			current_cell = stack.pop_back()
		else:
			# Algorithm finished (or got stuck)
			# Check if we got stuck prematurely
			if visited_count < total_cells:
				# Try to find another unvisited cell and restart from there (more robust)
				potential_starts.clear()
				for x in range(maze_width):
					for y in range(maze_height):
						if not _visited[x][y]:
							potential_starts.append(Vector2i(x,y))
				
				if not potential_starts.is_empty():
					current_cell = potential_starts[_rng.randi() % potential_starts.size()]
					_visited[current_cell.x][current_cell.y] = true
					visited_count += 1
					print("Restarting backtracking from an unvisited island at: ", current_cell)
					continue # Continue the while loop from the new cell
				else:
					# No more unvisited cells found, but count is still low? Error state.
					printerr("Maze generation algorithm stopped prematurely. Visited: ", visited_count, ", Total: ", total_cells)
					break # Exit loop
			else:
				# Normal finish
				break # Exit loop

## Finds valid, unvisited neighboring cells for a given cell.
func _get_unvisited_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)] # N, S, W, E

	for dir in directions:
		var neighbor_pos = cell + dir
		# Check if the neighbor is within grid bounds
		if _is_valid_cell(neighbor_pos):
			# Check if the neighbor hasn't been visited
			if not _visited[neighbor_pos.x][neighbor_pos.y]:
				neighbors.push_back(neighbor_pos)

	return neighbors

## Checks if a cell coordinate is within the maze boundaries.
func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < maze_width and \
		   cell.y >= 0 and cell.y < maze_height

## Records that the wall between two adjacent cells should be removed.
func _remove_wall(cell1: Vector2i, cell2: Vector2i) -> void:
	# Ensure cells are valid before proceeding
	if not _is_valid_cell(cell1) or not _is_valid_cell(cell2):
		printerr("Attempted to remove wall between invalid cells: ", cell1, ", ", cell2)
		return

	# Determine the canonical key (cell that comes first) and value (the other cell)
	var key = cell1 if (cell1.x < cell2.x or (cell1.x == cell2.x and cell1.y < cell2.y)) else cell2
	var value = cell2 if key == cell1 else cell1

	# Check if the key already exists in the dictionary
	if _removed_walls.has(key):
		# Key exists, append the value (neighbor) to the existing array if not already present
		if not _removed_walls[key].has(value):
			_removed_walls[key].push_back(value)
	else:
		# Key doesn't exist, create a new entry with an array containing the value
		_removed_walls[key] = [value]

## Checks if a wall should exist between two adjacent cells.
func _has_wall_between(cell1: Vector2i, cell2: Vector2i) -> bool:
	# Walls always exist at the boundary, check if either cell is out of bounds
	if not _is_valid_cell(cell1) or not _is_valid_cell(cell2):
		return true

	# Determine the canonical key/value pair for lookup
	var key = cell1 if (cell1.x < cell2.x or (cell1.x == cell2.x and cell1.y < cell2.y)) else cell2
	var value = cell2 if key == cell1 else cell1

	# Check if the key exists and the specific neighbor is connected
	if _removed_walls.has(key) and _removed_walls[key].has(value):
		return false # Wall was removed
	else:
		return true # Wall exists


# --- Wall, Floor, and Light Instantiation ---

## Removes previously generated maze elements using groups.
func _clear_maze() -> void:
	# Free all nodes in the maze element group
	get_tree().call_group(MAZE_ELEMENT_GROUP, "queue_free")

## Instantiates the wall segments based on the generated maze data.
func _instantiate_walls() -> void:
	if not wall_scene:
		printerr("MazeGenerator: Wall Scene is not assigned in the inspector!")
		return
	if not wall_scene.can_instantiate():
		printerr("MazeGenerator: Wall Scene cannot be instantiated. Check the scene file: ", wall_scene.resource_path)
		return

	# Calculate offset to center the maze around the node's origin
	var total_maze_width_units = maze_width * cell_size
	var total_maze_height_units = maze_height * cell_size
	var offset_x = -total_maze_width_units / 2.0
	var offset_z = -total_maze_height_units / 2.0

	# Instantiate Horizontal Walls (running along X-axis)
	for y in range(maze_height + 1):
		for x in range(maze_width):
			var cell_above = Vector2i(x, y - 1)
			var cell_below = Vector2i(x, y)
			if _has_wall_between(cell_above, cell_below):
				var wall_pos := Vector3(
					offset_x + x * cell_size + cell_size / 2.0,
					wall_height / 2.0,
					offset_z + y * cell_size
				)
				var wall_size := Vector3(cell_size, wall_height, wall_thickness)
				_create_wall_instance(wall_pos, wall_size)

	# Instantiate Vertical Walls (running along Z-axis)
	for x in range(maze_width + 1):
		for y in range(maze_height):
			var cell_left = Vector2i(x - 1, y)
			var cell_right = Vector2i(x, y)
			if _has_wall_between(cell_left, cell_right):
				var wall_pos := Vector3(
					offset_x + x * cell_size,
					wall_height / 2.0,
					offset_z + y * cell_size + cell_size / 2.0
				)
				var wall_size := Vector3(wall_thickness, wall_height, cell_size)
				_create_wall_instance(wall_pos, wall_size)

## Helper function to instantiate and configure a single wall segment.
func _create_wall_instance(pos: Vector3, size: Vector3) -> void:
	var wall_instance := wall_scene.instantiate() as StaticBody3D
	if not wall_instance:
		printerr("Failed to instantiate wall scene (returned null). Path: ", wall_scene.resource_path)
		return

	var mesh_instance := wall_instance.find_child("MeshInstance3D", true, false) as MeshInstance3D
	var collision_shape := wall_instance.find_child("CollisionShape3D", true, false) as CollisionShape3D

	if not mesh_instance or not collision_shape:
		printerr("Wall scene instance '", wall_scene.resource_path, "' is missing MeshInstance3D or CollisionShape3D child!")
		wall_instance.queue_free(); return

	var mesh_resource = mesh_instance.mesh
	var shape_resource = collision_shape.shape

	# Duplicate and resize Mesh
	if mesh_resource is BoxMesh:
		mesh_resource = mesh_resource.duplicate(true)
		mesh_instance.mesh = mesh_resource
		mesh_resource.size = size
	elif mesh_resource: printerr("Wall scene's MeshInstance3D mesh is not a BoxMesh! Path: ", wall_scene.resource_path); wall_instance.queue_free(); return
	else: printerr("Wall scene's MeshInstance3D has no mesh! Path: ", wall_scene.resource_path); wall_instance.queue_free(); return

	# Duplicate and resize Shape
	if shape_resource is BoxShape3D:
		shape_resource = shape_resource.duplicate(true)
		collision_shape.shape = shape_resource
		shape_resource.size = size
	elif shape_resource: printerr("Wall scene's CollisionShape3D shape is not a BoxShape3D! Path: ", wall_scene.resource_path); wall_instance.queue_free(); return
	else: printerr("Wall scene's CollisionShape3D has no shape! Path: ", wall_scene.resource_path); wall_instance.queue_free(); return

	wall_instance.position = pos
	wall_instance.name = "GeneratedWall"
	wall_instance.add_to_group(MAZE_ELEMENT_GROUP)
	add_child(wall_instance)

## Creates a large floor plane beneath the maze.
func _add_floor_plane() -> void:
	var floor := StaticBody3D.new()
	floor.name = "GeneratedFloor"

	var mesh_inst := MeshInstance3D.new()
	var collision_shape := CollisionShape3D.new()

	var plane_mesh := PlaneMesh.new()
	var floor_padding = cell_size
	plane_mesh.size = Vector2(maze_width*cell_size + floor_padding, maze_height*cell_size + floor_padding)
	mesh_inst.mesh = plane_mesh

	var box_shape_floor := BoxShape3D.new()
	var floor_thickness = 0.1
	box_shape_floor.size = Vector3(plane_mesh.size.x, floor_thickness, plane_mesh.size.y)
	collision_shape.shape = box_shape_floor
	collision_shape.position = Vector3(0, -floor_thickness / 2.0, 0)

	floor.add_child(mesh_inst)
	floor.add_child(collision_shape)
	floor.position = Vector3(0, 0, 0)
	floor.add_to_group(MAZE_ELEMENT_GROUP)
	add_child(floor)

## Instantiates lights randomly within maze cells.
func _instantiate_lights() -> void:
	if not light_scene:
		# print_debug("No light scene assigned, skipping light instantiation.")
		return # No light scene assigned, do nothing
	if light_spawn_chance <= 0.0:
		# print_debug("Light spawn chance is zero, skipping light instantiation.")
		return # Chance is zero, do nothing
	if not light_scene.can_instantiate():
		printerr("MazeGenerator: Light Scene cannot be instantiated. Check the scene file: ", light_scene.resource_path)
		return

	# Calculate offset to center the maze
	var total_maze_width_units = maze_width * cell_size
	var total_maze_height_units = maze_height * cell_size
	var offset_x = -total_maze_width_units / 2.0
	var offset_z = -total_maze_height_units / 2.0

	# Iterate through each cell in the grid
	for y in range(maze_height):
		for x in range(maze_width):
			# Check if a light should spawn based on probability
			if _rng.randf() < light_spawn_chance:
				# Calculate the center position of the current cell
				var light_pos := Vector3(
					offset_x + x * cell_size + cell_size / 2.0, # Center X of cell
					wall_height / 2.0 + light_vertical_offset, # Center Y of wall + offset
					offset_z + y * cell_size + cell_size / 2.0  # Center Z of cell
				)

				# Instantiate the light scene
				var light_instance := light_scene.instantiate() # Should be Node3D or derived
				if not light_instance is Node3D:
					printerr("Instantiated light scene is not a Node3D! Path: ", light_scene.resource_path)
					light_instance.queue_free() # Clean up invalid instance
					continue # Skip to next cell

				# Set position and add to the scene
				light_instance.position = light_pos
				light_instance.name = "GeneratedLight_%d_%d" % [x, y] # Unique name helpful for debugging
				light_instance.add_to_group(MAZE_ELEMENT_GROUP) # Add to group for cleanup
				add_child(light_instance)
