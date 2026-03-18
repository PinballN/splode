extends Area3D
class_name IncendiaryBomb

signal detonated(origin: Vector3, radius: float, concussion_value: float, fire_damage: float)

@export var bomb_id: StringName = &"test_incendiary"

# Loaded from BombRegistry.
var fuse_time: float = 10.0
var blast_radius: float = 5.0
var concussion_value: float = 0.15
var fire_damage: float = 3.0
var fire_radius: float = 6.0

@onready var fuse_timer: Timer = $FuseTimer
@onready var flash_light: OmniLight3D = get_node_or_null("FlashLight") as OmniLight3D
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SfxPlayer") as AudioStreamPlayer
@onready var bomb_mesh: MeshInstance3D = $MeshInstance3D as MeshInstance3D

var _time_left: float = 0.0

@export var beep_interval: float = 1.0
@export var beep_duration: float = 0.06
@export var beep_frequency_hz: float = 1200.0
@export var beep_amplitude: float = 0.12

@export var explosion_duration: float = 0.18
@export var explosion_amplitude: float = 0.35
var _explosion_amplitude_base: float = 0.35

@export var fast_beep_start_seconds_left: float = 2.0
@export var fast_beep_interval: float = 0.25

@export var beep_blink_light_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var beep_blink_light_energy: float = 5.0
@export var beep_blink_emission_energy_multiplier: float = 4.0
@export var min_beep_blink_seconds: float = 0.12

var _flash_light_base_visible := false
var _flash_light_base_energy := 0.0
var _flash_light_base_color: Color = Color(1, 1, 1, 1)
var _beep_cooldown_left: float = 0.0
var _last_beep_started_at_time_left: float = -1.0
var _beep_visual_time_left: float = 0.0

var _bomb_mesh_base_material_override: Material

var _sound_active: bool = false
var _sound_elapsed: float = 0.0
var _sound_duration: float = 0.0
var _sound_is_explosion: bool = false
var _sample_rate: float = 44100.0
var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0


func _ready() -> void:
	_load_bomb_stats()
	_explosion_amplitude_base = explosion_amplitude

	if flash_light:
		_flash_light_base_visible = flash_light.visible
		_flash_light_base_energy = flash_light.light_energy
		_flash_light_base_color = flash_light.light_color

	if bomb_mesh:
		_bomb_mesh_base_material_override = bomb_mesh.material_override

	fuse_timer.wait_time = fuse_time
	fuse_timer.timeout.connect(_detonate)
	_time_left = fuse_time
	# Kick off the HUD countdown immediately when the bomb is planted.
	get_tree().call_group("mission", "on_bomb_armed", fuse_time)
	fuse_timer.start()
	_beep_cooldown_left = 0.0
	set_process(true)

	if sfx_player and sfx_player.stream is AudioStreamGenerator:
		var gen: AudioStreamGenerator = sfx_player.stream as AudioStreamGenerator
		_sample_rate = float(gen.mix_rate)


func _process(delta: float) -> void:
	# Keep a local countdown for UI; actual detonation is driven by the Timer.
	_time_left -= delta
	if _time_left < 0.0:
		_time_left = 0.0

	# Turn off beep visuals after the beep duration, even if no SFX is configured.
	if _beep_visual_time_left > 0.0:
		_beep_visual_time_left -= delta
		if _beep_visual_time_left <= 0.0:
			_beep_visual_time_left = 0.0
			if flash_light:
				flash_light.visible = _flash_light_base_visible
				flash_light.light_energy = _flash_light_base_energy
				flash_light.light_color = _flash_light_base_color
			if bomb_mesh:
				bomb_mesh.material_override = _bomb_mesh_base_material_override

	# Quiet digital-ish beep: once per whole second while counting down.
	var seconds_left: int = int(ceil(_time_left - 0.0001))
	if seconds_left < 0:
		seconds_left = 0

	# Beep cadence can speed up near detonation.
	if _time_left > 0.0 and beep_interval > 0.0:
		var interval: float = beep_interval
		if _time_left <= fast_beep_start_seconds_left:
			interval = maxf(fast_beep_interval, 0.01)

		_beep_cooldown_left -= delta
		if _beep_cooldown_left <= 0.0:
			# Avoid double-triggering when seconds_left changes but interval is small.
			if absf(_last_beep_started_at_time_left - _time_left) > 0.02 or interval >= 0.99:
				_last_beep_started_at_time_left = _time_left
				_start_beep()
				_beep_cooldown_left = interval

	# Feed procedural audio buffer if we are currently playing a generated sound.
	_fill_sfx_audio()

	get_tree().call_group("mission", "on_bomb_countdown", _time_left)


func _detonate() -> void:
	# Ensure any beep blink is cleared when the explosion starts.
	_beep_visual_time_left = 0.0

	_start_explosion()
	detonated.emit(global_position, blast_radius, concussion_value, fire_damage)
	get_tree().call_group("mission", "register_explosion", global_position, fire_radius, concussion_value, fire_damage)
	get_tree().call_group("mission", "on_bomb_detonated")

	if flash_light:
		flash_light.visible = true

	# Keep the node alive long enough for the generated boom sound to play.
	await get_tree().create_timer(explosion_duration).timeout
	queue_free()


func _start_beep() -> void:
	# Visual blink first (works even if no SFX is configured).
	if flash_light:
		flash_light.visible = true
		flash_light.light_color = beep_blink_light_color
		flash_light.light_energy = beep_blink_light_energy

	if bomb_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = beep_blink_light_color
		mat.emission_enabled = true
		mat.emission = beep_blink_light_color
		mat.emission_energy_multiplier = beep_blink_emission_energy_multiplier
		bomb_mesh.material_override = mat

	_beep_visual_time_left = max(beep_duration, min_beep_blink_seconds)

	# Sound (optional).
	if not sfx_player:
		return

	_sound_active = true
	_sound_elapsed = 0.0
	_sound_duration = max(beep_duration, 0.01)
	_sound_is_explosion = false
	_phase = 0.0

	# Start the generator playback.
	sfx_player.play()
	_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _start_explosion() -> void:
	if not sfx_player:
		return

	_sound_active = true
	_sound_elapsed = 0.0
	_sound_duration = max(explosion_duration, 0.01)
	_sound_is_explosion = true
	_phase = 0.0

	# Scale boom feel by concussion (low concussion = quieter/less intense burst).
	explosion_amplitude = max(_explosion_amplitude_base, 0.01) * clampf(concussion_value, 0.0, 2.0)
	sfx_player.play()
	_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_sfx_audio() -> void:
	if not _sound_active:
		return
	if not sfx_player or not _playback:
		return

	var frames: int = _playback.get_frames_available()
	while frames > 0 and _sound_elapsed < _sound_duration:
		var t: float = _sound_elapsed / _sound_duration

		var sample: float = 0.0
		if _sound_is_explosion:
			# Noise burst with a fast attack/decay envelope.
			var env: float = (1.0 - t)
			env *= env
			sample = randf_range(-1.0, 1.0) * explosion_amplitude * env

			# Add a tiny low-frequency rumble to make it feel more "boom".
			sample += sin(t * 10.0 * TAU) * explosion_amplitude * 0.08 * env
		else:
			# Beep: sine wave with quick fade-in/out.
			var env: float = 1.0 - abs(t * 2.0 - 1.0)  # triangle envelope
			env = clampf(env, 0.0, 1.0)
			sample = sin(_phase) * beep_amplitude * env

			# Advance phase per sample.
			_phase += TAU * (beep_frequency_hz / _sample_rate)

		# Push stereo frame.
		_playback.push_frame(Vector2(sample, sample))
		_sound_elapsed += 1.0 / _sample_rate
		frames -= 1

	if _sound_elapsed >= _sound_duration:
		_sound_active = false
		# Note: visuals are turned off by `_beep_visual_time_left` so we can keep
		# the red blink visible longer than the audio beep itself.


func _load_bomb_stats() -> void:
	var stats: Dictionary = BombRegistry.get_bomb(bomb_id)
	if stats.is_empty():
		return

	fuse_time = float(stats.get("fuse_time", fuse_time))
	blast_radius = float(stats.get("blast_radius", blast_radius))
	concussion_value = float(stats.get("concussion_value", concussion_value))
	fire_damage = float(stats.get("fire_damage", fire_damage))
	fire_radius = float(stats.get("fire_radius", fire_radius))
