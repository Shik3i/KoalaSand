class_name ProceduralSfx
extends RefCounted

const SAMPLE_RATE := 22050

static func build(event_id: StringName, looped := false) -> AudioStreamWAV:
	var duration := 0.72 if looped else 0.13
	if event_id in [&"tree_crack", &"tree_impact", &"milestone_complete"]: duration = 0.34
	var count := maxi(64, roundi(SAMPLE_RATE * duration))
	var bytes := PackedByteArray(); bytes.resize(count)
	var seed := _stable_seed(str(event_id)); var frequency := 105.0 + float(seed % 360); var noise_mix := 0.08 + float((seed >> 8) % 18) / 100.0
	if event_id in [&"water", &"steam", &"fire", &"sand", &"conveyor", &"pump", &"vibration", &"turbine", &"generator", &"jetpack"]: noise_mix = 0.32
	if event_id in [&"tree_impact", &"dig", &"remove"]: frequency *= 0.45
	if event_id in [&"confirm", &"research_unlock", &"milestone_complete"]: frequency *= 1.65
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var drift := 1.0 + 0.018 * sin(TAU * 2.1 * t + float(seed % 13))
		var phase := TAU * frequency * drift * t
		var pulse := 0.68 + 0.32 * sin(TAU * (3.0 + float(seed % 5)) * t)
		var tone := sin(phase) * 0.50 + sin(phase * 0.503 + 0.7) * 0.19 + sin(phase * 1.997) * 0.08
		var noise := float((_hash_sample(seed, index) & 65535) - 32768) / 32768.0
		var envelope := (0.50 + pulse * 0.18) if looped else minf(1.0, t * 160.0) * pow(maxf(0.0, 1.0 - t / duration), 2.0)
		var texture := noise
		if event_id == &"water": texture = noise * (0.55 + 0.45 * sin(TAU * 7.0 * t))
		elif event_id == &"fire": texture = noise * (0.45 + 0.55 * abs(sin(TAU * 11.0 * t + sin(t * 19.0))))
		elif event_id == &"steam": texture = noise * (0.35 + 0.65 * t / duration)
		var sample := clampf((tone * (1.0 - noise_mix) + texture * noise_mix) * envelope, -1.0, 1.0)
		bytes[index] = clampi(roundi(sample * 110.0 + 128.0), 0, 255)
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_8_BITS; stream.mix_rate = SAMPLE_RATE; stream.stereo = false; stream.data = bytes
	if looped: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD; stream.loop_begin = 0; stream.loop_end = count
	return stream

static func _stable_seed(text: String) -> int:
	var value := 2166136261
	for index in text.length(): value = int((value ^ text.unicode_at(index)) * 16777619) & 0x7fffffff
	return value

static func _hash_sample(seed: int, index: int) -> int:
	var value := seed ^ (index * 374761393); value = (value ^ (value >> 13)) * 1274126177; return value ^ (value >> 16)
