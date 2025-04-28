extends Node

signal sound_emitted(sound_position: Vector3, sound_volume: float, sound_type: String)

func emit_sound_event(pos: Vector3, volume: float, type: String = "generic"):
	emit_signal("sound_emitted", pos, volume, type)
