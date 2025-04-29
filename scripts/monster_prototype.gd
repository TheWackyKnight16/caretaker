extends CharacterBody3D

@onready var nav_agent = $NavigationAgent3D
@onready var navmesh = $"../NavigationRegion3D"
@onready var wandering_points_holder = $"../WanderingPoints"
@onready var hearing_radius = $HearingRadius
@onready var animation_tree: AnimationTree = $AnimationTree

#debug stuff
@onready var debug_target = $"../Nav Target"
@onready var ray_pos_one = $"../RayPosOne"
@onready var ray_pos_two = $"../RayPosTwo"

@export_category("Movement Variables")
@export var movement_speed: float = 2.0

@export_category("Hearing Variables")
@export var base_hearing_radius: float = 60.0
@export var hearing_sensitivity: float = 1.0

@export_category("Wandering State")
@export var wandering_movement_speed: float = 2
@export var wandering_delay: float = 2
var wandering_points: Array = []
var wandering_timer: float = 0

@export_category("Alert State")
var alert_wait_time: float = 4
var alert_timer: float = 0
var alert_decided: bool = false
var alert_chance: float = 0.8
var importance_threshold: float = 0.3

@export_category("Investigating State")
var investigation_movement_speed: float = 3
var investigation_time: float = 10
var investigation_timer: float = 0
var investigation_radius: float = 10

var player
enum States {WANDERING, ALERT, STALKING, SEARCHING, ATTACKING}
var state: States = States.WANDERING

var last_heard_position: Vector3 = Vector3.ZERO
var last_heard_type: String = ""
var last_heard_volume: float = 0

var last_heard_sounds: Array = []
var sorted_heard_sounds: Array = []
var sound_memory_time: float = 30

var last_known_player_pos: Vector3 = Vector3.ZERO

var animation_playback: AnimationNodeStateMachinePlayback

func _ready():
	player = $"../Player"
	
	animation_playback = animation_tree.get("parameters/playback")
	
	SoundManager.sound_emitted.connect(on_sound_heard)
	for point in wandering_points_holder.get_children():
		wandering_points.append(point)

func _process(delta):
	match state:
		States.WANDERING:
			update_wandering(delta)
			move_toward_target()
		States.ALERT:
			if alert_timer >= alert_wait_time:
				state = States.SEARCHING
			else:
				alert_timer += delta
		
	if debug_target:
		debug_target.position = nav_agent.target_position

func update_wandering(delta):
	movement_speed = wandering_movement_speed
	if nav_agent.is_navigation_finished():
		wandering_timer += delta
		 
		if wandering_timer >= wandering_delay:
			nav_agent.target_position = wandering_points[randi() % wandering_points.size()].global_position
			wandering_timer = 0

func on_sound_heard(sound_position: Vector3, sound_volume: float, sound_type: String):
	var distance_to_sound = global_position.distance_to(sound_position)
	var effective_hearing_range = base_hearing_radius * hearing_sensitivity
	
	
	var space_state = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(global_position, sound_position)
	ray_query.collision_mask = 4
	var ray_result = space_state.intersect_ray(ray_query)
	
	var is_occluded = false
	if ray_result:
		is_occluded = true
	
	# debug hearing radius
	hearing_radius.mesh.radius = effective_hearing_range
	hearing_radius.mesh.height = effective_hearing_range * 2
	
	if distance_to_sound <= effective_hearing_range:
		#print(name + " heard a " + sound_type + " at " + str(sound_position))
		#print(sound_volume)
		
		last_heard_position = sound_position
		last_heard_volume = sound_volume
		last_heard_type = sound_type
		
		var type_weight = 0
		match last_heard_type:
			"shotgun": type_weight = 1
			"footstep": type_weight = 0.1
			_: type_weight = 0
			
		var proximity_score = (1.0 - clampf(distance_to_sound / effective_hearing_range, 0.0, 1.0))
		var volume_weight = clampf(sound_volume / 10 , 0.0, 1.0) # the 10 is the loudest sound
		var calculated_importance =  clampf((sound_volume * volume_weight) + type_weight + proximity_score, 0.0, 1.0)
		
		var sound_data = {
			"position": sound_position,
			"volume": sound_volume,
			"type": sound_type,
			"importance": calculated_importance,
			"time_heard": Time.get_ticks_msec() / 1000.0
		}
		
		last_heard_sounds.append(sound_data)
		
		for sound in last_heard_sounds:
			if sound["time_heard"] < (Time.get_ticks_msec() / 1000.0) - sound_memory_time:
				#print("Erased Sound With time: " + str(sound["time_heard"]) + "\nCurrent Time: " + str(Time.get_ticks_msec() / 1000.0))
				last_heard_sounds.erase(sound)
		
		if last_heard_sounds.size() >= 30:
			#print("Erased Sound: " + str(last_heard_sounds[0]))
			last_heard_sounds.remove_at(0)
		
		sorted_heard_sounds.clear()
		sorted_heard_sounds = last_heard_sounds.duplicate()
		sorted_heard_sounds.sort_custom(compare_importance)
		
		#print("Sorted sounds: \n")
		#for sound in sorted_heard_sounds:
			#print("Sound Importance: " + str(sound["importance"]) + " Sound Heard Time: " + str(sound["time_heard"]))
		
		match state:
			States.WANDERING:
				print("Heard sound while: WANDERING")
				print(sorted_heard_sounds[0])
				if sorted_heard_sounds[0]["importance"] >= 0.5:
					alert_timer = 0
					state = States.ALERT
					
					animation_playback.travel("t-pose")
			States.SEARCHING:
				pass

func move_toward_target():
	if nav_agent.is_navigation_finished():
		return
	
	animation_playback.travel("walking")
	
	var next_point = nav_agent.get_next_path_position()
	var target_dir = (next_point - global_position).normalized()
	var move_dir = Vector3(target_dir.x, 0, target_dir.z)
	
	velocity = move_dir * movement_speed
	
	rotation.y = lerp(rotation.y, atan2(velocity.x, velocity.z), 1)
	
	move_and_slide()

func compare_importance(a, b):
	if b == a:
		return b["time_heard"] < a["time_heard"]
	else:
		return b["importance"] < a["importance"]
