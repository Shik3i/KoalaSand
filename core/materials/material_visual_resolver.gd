class_name MaterialVisualResolver
extends RefCounted

const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]


static func sample(world: CellWorld, world_cell: Vector2i, material_id: int) -> Color:
	var definition := world.materials.get_definition(material_id)
	if definition == null or definition.category == MaterialDefinition.Category.EMPTY:
		return Color.TRANSPARENT
	return _sample_with_neighbors(
		world,
		world_cell,
		material_id,
		definition,
		world.get_cell(world_cell + Vector2i.UP),
		world.get_cell(world_cell + Vector2i.RIGHT),
		world.get_cell(world_cell + Vector2i.DOWN),
		world.get_cell(world_cell + Vector2i.LEFT)
	)


static func _sample_with_neighbors(
	world: CellWorld,
	world_cell: Vector2i,
	material_id: int,
	definition: MaterialDefinition,
	up: int,
	right: int,
	down: int,
	left: int
) -> Color:
	var palette := definition.visual_palette
	var color := definition.debug_color
	if not palette.is_empty():
		var fine_hash := DeterministicHash.hash_2d(world.seed, world_cell, material_id * 131)
		color = palette[fine_hash % palette.size()]

	if (definition.visual_flags & MaterialDefinition.VisualFlag.DEPTH_TINT) != 0:
		var coarse_position := Vector2i(
			WorldConfig.floor_div(world_cell.x, definition.visual_noise_scale),
			WorldConfig.floor_div(world_cell.y, definition.visual_noise_scale)
		)
		var coarse := DeterministicHash.unit_float(world.seed, coarse_position, material_id * 977)
		var coarse_amount := definition.visual_depth_tint * lerpf(0.25, 0.75, coarse)
		color = color.lerp(definition.visual_shadow_color, coarse_amount)

	var empty_neighbors := 0
	var same_neighbors := 0
	for neighbor_id in [up, right, down, left]:
		if neighbor_id == MaterialRegistry.EMPTY_ID:
			empty_neighbors += 1
		elif neighbor_id == material_id:
			same_neighbors += 1

	if (definition.visual_flags & MaterialDefinition.VisualFlag.SURFACE_EDGE) != 0:
		var above_empty := up == MaterialRegistry.EMPTY_ID
		if above_empty:
			var amount := 0.42 if definition.category == MaterialDefinition.Category.GRANULAR else 0.44
			color = color.lerp(definition.visual_surface_color, amount)
		elif empty_neighbors > 0:
			color = color.lerp(definition.visual_surface_color, 0.16)
		elif same_neighbors == 4:
			color = color.lerp(definition.visual_shadow_color, definition.visual_depth_tint)

	return color


static func build_chunk_image(world: CellWorld, chunk: SimChunk) -> Image:
	var image := Image.create_empty(
		WorldConfig.CHUNK_SIZE,
		WorldConfig.CHUNK_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	var world_origin := chunk.coordinate * WorldConfig.CHUNK_SIZE
	for index in WorldConfig.CELLS_PER_CHUNK:
		var local := WorldConfig.index_to_local(index)
		var material_id := chunk.material_ids[index]
		if material_id == MaterialRegistry.EMPTY_ID:
			continue
		var definition := world.materials.get_definition(material_id)
		if definition == null:
			continue
		var neighbor_ids := [0, 0, 0, 0]
		for direction in 4:
			var neighbor_local := local + CARDINAL_OFFSETS[direction]
			if (
				neighbor_local.x >= 0
				and neighbor_local.x < WorldConfig.CHUNK_SIZE
				and neighbor_local.y >= 0
				and neighbor_local.y < WorldConfig.CHUNK_SIZE
			):
				neighbor_ids[direction] = chunk.material_ids[WorldConfig.local_to_index(neighbor_local)]
			else:
				neighbor_ids[direction] = world.get_cell(world_origin + neighbor_local)
		image.set_pixelv(
			local,
			_sample_with_neighbors(
				world,
				world_origin + local,
				material_id,
				definition,
				neighbor_ids[0],
				neighbor_ids[1],
				neighbor_ids[2],
				neighbor_ids[3]
			)
		)
	return image
