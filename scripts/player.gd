extends CharacterBody3D

signal step_taken

@onready var cam = $Camera3D
@onready var step_audio = $AudioStreamPlayer3D
@onready var footstep_emitter = $FootstepEventEmitter3D

@export_category("Movement Speed")
@export var sprint_speed: float = 4.5
@export var walk_speed: float = 3
@export var slow_walk_speed: float = 1.5

@export_category("Volume")
@export var sprint_volume: float = 1.5
@export var walk_volume: float = 1
@export var slow_walk_volume: float = 0.5

@export_category("Misc")
@export var mouse_sensitivity: float = 0.002
@export var step_distance_threshold: float = 2.0

var move_speed: float = 3
var is_sprinting = false
var is_slow_walking = false

var step_distance: float = 0.0
var last_step_pos

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	last_step_pos = global_position

func _physics_process(delta):
	handle_movement()
	handle_footsteps()

func handle_movement():
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var move_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	
	move_and_slide()

func _input(event):
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			cam.rotate_x(-event.relative.y * mouse_sensitivity)
			cam.rotation.x = clamp(cam.rotation.x, -deg_to_rad(80), deg_to_rad(80))
			
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if Input.is_action_pressed("slow walk"):
		move_speed = slow_walk_speed
		is_slow_walking = true
	else:
		move_speed = walk_speed
		is_slow_walking = false
	
	if Input.is_action_pressed("sprint"):
		move_speed = sprint_speed
		is_sprinting = true
	else:
		move_speed = walk_speed
		is_sprinting = false

func handle_footsteps():
	var dist = last_step_pos.distance_to(global_position)
	step_distance += dist
	last_step_pos = global_position
	
	if step_distance >= step_distance_threshold:
		if is_slow_walking:
			footstep_emitter.volume = 0.5
			SoundManager.emit_sound_event(global_position, slow_walk_volume, "footstep")
		elif is_sprinting:
			footstep_emitter.volume = 1.5
			SoundManager.emit_sound_event(global_position, sprint_volume, "footstep")
		else: 
			footstep_emitter.volume = 1
			SoundManager.emit_sound_event(global_position, walk_volume, "footstep")
		
		footstep_emitter.play()
		
		step_taken.emit()
		
		step_distance = 0
