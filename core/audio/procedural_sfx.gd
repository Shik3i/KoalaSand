class_name ProceduralSfx
extends RefCounted

const SAMPLE_RATE := 32000
const LOOP_DURATION := 1.2

static func build(event_id: StringName, looped := false) -> AudioStreamWAV:
	var duration := LOOP_DURATION if looped else 0.16
	if event_id in [&"tree_crack", &"tree_impact", &"milestone_complete"]: duration = 0.34
	var count := maxi(64, roundi(SAMPLE_RATE * duration))
	var bytes := PackedByteArray(); bytes.resize(count * 2)
	var seed := _stable_seed(str(event_id)); var frequency := 105.0 + float(seed % 360); var texture_mix := 0.035 + float((seed >> 8) % 7) / 100.0
	if event_id in [&"water", &"steam", &"fire", &"sand", &"conveyor", &"pump", &"vibration", &"turbine", &"generator", &"jetpack"]: texture_mix = 0.12
	if event_id in [&"tree_impact", &"dig", &"remove"]: frequency *= 0.45
	if event_id in [&"confirm", &"research_unlock", &"milestone_complete"]: frequency *= 1.65
	var phase := 0.0
	var filtered_noise := 0.0
	var loop_cycles := maxi(1, roundi(frequency * duration))
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var unit := float(index) / float(count)
		var tone := 0.0
		var texture := 0.0
		var envelope := 0.0
		if looped:
			# Integer-cycle partials and periodic texture make the final-to-first
			# transition continuous. Never put raw white noise in a short loop.
			var loop_phase := TAU * float(loop_cycles) * unit
			tone = sin(loop_phase) * 0.56 + sin(loop_phase * 2.0 + 0.7) * 0.12
			var texture_cycles := 3 + seed % 5
			texture = sin(TAU * float(texture_cycles) * unit + float(seed % 17)) * 0.62
			texture += sin(TAU * float(texture_cycles * 2) * unit + 1.3) * 0.24
			envelope = 0.22
		else:
			var raw_noise := float((_hash_sample(seed, index) & 65535) - 32768) / 32768.0
			filtered_noise = lerpf(filtered_noise, raw_noise, 0.075)
			var drift := 1.0 + 0.012 * sin(TAU * 2.1 * t + float(seed % 13))
			phase += TAU * frequency * drift / SAMPLE_RATE
			tone = sin(phase) * 0.58 + sin(phase * 1.997) * 0.10
			texture = filtered_noise
			var attack := smoothstep(0.0, 0.012, t)
			var release := smoothstep(0.0, 0.045, duration - t)
			envelope = attack * release * 0.34
		var sample := clampf((tone * (1.0 - texture_mix) + texture * texture_mix) * envelope, -0.72, 0.72)
		var pcm := roundi(sample * 32767.0)
		if pcm < 0: pcm += 65536
		bytes[index * 2] = pcm & 0xff
		bytes[index * 2 + 1] = (pcm >> 8) & 0xff
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = SAMPLE_RATE; stream.stereo = false; stream.data = bytes
	if looped: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD; stream.loop_begin = 0; stream.loop_end = count
	return stream

static func _stable_seed(text: String) -> int:
	var value := 2166136261
	for index in text.length(): value = int((value ^ text.unicode_at(index)) * 16777619) & 0x7fffffff
	return value

static func _hash_sample(seed: int, index: int) -> int:
	var value := seed ^ (index * 374761393); value = (value ^ (value >> 13)) * 1274126177; return value ^ (value >> 16)
