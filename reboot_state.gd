extends RefCounted

enum Phase { SAFE_MODE, DIAGNOSTICS, SENSORS, FLIGHT, WAYFINDING, COMMS, CONTACTS, FIELD_REPAIR, ORDERS, HAULING }
const ORE_REQUIRED := 3
const PARTS_REQUIRED := 2
const HOLD := 5
const GRID := 32
const SENSOR_RANGE := 245.0
const INTERACT_RANGE := 82.0
const TURN_SPEED := 1.42
const ACCELERATION := 75.0
const MAX_SPEED := 145.0
const MINER_SPEED := 160.0
const MINER_ACCELERATION := 95.0
const MINER_EXTRACTION_TIME := 8.0
const MINER_UNLOAD_TIME := 5.0
const WORK_TIMES := {
	"Approach and scan": 3.5,
	"Extract ore sample": 6.0,
	"Recover spare part": 4.5,
	"Repair mining drone": 7.0,
}
const WORK_LABELS := {
	"Approach and scan": "Scanning contact",
	"Extract ore sample": "Extracting ore",
	"Recover spare part": "Recovering spare part",
	"Repair mining drone": "Repairing miner",
}
const WORLD := Rect2(-2200, -1550, 4700, 3450)
const FIELD := Vector2(530, -215)
const MINER := Vector2(405, 395)
const WRECK := Vector2(1180, 240)
const DRONE_A := Vector2(730, 525)
const DRONE_B := Vector2(1060, 600)
const STOCKPILE := Vector2(1060, 398)
const CONTACTS := ["ore", "miner", "wreck", "parts_a", "parts_b", "stockpile"]
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
var notice := ""
var notice_time := 0.0

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
		if player.distance_to(position_of(contact)) <= INTERACT_RANGE:
			start_work(contact, action)

func position_of(contact: String) -> Vector2:
	match contact:
		"ore": return FIELD
		"miner": return miner_position
		"wreck": return WRECK
		"parts_a": return DRONE_A
		"parts_b": return DRONE_B
		"stockpile": return STOCKPILE
	return Vector2.ZERO

func is_visible(contact: String) -> bool:
	if phase < Phase.CONTACTS:
		return false
	if contact in PRIMARY:
		return true
	if contact == "stockpile":
		return phase >= Phase.ORDERS
	return phase >= Phase.FIELD_REPAIR and not salvaged.has(contact)

func command_for(contact: String) -> String:
	if not is_visible(contact):
		return ""
	if contact in PRIMARY and not scanned.has(contact):
		return "Approach and scan"
	match contact:
		"ore":
			if phase == Phase.FIELD_REPAIR and ore < ORE_REQUIRED:
				return "Extract ore sample"
			if phase == Phase.ORDERS:
				return "Assign miner to this field"
		"parts_a", "parts_b": return "Recover spare part"
		"miner":
			if phase == Phase.FIELD_REPAIR and ore >= ORE_REQUIRED and parts >= PARTS_REQUIRED:
				return "Repair mining drone"
	return ""

func issue(contact: String) -> void:
	var action := command_for(contact)
	if action.is_empty() or contact == work_contact or contact == pending_contact:
		return
	if action == "Assign miner to this field":
		execute(contact, action)
		return
	if player.distance_to(position_of(contact)) <= INTERACT_RANGE and velocity.length() <= 25:
		has_destination = false
		pending_contact = ""
		pending_action = ""
		start_work(contact, action)
		return
	plot_move(position_of(contact))
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
	if player.distance_to(position_of(work_contact)) > INTERACT_RANGE or command_for(work_contact) != work_action:
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
			var amount := mini(ORE_REQUIRED - ore, mini(drill_loads, HOLD - ore - parts))
			drill_loads -= amount
			ore += amount
			report("Ore collected · %d/%d" % [ore, ORE_REQUIRED])
		"Recover spare part":
			if ore + parts < HOLD:
				parts += 1
				salvaged[contact] = true
				report("Spare parts recovered · %d/%d" % [parts, PARTS_REQUIRED])
		"Repair mining drone":
			ore -= ORE_REQUIRED
			parts -= PARTS_REQUIRED
			set_phase(Phase.ORDERS)
			report("Field Repair complete · Miner 031 online")
		"Assign miner to this field":
			set_phase(Phase.HAULING)
			report("Miner 031 assigned · Ore field → Wreck stockpile")

func contact_name(contact: String) -> String:
	match contact:
		"ore": return "Ore field" if scanned.has(contact) else "Contact 01"
		"miner":
			if not scanned.has(contact):
				return "Contact 02"
			return "Miner 031" if phase >= Phase.ORDERS else "Damaged miner"
		"wreck": return "MCV Asterion" if scanned.has(contact) else "Contact 03"
		"parts_a": return "Wrecked drone A"
		"parts_b": return "Wrecked drone B"
		"stockpile": return "Wreck stockpile"
	return "No contact selected"

func tick_miner(delta: float) -> void:
	var target := FIELD if to_field else STOCKPILE
	var distance := miner_position.distance_to(target)
	if distance > 0.0:
		var target_speed := minf(MINER_SPEED, sqrt(2 * MINER_ACCELERATION * distance))
		miner_speed = move_toward(miner_speed, target_speed, MINER_ACCELERATION * delta)
		miner_heading = miner_position.angle_to_point(target)
		miner_position = miner_position.move_toward(target, miner_speed * delta)
		return
	miner_speed = 0.0
	miner_work_time += delta
	var duration := MINER_EXTRACTION_TIME if to_field else MINER_UNLOAD_TIME
	if miner_work_time < duration:
		return
	miner_work_time = 0.0
	if to_field:
		miner_cargo = 3
	else:
		stock_ore += miner_cargo
		miner_cargo = 0
		deliveries += 1
		if deliveries == 1:
			report("First automated delivery · 3 ore at the wreck")
	to_field = not to_field

func miner_status() -> String:
	var target := FIELD if to_field else STOCKPILE
	if miner_position != target:
		return "Flying to ore field" if to_field else "Hauling ore to the wreck"
	var duration := MINER_EXTRACTION_TIME if to_field else MINER_UNLOAD_TIME
	var action := "Mining ore" if to_field else "Unloading ore"
	return "%s   %d%%" % [action, mini(99, floori(miner_work_time / duration * 100.0))]

func report(message: String) -> void:
	notice = message
	notice_time = 6.0
