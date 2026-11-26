extends RefCounted

const WorkerMotion = preload("res://worker_motion.gd")
const OreField = preload("res://ore_field.gd")

enum Phase { SAFE_MODE, DIAGNOSTICS, SENSORS, FLIGHT, WAYFINDING, COMMS, CONTACTS, FIELD_REPAIR, ORDERS, HAULING }
enum RefineryPhase { BURIED, EXPOSED, DISCONNECTING, EXTRACTING, STAGED, HAULING, ANCHORING, PLACED }

const ORE_REQUIRED := 3
const PARTS_REQUIRED := 2
const HOLD := 5
const GRID := 32
const SENSOR_RANGE := 245.0
const INTERACT_RANGE := 82.0
const TURN_SPEED := 1.42
const ACCELERATION := 75.0
const MAX_SPEED := 145.0
const MINER_SPEED := 110.0
const MINER_ACCELERATION := 70.0
# The existing 2020-world-unit Asterion hull is approximately 5 km long.
# Workers and founders retain their physical dimensions at any camera zoom.
const ASTERION_LENGTH_METRES := 5000.0
const CONTROLLER_LENGTH_METRES := 25.0
const WORKER_LENGTH_METRES := 4.0
const METRES_PER_WORLD_UNIT := ASTERION_LENGTH_METRES / 2020.0
const CONTROLLER_WORLD_LENGTH := CONTROLLER_LENGTH_METRES / METRES_PER_WORLD_UNIT
const WORKER_WORLD_LENGTH := WORKER_LENGTH_METRES / METRES_PER_WORLD_UNIT
const MINER_EXTRACTION_TIME := 8.0
const MINER_UNLOAD_TIME := 5.0
# Visual pixels are batches of recoverable matter, not individual simulated atoms.
const FIELD_RESERVE := OreField.TOTAL_UNITS
const HULL_RESERVE := 48
const REFINERY_EXPOSURE := 12
const SALVAGE_SITE_QUOTA := 4
const SALVAGE_CONTACTS := ["salvage_1", "salvage_2", "salvage_3"]
const SALVAGE_SPAWNS := [Vector2(1040, 560), Vector2(1225, 565), Vector2(1350, 430)]
const SALVAGE_SITES := [Vector2(1160, 285), Vector2(1255, 325), Vector2(1345, 370)]
# Initial controller constraints. Coordination upgrades are a much later Insight.
const DRONE_CAPACITY := 10
const COMMS_RANGE := 1450.0
const MINER_LOAD_SIZE := 3
const HULL_CUT_TIME := 12.0
const HULL_WORKSITE := Vector2(1275, 340)
const HULL_BOUNDS := Rect2(380, 45, 2020, 1136)
const REFINERY_BAY := HULL_WORKSITE + Vector2(36, 20)
const REFINERY_SIZE := Vector2(190, 116)
const REFINERY_CLEARANCE := 115.0
const REFINERY_STAGING := Vector2(REFINERY_BAY.x, -84)
const REFINERY_DISCONNECT_TIME := 8.0
const REFINERY_ANCHOR_TIME := 7.0
const REFINERY_TOW_SPEED := 38.0
const REFINERY_CREW_OFFSETS := [Vector2(66, -50), Vector2(66, 50), Vector2(-81, 0)]
const WORK_TIMES := {
	"Approach and scan": 3.5,
	"Extract ore sample": 6.0,
	"Recover spare part": 4.5,
	"Repair mining drone": 7.0,
	"Unload raw ore": 3.5,
	"Collect repair supplies": 4.0,
	"Repair salvage drone": 7.0,
}
const WORK_LABELS := {
	"Approach and scan": "Scanning contact",
	"Extract ore sample": "Extracting ore",
	"Recover spare part": "Recovering spare part",
	"Repair mining drone": "Repairing miner",
	"Unload raw ore": "Unloading raw ore",
	"Collect repair supplies": "Collecting repair supplies",
	"Repair salvage drone": "Restoring salvage worker",
}
const WORLD := Rect2(-2200, -1550, 4700, 3450)
const FIELD := Vector2(530, -215)
const MINER := Vector2(405, 395)
const WRECK := Vector2(1180, 240)
const DRONE_A := Vector2(730, 525)
const DRONE_B := Vector2(1060, 600)
# A provisional collection pad outside the Asterion, beside its former intake.
const STOCKPILE := Vector2(1020, -38)
const REFINERY_INTAKE := Vector2(1090, 66)
const CONTACTS := ["ore", "miner", "wreck", "parts_a", "parts_b", "stockpile", "salvage_1", "salvage_2", "salvage_3"]
const PRIMARY := ["ore", "miner", "wreck"]

var phase := Phase.SAFE_MODE
var name_text := ""
var phase_time := 0.0
var player := Vector2.ZERO
var heading := 0.0
var velocity := Vector2.ZERO
var destination := Vector2.ZERO
var has_destination := false
var pending_contact := ""
var pending_action := ""
var work_contact := ""
var work_action := ""
var work_time := 0.0
var chart := {}
var scanned := {}
var salvaged := {}
var ore := 0
var parts := 0
var drill_loads := 6
var field_extracted := 0
var hull_extracted := 0
var hull_stock := 0
var salvage_deliveries := 0
var salvage_mode := false
var miner_cargo_type := "ore"
var refinery_exposed := false
var refinery_phase := RefineryPhase.BURIED
var refinery_position := REFINERY_BAY
var refinery_destination := REFINERY_STAGING
var refinery_work_time := 0.0
var refinery_crew := PackedInt32Array()
var refinery_link_paused := false
var zoomed_in := false
var zoomed_out := false
var turned := false
var thrust_used := false
var miner_position := MINER
var miner_heading := -0.25
var miner_cargo := 0
var stock_ore := 0
var deliveries := 0
var to_field := true
var miner_work_time := 0.0
var miner_speed := 0.0
var miner_velocity := Vector2.ZERO
var miner_flight_clock := 0.0
var miner_leg_number := 0
var notice := ""
var notice_time := 0.0
var active_drones := 0
var salvage_insight_ready := false
# A repaired worker selects a physical asteroid surface, never the field centre.
var asteroid_mined := PackedInt32Array()
var miner_rock := -1
var miner_worksite := Vector2.ZERO
var miner_selection_round := 0
var miner_linked := true
# The first field is raw matter with real species, not generic instant components.
var field_fe_extracted := 0
var field_cu_extracted := 0
var field_si_extracted := 0
var miner_fe := 0
var miner_cu := 0
var miner_si := 0
var stock_fe := 0
var stock_cu := 0
var stock_si := 0
# Raw material carried by HAL for personal mining and stockpile drops.
var cargo_fe := 0
var cargo_cu := 0
var cargo_si := 0
var spent_fe := 0
var spent_cu := 0
var spent_si := 0
var repair_kits := 0
var manual_rock := -1
var manual_worksite := Vector2.ZERO
var salvage_insight_unlocked := false
var salvage_workers: Array[Dictionary] = []
var hull_site_units := PackedInt32Array([0, 0, 0])

func _init() -> void:
	for i in range(OreField.ROCK_COUNT):
		asteroid_mined.append(0)
	for i in range(SALVAGE_CONTACTS.size()):
		salvage_workers.append({
			"active": false,
			"position": SALVAGE_SPAWNS[i],
			"velocity": Vector2.ZERO,
			"heading": 0.0,
			"clock": float(i) * 0.7,
			"leg": i,
			"index": i,
			"site_index": i,
			"to_hull": true,
			"time": 0.0,
			"cargo": 0,
			"linked": true
		})

func salvage_index(contact: String) -> int:
	return SALVAGE_CONTACTS.find(contact)

func salvage_worker_active(contact: String) -> bool:
	var index := salvage_index(contact)
	return index >= 0 and bool(salvage_workers[index]["active"])

func unlock_salvage() -> void:
	if not salvage_insight_ready or salvage_insight_unlocked:
		return
	salvage_insight_unlocked = true
	report("SALVAGE UNLOCKED · Three dormant workers detected near the hull")

func controller_load() -> int:
	return ore + parts + repair_kits * 3

func can_collect_repair_supplies() -> bool:
	return salvage_insight_unlocked and has_worker_capacity() and repair_kits == 0 and controller_load() + 3 <= HOLD and stock_fe >= 2 and stock_cu >= 1

func manual_ore_destination() -> Vector2:
	if manual_rock < 0 or rock_remaining(manual_rock) <= 0:
		manual_rock = OreField.rock_for_manual_sample(player, asteroid_mined)
	if manual_rock < 0:
		return FIELD
	manual_worksite = OreField.near_surface(manual_rock, player)
	return manual_worksite

func action_position(contact: String, action: String) -> Vector2:
	if contact == "ore" and action == "Extract ore sample" and manual_rock >= 0:
		return manual_worksite
	return position_of(contact)

func has_worker_capacity() -> bool:
	return active_drones < DRONE_CAPACITY

func link_status() -> String:
	if phase < Phase.HAULING:
		return "STANDBY"
	if miner_position.distance_to(player) > COMMS_RANGE:
		return "RECONNECTING"
	if to_field and miner_worksite.distance_to(player) > COMMS_RANGE:
		return "WORKSITE OUT OF RANGE"
	if STOCKPILE.distance_to(player) > COMMS_RANGE:
		return "STOCKPILE OUT OF RANGE"
	return "CONNECTED"

func rock_remaining(index: int) -> int:
	return maxi(0, OreField.rock_capacity(index) - asteroid_mined[index])

func extract_rock(index: int, count: int) -> Dictionary:
	var yield_amount := mini(count, rock_remaining(index))
	var minerals := {"Fe": 0, "Cu": 0, "Si": 0}
	for j in range(yield_amount):
		var element := OreField.mineral_at(field_extracted)
		minerals[element] += 1
		match element:
			"Fe": field_fe_extracted += 1
			"Cu": field_cu_extracted += 1
			"Si": field_si_extracted += 1
		asteroid_mined[index] += 1
		field_extracted += 1
	return minerals

func choose_mining_site() -> bool:
	if miner_rock >= 0 and rock_remaining(miner_rock) > 0:
		return true
	miner_selection_round += 1
	miner_rock = OreField.nearest_viable_rock(
		STOCKPILE, player, COMMS_RANGE, asteroid_mined, miner_selection_round
	)
	if miner_rock < 0:
		miner_worksite = Vector2.ZERO
		return false
	miner_worksite = OreField.near_surface(miner_rock, STOCKPILE)
	return true

func rock_visual_units(index: int) -> float:
	var progress := float(asteroid_mined[index])
	if work_action == "Extract ore sample" and manual_rock == index:
		progress += minf(3.0, float(rock_remaining(index))) * work_fraction()
	if phase == Phase.HAULING and not salvage_mode and to_field and miner_rock == index:
		if miner_position.distance_to(miner_worksite) <= 2.5:
			progress += float(mini(MINER_LOAD_SIZE, rock_remaining(index))) * clampf(
				miner_work_time / MINER_EXTRACTION_TIME, 0.0, 1.0
			)
	return clampf(progress / float(OreField.rock_capacity(index)), 0.0, 1.0)

func field_remaining_material() -> Dictionary:
	return {
		"Fe": OreField.FE_UNITS - field_fe_extracted,
		"Cu": OreField.CU_UNITS - field_cu_extracted,
		"Si": OreField.SI_UNITS - field_si_extracted
	}


func begin(designation: String) -> bool:
	var cleaned := designation.strip_edges()
	if phase != Phase.SAFE_MODE or cleaned.is_empty():
		return false
	name_text = cleaned
	set_phase(Phase.DIAGNOSTICS)
	return true

func set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0.0
	if phase >= Phase.SENSORS and chart.is_empty():
		chart_position()

func tick(delta: float, turn: float, thrust: float) -> void:
	phase_time += delta
	notice_time = maxf(0, notice_time - delta)
	match phase:
		Phase.DIAGNOSTICS:
			if phase_time >= 3.0:
				set_phase(Phase.SENSORS)
		Phase.SENSORS:
			if zoomed_in and zoomed_out:
				set_phase(Phase.FLIGHT)
		Phase.COMMS:
			if phase_time >= 2.4:
				set_phase(Phase.CONTACTS)
	if phase >= Phase.FLIGHT:
		fly(delta, turn, thrust)
		tick_work(delta)
	if phase == Phase.FLIGHT and turned and thrust_used:
		set_phase(Phase.WAYFINDING)
	if phase == Phase.HAULING:
		tick_miner(delta)
		if salvage_insight_unlocked:
			tick_salvage_workers(delta)
			tick_refinery_recovery(delta)

func fly(delta: float, turn: float, thrust: float) -> void:
	if turn != 0.0 or thrust != 0.0:
		has_destination = false
		pending_contact = ""
		pending_action = ""
		cancel_work()
		heading = wrapf(heading + turn * TURN_SPEED * delta, -PI, PI)
		turned = turned or turn != 0
		thrust_used = thrust_used or thrust != 0
	var desired_velocity := Vector2.from_angle(heading) * thrust * MAX_SPEED
	var acceleration := ACCELERATION if thrust != 0.0 else ACCELERATION * 0.85
	if has_destination:
		var offset := destination - player
		var distance := offset.length()
		if distance > 0.1:
			var desired_heading := offset.angle()
			heading = rotate_toward(heading, desired_heading, TURN_SPEED * delta)
			var alignment := maxf(0, cos(angle_difference(heading, desired_heading)))
			var desired_speed := minf(MAX_SPEED, sqrt(2 * ACCELERATION * 0.7 * maxf(0, distance - 12)))
			desired_velocity = Vector2.from_angle(heading) * desired_speed * alignment
		if distance <= 24 and velocity.length() <= 25:
			arrive()
			desired_velocity = Vector2.ZERO
	var before := player
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	player = (player + velocity * delta).clamp(WORLD.position + Vector2.ONE, WORLD.end - Vector2.ONE)
	if not player.is_equal_approx(before):
		chart_position()

func chart_position() -> void:
	var center := Vector2i((player / GRID).floor())
	var radius := ceili(SENSOR_RANGE / GRID)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(x, y)
			if (Vector2(tile) * GRID + Vector2.ONE * GRID * 0.5).distance_squared_to(player) <= SENSOR_RANGE * SENSOR_RANGE:
				chart[tile] = true

func is_charted(world_position: Vector2) -> bool:
	return chart.has(Vector2i((world_position / GRID).floor()))

func mark_zoom(previous: float, current: float) -> void:
	if phase != Phase.SENSORS:
		return
	zoomed_in = zoomed_in or current > previous
	zoomed_out = zoomed_out or current < previous

func plot_move(point: Vector2) -> void:
	if phase < Phase.WAYFINDING:
		return
	cancel_work()
	destination = point.clamp(WORLD.position + Vector2.ONE, WORLD.end - Vector2.ONE)
	has_destination = true
	pending_contact = ""
	pending_action = ""

func arrive() -> void:
	has_destination = false
	if phase == Phase.WAYFINDING:
		set_phase(Phase.COMMS)
	if phase >= Phase.CONTACTS and not pending_contact.is_empty():
		var contact := pending_contact
		var action := pending_action
		pending_contact = ""
		pending_action = ""
		if player.distance_to(action_position(contact, action)) <= INTERACT_RANGE:
			start_work(contact, action)

func position_of(contact: String) -> Vector2:
	match contact:
		"ore": return FIELD
		"miner": return miner_position
		"wreck": return WRECK
		"parts_a": return DRONE_A
		"parts_b": return DRONE_B
		"stockpile": return STOCKPILE
	var index := salvage_index(contact)
	if index >= 0:
		return salvage_workers[index]["position"]
	return Vector2.ZERO

func is_visible(contact: String) -> bool:
	if phase < Phase.CONTACTS:
		return false
	if contact in PRIMARY:
		return true
	if contact == "stockpile":
		return phase >= Phase.ORDERS
	if salvage_index(contact) >= 0:
		return salvage_insight_unlocked
	return phase >= Phase.FIELD_REPAIR and not salvaged.has(contact)

func command_for(contact: String) -> String:
	if not is_visible(contact):
		return ""
	if contact in PRIMARY and not scanned.has(contact):
		return "Approach and scan"
	match contact:
		"ore":
			if phase >= Phase.FIELD_REPAIR and controller_load() < HOLD and field_extracted < FIELD_RESERVE:
				return "Extract ore sample"
		"parts_a", "parts_b":
			return "Recover spare part" if controller_load() < HOLD else ""
		"miner":
			if phase == Phase.FIELD_REPAIR and ore >= ORE_REQUIRED and parts >= PARTS_REQUIRED:
				return "Repair mining drone"
		"stockpile":
			if ore > 0:
				return "Unload raw ore"
			if can_collect_repair_supplies():
				return "Collect repair supplies"
	var index := salvage_index(contact)
	if index >= 0 and salvage_insight_unlocked and not bool(salvage_workers[index]["active"]):
		if repair_kits > 0 and has_worker_capacity():
			return "Repair salvage drone"
	return ""

func issue(contact: String) -> void:
	var action := command_for(contact)
	if action.is_empty() or contact == work_contact or contact == pending_contact:
		return
	if contact == "ore" and action == "Extract ore sample":
		manual_ore_destination()
	if player.distance_to(action_position(contact, action)) <= INTERACT_RANGE and velocity.length() <= 25:
		has_destination = false
		pending_contact = ""
		pending_action = ""
		start_work(contact, action)
		return
	plot_move(action_position(contact, action))
	pending_contact = contact
	pending_action = action

func start_work(contact: String, action: String) -> void:
	work_contact = contact
	work_action = action
	work_time = 0.0

func cancel_work() -> void:
	work_contact = ""
	work_action = ""
	work_time = 0.0

func tick_work(delta: float) -> void:
	if work_action.is_empty():
		return
	if player.distance_to(action_position(work_contact, work_action)) > INTERACT_RANGE or command_for(work_contact) != work_action:
		cancel_work()
		return
	work_time += delta
	if work_time >= float(WORK_TIMES[work_action]):
		var contact := work_contact
		var action := work_action
		cancel_work()
		execute(contact, action)

func work_fraction() -> float:
	if work_action.is_empty():
		return 0.0
	return minf(work_time / float(WORK_TIMES[work_action]), 1.0)

func execute(contact: String, action: String) -> void:
	if command_for(contact) != action:
		return
	match action:
		"Approach and scan":
			scanned[contact] = true
			report(contact_name(contact) + " identified")
			if scanned.size() == PRIMARY.size():
				set_phase(Phase.FIELD_REPAIR)
				report("Insight recorded · Field Repair")
		"Extract ore sample":
			var amount := mini(3, HOLD - controller_load())
			if manual_rock < 0 or rock_remaining(manual_rock) <= 0:
				manual_rock = OreField.rock_for_manual_sample(player, asteroid_mined)
			if manual_rock < 0:
				return
			amount = mini(amount, rock_remaining(manual_rock))
			if amount <= 0:
				return
			ore += amount
			var raw := extract_rock(manual_rock, amount)
			cargo_fe += int(raw["Fe"])
			cargo_cu += int(raw["Cu"])
			cargo_si += int(raw["Si"])
			manual_rock = -1
			report("Raw sample recovered · %d units in HAL's hold" % ore)
		"Recover spare part":
			if controller_load() < HOLD:
				parts += 1
				salvaged[contact] = true
				report("Spare parts recovered · %d/%d" % [parts, PARTS_REQUIRED])
		"Repair mining drone":
			if not has_worker_capacity():
				report("Coordination capacity reached · %d drones" % DRONE_CAPACITY)
				return
			spent_fe += cargo_fe
			spent_cu += cargo_cu
			spent_si += cargo_si
			cargo_fe = 0
			cargo_cu = 0
			cargo_si = 0
			ore -= ORE_REQUIRED
			parts -= PARTS_REQUIRED
			active_drones += 1
			set_phase(Phase.HAULING)
			choose_mining_site()
			report("Field Repair complete · Miner 031 autonomously mining")
		"Unload raw ore":
			stock_ore += ore
			stock_fe += cargo_fe
			stock_cu += cargo_cu
			stock_si += cargo_si
			report("HAL unloaded %d raw units at the intake cache" % ore)
			ore = 0
			cargo_fe = 0
			cargo_cu = 0
			cargo_si = 0
		"Collect repair supplies":
			stock_ore -= 3
			stock_fe -= 2
			stock_cu -= 1
			repair_kits += 1
			report("Repair supplies secured · 2 Fe + 1 Cu")
		"Repair salvage drone":
			var index := salvage_index(contact)
			if index < 0 or repair_kits == 0 or not has_worker_capacity():
				return
			repair_kits -= 1
			spent_fe += 2
			spent_cu += 1
			active_drones += 1
			salvage_workers[index]["active"] = true
			report("%s restored · Autonomous hull salvage online" % contact_name(contact))

func contact_name(contact: String) -> String:
	match contact:
		"ore": return "Depleted Ore Field" if scanned.has(contact) else "Contact 01"
		"miner":
			if not scanned.has(contact):
				return "Contact 02"
			return "Miner 031" if phase >= Phase.ORDERS else "Damaged miner"
		"wreck": return "MCV Asterion" if scanned.has(contact) else "Contact 03"
		"parts_a": return "Wrecked drone A"
		"parts_b": return "Wrecked drone B"
		"stockpile": return "Asterion intake cache"
	var index := salvage_index(contact)
	if index >= 0:
		return "Salvager %03d" % [42 + index] if bool(salvage_workers[index]["active"]) else "Damaged salvager %03d" % [42 + index]
	return "No contact selected"

func tick_miner(delta: float) -> void:
	# The worker remains a link-dependent autonomous agent. If HAL flies off,
	# recover the signal before continuing the existing task.
	if miner_position.distance_to(player) > COMMS_RANGE * 0.98:
		miner_linked = false
		fly_miner_to(player, delta)
		return
	if not miner_linked:
		if miner_position.distance_to(player) > COMMS_RANGE * 0.80:
			fly_miner_to(player, delta)
			return
		miner_linked = true
	if to_field and not salvage_mode and not choose_mining_site():
		miner_velocity = miner_velocity.move_toward(Vector2.ZERO, MINER_ACCELERATION * delta)
		return
	var source := HULL_WORKSITE if salvage_mode else miner_worksite
	var target := source if to_field else STOCKPILE
	if target.distance_to(player) > COMMS_RANGE:
		miner_velocity = miner_velocity.move_toward(Vector2.ZERO, MINER_ACCELERATION * delta)
		miner_speed = miner_velocity.length()
		return
	if miner_position.distance_to(target) > 2.5:
		fly_miner_to(target, delta)
		return
	miner_position = target
	miner_velocity = Vector2.ZERO
	miner_speed = 0.0
	if to_field:
		var remaining := HULL_RESERVE - hull_extracted if salvage_mode else rock_remaining(miner_rock)
		if remaining <= 0:
			if not salvage_mode:
				miner_rock = -1
			return
		miner_work_time += delta
		var duration := HULL_CUT_TIME if salvage_mode else MINER_EXTRACTION_TIME
		if miner_work_time < duration:
			return
		miner_work_time = 0.0
		miner_cargo = mini(MINER_LOAD_SIZE, remaining)
		if salvage_mode:
			hull_extracted += miner_cargo
			miner_cargo_type = "hull"
			if hull_extracted >= 9 and not refinery_exposed:
				refinery_exposed = true
				report("Asterion subsystem exposed · Damaged refinery assembly")
		else:
			var minerals := extract_rock(miner_rock, miner_cargo)
			miner_fe = int(minerals["Fe"])
			miner_cu = int(minerals["Cu"])
			miner_si = int(minerals["Si"])
			miner_cargo_type = "ore"
	else:
		miner_work_time += delta
		if miner_work_time < MINER_UNLOAD_TIME:
			return
		miner_work_time = 0.0
		if miner_cargo_type == "hull":
			hull_stock += miner_cargo
			salvage_deliveries += 1
			if salvage_deliveries == 1:
				report("First hull feedstock delivered · Wreck excavation underway")
		else:
			stock_ore += miner_cargo
			stock_fe += miner_fe
			stock_cu += miner_cu
			stock_si += miner_si
			deliveries += 1
			if deliveries == 1:
				report("First automated delivery · %d ore at the wreck" % miner_cargo)
			elif deliveries >= 5 and not salvage_insight_ready:
				salvage_insight_ready = true
				report("Why is ore collecting here? · Asterion intake identified")
		miner_cargo = 0
		miner_fe = 0
		miner_cu = 0
		miner_si = 0
	to_field = not to_field
	miner_leg_number += 1
	miner_flight_clock = 0.0
	# Keep working an asteroid until exhausted; then find another surface.
	if to_field and not salvage_mode and miner_rock >= 0 and rock_remaining(miner_rock) == 0:
		miner_rock = -1

func fly_miner_to(target: Vector2, delta: float) -> void:
	var distance := miner_position.distance_to(target)
	if distance <= 2.5:
		miner_position = target
		miner_velocity = Vector2.ZERO
		miner_speed = 0.0
		return
	miner_flight_clock += delta
	miner_velocity = WorkerMotion.next_velocity(
		miner_position, miner_velocity, target, delta,
		miner_flight_clock, float(miner_leg_number) * 1.73 + 0.6,
		MINER_SPEED, MINER_ACCELERATION
	)
	miner_speed = miner_velocity.length()
	if miner_speed > 0.5:
		miner_heading = lerp_angle(miner_heading, miner_velocity.angle(), clampf(delta * 4.0, 0.0, 1.0))
	var step := miner_velocity * delta
	var next_position := target if step.length() >= distance else miner_position + step
	# Do not let even one simulated step carry the worker outside the bubble.
	if next_position.distance_to(player) > COMMS_RANGE:
		next_position = player + (next_position - player).normalized() * COMMS_RANGE
		miner_velocity = Vector2.ZERO
	miner_position = next_position

func miner_status() -> String:
	if phase < Phase.HAULING:
		return "Awaiting repair"
	if not miner_linked:
		return "Recovering controller link"
	var link := link_status()
	if link != "CONNECTED":
		return "Paused · " + link.to_lower()
	if to_field:
		if miner_rock < 0:
			return "Searching for accessible material"
		if miner_position.distance_to(miner_worksite) > 2.5:
			return "Approaching asteroid %02d surface" % (miner_rock + 1)
		return "Mining asteroid %02d · %d%%" % [
			miner_rock + 1, mini(99, floori(miner_work_time / MINER_EXTRACTION_TIME * 100.0))
		]
	if miner_position.distance_to(STOCKPILE) > 2.5:
		return "Returning with %d units" % miner_cargo
	return "Unloading cargo · %d%%" % mini(99, floori(miner_work_time / MINER_UNLOAD_TIME * 100.0))

func field_cut_fraction() -> float:
	return clampf(float(field_extracted) / float(FIELD_RESERVE), 0.0, 1.0)

func hull_cut_fraction() -> float:
	return clampf(float(hull_extracted) / float(REFINERY_EXPOSURE), 0.0, 1.0)

func hull_site_visual_units(site_index: int) -> float:
	var progress := float(hull_site_units[site_index])
	for worker in salvage_workers:
		if not bool(worker["active"]) or not bool(worker["to_hull"]):
			continue
		if int(worker["site_index"]) != site_index:
			continue
		if Vector2(worker["position"]).distance_to(SALVAGE_SITES[site_index]) > 2.5:
			continue
		var uncut := SALVAGE_SITE_QUOTA - hull_site_units[site_index]
		progress += float(mini(MINER_LOAD_SIZE, uncut)) * clampf(float(worker["time"]) / HULL_CUT_TIME, 0.0, 1.0)
	return clampf(progress / float(SALVAGE_SITE_QUOTA), 0.0, 1.0)

func choose_salvage_site(worker: Dictionary) -> bool:
	var current: int = worker["site_index"]
	if hull_site_units[current] < SALVAGE_SITE_QUOTA:
		return true
	var closest := -1
	var score := INF
	var position: Vector2 = worker["position"]
	for i in range(SALVAGE_SITES.size()):
		if hull_site_units[i] >= SALVAGE_SITE_QUOTA:
			continue
		var distance := position.distance_squared_to(SALVAGE_SITES[i])
		if distance < score:
			score = distance
			closest = i
	if closest < 0:
		return false
	worker["site_index"] = closest
	worker["time"] = 0.0
	return true

func tick_salvage_workers(delta: float) -> void:
	for i in range(salvage_workers.size()):
		if not bool(salvage_workers[i]["active"]) or i in refinery_crew:
			continue
		var worker: Dictionary = salvage_workers[i]
		var current: Vector2 = worker["position"]
		var to_hull: bool = worker["to_hull"]
		var cargo: int = worker["cargo"]
		if current.distance_to(player) > COMMS_RANGE * 0.98:
			worker["linked"] = false
			move_salvager(worker, player, delta, i)
			continue
		if not bool(worker["linked"]):
			if current.distance_to(player) > COMMS_RANGE * 0.8:
				move_salvager(worker, player, delta, i)
				continue
			worker["linked"] = true
		if to_hull and hull_extracted >= REFINERY_EXPOSURE:
			continue # Don't damage the newly uncovered refinery.
		if to_hull and not choose_salvage_site(worker):
			continue
		var site_index: int = worker["site_index"]
		var site: Vector2 = SALVAGE_SITES[site_index]
		var target := site if to_hull else STOCKPILE
		if target.distance_to(player) > COMMS_RANGE:
			worker["velocity"] = Vector2.ZERO
			continue
		if current.distance_to(target) > 2.5:
			move_salvager(worker, target, delta, i)
			continue
		worker["position"] = target
		worker["velocity"] = Vector2.ZERO
		worker["time"] = float(worker["time"]) + delta
		var duration := HULL_CUT_TIME if to_hull else MINER_UNLOAD_TIME
		if float(worker["time"]) < duration:
			continue
		worker["time"] = 0.0
		if to_hull:
			var removed := mini(MINER_LOAD_SIZE, mini(REFINERY_EXPOSURE - hull_extracted,
				SALVAGE_SITE_QUOTA - hull_site_units[site_index]))
			if removed <= 0:
				continue
			hull_extracted += removed
			hull_site_units[site_index] += removed
			worker["cargo"] = removed
			worker["to_hull"] = false
			if hull_extracted >= REFINERY_EXPOSURE and not refinery_exposed:
				refinery_exposed = true
				refinery_phase = RefineryPhase.EXPOSED
				report("Damaged refinery uncovered · Salvage paused to protect it")
		else:
			hull_stock += cargo
			salvage_deliveries += 1
			worker["cargo"] = 0
			worker["to_hull"] = true
			if salvage_deliveries == 1:
				report("Asterion hull feedstock delivered to intake cache")
		worker["leg"] = int(worker["leg"]) + 1
		worker["clock"] = 0.0

func begin_refinery_recovery() -> bool:
	if refinery_phase != RefineryPhase.EXPOSED:
		return false
	refinery_phase = RefineryPhase.DISCONNECTING
	report("Recovery queued · Salvagers will finish unloading and assemble at the bay")
	return true

func refinery_placement_error(point: Vector2) -> String:
	if not WORLD.grow(-REFINERY_CLEARANCE).has_point(point):
		return "Choose a site inside the sector"
	if point.y + REFINERY_CLEARANCE > HULL_BOUNDS.position.y:
		return "Choose open space above the hull"
	if not is_charted(point):
		return "Survey the site with HAL first"
	if point.distance_to(REFINERY_STAGING) < REFINERY_CLEARANCE:
		return "Clear the recovery staging area"
	if not refinery_in_range(REFINERY_STAGING) or not refinery_in_range(point):
		return "Keep the staging area and site within HAL’s link"
	# Check the swept footprint of the straight tow, including clearance at the destination.
	var cache_clearance := REFINERY_CLEARANCE + 35.0
	var near_cache := Geometry2D.get_closest_point_to_segment(STOCKPILE, REFINERY_STAGING, point)
	if near_cache.distance_to(STOCKPILE) < cache_clearance:
		return "Keep the tow clear of the intake cache"
	for i in range(OreField.ROCK_COUNT):
		if rock_remaining(i) == 0:
			continue
		var center := OreField.rock_center(i)
		var nearest := Geometry2D.get_closest_point_to_segment(center, REFINERY_STAGING, point)
		if nearest.distance_to(center) < REFINERY_CLEARANCE + OreField.rock_radius(i):
			return "Keep the tow clear of the asteroid field"
	return ""

func place_refinery(point: Vector2) -> bool:
	if refinery_phase != RefineryPhase.STAGED:
		return false
	var error := refinery_placement_error(point)
	if not error.is_empty():
		report(error)
		return false
	refinery_destination = point
	refinery_phase = RefineryPhase.HAULING
	report("Site confirmed · Salvagers towing the refinery")
	return true

func refinery_in_range(point: Vector2) -> bool:
	return point.distance_to(player) <= COMMS_RANGE - REFINERY_CLEARANCE

func tick_refinery_recovery(delta: float) -> void:
	match refinery_phase:
		RefineryPhase.DISCONNECTING:
			tick_refinery_disconnect(delta)
		RefineryPhase.EXTRACTING, RefineryPhase.HAULING:
			tick_refinery_tow(delta)
		RefineryPhase.ANCHORING:
			refinery_link_paused = not refinery_in_range(refinery_position)
			if refinery_link_paused:
				return
			refinery_work_time += delta
			if refinery_work_time >= REFINERY_ANCHOR_TIME:
				refinery_phase = RefineryPhase.PLACED
				refinery_crew.clear()
				report("Refinery anchored · Damaged and offline")

func tick_refinery_disconnect(delta: float) -> void:
	refinery_link_paused = not refinery_in_range(REFINERY_BAY)
	if refinery_link_paused:
		return
	# Finish all outstanding bulk deliveries before committing the recovery crew.
	if refinery_crew.is_empty():
		for worker in salvage_workers:
			if int(worker["cargo"]) > 0:
				return
		for i in range(salvage_workers.size()):
			if bool(salvage_workers[i]["active"]):
				refinery_crew.append(i)
		if refinery_crew.is_empty():
			return
	var ready := true
	for index in refinery_crew:
		var worker := salvage_workers[index]
		var berth: Vector2 = REFINERY_BAY + REFINERY_CREW_OFFSETS[index]
		var position: Vector2 = worker["position"]
		if position.distance_to(berth) > 2.5:
			var target: Vector2 = player if position.distance_to(player) > COMMS_RANGE else berth
			move_salvager(worker, target, delta, index)
			ready = false
		else:
			worker["position"] = berth
			worker["velocity"] = Vector2.ZERO
	if not ready:
		return
	refinery_work_time += delta
	if refinery_work_time >= REFINERY_DISCONNECT_TIME:
		refinery_phase = RefineryPhase.EXTRACTING
		refinery_work_time = 0.0
		report("Restraints released · Towing the assembly out of the hull")

func tick_refinery_tow(delta: float) -> void:
	refinery_link_paused = not refinery_in_range(refinery_position) or not refinery_in_range(refinery_destination)
	if refinery_link_paused:
		return
	var previous := refinery_position
	refinery_position = refinery_position.move_toward(refinery_destination, REFINERY_TOW_SPEED * delta)
	for index in refinery_crew:
		var worker := salvage_workers[index]
		worker["position"] = refinery_position + REFINERY_CREW_OFFSETS[index]
		worker["heading"] = (refinery_position - previous).angle()
		worker["velocity"] = Vector2.ZERO
	if refinery_position != refinery_destination:
		return
	if refinery_phase == RefineryPhase.EXTRACTING:
		refinery_phase = RefineryPhase.STAGED
		report("Refinery clear of the hull · Choose an installation site")
	else:
		refinery_phase = RefineryPhase.ANCHORING
		report("Refinery on site · Anchoring assembly")

func move_salvager(worker: Dictionary, target: Vector2, delta: float, index: int) -> void:
	var position: Vector2 = worker["position"]
	var distance := position.distance_to(target)
	if distance <= 2.5:
		worker["position"] = target
		worker["velocity"] = Vector2.ZERO
		return
	worker["clock"] = float(worker["clock"]) + delta
	var movement: Vector2 = WorkerMotion.next_velocity(
		position, worker["velocity"], target, delta,
		float(worker["clock"]), float(index) * 3.71 + float(worker["leg"]) * 1.17,
		MINER_SPEED, MINER_ACCELERATION
	)
	worker["velocity"] = movement
	if movement.length() > 0.5:
		worker["heading"] = lerp_angle(float(worker["heading"]), movement.angle(), clampf(delta * 4.0, 0.0, 1.0))
	var step := movement * delta
	var next_position := target if step.length() >= distance else position + step
	if next_position.distance_to(player) > COMMS_RANGE:
		next_position = player + (next_position - player).normalized() * COMMS_RANGE
		worker["velocity"] = Vector2.ZERO
	worker["position"] = next_position

func report(message: String) -> void:
	notice = message
	notice_time = 6.0
