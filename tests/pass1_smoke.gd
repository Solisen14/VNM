extends SceneTree

# Run with: godot --headless --path . --script res://tests/pass1_smoke.gd
# The original reboot and repair are retained; worker assignment is now automatic.
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
	assert(state.phase == State.Phase.HAULING, "Repaired miner did not start automatically")
	assert(state.active_drones == 1 and state.ore == 0 and state.parts == 0, "Repair failed")
	assert(state.miner_rock >= 0, "Autonomous worksite not selected")
	assert(state.miner_worksite.distance_to(State.FIELD) > 1, "Worker still flies to the field centre")
	var chart_before := state.chart.size()
	var initial_mined := state.field_extracted
	var load := mini(State.MINER_LOAD_SIZE, state.rock_remaining(state.miner_rock))
	state.miner_position = state.miner_worksite
	state.tick_miner(State.MINER_EXTRACTION_TIME + 0.01)
	assert(state.miner_cargo == load and state.field_extracted == initial_mined + load, "Mining accounting failed")
	state.miner_position = State.STOCKPILE
	state.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
	assert(state.stock_ore == load and state.deliveries == 1, "First automatic delivery failed")
	assert(state.stock_fe + state.stock_cu + state.stock_si == state.stock_ore, "Material mix wasn't hauled")
	assert(state.chart.size() == chart_before, "Worker revealed unexplored terrain")
	assert(state.command_for("wreck").is_empty(), "Salvage unlocked before its Insight")
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
	print("PASS: VNM Pass 1 reboot + first autonomous delivery")
	quit(0)
