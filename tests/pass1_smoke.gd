extends SceneTree

# Run with: godot --headless --path . --script res://tests/pass1_smoke.gd
# Checks the opening gameplay invariants without needing rendered gameplay input.
const State = preload("res://reboot_state.gd")
const Motion = preload("res://worker_motion.gd")

func _initialize() -> void:
	var state := State.new()
	assert(state.phase == State.Phase.SAFE_MODE, "Safe-mode opening changed")
	assert(state.begin("HAL"), "Designation no longer works")
	state.set_phase(State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		state.execute(contact, "Approach and scan")
	assert(state.phase == State.Phase.FIELD_REPAIR, "First Insight not unlocked")
	state.execute("ore", "Extract ore sample")
	state.execute("parts_a", "Recover spare part")
	state.execute("parts_b", "Recover spare part")
	assert(state.ore == State.ORE_REQUIRED and state.parts == State.PARTS_REQUIRED, "Repair resources changed")
	state.execute("miner", "Repair mining drone")
	assert(state.phase == State.Phase.ORDERS and state.ore == 0 and state.parts == 0, "Repair failed")
	state.execute("ore", "Assign miner to this field")
	assert(state.phase == State.Phase.HAULING, "First worker order failed")
	var chart_before := state.chart.size()
	state.miner_position = State.FIELD
	state.tick_miner(State.MINER_EXTRACTION_TIME + 0.01)
	assert(state.miner_cargo == 3 and state.field_extracted == 6, "Mining material accounting failed")
	state.miner_position = State.STOCKPILE
	state.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
	assert(state.stock_ore == 3 and state.deliveries == 1, "First delivery failed")
	assert(state.chart.size() == chart_before, "Worker revealed unexplored terrain")
	state.execute("wreck", "Assign miner to strip hull")
	assert(state.salvage_mode, "Hull salvage order failed")
	for i in range(3):
		state.miner_position = State.HULL_WORKSITE
		state.tick_miner(State.HULL_CUT_TIME + 0.01)
		state.miner_position = State.STOCKPILE
		state.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
	assert(state.hull_extracted == 9 and state.hull_stock == 9, "Hull material accounting failed")
	assert(state.refinery_exposed, "Refinery reveal milestone not reached")
	assert(state.chart.size() == chart_before, "Hull workers charted the map")
	var position := Vector2(405, 395)
	var velocity := Vector2.ZERO
	var target := Vector2(530, -215)
	var arrived := false
	for i in range(1800):
		velocity = Motion.next_velocity(position, velocity, target, 1.0 / 60.0,
			float(i) / 60.0, 0.6, State.MINER_SPEED, State.MINER_ACCELERATION)
		position += velocity / 60.0
		if position.distance_to(target) < 2.5:
			arrived = true
			break
	assert(arrived, "Curved worker navigation failed to arrive")
	assert(is_equal_approx(State.ASTERION_LENGTH_METRES / State.CONTROLLER_LENGTH_METRES, 200.0), "Ship scale changed")
	print("PASS: VNM Pass 1 smoke tests")
	quit(0)
