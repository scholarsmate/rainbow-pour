extends Node

const MUSIC_BUS := "Music"
const EFFECTS_BUS := "Effects"
const MUSIC_VOLUME_DB := -22.0
const MUSIC_FADE_DB := -38.0
const MUSIC_LOOP_BASE_SECONDS := 63.0
const MUSIC_LOOP_LIMIT_SECONDS := 58.0
const DISABLE_ANDROID_AUDIO := false
const DISABLE_ANDROID_MUSIC := false
const USE_IMPORTED_ANDROID_MUSIC := true
const IMPORTED_GAME_MUSIC_PATH := "res://assets/audio/generated/game_loop.wav"
const IMPORTED_MENU_MUSIC_PATH := "res://assets/audio/generated/menu_loop.wav"
const IMPORTED_SOLVED_MUSIC_PATH := "res://assets/audio/generated/solved_loop.wav"
const IMPORTED_FAILED_MUSIC_PATH := "res://assets/audio/generated/failed_loop.wav"

var _audio_disabled := false
var _music_disabled := false
var _using_imported_music := false
var _click: AudioStreamPlayer
var _select: AudioStreamPlayer
var _pour: AudioStreamPlayer
var _pour_stream_player: AudioStreamPlayer
var _pour_splash_player: AudioStreamPlayer
var _move: AudioStreamPlayer
var _invalid: AudioStreamPlayer
var _cap: AudioStreamPlayer
var _crack: AudioStreamPlayer
var _pipette_suck: AudioStreamPlayer
var _pipette_squirt: AudioStreamPlayer
var _pipette_stir: AudioStreamPlayer
var _win: AudioStreamPlayer
var _loss: AudioStreamPlayer
var _spill: AudioStreamPlayer
var _music: AudioStreamPlayer
var _game_music_stream: AudioStream
var _menu_music_stream: AudioStream
var _solved_music_stream: AudioStream
var _failed_music_stream: AudioStream
var _music_mode := ""
var _music_transition_tween: Tween
var _star_boom_players: Array[AudioStreamPlayer] = []
var _star_boom_next := 0
var _pour_streams: Array[AudioStream] = []
var _pour_splashes: Array[AudioStream] = []
var _pipette_sucks: Array[AudioStream] = []
var _pipette_squirts: Array[AudioStream] = []
var _pipette_stirs: Array[AudioStream] = []
var _pour_stop_tween: Tween
var _loop_pressure := 0.0

func _ready():
	_audio_disabled = DISABLE_ANDROID_AUDIO and OS.get_name() == "Android"
	_music_disabled = DISABLE_ANDROID_MUSIC and OS.get_name() == "Android"
	_using_imported_music = USE_IMPORTED_ANDROID_MUSIC and OS.get_name() == "Android"
	if _audio_disabled:
		print("Android audio disabled to avoid native AudioTrack crash.")
		return
	var headless := DisplayServer.get_name() == "headless"
	_ensure_audio_bus(MUSIC_BUS)
	_ensure_audio_bus(EFFECTS_BUS)
	get_tree().root.tree_exiting.connect(_stop_all)
	if not headless:
		_load_pour_assets()
		_load_pipette_assets()
	_click   = _add(null if headless else _gen_tone(720.0, 0.045, 48.0, 0.36), -4.0, EFFECTS_BUS)
	_select  = _add(null if headless else _gen_tone(880.0, 0.07, 32.0, 0.50), -3.0, EFFECTS_BUS)
	_pour    = _add(null if headless else _gen_pour(), -7.0, EFFECTS_BUS)
	_pour_stream_player = _add(null, -2.0, EFFECTS_BUS)
	_pour_splash_player = _add(null, -5.5, EFFECTS_BUS)
	_move    = _add(null if headless else _gen_tone(440.0, 0.06, 28.0, 0.45), -4.0, EFFECTS_BUS)
	_invalid = _add(null if headless else _gen_tone(175.0, 0.14, 16.0, 0.65), -2.0, EFFECTS_BUS)
	_cap     = _add(null if headless else _gen_cap_chime(), -2.8, EFFECTS_BUS)
	_crack   = _add(null if headless else _gen_glass_crack(), -3.0, EFFECTS_BUS)
	_pipette_suck = _add(null if headless or not _pipette_sucks.is_empty() else _gen_pipette_suck(), -2.6, EFFECTS_BUS)
	_pipette_squirt = _add(null if headless or not _pipette_squirts.is_empty() else _gen_pipette_squirt(), -3.1, EFFECTS_BUS)
	_pipette_stir = _add(null if headless or not _pipette_stirs.is_empty() else _gen_liquid_spill(), -3.8, EFFECTS_BUS)
	_win     = _add(null if headless else _gen_win(), -1.0, EFFECTS_BUS)
	_loss    = _add(null if headless else _gen_glass_shatter(), -2.0, EFFECTS_BUS)
	_spill   = _add(null if headless else _gen_liquid_spill(), -4.0, EFFECTS_BUS)
	var star_boom_stream: AudioStream = null if headless else _gen_star_boom()
	for i in 5:
		_star_boom_players.append(_add(star_boom_stream, -0.8, EFFECTS_BUS))
	if not headless:
		if _using_imported_music:
			_load_imported_music_streams()
		elif not _music_disabled:
			_game_music_stream = _gen_music_loop()
			_menu_music_stream = _gen_menu_music_loop()
			_solved_music_stream = _gen_result_music_loop(true)
			_failed_music_stream = _gen_result_music_loop(false)
		if not _music_disabled and _game_music_stream:
			_music = _add(_game_music_stream, MUSIC_VOLUME_DB, MUSIC_BUS)
	var music_mode := "disabled" if _music_disabled else ("imported" if _using_imported_music else "generated")
	print("Audio enabled | music mode: %s | mix rate: %s | output latency: %.4f" % [music_mode, AudioServer.get_mix_rate(), AudioServer.get_output_latency()])
	apply_volume_settings()
	if _music:
		play_game_music(0.0, false)

func _exit_tree():
	_stop_all()

func _stop_all():
	if _pour_stop_tween and _pour_stop_tween.is_valid():
		_pour_stop_tween.kill()
	if _music_transition_tween and _music_transition_tween.is_valid():
		_music_transition_tween.kill()
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func play_click():
	if _audio_disabled or not _click:
		return
	_click.play()

func play_select():
	if _audio_disabled or not _select:
		return
	_select.play()

func play_pour():
	if _audio_disabled:
		return
	if not _pour_streams.is_empty():
		_play_sampled_pour()
		return
	if not _pour:
		return
	if _pour.playing:
		_pour.stop()
	_pour.play()

func play_move():
	if _audio_disabled or not _move:
		return
	_move.play()

func play_invalid():
	if _audio_disabled or not _invalid:
		return
	_invalid.play()

func play_beaker_capped():
	if _audio_disabled or not _cap:
		return
	if _cap.playing:
		_cap.stop()
	_cap.pitch_scale = randf_range(0.98, 1.04)
	_cap.play()

func play_glass_crack():
	if _audio_disabled or not _crack:
		return
	if _crack.playing:
		_crack.stop()
	_crack.pitch_scale = randf_range(0.97, 1.04)
	_crack.play()

func play_pipette_suck():
	if _audio_disabled or not _pipette_suck:
		return
	if not _pipette_sucks.is_empty():
		_pipette_suck.stop()
		_pipette_suck.stream = _pipette_sucks.pick_random()
		_pipette_suck.volume_db = randf_range(-3.8, -2.1)
		_pipette_suck.pitch_scale = randf_range(0.84, 0.96)
		_pipette_suck.play()
		return
	if _pipette_suck.playing:
		_pipette_suck.stop()
	_pipette_suck.volume_db = -2.6
	_pipette_suck.pitch_scale = randf_range(0.96, 1.05)
	_pipette_suck.play()

func play_pipette_squirt():
	if _audio_disabled or not _pipette_squirt:
		return
	if not _pipette_squirts.is_empty():
		_pipette_squirt.stop()
		_pipette_squirt.stream = _pipette_squirts.pick_random()
		_pipette_squirt.volume_db = randf_range(-2.8, -0.9)
		_pipette_squirt.pitch_scale = randf_range(1.00, 1.13)
		_pipette_squirt.play()
		return
	if _pipette_squirt.playing:
		_pipette_squirt.stop()
	_pipette_squirt.volume_db = -3.1
	_pipette_squirt.pitch_scale = randf_range(0.97, 1.06)
	_pipette_squirt.play()

func play_pipette_stir():
	if _audio_disabled or not _pipette_stir:
		return
	if not _pipette_stirs.is_empty():
		_pipette_stir.stop()
		_pipette_stir.stream = _pipette_stirs.pick_random()
		_pipette_stir.volume_db = randf_range(-4.2, -2.4)
		_pipette_stir.pitch_scale = randf_range(0.88, 1.05)
		_pipette_stir.play()
		return
	if _pipette_stir.playing:
		_pipette_stir.stop()
	_pipette_stir.volume_db = -3.8
	_pipette_stir.pitch_scale = randf_range(0.92, 1.04)
	_pipette_stir.play()

func play_win():
	if _audio_disabled or not _win:
		return
	_win.play()

func play_loss():
	if _audio_disabled or not _loss:
		return
	if _loss.playing:
		_loss.stop()
	_loss.pitch_scale = 1.0
	_loss.play()

func play_shatter():
	if _audio_disabled or not _loss:
		return
	if _loss.playing:
		_loss.stop()
	_loss.pitch_scale = randf_range(0.96, 1.04)
	_loss.play()

func play_liquid_spill():
	if _audio_disabled or not _spill:
		return
	if _spill.playing:
		_spill.stop()
	_spill.pitch_scale = randf_range(0.94, 1.06)
	_spill.play()

func play_star_boom(star_index: int = 0):
	if _audio_disabled:
		return
	if _star_boom_players.is_empty():
		return
	var player := _star_boom_players[_star_boom_next]
	_star_boom_next = (_star_boom_next + 1) % _star_boom_players.size()
	var boom_step := minf(float(star_index), 4.0)
	var final_boom := star_index >= 4
	player.stop()
	player.volume_db = 3.8 if final_boom else -4.8 + boom_step * 1.15
	player.pitch_scale = (0.82 if final_boom else 0.90 + boom_step * 0.045) + randf_range(-0.018, 0.018)
	player.play()
	if final_boom and _star_boom_players.size() > 1:
		var sub_player := _star_boom_players[_star_boom_next]
		_star_boom_next = (_star_boom_next + 1) % _star_boom_players.size()
		sub_player.stop()
		sub_player.volume_db = 0.6
		sub_player.pitch_scale = 0.62 + randf_range(-0.012, 0.012)
		sub_player.play()

func apply_volume_settings() -> void:
	if _audio_disabled:
		return
	set_music_volume(GameSettings.music_volume)
	set_effects_volume(GameSettings.effects_volume)

func set_music_volume(value: float) -> void:
	if _audio_disabled:
		return
	_set_bus_volume(MUSIC_BUS, value)

func set_effects_volume(value: float) -> void:
	if _audio_disabled:
		return
	_set_bus_volume(EFFECTS_BUS, value)

func play_game_music(progress: float = 0.0, fade: bool = true) -> void:
	if _audio_disabled or _music_disabled:
		return
	_loop_pressure = clampf(progress, 0.0, 1.0)
	_switch_music("game", _game_music_stream, _game_pitch_scale(), fade)

func play_menu_music(fade: bool = true) -> void:
	if _audio_disabled or _music_disabled:
		return
	_switch_music("menu", _menu_music_stream, 1.0, fade)

func play_solved_music() -> void:
	if _audio_disabled or _music_disabled:
		return
	_switch_music("solved", _solved_music_stream, 1.0, true)

func play_failed_music() -> void:
	if _audio_disabled or _music_disabled:
		return
	_switch_music("failed", _failed_music_stream, 1.0, true)

func set_loop_pressure(progress: float) -> void:
	if _audio_disabled or _music_disabled:
		return
	_loop_pressure = clampf(progress, 0.0, 1.0)
	if not _music or _music_mode != "game":
		return
	_music.pitch_scale = _game_pitch_scale()

func _game_pitch_scale() -> float:
	var eased := smoothstep(0.0, 1.0, _loop_pressure)
	return lerpf(1.0, MUSIC_LOOP_BASE_SECONDS / MUSIC_LOOP_LIMIT_SECONDS, eased)

func _switch_music(mode: String, stream: AudioStream, pitch_scale: float, fade: bool) -> void:
	if _audio_disabled or _music_disabled:
		return
	if not _music or not stream:
		return
	if _music_mode == mode:
		_music.pitch_scale = pitch_scale
		if not _music.playing:
			_music.play()
		return
	if _music_transition_tween and _music_transition_tween.is_valid():
		_music_transition_tween.kill()
	var apply_stream := func():
		_music_mode = mode
		_music.stream = stream
		_music.pitch_scale = pitch_scale
		_music.play()
	if not fade:
		apply_stream.call()
		_music.volume_db = MUSIC_VOLUME_DB
		return
	_music_transition_tween = create_tween()
	_music_transition_tween.tween_property(_music, "volume_db", MUSIC_FADE_DB, 0.16)
	_music_transition_tween.tween_callback(apply_stream)
	_music_transition_tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB, 0.24)

func _add(stream: AudioStream = null, volume_db: float = 0.0, bus_name: String = EFFECTS_BUS) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus_name
	add_child(p)
	return p

func _ensure_audio_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _set_bus_volume(bus_name: String, value: float) -> void:
	if _audio_disabled:
		return
	var idx := _ensure_audio_bus(bus_name)
	var clamped := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.001)
	AudioServer.set_bus_volume_db(idx, -80.0 if clamped <= 0.001 else linear_to_db(clamped))

func _load_imported_music_streams() -> void:
	_game_music_stream = _load_imported_music_stream(IMPORTED_GAME_MUSIC_PATH)
	_menu_music_stream = _load_imported_music_stream(IMPORTED_MENU_MUSIC_PATH)
	_solved_music_stream = _load_imported_music_stream(IMPORTED_SOLVED_MUSIC_PATH)
	_failed_music_stream = _load_imported_music_stream(IMPORTED_FAILED_MUSIC_PATH)
	if not _game_music_stream or not _menu_music_stream or not _solved_music_stream or not _failed_music_stream:
		_music_disabled = true
		_using_imported_music = false
		print("Imported Android music missing; keeping sound effects enabled and music disabled.")

func _load_imported_music_stream(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Missing imported music stream: %s" % path)
		return null
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var loop_end := int(round(wav.get_length() * float(wav.mix_rate)))
		wav.loop_end = loop_end if loop_end > 0 else -1
	return stream

func _load_pour_assets() -> void:
	_pour_streams = _load_audio_streams([
		"res://assets/audio/water/pour_stream_01.ogg",
		"res://assets/audio/water/pour_stream_02.ogg",
		"res://assets/audio/water/pour_stream_03.ogg",
	])
	_pour_splashes = _load_audio_streams([
		"res://assets/audio/water/pour_splash_01.ogg",
		"res://assets/audio/water/pour_splash_02.ogg",
		"res://assets/audio/water/pour_splash_03.ogg",
	])

func _load_pipette_assets() -> void:
	_pipette_sucks = _load_audio_streams([
		"res://assets/audio/pipette/pipette_suck_01.ogg",
		"res://assets/audio/pipette/pipette_suck_02.ogg",
		"res://assets/audio/pipette/pipette_suck_03.ogg",
	])
	_pipette_squirts = _load_audio_streams([
		"res://assets/audio/pipette/pipette_squirt_01.ogg",
		"res://assets/audio/pipette/pipette_squirt_02.ogg",
		"res://assets/audio/pipette/pipette_squirt_03.ogg",
	])
	_pipette_stirs = _load_audio_streams([
		"res://assets/audio/pipette/pipette_stir_01.ogg",
		"res://assets/audio/pipette/pipette_stir_02.ogg",
		"res://assets/audio/pipette/pipette_stir_03.ogg",
	])

func _load_audio_streams(paths: Array) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		var stream = load(path)
		if stream is AudioStream:
			streams.append(stream)
	return streams

func _play_sampled_pour() -> void:
	if _audio_disabled:
		return
	if _pour_stop_tween and _pour_stop_tween.is_valid():
		_pour_stop_tween.kill()

	var stream: AudioStream = _pour_streams.pick_random()
	_pour_stream_player.stop()
	_pour_stream_player.stream = stream
	_pour_stream_player.volume_db = randf_range(-2.4, -1.2)
	_pour_stream_player.pitch_scale = randf_range(0.96, 1.05)

	var from_position := 0.0
	var length := stream.get_length()
	if length > 1.0:
		from_position = randf_range(0.05, length - 0.85)
	_pour_stream_player.play(from_position)

	if not _pour_splashes.is_empty():
		_pour_splash_player.stop()
		_pour_splash_player.stream = _pour_splashes.pick_random()
		_pour_splash_player.volume_db = randf_range(-7.0, -4.6)
		_pour_splash_player.pitch_scale = randf_range(0.92, 1.08)
		_pour_splash_player.play()

	_pour_stop_tween = create_tween()
	_pour_stop_tween.tween_interval(0.52)
	_pour_stop_tween.tween_property(_pour_stream_player, "volume_db", -22.0, 0.24)
	_pour_stop_tween.tween_callback(func():
		_pour_stream_player.stop()
		_pour_stream_player.volume_db = -2.0
	)

func _wav(b: PackedByteArray, rate: int = 22050, loop: bool = false) -> AudioStreamWAV:
	var s = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = b
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(b.size() / 2)
	return s

func _gen_tone(hz: float, dur: float, decay: float, amp: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := int(sin(TAU * hz * t) * exp(-t * decay) * amp * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_pour() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.72
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var stream := 0.0
	var droplets := [
		[0.06, 760.0, 0.10],
		[0.14, 520.0, 0.08],
		[0.26, 690.0, 0.09],
		[0.41, 430.0, 0.07],
		[0.56, 610.0, 0.06],
	]
	for i in n:
		var t := float(i) / rate
		var attack := minf(1.0, t / 0.09)
		var release := minf(1.0, (dur - t) / 0.20)
		var env := attack * release
		var white := randf_range(-1.0, 1.0)
		stream = lerpf(stream, white, 0.16)
		var hiss := white - stream
		var gurgle := sin(TAU * (92.0 + sin(t * 15.0) * 18.0) * t) * 0.045
		var sample := (stream * 0.34 + hiss * 0.065 + gurgle) * env

		if t > 0.34:
			var tail_t := t - 0.34
			sample += randf_range(-1.0, 1.0) * exp(-tail_t * 5.0) * 0.055
			sample += sin(TAU * 145.0 * tail_t) * exp(-tail_t * 8.0) * 0.035

		for droplet in droplets:
			var start := float(droplet[0])
			if t < start:
				continue
			var local_t := t - start
			if local_t > 0.10:
				continue
			var hz := float(droplet[1])
			var amp := float(droplet[2])
			sample += sin(TAU * hz * local_t) * exp(-local_t * 38.0) * amp
			sample += randf_range(-1.0, 1.0) * exp(-local_t * 70.0) * amp * 0.32

		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_liquid_spill() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.05
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var stream := 0.0
	var splats := [
		[0.05, 0.18],
		[0.16, 0.13],
		[0.31, 0.11],
		[0.49, 0.08],
	]
	for i in n:
		var t := float(i) / rate
		var attack := minf(1.0, t / 0.035)
		var tail := minf(1.0, (dur - t) / 0.30)
		var env := attack * tail * exp(-t * 0.75)
		var white := randf_range(-1.0, 1.0)
		stream = lerpf(stream, white, 0.10)
		var hiss := white - stream
		var low_slosh := sin(TAU * (64.0 + sin(t * 19.0) * 16.0) * t) * 0.055
		var sample := (stream * 0.42 + hiss * 0.052 + low_slosh) * env
		for splat in splats:
			var start := float(splat[0])
			if t < start:
				continue
			var local_t := t - start
			if local_t > 0.18:
				continue
			var amp := float(splat[1])
			sample += randf_range(-1.0, 1.0) * exp(-local_t * 23.0) * amp
			sample += sin(TAU * 105.0 * local_t) * exp(-local_t * 12.0) * amp * 0.45
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_pipette_suck() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.44
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var fluid := 0.0
	for i in n:
		var t := float(i) / rate
		var attack := minf(1.0, t / 0.026)
		var tail := minf(1.0, (dur - t) / 0.11)
		var env := attack * tail
		var white := randf_range(-1.0, 1.0)
		fluid = lerpf(fluid, white, 0.12)
		var suction_hiss := (white - fluid) * 0.070
		var rising := 420.0 + 690.0 * minf(1.0, t / dur)
		var whistle := sin(TAU * rising * t) * exp(-t * 2.4) * 0.042
		var sample := (fluid * 0.20 + suction_hiss + whistle) * env
		for raw_start in [0.09, 0.18, 0.29]:
			var start := float(raw_start)
			if t < start:
				continue
			var local_t := t - start
			if local_t > 0.09:
				continue
			sample += sin(TAU * (760.0 + start * 940.0) * local_t) * exp(-local_t * 42.0) * 0.085
			sample += randf_range(-1.0, 1.0) * exp(-local_t * 58.0) * 0.030
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_pipette_squirt() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.48
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var stream := 0.0
	for i in n:
		var t := float(i) / rate
		var attack := minf(1.0, t / 0.018)
		var tail := minf(1.0, (dur - t) / 0.13)
		var env := attack * tail
		var white := randf_range(-1.0, 1.0)
		stream = lerpf(stream, white, 0.18)
		var hiss := white - stream
		var pressure := sin(TAU * (185.0 + sin(t * 34.0) * 28.0) * t) * 0.052
		var sample := (stream * 0.30 + hiss * 0.090 + pressure) * env
		if t >= 0.24:
			var splash_t := t - 0.24
			sample += randf_range(-1.0, 1.0) * exp(-splash_t * 24.0) * 0.090
			sample += sin(TAU * 540.0 * splash_t) * exp(-splash_t * 28.0) * 0.060
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_win() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.50]  # C5 E5 G5 C6
	var step  := 0.13
	var n := int(rate * (step * notes.size() + 0.35))
	var b := PackedByteArray(); b.resize(n * 2)
	for ni in notes.size():
		var start := int(ni * step * rate)
		var nn    := int((step + 0.22) * rate)
		for i in nn:
			var t := float(i) / rate
			var v := int(sin(TAU * notes[ni] * t) * exp(-t * 5.0) * 0.40 * 32767.0)
			var si := start + i
			if si < n:
				b.encode_s16(si * 2, clampi(b.decode_s16(si * 2) + v, -32768, 32767))
	return _wav(b)

func _gen_cap_chime() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.48
	var n := int(rate * dur)
	var b := PackedByteArray()
	b.resize(n * 2)
	var notes := [
		[0.00, 783.99, 0.18],
		[0.07, 987.77, 0.16],
		[0.15, 1318.51, 0.12],
	]
	for note in notes:
		var start := int(float(note[0]) * rate)
		var hz := float(note[1])
		var amp := float(note[2])
		var length := int(0.34 * rate)
		for i in length:
			var si := start + i
			if si >= n:
				break
			var t := float(i) / rate
			var attack := minf(1.0, t / 0.018)
			var tail := exp(-t * 7.0)
			var bell := sin(TAU * hz * t) + sin(TAU * hz * 2.01 * t) * 0.24
			var sample := bell * attack * tail * amp
			var v := int(sample * 32767.0)
			b.encode_s16(si * 2, clampi(b.decode_s16(si * 2) + v, -32768, 32767))
	return _wav(b)

func _gen_glass_shatter() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.85
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var shards := [
		[0.00, 3180.0, 0.34],
		[0.03, 4860.0, 0.28],
		[0.07, 2550.0, 0.24],
		[0.13, 6120.0, 0.18],
		[0.21, 3820.0, 0.16],
	]
	for i in n:
		var t := float(i) / rate
		var noise := randf_range(-1.0, 1.0) * exp(-t * 5.8) * 0.13
		var sample := noise
		for shard in shards:
			var start := float(shard[0])
			if t < start:
				continue
			var local_t := t - start
			var hz := float(shard[1])
			var amp := float(shard[2])
			sample += sin(TAU * hz * local_t) * exp(-local_t * 24.0) * amp
			sample += randf_range(-1.0, 1.0) * exp(-local_t * 32.0) * amp * 0.35
		var debris := randf_range(-1.0, 1.0) * exp(-t * 2.6) * 0.045
		var v := int((sample + debris) * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _gen_glass_crack() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.46
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var ceramic_ticks := [
		[0.012, 1320.0, 0.42],
		[0.030, 2860.0, 0.30],
		[0.055, 4380.0, 0.23],
		[0.095, 2180.0, 0.20],
		[0.145, 5260.0, 0.12],
	]
	for i in n:
		var t := float(i) / rate
		var impact_attack := minf(1.0, t / 0.010)
		var stone_thump := sin(TAU * (118.0 - 38.0 * minf(1.0, t / 0.09)) * t) * impact_attack * exp(-t * 18.0) * 0.46
		var knock := sin(TAU * 360.0 * t) * exp(-t * 34.0) * 0.20
		var fissure_noise := randf_range(-1.0, 1.0) * exp(-maxf(0.0, t - 0.036) * 18.0) * _smooth_audio_window(t, 0.034, 0.28) * 0.10
		var rising_fissure := 0.0
		if t >= 0.042:
			var ft := t - 0.042
			var hz := 980.0 + 1880.0 * minf(1.0, ft / 0.20)
			rising_fissure = sin(TAU * hz * ft) * exp(-ft * 9.0) * 0.075
		var sample := stone_thump + knock + fissure_noise + rising_fissure
		for tick in ceramic_ticks:
			var start := float(tick[0])
			if t < start:
				continue
			var local_t := t - start
			var hz := float(tick[1])
			var amp := float(tick[2])
			sample += sin(TAU * hz * local_t) * exp(-local_t * 46.0) * amp
			sample += sin(TAU * hz * 1.52 * local_t) * exp(-local_t * 58.0) * amp * 0.28
			sample += randf_range(-1.0, 1.0) * exp(-local_t * 72.0) * amp * 0.20
		var tail_tick := 0.0
		if t >= 0.23:
			var tt := t - 0.23
			tail_tick = sin(TAU * 1540.0 * tt) * exp(-tt * 19.0) * 0.055
		sample += tail_tick
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _smooth_audio_window(t: float, start: float, end: float) -> float:
	if t < start or t > end:
		return 0.0
	var fade_in := minf(1.0, (t - start) / 0.018)
	var fade_out := minf(1.0, (end - t) / 0.10)
	return fade_in * fade_out

func _gen_star_boom() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.74
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var rumble := 0.0
	for i in n:
		var t := float(i) / rate
		var attack := minf(1.0, t / 0.018)
		var tail := exp(-t * 4.1)
		var low_drop := 82.0 - 44.0 * minf(1.0, t / 0.34)
		var sub := sin(TAU * low_drop * t) * attack * tail * 0.58
		var punch := sin(TAU * 118.0 * t) * exp(-t * 12.0) * 0.34
		var crack := randf_range(-1.0, 1.0) * exp(-t * 32.0) * 0.25
		rumble = lerpf(rumble, randf_range(-1.0, 1.0), 0.045)
		var rolling := rumble * exp(-t * 2.2) * 0.19
		var sparkle := 0.0
		for raw_offset in [0.045, 0.072, 0.116]:
			var offset := float(raw_offset)
			if t < offset:
				continue
			var local_t: float = t - offset
			sparkle += sin(TAU * (720.0 + offset * 3200.0) * local_t) * exp(-local_t * 26.0) * 0.055
		var sample := sub + punch + crack + rolling + sparkle
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b)

func _music_kick(hit_t: float, amp: float = 1.0) -> float:
	var attack := minf(1.0, hit_t / 0.012)
	var tail := exp(-hit_t * 24.0)
	var drop := 84.0 - 50.0 * minf(1.0, hit_t / 0.13)
	var sub := sin(TAU * drop * hit_t) * attack * tail * 0.34
	var low := sin(TAU * 43.0 * hit_t) * exp(-hit_t * 13.0) * 0.21
	var knock := sin(TAU * 118.0 * hit_t) * exp(-hit_t * 38.0) * 0.055
	var click := randf_range(-1.0, 1.0) * attack * exp(-hit_t * 120.0) * 0.028
	return (sub + low + knock + click) * amp

func _music_snare(hit_t: float, amp: float = 1.0) -> float:
	var snap := randf_range(-1.0, 1.0) * exp(-hit_t * 64.0) * 0.034
	var brush := randf_range(-1.0, 1.0) * exp(-hit_t * 25.0) * 0.026
	var tick := sin(TAU * 720.0 * hit_t) * exp(-hit_t * 36.0) * 0.018
	var air := sin(TAU * 1350.0 * hit_t) * exp(-hit_t * 52.0) * 0.006
	return (snap + brush + tick + air) * amp

func _loop_hz(hz: float, dur: float) -> float:
	return round(hz * dur) / dur

func _quantize_notes(notes: Array, dur: float) -> Array:
	var quantized := []
	for hz in notes:
		quantized.append(_loop_hz(float(hz), dur))
	return quantized

func _quantize_chords(chords: Array, dur: float) -> Array:
	var quantized := []
	for chord in chords:
		quantized.append(_quantize_notes(chord, dur))
	return quantized

func _gen_music_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := MUSIC_LOOP_BASE_SECONDS
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var chords := [
		[261.63, 329.63, 392.00],
		[293.66, 349.23, 440.00],
		[329.63, 392.00, 493.88],
		[246.94, 329.63, 392.00],
		[261.63, 349.23, 440.00],
		[293.66, 369.99, 440.00],
		[329.63, 415.30, 493.88],
		[246.94, 329.63, 440.00],
		[261.63, 392.00, 523.25],
		[293.66, 349.23, 523.25],
		[329.63, 392.00, 587.33],
		[246.94, 369.99, 493.88],
		[261.63, 329.63, 440.00],
		[293.66, 392.00, 493.88],
		[329.63, 440.00, 659.25],
		[246.94, 329.63, 392.00],
	]
	chords = _quantize_chords(chords, dur)
	var ripples := _quantize_notes([
		659.25, 783.99, 880.00, 987.77,
		783.99, 659.25, 587.33, 523.25,
		698.46, 880.00, 987.77, 1046.50,
		880.00, 783.99, 659.25, 587.33,
		783.99, 987.77, 1174.66, 1318.51,
		1046.50, 880.00, 783.99, 659.25,
		587.33, 659.25, 783.99, 880.00,
		987.77, 880.00, 659.25, 523.25,
	], dur)
	var chord_step := dur / float(chords.size())
	var kick_hits := [0.0, chord_step * 0.25, chord_step * 0.4375, chord_step * 0.625, chord_step * 0.75]
	var kick_amps := [1.34, 0.94, 0.74, 1.16, 0.64]
	var snare_hits := [chord_step * 0.1875, chord_step * 0.375, chord_step * 0.5625, chord_step * 0.84375]
	var snare_amps := [0.26, 0.48, 0.22, 0.36]
	var low_hz := _loop_hz(110.0, dur)
	for i in n:
		var t := float(i) / rate
		var chord_idx := int(t / chord_step) % chords.size()
		var chord: Array = chords[chord_idx]
		var section_swell := 0.92 + 0.08 * sin(TAU * t / (dur * 0.5))
		var sample := 0.0
		for hz in chord:
			var hz_f := float(hz)
			sample += sin(TAU * hz_f * 0.5 * t) * 0.056 * section_swell
			sample += sin(TAU * hz_f * t) * 0.017
		var ripple_t := fmod(t, 0.5)
		var ripple_idx := int(t * 2.0) % ripples.size()
		var ripple_hz: float = ripples[ripple_idx]
		var ripple_amp := 0.035 + 0.008 * sin(TAU * (float(ripple_idx) / float(ripples.size())))
		sample += sin(TAU * ripple_hz * t) * exp(-ripple_t * 8.0) * ripple_amp
		if int(t * 2.0) % 16 == 7:
			var echo_t := fmod(t + 0.18, 0.5)
			sample += sin(TAU * ripple_hz * 0.5 * t) * exp(-echo_t * 7.0) * 0.014
		sample += sin(TAU * low_hz * t + sin(TAU * 8.0 * t / dur) * 0.18) * 0.036
		var pattern_t := fmod(t, chord_step)
		for hit_idx in kick_hits.size():
			var hit_t := pattern_t - float(kick_hits[hit_idx])
			if hit_t >= 0.0 and hit_t < 0.19:
				sample += _music_kick(hit_t, float(kick_amps[hit_idx]))
		for hit_idx in snare_hits.size():
			var hit_t := pattern_t - float(snare_hits[hit_idx])
			if hit_t >= 0.0 and hit_t < 0.22:
				sample += _music_snare(hit_t, float(snare_amps[hit_idx]))
		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b, rate, true)

func _gen_menu_music_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := 32.0
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var chords := _quantize_chords([
		[261.63, 329.63, 392.00, 523.25],
		[293.66, 349.23, 440.00, 587.33],
		[246.94, 329.63, 392.00, 493.88],
		[261.63, 349.23, 440.00, 523.25],
		[329.63, 392.00, 493.88, 659.25],
		[293.66, 369.99, 440.00, 587.33],
		[246.94, 329.63, 415.30, 493.88],
		[261.63, 329.63, 392.00, 523.25],
	], dur)
	var melody := _quantize_notes([
		659.25, 783.99, 880.00, 783.99,
		587.33, 659.25, 783.99, 659.25,
		523.25, 587.33, 659.25, 783.99,
		880.00, 783.99, 659.25, 523.25,
	], dur)
	var chord_step := dur / float(chords.size())
	var note_step := dur / float(melody.size())
	var low_hz := _loop_hz(65.41, dur)
	var shimmer_hz := _loop_hz(1318.51, dur)
	for i in n:
		var t := float(i) / rate
		var chord_idx := int(t / chord_step) % chords.size()
		var chord: Array = chords[chord_idx]
		var sample := 0.0
		var swell := 0.86 + 0.14 * sin(TAU * t / dur)
		for hz in chord:
			var hz_f := float(hz)
			sample += sin(TAU * hz_f * 0.5 * t) * 0.038 * swell
			sample += sin(TAU * hz_f * t) * 0.010

		var note_t := fmod(t, note_step)
		var note_idx := int(t / note_step) % melody.size()
		var note_hz := float(melody[note_idx])
		var bell_env := exp(-note_t * 5.8)
		sample += sin(TAU * note_hz * t) * bell_env * 0.042
		sample += sin(TAU * note_hz * 2.0 * t) * bell_env * 0.012

		var ripple_t := fmod(t + note_step * 0.5, note_step)
		if ripple_t < note_step * 0.62:
			sample += sin(TAU * shimmer_hz * 0.5 * t) * exp(-ripple_t * 7.0) * 0.014
		sample += sin(TAU * low_hz * t + sin(TAU * 2.0 * t / dur) * 0.16) * 0.024

		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b, rate, true)

func _gen_result_music_loop(solved: bool) -> AudioStreamWAV:
	var rate := 22050
	var dur := 16.0
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	var chords := []
	var melody := []
	if solved:
		chords = [
			[261.63, 329.63, 392.00, 523.25],
			[293.66, 369.99, 440.00, 587.33],
			[329.63, 392.00, 493.88, 659.25],
			[392.00, 493.88, 587.33, 783.99],
		]
		melody = [783.99, 987.77, 1046.50, 1318.51, 1174.66, 987.77, 880.00, 1046.50]
	else:
		chords = [
			[220.00, 261.63, 329.63],
			[196.00, 246.94, 293.66],
			[174.61, 220.00, 261.63],
			[196.00, 233.08, 293.66],
		]
		melody = [392.00, 349.23, 329.63, 293.66, 261.63, 246.94, 220.00, 196.00]

	chords = _quantize_chords(chords, dur)
	melody = _quantize_notes(melody, dur)
	var failed_low_hz := _loop_hz(72.0, dur)
	for i in n:
		var t := float(i) / rate
		var chord_idx := int(t / 4.0) % chords.size()
		var chord: Array = chords[chord_idx]
		var sample := 0.0
		for hz in chord:
			var hz_f := float(hz)
			if solved:
				sample += sin(TAU * hz_f * 0.5 * t) * 0.035
				sample += sin(TAU * hz_f * t) * 0.012
			else:
				sample += sin(TAU * hz_f * 0.5 * t) * 0.045
				sample += sin(TAU * hz_f * 0.25 * t) * 0.020

		if solved:
			var step := 0.50
			var note_t := fmod(t, step)
			var note_idx := int(t / step) % melody.size()
			var hz := float(melody[note_idx])
			var bell_env := exp(-note_t * 7.5)
			sample += sin(TAU * hz * t) * bell_env * 0.065
			sample += sin(TAU * hz * 2.0 * t) * bell_env * 0.020
			if int(t / 2.0) % 2 == 0:
				var sparkle_t := fmod(t + 0.125, 0.50)
				sample += sin(TAU * hz * 1.5 * t) * exp(-sparkle_t * 9.0) * 0.018
		else:
			var step := 1.0
			var note_t := fmod(t, step)
			var note_idx := int(t / step) % melody.size()
			var hz := float(melody[note_idx])
			var soft_env := exp(-note_t * 3.6)
			sample += sin(TAU * hz * 0.5 * t) * soft_env * 0.050
			sample += sin(TAU * failed_low_hz * t + sin(TAU * 3.0 * t / dur) * 0.22) * 0.028
			if note_t < 0.28 and note_idx % 2 == 1:
				sample += _music_kick(note_t, 0.20)
			sample += sin(TAU * _loop_hz(997.0, dur) * t) * exp(-note_t * 5.0) * 0.006

		var v := int(sample * 32767.0)
		b.encode_s16(i * 2, clampi(v, -32768, 32767))
	return _wav(b, rate, true)
