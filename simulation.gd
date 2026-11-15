extends RefCounted

const WRECK = Vector2(-150, 75)
const INNER = Vector2(75, -105)
const OUTER = Vector2(500, -18)
const FIELDS = [INNER, OUTER]
const HOME_RANGE = 340.0
const RELAY_RANGE = 345.0
const CAPACITY = 4
const RELAY_COST = 1
const FACTORY_FRAMES = 3
const FACTORY_MODULES = 2
const ASSEMBLY_TIME = 2.5
const PART_BUFFER = 4
const ORIGINAL = Vector3i(49, 49, 2)
# Per 100 ore units: iron, carbon, copper, silicon. The balance is tailings.
const YIELDS = [Vector4i(42, 18, 12, 18), Vector4i(15, 10, 30, 35)]
const FRAME_RECIPE = Vector4i(3, 1, 0, 0)
const MODULE_RECIPE = Vector4i(0, 0, 2, 2)

class Drone:
	var id: int
	var generation: int
	var weights: Vector3i
	var founder := 0
	var restored := false
	var salvage_priority := 0
	var restore_priority := 0
	var contact_index := -1
	var position: Vector2
	var target: Vector2
	var ore := 0
	var frames := 0
	var modules := 0
	var carrying_salvage := false
	var repair_module := false
	var condition := 100.0
	var order := "Mine"
	var reason := "Original mining directive"
	var timer := 0.0
	var last_field := 0

	func _init(number: int, origin: Vector2, version: int, priorities: Vector3i) -> void:
		id = number
		position = origin
		target = origin
		generation = version
		weights = priorities

var drones: Array[Drone] = []
var restored_queue: Array[Drone] = []
var contacts: Array = []
var next_drone_id := 6
var refinery := false
var insight := false
var fabricator := false
var factory := false
var factory_position := Vector2.ZERO
var relay := false
var relay_online := false
var relay_position := Vector2.ZERO
var outer_seen := false
var ore_remaining := [260, 420]
var ore_buffer := [0, 0]
var ore_cache := [0, 0]
var refinery_remainders := [Vector4i.ZERO, Vector4i.ZERO]
var elements := Vector4i.ZERO
var frames := 0
var modules := 0
var frame_progress := 0.0
var module_progress := 0.0
var factory_frames := 0
var factory_modules := 0
var mine_field := -1
var refine_timer := 0.0
var generation := 1
var latest_weights := ORIGINAL
var fabrication_time := 0.0

func _init() -> void:
	for i in range(5):
		var drone := Drone.new(i + 1, WRECK + Vector2(30 + i * 14, -30 + i * 11), 1, ORIGINAL)
		drone.founder = i + 1
		drones.append(drone)
		set_order(drone, "Mine", INNER, "Original mining directive")

func in_coverage(point: Vector2) -> bool:
	return point.distance_to(WRECK) <= HOME_RANGE or (
		relay_online and point.distance_to(relay_position) <= RELAY_RANGE
	)

func can_build_factory() -> bool:
	return fabricator and frames >= FACTORY_FRAMES and modules >= FACTORY_MODULES

func place_error(kind: String, point: Vector2) -> String:
	if kind == "relay" and point.distance_to(WRECK) > HOME_RANGE:
		return "Choose a site within the wreck’s sensor range."
	if not in_coverage(point):
		return "Choose a site within sensor coverage."
	if point.distance_to(WRECK) < 45 or point.distance_to(INNER) < 45:
		return "Give the structure some room."
	if outer_seen and point.distance_to(OUTER) < 45:
		return "Give the ore field some room."
	if factory and point.distance_to(factory_position) < 45:
		return "Too close to the factory."
	if relay and kind != "relay" and point.distance_to(relay_position) < 45:
		return "Too close to the relay."
	if kind == "factory" and (factory or not can_build_factory()):
		return "The factory needs 3 frames and 2 control modules."
	if kind == "relay" and (not refinery or (not relay and frames < RELAY_COST)):
		return "The relay needs one frame."
	return ""

func place(kind: String, point: Vector2) -> bool:
	if not place_error(kind, point).is_empty():
		return false
	match kind:
		"factory":
			frames -= FACTORY_FRAMES
			modules -= FACTORY_MODULES
			factory = true
			factory_position = point
		"relay":
			if not relay:
				frames -= RELAY_COST
			relay = true
			relay_online = true
			relay_position = point
			update_discovery()
		_:
			return false
	return true

func update_discovery() -> void:
	outer_seen = outer_seen or in_coverage(OUTER)

func tick(delta: float) -> void:
	if refinery:
		update_refinery(delta)
	if fabricator:
		update_fabricator(delta)
	for drone in drones:
		advance(drone, delta)
	for drone in restored_queue:
		drones.append(drone)
	restored_queue.clear()
	if not insight:
		var full := 0
		for drone in drones:
			if drone.ore == CAPACITY:
				full += 1
		insight = full == 5
	update_factory(delta)

func update_refinery(delta: float) -> void:
	if ore_buffer[0] + ore_buffer[1] == 0:
		refine_timer = 0.0
		return
	refine_timer += delta
	if refine_timer < 0.28:
		return
	refine_timer -= 0.28
	var field := 0 if ore_buffer[0] >= ore_buffer[1] else 1
	ore_buffer[field] -= 1
	var remainder: Vector4i = refinery_remainders[field] + YIELDS[field]
	for i in range(4):
		if remainder[i] >= 100:
			elements[i] += 1
			remainder[i] -= 100
	refinery_remainders[field] = remainder

func has_elements(recipe: Vector4i) -> bool:
	return elements.x >= recipe.x and elements.y >= recipe.y and elements.z >= recipe.z and elements.w >= recipe.w

func update_fabricator(delta: float) -> void:
	if has_elements(FRAME_RECIPE):
		frame_progress += delta
		if frame_progress >= 1.6:
			frame_progress = 0
			elements -= FRAME_RECIPE
			frames += 1
	if has_elements(MODULE_RECIPE):
		module_progress += delta
		if module_progress >= 2.2:
			module_progress = 0
			elements -= MODULE_RECIPE
			modules += 1

func apply_template(weights: Vector3i) -> void:
	if factory and weights != Vector3i.ZERO and (generation == 1 or weights != latest_weights):
		generation += 1
		latest_weights = weights

func update_factory(delta: float) -> void:
	if generation == 1 or factory_frames == 0 or factory_modules == 0:
		return
	fabrication_time += delta
	if fabrication_time < ASSEMBLY_TIME:
		return
	factory_frames -= 1
	factory_modules -= 1
	fabrication_time = 0
	var drone := Drone.new(next_drone_id, factory_position, generation, latest_weights)
	next_drone_id += 1
	drones.append(drone)
	choose_order(drone)

func factory_status() -> String:
	if not factory:
		return "Factory awaiting construction"
	if generation == 1:
		return "Apply a template to start assembly"
	if factory_frames > 0 and factory_modules > 0:
		return "Assembling · %d%%" % mini(99, int(fabrication_time / ASSEMBLY_TIME * 100))
	if factory_frames == 0 and factory_modules == 0:
		if frames > 0 or modules > 0:
			return "Waiting for component deliveries"
		return "Waiting for both component lines"
	if factory_frames == 0:
		if frames > 0:
			return "Waiting for frame delivery"
		return component_status("Frames", FRAME_RECIPE)
	if modules > 0:
		return "Waiting for module delivery"
	return component_status("Modules", MODULE_RECIPE)

func component_status(part: String, recipe: Vector4i) -> String:
	var names := ["iron", "carbon", "copper", "silicon"]
	var missing := PackedStringArray()
	for i in range(names.size()):
		if elements[i] < recipe[i]:
			missing.append(names[i])
	return "%s · Fabricating at wreck" % part if missing.is_empty() else "%s · Need %s" % [part, " and ".join(missing)]

func set_order(drone: Drone, order: String, destination: Vector2, reason: String) -> void:
	drone.order = order
	drone.target = destination + Vector2.from_angle(drone.id * 2.4) * 15.0
	drone.reason = reason
	drone.timer = 0.0

func choose_order(drone: Drone) -> void:
	if drone.carrying_salvage:
		set_order(drone, "Return salvage", WRECK, "Bringing recovered hardware to the wreck")
		return
	if drone.repair_module:
		set_order(drone, "Return module", WRECK, "Returning the unused repair module")
		return
	if drone.frames + drone.modules > 0:
		set_order(drone, "Supply factory", factory_position, "Components loaded for drone assembly")
		return
	if drone.condition <= 18.0 and refinery:
		set_order(drone, "Service", WRECK, "Critical wear triggered emergency servicing")
		return
	if drone.ore == CAPACITY:
		if refinery and drone.weights.y > 0:
			set_order(drone, "Deliver ore", WRECK, "Cargo hold full")
		elif refinery:
			set_order(drone, "Cache ore", FIELDS[drone.last_field], "Leaving ore for a hauler")
		else:
			wait_for_job(drone, "Cargo hold full. Ship intake offline.")
		return

	var field := mining_target(drone.position)
	var best := -1
	var order := ""
	var destination := WRECK
	var reason := ""
	if field >= 0 and drone.weights.x > 0 and (drone.ore == 0 or field == drone.last_field):
		best = drone.weights.x
		order = "Mine"
		destination = FIELDS[field]
		reason = "Mining has the highest available priority"
	if refinery and drone.ore > 0 and (drone.weights.y > 0 or field != drone.last_field):
		var score := drone.weights.y + 8 * (drone.ore - 1)
		if score >= best:
			best = score
			order = "Deliver ore" if drone.weights.y > 0 else "Cache ore"
			destination = WRECK if drone.weights.y > 0 else FIELDS[drone.last_field]
			reason = "Clearing the cargo hold"
	if refinery and drone.condition < 85.0 and drone.weights.z > 0:
		var score := drone.weights.z + int((85.0 - drone.condition) * 0.45)
		if score >= best:
			best = score
			order = "Service"
			destination = WRECK
			reason = "Maintenance priority increased by wear"
	if refinery and drone.ore == 0 and drone.weights.y > 0:
		var cache := available_cache()
		if cache >= 0 and drone.weights.y + 5 >= best:
			best = drone.weights.y + 5
			field = cache
			order = "Collect ore"
			destination = FIELDS[cache]
			reason = "Ore is waiting for pickup"
		if generation > 1 and needs_component_delivery() and drone.weights.y + 10 >= best:
			best = drone.weights.y + 10
			order = "Collect components"
			destination = WRECK
			reason = "Factory storage needs components"
	var contact := -1
	if refinery and drone.ore == 0:
		if drone.salvage_priority > 0 and drone.salvage_priority >= best:
			contact = find_contact(drone.position, "debris")
			if contact >= 0:
				best = drone.salvage_priority
				order = "Salvage"
				reason = "Recover intact components for the wreck’s storage"
		if drone.restore_priority > 0 and drone.restore_priority >= best and modules > 0:
			var disabled := find_contact(drone.position, "disabled")
			if disabled >= 0:
				contact = disabled
				order = "Collect repair module"
				reason = "Collect a control module to restore an old miner"
	if contact >= 0:
		drone.contact_index = contact
		contacts[contact].claimed = true
		destination = WRECK if order == "Collect repair module" else contacts[contact].position
	if order.is_empty():
		wait_for_job(drone, "No available task under these priorities")
		return
	if order in ["Mine", "Collect ore"]:
		drone.last_field = field
	set_order(drone, order, destination, reason)

func wait_for_job(drone: Drone, reason: String) -> void:
	drone.order = "Waiting"
	drone.target = drone.position
	drone.reason = reason
	drone.timer = 0

func mining_target(position: Vector2) -> int:
	var nearest := -1
	var distance := INF
	for field in range(FIELDS.size()):
		if mine_field >= 0 and field != mine_field:
			continue
		if ore_remaining[field] > 0 and in_coverage(FIELDS[field]):
			var candidate := position.distance_squared_to(FIELDS[field])
			if candidate < distance:
				distance = candidate
				nearest = field
	return nearest

func available_cache() -> int:
	for field in range(FIELDS.size()):
		var reserved := 0
		for other in drones:
			if other.order == "Collect ore" and other.last_field == field:
				reserved += CAPACITY
		if ore_cache[field] > reserved and in_coverage(FIELDS[field]):
			return field
	return -1

func needs_component_delivery() -> bool:
	var inbound_frames := factory_frames
	var inbound_modules := factory_modules
	for other in drones:
		if other.order == "Supply factory":
			inbound_frames += other.frames
			inbound_modules += other.modules
		if other.order == "Collect components":
			return false
	return (frames > 0 and inbound_frames < PART_BUFFER) or (modules > 0 and inbound_modules < PART_BUFFER)

func find_contact(origin: Vector2, kind: String) -> int:
	var nearest := -1
	var distance := INF
	for index in range(contacts.size()):
		var contact = contacts[index]
		if contact.removed or contact.claimed or contact.kind != kind or not in_coverage(contact.position):
			continue
		var candidate: float = origin.distance_squared_to(contact.position)
		if candidate < distance:
			distance = candidate
			nearest = index
	return nearest

func advance(drone: Drone, delta: float) -> void:
	if drone.order == "Waiting":
		drone.timer += delta
		if drone.timer >= 0.5:
			choose_order(drone)
		return
	if drone.contact_index >= 0:
		var contact = contacts[drone.contact_index]
		if not in_coverage(contact.position):
			contact.claimed = false
			drone.contact_index = -1
			choose_order(drone)
			return
		if drone.order != "Collect repair module":
			drone.target = contact.position
	if drone.position.distance_to(drone.target) > 1.0:
		drone.position = drone.position.move_toward(drone.target, 120.0 * delta)
		return
	drone.timer += delta
	var duration := 0.36
	match drone.order:
		"Mine": duration = 0.72
		"Service", "Salvage": duration = 1.2
		"Restore": duration = 1.8
	if drone.timer < duration:
		return
	if drone.order == "Collect repair module":
		if modules > 0:
			modules -= 1
			drone.repair_module = true
			set_order(drone, "Restore", contacts[drone.contact_index].position, "Delivering a control module to a disabled miner")
		else:
			contacts[drone.contact_index].claimed = false
			drone.contact_index = -1
			choose_order(drone)
		return
	complete_order(drone)
	if drone.order == "Collect ore" and drone.ore > 0:
		set_order(drone, "Deliver ore", WRECK, "Hauling ore from the field cache")
	else:
		choose_order(drone)

func complete_order(drone: Drone) -> void:
	var field := drone.last_field
	match drone.order:
		"Mine":
			if ore_remaining[field] > 0 and in_coverage(FIELDS[field]):
				ore_remaining[field] -= 1
				drone.ore += 1
				if refinery:
					drone.condition = maxf(0.0, drone.condition - 2.4)
		"Cache ore":
			ore_cache[field] += drone.ore
			drone.ore = 0
		"Collect ore":
			drone.ore = mini(ore_cache[field], CAPACITY)
			ore_cache[field] -= drone.ore
		"Deliver ore":
			ore_buffer[field] += drone.ore
			drone.ore = 0
		"Service":
			drone.condition = 100.0
		"Collect components":
			var inbound_frames := factory_frames
			var inbound_modules := factory_modules
			for other in drones:
				if other.order == "Supply factory":
					inbound_frames += other.frames
					inbound_modules += other.modules
			drone.frames = mini(frames, maxi(0, PART_BUFFER - inbound_frames))
			drone.modules = mini(modules, maxi(0, PART_BUFFER - inbound_modules))
			frames -= drone.frames
			modules -= drone.modules
		"Supply factory":
			factory_frames += drone.frames
			factory_modules += drone.modules
			drone.frames = 0
			drone.modules = 0
		"Return module":
			modules += 1
			drone.repair_module = false
		"Return salvage":
			drone.carrying_salvage = false
			frames += drone.frames
			modules += drone.modules
			drone.frames = 0
			drone.modules = 0
		"Salvage", "Restore":
			complete_recovery(drone)

func complete_recovery(drone: Drone) -> void:
	var contact = contacts[drone.contact_index]
	drone.contact_index = -1
	contact.claimed = false
	if drone.order == "Salvage":
		contact.removed = true
		drone.frames = 1 if contact.id % 2 == 0 else 0
		drone.modules = 1 - drone.frames
		drone.carrying_salvage = true
	elif drone.repair_module:
		drone.repair_module = false
		contact.removed = true
		var restored_drone := Drone.new(contact.id, contact.position, 1, ORIGINAL)
		restored_drone.restored = true
		choose_order(restored_drone)
		restored_queue.append(restored_drone)
