extends RefCounted

# Deterministic field layout, independent of the renderer.
# The field contains exactly 100 raw material units: 65 Fe, 25 Cu, 10 Si.
const CENTER := Vector2(530, -215)
const ROCK_COUNT := 26
const TOTAL_UNITS := 100
const FE_UNITS := 65
const CU_UNITS := 25
const SI_UNITS := 10

static func rock_center(index: int) -> Vector2:
	return CENTER + Vector2.from_angle(float(index) * 2.39996) * sqrt(float(index)) * 21.0

static func rock_radius(index: int) -> float:
	return 12.0 + float((index * 9) % 11)

static func rock_capacity(index: int) -> int:
	# Multiplying by 7 permutes the indices mod 26. Ten asteroids have
	# 3 units, ten have 4 and six have 5, giving precisely 100.
	var slot := (index * 7) % ROCK_COUNT
	if slot < 6:
		return 5
	if slot < 16:
		return 4
	return 3

static func mineral_at(ordinal: int) -> String:
	# Full-period permutation across the 100 extraction events. Local
	# batches are mixed, while the whole field's chemistry is exact.
	var slot := (ordinal * 37 + 11) % TOTAL_UNITS
	if slot < FE_UNITS:
		return "Fe"
	if slot < FE_UNITS + CU_UNITS:
		return "Cu"
	return "Si"

static func near_surface(index: int, base: Vector2) -> Vector2:
	var center := rock_center(index)
	var direction := (base - center).normalized()
	# A little deterministic variation produces a believable spread of
	# landing positions without wasting long trips.
	var lean := sin(float(index) * 1.91) * 0.14
	return center + direction.rotated(lean) * (rock_radius(index) + 4.0)

static func material_available(index: int, mined: PackedInt32Array) -> bool:
	return index >= 0 and index < ROCK_COUNT and mined[index] < rock_capacity(index)

static func rock_for_manual_sample(origin: Vector2, mined: PackedInt32Array) -> int:
	var best := -1
	var nearest := INF
	for i in range(ROCK_COUNT):
		if not material_available(i, mined):
			continue
		var distance := origin.distance_squared_to(rock_center(i))
		if distance < nearest:
			nearest = distance
			best = i
	return best

static func nearest_viable_rock(
	stockpile: Vector2,
	controller: Vector2,
	max_range: float,
	mined: PackedInt32Array,
	selection_round: int
) -> int:
	var best := -1
	var best_score := INF
	for i in range(ROCK_COUNT):
		if not material_available(i, mined):
			continue
		var site := near_surface(i, stockpile)
		if site.distance_to(controller) > max_range:
			continue
		# Mostly choose the stockpile-facing nearest asteroid. Slight
		# variance breaks ties without producing inexplicable journeys.
		var variation := sin(float(i) * 7.23 + float(selection_round) * 1.79) * 6.0
		var score := site.distance_to(stockpile) + variation
		if score < best_score:
			best_score = score
			best = i
	return best

static func within_field(point: Vector2) -> bool:
	for i in range(ROCK_COUNT):
		if point.distance_to(rock_center(i)) <= rock_radius(i) + 8.0:
			return true
	return false
