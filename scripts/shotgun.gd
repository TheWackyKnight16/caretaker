extends Node3D

@onready var barrel_position = $BarrelPosition
@onready var shotgun_emitter = $ShotgunEventEmitter3D

var weapon_holder

const BULLET_IMPACT = preload("res://scenes/bullet_impact.tscn")

@export_category("Recoil Kick")
@export var recoil_impulse_rot_deg: Vector3 = Vector3(-5.0, 0.5, 0.0)
@export var recoil_impulse_pos: Vector3 = Vector3(0.0, 0.01, -0.05)

@export_category("Weapon Variables")
@export var ray_distance: float = 15
@export var spread: float = 5
@export var projectiles: int = 16
@export var max_ammo: int = 10
var current_ammo: int = 1

@export var shotgun_volume: float = 10

func _ready():
	current_ammo = max_ammo

func _process(delta):
	if Input.is_action_just_pressed("shoot"):
		shoot()
	
	weapon_holder = get_parent()

func shoot():
	if current_ammo <= 0:
		return
	
	SoundManager.emit_sound_event(global_position, shotgun_volume, "shotgun")
	shotgun_emitter.play()
	
	var random_rot_y_deg = randf_range(-recoil_impulse_rot_deg.y, recoil_impulse_rot_deg.y)
	var kick_rotation_deg = Vector3(recoil_impulse_rot_deg.x, random_rot_y_deg, recoil_impulse_rot_deg.z)
	var kick_position = recoil_impulse_pos
	
	if weapon_holder and weapon_holder.has_method("apply_recoil_impulse"):
		weapon_holder.apply_recoil_impulse(kick_rotation_deg, kick_position)
	else:
		push_warning("WeaponHolder reference not found or doesn't have apply_recoil_impulse method.")
	
	
	for i in range(projectiles):
			var shoot_ray = RayCast3D.new()
			add_child(shoot_ray)
			
			shoot_ray.global_position = barrel_position.global_position
			shoot_ray.target_position = Vector3(0, 0, -ray_distance)
			shoot_ray.rotation.x = deg_to_rad(randf_range(-spread, spread))
			shoot_ray.rotation.y = deg_to_rad(randf_range(-spread, spread))
			shoot_ray.force_raycast_update()
			
			if shoot_ray.is_colliding():
				var collider = shoot_ray.get_collider()
				var hit_point = shoot_ray.get_collision_point()
				
				var bullet_impact = BULLET_IMPACT.instantiate()
				collider.add_child(bullet_impact)
				var bullet_particles = bullet_impact.get_child(0)
				bullet_particles.emitting = true
				bullet_impact.global_position = hit_point + (shoot_ray.get_collision_normal() / 100)
				bullet_impact.look_at(bullet_impact.global_position + shoot_ray.get_collision_normal())
			
			shoot_ray.queue_free()
	current_ammo -= 1
