extends RefCounted

const Simulation = preload("res://simulation.gd")
const FLEET_SIZE := 256
const RECALL_AT := 6.0
const BLAST_AT := 9.5
const HANDOFF_AT := 13.0

class Contact:
	var id: int
	var position: Vector2
	var velocity: Vector2
	var kind: String
	var angle: float

	func _init(number: int, origin: Vector2, drift: Vector2, state: String, heading: float) -> void:
		id = number
		position = origin
		velocity = drift
		kind = state
		angle = heading

var time := 0.0
var dock_ports := PackedVector2Array()
var mining_sites := PackedVector2Array()
var phases := PackedFloat32Array()
var periods := PackedFloat32Array()
var casualties: Array[Contact] = []
var survivors := PackedVector2Array()
var survivor_ids := PackedInt32Array()
var destroyed := 0
var disabled := 0

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2456
	for i in range(FLEET_SIZE):
		dock_ports.append(Simulation.WRECK + Vector2(rng.randf_range(-40, 38), rng.randf_range(-28, 28)))
		mining_sites.append(Simulation.INNER + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(12, 90))
		phases.append(rng.randf())
		periods.append(rng.randf_range(5.2, 9.4))

func advance(delta: float) -> void:
	time += delta
	if time >= BLAST_AT and casualties.is_empty():
		resolve_blast()
	var drift_delta := minf(delta, maxf(0, time - BLAST_AT))
	for contact in casualties:
		contact.position += contact.velocity * drift_delta
		contact.angle += (0.12 if contact.kind == "disabled" else 0.48) * drift_delta

func position_at(index: int, moment: float) -> Vector2:
	var sample := minf(moment, RECALL_AT)
	var cycle := fposmod(phases[index] + sample / periods[index], 1.0)
	var progress := 1.0 - absf(2.0 * cycle - 1.0)
	var position := dock_ports[index].lerp(mining_sites[index], progress)
	var lane := (mining_sites[index] - dock_ports[index]).normalized().orthogonal()
	position += lane * sin(progress * PI) * (18.0 if cycle < 0.5 else -18.0)
	if moment > RECALL_AT:
		return position.move_toward(dock_ports[index], (moment - RECALL_AT) * (26.0 + (index % 37)))
	return position

func resolve_blast() -> void:
	# Surviving craft are drawn from the units farthest from the reactor at ignition.
	var by_distance: Array[int] = []
	for i in range(FLEET_SIZE):
		by_distance.append(i)
	by_distance.sort_custom(func(a: int, b: int) -> bool:
		return position_at(a, BLAST_AT).distance_squared_to(Simulation.WRECK) > position_at(b, BLAST_AT).distance_squared_to(Simulation.WRECK)
	)
	for i in range(5):
		var index: int = by_distance.pop_front()
		survivors.append(position_at(index, BLAST_AT))
		survivor_ids.append(index + 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for index in by_distance:
		var origin := position_at(index, BLAST_AT)
		var distance := origin.distance_to(Simulation.WRECK)
		var is_destroyed := distance < rng.randf_range(38.0, 145.0)
		var heading := rng.randf_range(0, TAU)
		if is_destroyed:
			destroyed += 1
			var outward := (origin - Simulation.WRECK).normalized().rotated(rng.randf_range(-0.7, 0.7))
			casualties.append(Contact.new(index + 1, origin, outward * rng.randf_range(1.5, 7.5), "debris", heading))
		else:
			disabled += 1
			casualties.append(Contact.new(index + 1, origin, Vector2.from_angle(heading) * rng.randf_range(0.3, 1.4), "disabled", heading))
