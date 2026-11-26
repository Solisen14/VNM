extends RefCounted
## Physical commissioning sequence for the first refinery.

const Refinery = preload("res://refinery_unit.gd")
const Motion = preload("res://worker_motion.gd")
const OreField = preload("res://ore_field.gd")

enum Stage { LOCKED, REPAIR, REACTOR_CUT, REACTOR_RELEASE, REACTOR_EXTRACT, REACTOR_SITE,
	REACTOR_TOW, REACTOR_RESTORE, CONDUIT, CABLE_ROUTE, CABLE_INSTALL, POWER_START, SEARCH,
	CONTROLLER_REPAIR, CONTROLLER_FLIGHT, SPECIALIZE, COMMISSION, ONLINE }

const REPAIR_CACHE := Vector2(1470, 132)
const REACTOR_BAY := Vector2(1675, 266)
const REACTOR_STAGING := Vector2(1675, -86)
const CONDUIT_CACHE := Vector2(1560, 154)
const SEARCH_CENTER := Vector2(-575, -460)
const FOUNDER_SITE := Vector2(-756, -496)
const RICH_FIELD := Vector2(-870, -665)
const RICH_ROCKS := 26
const RICH_UNITS_PER_ROCK := 14
const REVEAL_DISTANCE := 190.0
const SIGNAL_DISTANCE := 670.0
const REACTOR_OUTPUT := 30
const STARTER_ENERGY := 14400.0
const CUT_REQUIRED := 6
const REACTOR_SIZE := Vector2(128, 94)
const CABLE_UNIT_LENGTH := 95.0
const CONDUIT_RESERVE := 11
const COMMISSION_TIME := 9.0

const CONTACTS := ["refinery", "repair_cache", "reactor_bay", "reactor", "conduit_cache", "controller_2", "rich_ore"]
const TIMES := {
	"Recover service components": 4.0, "Deliver service components": 3.0,
	"Repair refinery": 8.0, "Strip reactor shielding": 6.0,
	"Restore auxiliary reactor": 8.0, "Recover conduit": 4.0, "Deliver conduit": 3.0,
	"Scan Controller 2": 4.0, "Restore Controller 2": 7.0, "Extract rich ore": 6.0,
}
const SERVICE_STOCK := {"refinery": 3, "reactor": 2, "controller": 2}

var stage := Stage.LOCKED
var refinery: Refinery = Refinery.new()
var service_remaining := SERVICE_STOCK.duplicate()
var service_carried := ""
var service_cargo := 0
var service_delivered := 0
var service_spent := {"refinery": 0, "reactor": 0, "controller": 0}
var conduit_remaining := CONDUIT_RESERVE
var conduit_cargo := 0
var conduit_stock := 0
var conduit_installed := 0
var cable_cost := 0
var cable_route := PackedVector2Array()
var cable_progress := 0.0
var reactor_position := REACTOR_BAY
var reactor_destination := REACTOR_STAGING
var reactor_cuts := 0
var reactor_hull_stock := 0
var reactor_ready := false
var energy := STARTER_ENERGY
var founder_position := FOUNDER_SITE
var founder_velocity := Vector2.ZERO
var founder_heading := 0.0
var founder_clock := 0.0
var founder_scanned := false
var founder_docking := false
var signal_strength := 0
var rich_field_discovered := false
var rich_mined := PackedInt32Array()
var rich_total := 0
var rich_sample_rock := -1
var rich_sample_surface := Vector2.ZERO
var rich_sample_valid := false
var logistics_unlocked := false
var elapsed := 0.0
var paused := false

# Temporary industrial assignment uses an existing autonomous drone. The
# assigned worker finishes its current bulk delivery before being reserved.
var crew := -1
var job_cargo := 0
var job_kind := ""
var work_clock := 0.0

func _init() -> void:
	rich_mined.resize(RICH_ROCKS)

func start(position: Vector2) -> void:
	if stage == Stage.LOCKED:
		refinery.position = position
		stage = Stage.REPAIR

func hal_load() -> int:
	return service_cargo + conduit_cargo

func service_target() -> String:
	match stage:
		Stage.REPAIR: return "refinery"
		Stage.REACTOR_RESTORE: return "reactor"
		Stage.CONTROLLER_REPAIR:
			return "controller" if founder_scanned else ""
	return ""

func visible(contact: String) -> bool:
	match contact:
		"refinery": return stage != Stage.LOCKED
		"repair_cache": return not service_target().is_empty()
		"reactor_bay": return stage >= Stage.REACTOR_CUT and stage <= Stage.REACTOR_RELEASE
		"reactor": return stage >= Stage.REACTOR_EXTRACT
		"conduit_cache": return stage == Stage.CONDUIT or stage == Stage.CABLE_ROUTE
		"controller_2": return stage >= Stage.CONTROLLER_REPAIR
		"rich_ore": return rich_field_discovered
	return false

func position_of(contact: String) -> Vector2:
	match contact:
		"refinery": return refinery.position
		"repair_cache": return REPAIR_CACHE
		"reactor_bay": return REACTOR_BAY
		"reactor": return reactor_position
		"conduit_cache": return CONDUIT_CACHE
		"controller_2": return founder_position
		"rich_ore": return RICH_FIELD
	return Vector2.ZERO

func contact_name(contact: String) -> String:
	match contact:
		"refinery": return "Refinery 01"
		"repair_cache": return "Authorized service locker"
		"reactor_bay": return "Auxiliary reactor compartment"
		"reactor": return "Auxiliary Fusion Reactor"
		"conduit_cache": return "Authorized conduit locker"
		"controller_2": return "Controller 2" if founder_scanned else "Unresolved control craft"
		"rich_ore": return "Ore Field 02 · Rich deposit"
	return ""

func command(contact: String, free_hold: int) -> String:
	if not visible(contact):
		return ""
	var target := service_target()
	match contact:
		"repair_cache":
			if int(service_remaining.get(target, 0)) > 0 and free_hold > 0:
				return "Recover service components"
		"refinery", "reactor", "controller_2":
			if contact == "controller_2" and stage == Stage.CONTROLLER_REPAIR and not founder_scanned:
				return "Scan Controller 2"
			if contact == target or (contact == "controller_2" and target == "controller"):
				if service_cargo > 0 and service_carried == target:
					return "Deliver service components"
				if service_delivered == int(SERVICE_STOCK[target]) and not (job_kind == "service" and job_cargo > 0):
					match target:
						"refinery": return "Repair refinery"
						"reactor": return "Restore auxiliary reactor"
						"controller": return "Restore Controller 2"
			if contact == "reactor" and conduit_cargo > 0 and stage in [Stage.CONDUIT, Stage.CABLE_ROUTE]:
				return "Deliver conduit"
		"reactor_bay":
			if stage == Stage.REACTOR_CUT and reactor_cuts < CUT_REQUIRED:
				return "Strip reactor shielding"
		"conduit_cache":
			if conduit_remaining > 0 and free_hold > 0:
				return "Recover conduit"
		"rich_ore":
			if free_hold > 0 and rich_total < RICH_ROCKS * RICH_UNITS_PER_ROCK:
				return "Extract rich ore"
	return ""

func interaction_hint(contact: String, free_hold: int) -> String:
	if contact in ["repair_cache", "conduit_cache", "rich_ore"] and free_hold <= 0:
		return "HAL's hold is full. Deliver its cargo before recovering more."
	if contact == "refinery":
		if stage == Stage.REPAIR:
			return "Service components delivered: %d / 3." % service_delivered
		return refinery.status()
	if contact == "reactor" and reactor_ready:
		return "Auxiliary output: %d kW · Starter reserve: %d kJ" % [REACTOR_OUTPUT if energy > 0.0 else 0, ceili(energy)]
	if contact == "controller_2" and refinery.controller_id == 2:
		return "Docked · Dedicated to Refinery 01"
	return ""

func execute(game, action: String) -> void:
	var target := service_target()
	var free: int = game.HOLD - game.controller_load()
	match action:
		"Recover service components":
			var amount := mini(free, int(service_remaining[target]))
			service_remaining[target] -= amount
			service_carried = target
			service_cargo += amount
		"Deliver service components":
			service_delivered += service_cargo
			service_carried = ""
			service_cargo = 0
		"Repair refinery", "Restore auxiliary reactor", "Restore Controller 2":
			service_spent[target] += service_delivered
			service_delivered = 0
			if target == "refinery":
				refinery.repaired = true
				stage = Stage.REACTOR_CUT
				game.report("Refinery restored · Auxiliary Fusion Reactor located in a separate compartment")
			elif target == "reactor":
				reactor_ready = true
				stage = Stage.CONDUIT
				game.report("Auxiliary reactor restored · Recover conduit from the authorized locker")
			else:
				stage = Stage.CONTROLLER_FLIGHT
				game.report("Controller 2 reactivated · Returning to the refinery")
		"Strip reactor shielding":
			cut_reactor(2)
		"Recover conduit":
			var amount := mini(free, conduit_remaining)
			conduit_remaining -= amount
			conduit_cargo += amount
		"Deliver conduit":
			conduit_stock += conduit_cargo
			conduit_cargo = 0
		"Scan Controller 2":
			founder_scanned = true
			game.report("Controller 2 in emergency standby · Recover its two compatible service modules")
		"Extract rich ore":
			if not rich_sample_valid or rich_sample_rock < 0:
				return
			var amount := mini(mini(free, 3), RICH_UNITS_PER_ROCK - rich_mined[rich_sample_rock])
			for i in range(amount):
				match OreField.mineral_at(rich_total + i):
					"Fe": game.cargo_fe += 1
					"Cu": game.cargo_cu += 1
					"Si": game.cargo_si += 1
			rich_mined[rich_sample_rock] += amount
			rich_total += amount
			game.ore += amount
			rich_sample_valid = false

func cut_reactor(amount: int) -> void:
	if stage != Stage.REACTOR_CUT:
		return
	var removed := mini(amount, CUT_REQUIRED - reactor_cuts)
	reactor_cuts += removed
	# The shielding is removed into the adjacent compartment's secured bin.
	reactor_hull_stock += removed
	if reactor_cuts == CUT_REQUIRED:
		stage = Stage.REACTOR_RELEASE
		work_clock = 0.0

func rich_center(index: int) -> Vector2:
	return OreField.rock_center(index) - OreField.CENTER + RICH_FIELD

func select_rich_rock(origin: Vector2) -> void:
	rich_sample_rock = -1
	var distance := INF
	for i in range(RICH_ROCKS):
		if rich_mined[i] >= RICH_UNITS_PER_ROCK:
			continue
		var next := origin.distance_squared_to(rich_center(i))
		if next < distance:
			distance = next
			rich_sample_rock = i
	if rich_sample_rock >= 0:
		var center := rich_center(rich_sample_rock)
		rich_sample_surface = center + (origin - center).normalized() * (OreField.rock_radius(rich_sample_rock) + 4.0)
		rich_sample_valid = true

func reactor_site_error(game, point: Vector2) -> String:
	if not game.WORLD.grow(-85).has_point(point) or point.y > -85:
		return "Choose open space above the hull"
	if not game.is_charted(point):
		return "Survey the installation site with HAL"
	if point.distance_to(refinery.position) < 174.0 or point.distance_to(refinery.position) > 425.0:
		return "Choose a site 174–425 units from the refinery"
	if not linked(game, point) or not linked(game, REACTOR_STAGING):
		return "Keep the staging area and site within HAL's link"
	var nearest := Geometry2D.get_closest_point_to_segment(refinery.position, REACTOR_STAGING, point)
	if nearest.distance_to(refinery.position) < 170.0:
		return "Keep the tow clear of the refinery"
	var cache := Geometry2D.get_closest_point_to_segment(game.STOCKPILE, REACTOR_STAGING, point)
	if cache.distance_to(game.STOCKPILE) < 110:
		return "Keep the tow clear of the Collection Point"
	for i in range(OreField.ROCK_COUNT):
		var center := OreField.rock_center(i)
		if game.rock_remaining(i) > 0 and Geometry2D.get_closest_point_to_segment(center, REACTOR_STAGING, point).distance_to(center) < 86.0 + OreField.rock_radius(i):
			return "Keep the tow clear of the asteroid field"
	return ""

func place_reactor(game, point: Vector2) -> String:
	if stage != Stage.REACTOR_SITE:
		return "The reactor is not staged"
	var error := reactor_site_error(game, point)
	if error.is_empty():
		reactor_destination = point
		stage = Stage.REACTOR_TOW
	return error

func route_cost(point: Vector2) -> int:
	return ceili((reactor_position.distance_to(point) + point.distance_to(refinery.position)) / CABLE_UNIT_LENGTH)

func cable_error(game, point: Vector2) -> String:
	if not game.WORLD.has_point(point) or point.y >= game.HULL_BOUNDS.position.y or not game.is_charted(point):
		return "Choose a surveyed waypoint above the hull"
	if not linked(game, point) or not linked(game, reactor_position) or not linked(game, refinery.position):
		return "Keep the entire route within HAL's link"
	var previous := reactor_position
	for endpoint in [point, refinery.position]:
		if Geometry2D.get_closest_point_to_segment(game.STOCKPILE, previous, endpoint).distance_to(game.STOCKPILE) < 42.0:
			return "Route around the Collection Point"
		for i in range(OreField.ROCK_COUNT):
			var center := OreField.rock_center(i)
			if game.rock_remaining(i) > 0 and Geometry2D.get_closest_point_to_segment(center, previous, endpoint).distance_to(center) < OreField.rock_radius(i) + 8.0:
				return "Route around the asteroid field"
		previous = endpoint
	var cost := route_cost(point)
	if cost > conduit_stock:
		return "Route needs %d conduit · %d delivered" % [cost, conduit_stock]
	return ""

func install_cable(game, point: Vector2) -> String:
	if stage not in [Stage.CONDUIT, Stage.CABLE_ROUTE] or not reactor_ready:
		return "Restore the auxiliary reactor first"
	var error := cable_error(game, point)
	if error.is_empty():
		cable_cost = route_cost(point)
		conduit_stock -= cable_cost
		cable_route = PackedVector2Array([reactor_position, point, refinery.position])
		stage = Stage.CABLE_INSTALL
	return error

func linked(game, point: Vector2) -> bool:
	return point.distance_to(game.player) <= game.COMMS_RANGE - 90.0

func select_material(material: String) -> bool:
	if stage != Stage.SPECIALIZE or not refinery.select_material(material):
		return false
	stage = Stage.COMMISSION
	elapsed = 0.0
	return true

func dock_port() -> Vector2:
	return refinery.position + Vector2(-53, 67)

func tick(game, delta: float) -> void:
	paused = false
	match stage:
		Stage.REPAIR, Stage.REACTOR_RESTORE:
			tick_service(game, delta)
		Stage.REACTOR_CUT, Stage.REACTOR_RELEASE:
			tick_reactor_bay(game, delta)
		Stage.REACTOR_EXTRACT, Stage.REACTOR_TOW:
			tick_reactor_tow(game, delta)
		Stage.CONDUIT, Stage.CABLE_ROUTE:
			tick_conduit(game, delta)
		Stage.CABLE_INSTALL:
			tick_cable(game, delta)
		Stage.POWER_START:
			elapsed += delta
			if elapsed >= 3.0:
				refinery.powered = reactor_ready and conduit_installed > 0 and REACTOR_OUTPUT >= refinery.power_draw and energy > 0.0
				stage = Stage.SEARCH
				game.report("Power available · Intermittent control-frequency anomaly to the west")
		Stage.SEARCH:
			tick_search(game)
		Stage.CONTROLLER_FLIGHT:
			tick_founder(delta)
		Stage.COMMISSION, Stage.ONLINE:
			if reactor_ready and conduit_installed > 0 and refinery.powered and refinery.can_operate():
				# The reserve is isolated until commissioning requests a real load.
				var draw := float(refinery.power_draw) if stage == Stage.COMMISSION else 2.0
				energy = maxf(0.0, energy - delta * draw)
			refinery.powered = reactor_ready and conduit_installed > 0 and energy > 0.0 and REACTOR_OUTPUT >= refinery.power_draw
			if stage == Stage.COMMISSION and refinery.can_operate():
				elapsed += delta
				if elapsed >= COMMISSION_TIME:
					refinery.commissioned = true
					logistics_unlocked = true
					stage = Stage.ONLINE
					game.report("Refinery online · Logistics / Hauling Insight unlocked")

func tick_search(game) -> void:
	var distance: float = game.player.distance_to(FOUNDER_SITE)
	signal_strength = roundi(100.0 * clampf(1.0 - distance / SIGNAL_DISTANCE, 0.0, 1.0))
	if game.is_charted(RICH_FIELD) and game.player.distance_to(RICH_FIELD) <= game.SENSOR_RANGE:
		rich_field_discovered = true
	if rich_field_discovered and distance <= REVEAL_DISTANCE and game.is_charted(FOUNDER_SITE):
		stage = Stage.CONTROLLER_REPAIR
		game.report("Control-frequency source resolved · Right-click to scan the craft")

func tick_founder(delta: float) -> void:
	founder_clock += delta
	var port := dock_port()
	var target := port + Vector2(0, 95) if not founder_docking else port
	var offset := target - founder_position
	if offset.length() <= 3.0 and founder_velocity.length() < 22.0:
		founder_position = target
		founder_velocity = Vector2.ZERO
		if not founder_docking:
			founder_docking = true
		else:
			founder_heading = rotate_toward(founder_heading, -PI / 2.0, delta)
			if absf(angle_difference(founder_heading, -PI / 2.0)) < 0.03:
				refinery.controller_id = 2
				stage = Stage.SPECIALIZE
		return
	var speed := 32.0 if founder_docking else 118.0
	founder_velocity = Motion.next_velocity(founder_position, founder_velocity, target, delta, founder_clock, 1.7, speed, 32.0)
	founder_heading = rotate_toward(founder_heading, offset.angle(), 1.3 * delta)
	founder_position += founder_velocity * delta

func reserve_worker(game) -> bool:
	if crew >= 0:
		return true
	for i in range(game.salvage_workers.size()):
		var worker: Dictionary = game.salvage_workers[i]
		if bool(worker["active"]) and int(worker["cargo"]) == 0:
			crew = i
			worker["time"] = 0.0
			return true
	return false

func release_worker(game) -> void:
	if crew >= 0:
		game.assign_worker_task(game.salvage_workers[crew], 42 + crew)
		crew = -1
	work_clock = 0.0

func work_at(game, point: Vector2, delta: float, duration: float) -> bool:
	if not linked(game, point):
		paused = true
		return false
	if not reserve_worker(game):
		return false
	var worker: Dictionary = game.salvage_workers[crew]
	var position: Vector2 = worker["position"]
	if position.distance_to(point) > 3.0:
		var destination: Vector2 = game.player if position.distance_to(game.player) > game.COMMS_RANGE else point
		game.move_salvager(worker, destination, delta, crew)
		return false
	worker["position"] = point
	worker["velocity"] = Vector2.ZERO
	work_clock += delta
	if work_clock < duration:
		return false
	work_clock = 0.0
	return true

func tick_service(game, delta: float) -> void:
	var target := service_target()
	if service_delivered >= int(SERVICE_STOCK[target]):
		return
	if job_cargo > 0:
		var point := refinery.position if target == "refinery" else reactor_position
		if work_at(game, point, delta, 2.0):
			service_delivered += job_cargo
			job_cargo = 0
			job_kind = ""
			release_worker(game)
	elif int(service_remaining[target]) > 0 and work_at(game, REPAIR_CACHE, delta, 4.0):
		job_cargo = int(service_remaining[target])
		service_remaining[target] = 0
		job_kind = "service"
	elif int(service_remaining[target]) == 0 and crew >= 0:
		release_worker(game)

func tick_reactor_bay(game, delta: float) -> void:
	var duration := 6.0 if stage == Stage.REACTOR_CUT else 8.0
	if not work_at(game, REACTOR_BAY, delta, duration):
		return
	if stage == Stage.REACTOR_CUT:
		cut_reactor(2)
	else:
		stage = Stage.REACTOR_EXTRACT
		game.report("Auxiliary reactor disconnected · Towing it clear")

func tick_reactor_tow(game, delta: float) -> void:
	if not linked(game, reactor_position) or not linked(game, reactor_destination):
		paused = true
		return
	reactor_position = reactor_position.move_toward(reactor_destination, 33.0 * delta)
	var worker: Dictionary = game.salvage_workers[crew]
	worker["position"] = reactor_position + Vector2(-65, 8)
	worker["velocity"] = Vector2.ZERO
	if reactor_position == reactor_destination:
		if stage == Stage.REACTOR_EXTRACT:
			stage = Stage.REACTOR_SITE
		else:
			stage = Stage.REACTOR_RESTORE
			release_worker(game)

func tick_conduit(game, delta: float) -> void:
	if job_cargo > 0:
		if work_at(game, reactor_position, delta, 3.0):
			conduit_stock += job_cargo
			job_kind = ""
			job_cargo = 0
			release_worker(game)
	elif conduit_remaining > 0 and work_at(game, CONDUIT_CACHE, delta, 4.0):
		job_cargo = mini(4, conduit_remaining)
		conduit_remaining -= job_cargo
		job_kind = "conduit"
	elif conduit_remaining == 0 and crew >= 0:
		release_worker(game)
	if conduit_stock >= ceili(reactor_position.distance_to(refinery.position) / CABLE_UNIT_LENGTH):
		stage = Stage.CABLE_ROUTE

func cable_point(fraction: float) -> Vector2:
	var first := cable_route[0].distance_to(cable_route[1])
	var second := cable_route[1].distance_to(cable_route[2])
	var distance := (first + second) * fraction
	if distance <= first and first > 0.0:
		return cable_route[0].lerp(cable_route[1], distance / first)
	return cable_route[1].lerp(cable_route[2], (distance - first) / maxf(second, 0.001))

func tick_cable(game, delta: float) -> void:
	for point in cable_route:
		if not linked(game, point):
			paused = true
			return
	# Finish a conduit delivery already in transit before starting the install.
	if job_cargo > 0:
		if work_at(game, reactor_position, delta, 3.0):
			conduit_stock += job_cargo
			job_cargo = 0
			job_kind = ""
		return
	var point := cable_point(cable_progress)
	if not work_at(game, point, delta, 0.0):
		return
	cable_progress = minf(1.0, cable_progress + delta / (4.0 + float(cable_cost) * 2.0))
	if cable_progress >= 1.0:
		conduit_installed = cable_cost
		stage = Stage.POWER_START
		elapsed = 0.0
		release_worker(game)
		game.report("Cable connected · Stabilizing auxiliary power")
