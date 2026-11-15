extends RefCounted

const WRECK = Vector2(-150, 75)
const INNER = Vector2(75, -105)
const OUTER = Vector2(500, -18)
const HOME_RANGE = 340.0
const RELAY_RANGE = 345.0
const CAPACITY = 4
const FACTORY_COST = 10
const RELAY_COST = 5
const DRONE_COST = 6
const FABRICATION_TIME = 2.5
const ORIGINAL = Vector3i(49, 49, 2)

class Drone:
	var id: int
	var generation: int
	var weights: Vector3i
	var position: Vector2
	var target: Vector2
	var ore := 0
	var cargo_metal := 0
	var condition := 100.0
	var order := "Mine"
	var reason := "Original mining directive"
	var timer := 0.0
	var last_field := -1

	func _init(number: int, origin: Vector2, version: int, priorities: Vector3i) -> void:
		id = number
		position = origin
		target = origin
		generation = version
		weights = priorities

var drones: Array[Drone] = []
var next_drone_id := 6
var refinery := false
var insight := false
var factory := false
var factory_position := Vector2.ZERO
var relay := false
var relay_online := false
var relay_position := Vector2.ZERO
var outer_seen := false
var ore_buffer := 0
var metal := 0
var factory_metal := 0
var ore_remaining := [160, 280]
var refine_timer := 0.0
var generation := 1
var latest_weights := ORIGINAL
var fabrication_time := 0.0
var elapsed := 0.0

func _init() -> void:
	for i in range(5):
		var drone := Drone.new(i + 1, WRECK + Vector2(30 + i * 14, -30 + i * 11), 1, ORIGINAL)
		drones.append(drone)
		drone.last_field = 0
		set_order(drone, "Mine", INNER, "Original mining directive")

func in_coverage(point: Vector2) -> bool:
	return point.distance_to(WRECK) <= HOME_RANGE or (
		relay_online and point.distance_to(relay_position) <= RELAY_RANGE
	)

func place_error(kind: String, point: Vector2) -> String:
	if kind == "relay" and point.distance_to(WRECK) > HOME_RANGE:
		return "The relay needs a link to the wreck. Choose a site within its sensor range."
	if not in_coverage(point):
		return "Choose a site within sensor coverage."
	if point.distance_to(WRECK) < 45.0 or point.distance_to(INNER) < 45.0:
		return "Give the structure some room."
	if outer_seen and point.distance_to(OUTER) < 45.0:
		return "Give the ore field some room."
	if factory and point.distance_to(factory_position) < 45.0:
		return "Too close to the factory."
	if relay and kind != "relay" and point.distance_to(relay_position) < 45.0:
		return "Too close to the relay."
	if kind == "factory" and (factory or not refinery or metal < FACTORY_COST):
		return "Factory placement is unavailable."
	if kind == "relay" and (not refinery or (not relay and metal < RELAY_COST)):
		return "Relay placement is unavailable."
	return ""

func place(kind: String, point: Vector2) -> bool:
	if not place_error(kind, point).is_empty():
		return false
	match kind:
		"factory":
			metal -= FACTORY_COST
			factory = true
			factory_position = point
		"relay":
			if not relay:
				metal -= RELAY_COST
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
	elapsed += delta
	if refinery and ore_buffer > 0:
		refine_timer += delta
		while refine_timer >= 0.4 and ore_buffer > 0:
			refine_timer -= 0.4
			ore_buffer -= 1
			metal += 1
	else:
		refine_timer = 0.0
	for drone in drones:
		advance(drone, delta)
	if not insight:
		var blocked := 0
		for drone in drones:
			if drone.ore == CAPACITY:
				blocked += 1
		insight = blocked == 5
	update_factory(delta)

func apply_template(weights: Vector3i) -> void:
	if factory and weights != Vector3i.ZERO and (generation == 1 or weights != latest_weights):
		generation += 1
		latest_weights = weights

func update_factory(delta: float) -> void:
	if generation == 1 or factory_metal < DRONE_COST:
		return
	fabrication_time += delta
	if fabrication_time < FABRICATION_TIME:
		return
	factory_metal -= DRONE_COST
	fabrication_time = 0.0
	var new_drone := Drone.new(next_drone_id, factory_position, generation, latest_weights)
	next_drone_id += 1
	drones.append(new_drone)
	choose_order(new_drone)

func factory_status() -> String:
	if not factory:
		return "Place a drone factory to apply a template."
	if generation == 1:
		return "Factory idle · Apply a template to start."
	if factory_metal >= DRONE_COST:
		return "Fabricating · %d%%" % mini(99, int(fabrication_time / FABRICATION_TIME * 100))
	for drone in drones:
		if drone.order == "Collect metal" or drone.cargo_metal > 0:
			return "Waiting for metal in transit"
	if metal > 0:
		return "Waiting for drones to deliver metal"
	if ore_buffer > 0:
		return "Waiting for the refinery to process ore"
	return "Waiting for ore to reach the refinery"

func set_order(drone: Drone, order: String, destination: Vector2, reason: String) -> void:
	drone.order = order
	drone.target = destination + Vector2.from_angle(drone.id * 2.4) * 15.0
	drone.reason = reason
	drone.timer = 0.0

func choose_order(drone: Drone) -> void:
	if drone.cargo_metal > 0:
		set_order(drone, "Supply factory", factory_position, "Refined metal loaded for the factory")
		return
	if drone.condition <= 18.0 and refinery:
		set_order(drone, "Repair", WRECK, "Critical wear triggered emergency repair")
		return
	if drone.ore == CAPACITY:
		if refinery:
			set_order(drone, "Deliver", WRECK, "Cargo hold full")
		else:
			set_order(drone, "Waiting", drone.position - Vector2.from_angle(drone.id * 2.4) * 15.0, "Cargo hold full. Ship intake offline.")
		return

	var field := -1
	var mine_score := -1
	if ore_remaining[0] > 0:
		field = 0
	if in_coverage(OUTER) and ore_remaining[1] > 0:
		if field < 0 or drone.position.distance_to(OUTER) < drone.position.distance_to(INNER):
			field = 1
	if field >= 0 and drone.weights.x > 0:
		mine_score = drone.weights.x
	var deliver_score := -1
	if refinery and drone.ore > 0 and drone.weights.y > 0:
		deliver_score = drone.weights.y + 8 * (drone.ore - 1)
	var supply_score := -1
	if generation > 1 and metal > 0 and drone.ore == 0 and drone.weights.y > 0:
		var inbound := factory_metal
		for other in drones:
			inbound += other.cargo_metal
			if other.order == "Collect metal":
				inbound += CAPACITY
		if inbound < DRONE_COST:
			supply_score = drone.weights.y + 10
	var repair_score := -1
	if refinery and drone.condition < 85.0 and drone.weights.z > 0:
		repair_score = drone.weights.z + int((85.0 - drone.condition) * 0.45)
	var best := maxi(maxi(mine_score, deliver_score), maxi(supply_score, repair_score))
	if best < 0:
		if refinery and drone.ore > 0:
			set_order(drone, "Deliver", WRECK, "No reachable ore remains. Unloading the remaining cargo.")
		else:
			set_order(drone, "Waiting", drone.position - Vector2.from_angle(drone.id * 2.4) * 15.0, "No available task under this generation’s priorities")
	elif best == supply_score:
		set_order(drone, "Collect metal", WRECK, "The factory needs refined metal for automatic production")
	elif best == repair_score:
		set_order(drone, "Repair", WRECK, "Repair priority increased by wear")
	elif best == deliver_score:
		set_order(drone, "Deliver", WRECK, "Delivery priority increased by cargo load")
	else:
		drone.last_field = field
		var location := INNER if field == 0 else OUTER
		set_order(drone, "Mine", location, "Mining has the highest available priority")

func advance(drone: Drone, delta: float) -> void:
	if drone.order == "Waiting":
		drone.timer += delta
		if drone.timer >= 0.5:
			choose_order(drone)
		return
	if drone.position.distance_to(drone.target) > 1.0:
		drone.position = drone.position.move_toward(drone.target, 120.0 * delta)
		return
	drone.timer += delta
	var duration := 0.36
	if drone.order == "Mine":
		duration = 0.72
	elif drone.order == "Repair":
		duration = 1.2
	if drone.timer < duration:
		return
	match drone.order:
		"Mine":
			var field := drone.last_field
			if field >= 0 and ore_remaining[field] > 0:
				ore_remaining[field] -= 1
				drone.ore += 1
				if refinery:
					drone.condition = maxf(0.0, drone.condition - 2.4)
		"Deliver":
			ore_buffer += drone.ore
			drone.ore = 0
		"Repair":
			drone.condition = 100.0
		"Collect metal":
			drone.cargo_metal = mini(metal, CAPACITY)
			metal -= drone.cargo_metal
		"Supply factory":
			factory_metal += drone.cargo_metal
			drone.cargo_metal = 0
	choose_order(drone)
