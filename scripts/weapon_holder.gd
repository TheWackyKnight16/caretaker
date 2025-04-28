extends Node3D

@onready var player = $"../.."

@export_category("Sway & Bob")
@export var sway_strength: float = 0.05
@export var sway_return_speed: float = 6.0
@export var move_sway_strength: float = 0.02
@export var move_sway_speed: float = 4.0

@export_category("Idle")
@export var idle_sway_amplitude_pos: Vector3 = Vector3(0.002, 0.003, 0.0)
@export var idle_sway_amplitude_rot: Vector3 = Vector3(0.05, 0.05, 0.0) # In degrees
@export var idle_sway_speed: float = 0.5

# --- Recoil State & Recovery Exports (Add these) ---
@export_category("Recoil Recovery")
@export var recoil_recover_speed: float = 10.0
@export var recoil_return_speed: float = 5.0

# --- Internal State Variables ---
var target_sway = Vector3.ZERO
var current_sway = Vector3.ZERO
var target_move_bob = Vector3.ZERO
var current_move_bob = Vector3.ZERO

# Recoil state (Moved here)
var current_recoil_rot = Vector3.ZERO
var current_recoil_pos = Vector3.ZERO
var target_recoil_rot = Vector3.ZERO
var target_recoil_pos = Vector3.ZERO

@export var step_bob_offset: Vector3 = Vector3(0.0, -0.5, 0.0)
var step_bob_amount = Vector3.ZERO

@onready var original_local_position = position
@onready var original_local_basis = transform.basis

func _ready():
	set_physics_process(true)
	original_local_position = position
	original_local_basis = transform.basis
	
	player.connect("step_taken", Callable(self, "on_step_taken"), CONNECT_PERSIST)

func _input(event):
	if event is InputEventMouseMotion:
		target_sway.x -= event.relative.y * sway_strength * 0.01
		target_sway.y -= event.relative.x * sway_strength * 0.01
		
		target_sway.x = clamp(target_sway.x, -0.5, 0.5)
		target_sway.y = clamp(target_sway.y, -0.7, 0.7)

func apply_recoil_impulse(p_kick_rot_deg: Vector3, p_kick_pos: Vector3):
	var kick_rot_rad = Vector3(
		deg_to_rad(p_kick_rot_deg.x),
		deg_to_rad(p_kick_rot_deg.y),
		deg_to_rad(p_kick_rot_deg.z)
	)
	
	target_recoil_rot += kick_rot_rad
	target_recoil_pos += p_kick_pos

func update_recoil(delta):
	current_recoil_rot = lerp(current_recoil_rot, target_recoil_rot, recoil_recover_speed * delta)
	current_recoil_pos = lerp(current_recoil_pos, target_recoil_pos, recoil_recover_speed * delta)
	
	target_recoil_rot = lerp(target_recoil_rot, Vector3.ZERO, recoil_return_speed * delta)
	target_recoil_pos = lerp(target_recoil_pos, Vector3.ZERO, recoil_return_speed * delta)

func on_step_taken():
	step_bob_amount = step_bob_offset

func _physics_process(delta):
	update_recoil(delta)
	
	target_sway = lerp(target_sway, Vector3.ZERO, sway_return_speed * delta)
	current_sway = lerp(current_sway, target_sway, sway_return_speed * 2.0 * delta)
	
	var velocity = player.velocity
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var speed = horizontal_velocity.length()
	
	if speed > 0.1:
		var time = Time.get_ticks_msec() * 0.001
		var bob_amount_x = sin(time * move_sway_speed) * move_sway_strength * speed * 0.1
		var bob_amount_y = cos(time * move_sway_speed * 2.0) * move_sway_strength * speed * 0.05
		target_move_bob = Vector3(bob_amount_x, bob_amount_y, 0) + step_bob_amount
	else:
		target_move_bob = Vector3.ZERO
	
	step_bob_amount = Vector3.ZERO
	
	current_move_bob = lerp(current_move_bob, target_move_bob, move_sway_speed * delta)
	
	var time = Time.get_ticks_msec() * 0.001 * idle_sway_speed
	var idle_offset_pos = Vector3(
		sin(time) * idle_sway_amplitude_pos.x,
		cos(time * 1.2) * idle_sway_amplitude_pos.y,
		0
	)
	var idle_offset_rot = Vector3(
		sin(time * 0.8) * deg_to_rad(idle_sway_amplitude_rot.x),
		cos(time) * deg_to_rad(idle_sway_amplitude_rot.y),
		0
	)
	
	var final_target_pos = original_local_position + current_move_bob + idle_offset_pos + current_recoil_pos
	
	var combined_sway_x = current_sway.x + idle_offset_rot.x + current_recoil_rot.x
	var combined_sway_y = current_sway.y + idle_offset_rot.y + current_recoil_rot.y
	var combined_sway_z = current_recoil_rot.z
	
	var final_target_rot_basis = Basis.IDENTITY.rotated(Vector3.UP, combined_sway_y).rotated(Vector3.RIGHT, combined_sway_x).rotated(Vector3.FORWARD, combined_sway_z)
	
	var rot_interp_speed = sway_return_speed
	var pos_interp_speed = move_sway_speed
	
	transform.basis = transform.basis.slerp(final_target_rot_basis, rot_interp_speed * delta)
	position = lerp(position, final_target_pos, pos_interp_speed * delta)
