extends Node

var _select: AudioStreamPlayer
var _pour: AudioStreamPlayer
var _move: AudioStreamPlayer
var _invalid: AudioStreamPlayer
var _win: AudioStreamPlayer

func _ready():
	_select  = _add(_gen_tone(880.0, 0.07, 32.0, 0.50))
	_pour    = _add(_gen_pour())
	_move    = _add(_gen_tone(440.0, 0.06, 28.0, 0.45))
	_invalid = _add(_gen_tone(175.0, 0.14, 16.0, 0.65))
	_win     = _add(_gen_win())

func play_select():  _select.play()
func play_pour():
	if _pour.playing: _pour.stop()
	_pour.play()
func play_move():    _move.play()
func play_invalid(): _invalid.play()
func play_win():     _win.play()

func _add(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p

func _wav(b: PackedByteArray, rate: int = 22050) -> AudioStreamWAV:
	var s = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = b
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
	var rate := 22050; var dur := 0.42
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := sin(PI * t / dur)
		var freq := 360.0 + sin(t * 22.0) * 90.0 + sin(t * 13.7) * 40.0
		var v := int((sin(TAU * freq * t) * 0.55 + randf_range(-1.0, 1.0) * 0.38)
					  * env * 0.36 * 32767.0)
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
