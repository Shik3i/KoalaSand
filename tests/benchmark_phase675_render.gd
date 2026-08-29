extends SceneTree

const WIDTH := 1920
const HEIGHT := 1080
const WARMUP := 60
const FRAMES := 240

var _root: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	_root = Node2D.new()
	get_root().add_child(_root)
	print("phase675_render environment godot=%s os=%s cpu=%s logical_cores=%d renderer=%s resolution=%dx%d" % [
		Engine.get_version_info().get("string", "unknown"), OS.get_name(), OS.get_processor_name(),
		OS.get_processor_count(), RenderingServer.get_current_rendering_method(), WIDTH, HEIGHT,
	])
	await _measure_full_texture("rgba8_full", Image.FORMAT_RGBA8, null)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float v=texture(TEXTURE,UV).r; vec3 deep=vec3(0.02,0.25,0.38); vec3 light=vec3(0.16,0.72,0.84); COLOR=vec4(mix(deep,light,v),max(0.15,v)); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	await _measure_full_texture("r8_material_id", Image.FORMAT_R8, material)
	await _measure_chunk_updates("rgba8_chunks_full", 510)
	await _measure_chunk_updates("rgba8_chunks_partial", 128)
	quit(0)


func _measure_full_texture(label: String, format: Image.Format, material: Material) -> void:
	var bytes_per_pixel := 4 if format == Image.FORMAT_RGBA8 else 1
	var pixels := PackedByteArray()
	pixels.resize(WIDTH * HEIGHT * bytes_per_pixel)
	for index in pixels.size(): pixels[index] = (index * 37 + index / maxi(1, WIDTH * bytes_per_pixel) * 13) & 0xff
	var image := Image.create_from_data(WIDTH, HEIGHT, false, format, pixels)
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	sprite.material = material
	_root.add_child(sprite)
	for frame in WARMUP:
		image.set_pixel((frame * 17) % WIDTH, (frame * 29) % HEIGHT, Color(0.2, 0.7, 0.9, 1.0))
		texture.update(image)
		await process_frame
	var upload_samples: Array[float] = []
	var frame_samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in FRAMES:
		image.set_pixel((frame * 31) % WIDTH, (frame * 47) % HEIGHT, Color(0.1, float(frame & 255) / 255.0, 0.8, 1.0))
		var upload_start := Time.get_ticks_usec()
		texture.update(image)
		upload_samples.append(float(Time.get_ticks_usec() - upload_start) / 1000.0)
		await process_frame
		var now := Time.get_ticks_usec()
		frame_samples.append(float(now - previous) / 1000.0)
		previous = now
	_print_samples(label, WIDTH * HEIGHT * bytes_per_pixel, 1, upload_samples, frame_samples)
	sprite.queue_free()
	await process_frame


func _measure_chunk_updates(label: String, update_count: int) -> void:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04, 0.45, 0.62, 0.9))
	var textures: Array[ImageTexture] = []
	var sprites: Array[Sprite2D] = []
	for index in 510:
		var texture := ImageTexture.create_from_image(image)
		textures.append(texture)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = texture
		sprite.position = Vector2((index % 30) * 64, (index / 30) * 64)
		_root.add_child(sprite)
		sprites.append(sprite)
	for frame in WARMUP:
		image.set_pixel(frame % 64, (frame * 3) % 64, Color(0.1, 0.65, 0.8, 1.0))
		for index in update_count: textures[index].update(image)
		await process_frame
	var upload_samples: Array[float] = []
	var frame_samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in FRAMES:
		image.set_pixel(frame % 64, (frame * 7) % 64, Color(0.1, float(frame & 255) / 255.0, 0.8, 1.0))
		var upload_start := Time.get_ticks_usec()
		for index in update_count: textures[index].update(image)
		upload_samples.append(float(Time.get_ticks_usec() - upload_start) / 1000.0)
		await process_frame
		var now := Time.get_ticks_usec()
		frame_samples.append(float(now - previous) / 1000.0)
		previous = now
	_print_samples(label, update_count * 64 * 64 * 4, update_count, upload_samples, frame_samples)
	for sprite in sprites: sprite.queue_free()
	await process_frame


func _print_samples(label: String, upload_bytes: int, calls: int, uploads: Array[float], frames: Array[float]) -> void:
	uploads.sort()
	frames.sort()
	var upload_avg := _average(uploads)
	var frame_avg := _average(frames)
	print("phase675_render strategy=%s upload_bytes=%d calls=%d upload_avg_ms=%.4f upload_p95_ms=%.4f upload_p99_ms=%.4f frame_avg_ms=%.4f frame_p95_ms=%.4f frame_p99_ms=%.4f frame_worst_ms=%.4f fps=%.1f" % [
		label, upload_bytes, calls, upload_avg, _percentile(uploads, 0.95), _percentile(uploads, 0.99),
		frame_avg, _percentile(frames, 0.95), _percentile(frames, 0.99), frames[-1], 1000.0 / frame_avg,
	])


func _average(values: Array[float]) -> float:
	var sum := 0.0
	for value in values: sum += value
	return sum / maxi(1, values.size())


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]
