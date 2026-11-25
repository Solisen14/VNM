extends SceneTree

# Full deterministic mechanics test: Godot --headless --path . --script res://tests/pass2_smoke.gd
const State = preload("res://reboot_state.gd")
const OreField = preload("res://ore_field.gd")

func _initialize() -> void:
	var state := State.new()
	var total_capacity := 0
	for i in range(OreField.ROCK_COUNT):
		total_capacity += OreField.rock_capacity(i)
		var surface := OreField.near_surface(i, State.STOCKPILE)
		var center := OreField.rock_center(i)
		assert(surface.distance_to(center) > OreField.rock_radius(i), "Worker assigned inside an asteroid")
		assert((surface - center).dot(State.STOCKPILE - center) > 0.0, "Worksite not stockpile-facing")
	assert(total_capacity == 137, "Asteroid sizes do not sum to 137")
	assert(OreField.FE_UNITS == 89 and OreField.CU_UNITS == 34 and OreField.SI_UNITS == 14, "Field mineral design changed")
	for i in range(OreField.ROCK_COUNT):
		var result: Dictionary = state.extract_rock(i, OreField.rock_capacity(i))
		assert(int(result["Fe"]) + int(result["Cu"]) + int(result["Si"]) == OreField.rock_capacity(i))
	assert(state.field_extracted == 137, "Field accounting drift")
	assert(state.field_fe_extracted == 89 and state.field_cu_extracted == 34 and state.field_si_extracted == 14,
		"Extraction failed to conserve the specified composition")
	assert(state.field_remaining_material() == {"Fe": 0, "Cu": 0, "Si": 0}, "Depleted field contains phantom material")
	assert(OreField.nearest_viable_rock(State.STOCKPILE, Vector2.ZERO, State.COMMS_RANGE,
		state.asteroid_mined, 0) == -1, "A depleted field is still selectable")

	var game := State.new()
	assert(game.begin("HAL"), "Safe mode lost")
	game.set_phase(State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		game.execute(contact, "Approach and scan")
	game.execute("ore", "Extract ore sample")
	game.execute("parts_a", "Recover spare part")
	game.execute("parts_b", "Recover spare part")
	game.execute("miner", "Repair mining drone")
	assert(game.phase == State.Phase.HAULING and game.active_drones == 1, "Autonomy not initialized")
	assert(game.has_worker_capacity(), "Controller should have nine free slots")
	game.active_drones = 10
	assert(not game.has_worker_capacity(), "Initial 10 worker limit was bypassed")
	game.active_drones = 1

	var chart_before := game.chart.size()
	var start_position := game.miner_position
	game.player = Vector2(-1850, -1200)
	game.tick_miner(0.1)
	assert(game.field_extracted == 3 and game.miner_cargo == 0, "Out-of-range miner began mining")
	assert(game.miner_position.distance_to(game.player) < start_position.distance_to(game.player),
		"Disconnected miner did not try to return to HAL")
	assert(game.chart.size() == chart_before, "Worker disclosed new map cells")
	game.player = Vector2(530, 100)
	game.miner_position = game.miner_worksite
	game.miner_linked = true
	var seen_rocks: Dictionary = {}
	for i in range(5):
		if game.miner_rock < 0:
			assert(game.choose_mining_site(), "Worker did not choose next live rock")
		seen_rocks[game.miner_rock] = true
		game.miner_position = game.miner_worksite
		game.tick_miner(State.MINER_EXTRACTION_TIME + 0.01)
		assert(game.miner_cargo > 0 and game.miner_cargo <= 3, "Extraction cargo size invalid")
		game.miner_position = State.STOCKPILE
		game.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
		assert(game.miner_cargo == 0, "Unload failed")
	assert(game.deliveries == 5 and game.salvage_insight_ready, "Five-delivery threshold missed")
	assert(not game.salvage_insight_unlocked, "Salvage should need a second Insight confirmation")
	assert(not game.salvage_mode and game.command_for("wreck").is_empty(), "Salvage activated early")
	assert(game.stock_ore == game.stock_fe + game.stock_cu + game.stock_si, "Stockpile mineral conservation failed")
	assert(game.field_extracted == game.stock_ore + 3, "Field material was lost or duplicated")
	assert(game.field_extracted == game.field_fe_extracted + game.field_cu_extracted + game.field_si_extracted,
		"Extracted elemental matter does not match removed rock units")
	assert(seen_rocks.size() >= 2, "Worker never changed a depleted worksite")
	assert(game.chart.size() == chart_before, "Autonomous mining expanded explored terrain")
	# Full flight integration: zero teleportation or fake arrival events.
	var flight := State.new()
	flight.begin("HAL")
	flight.set_phase(State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		flight.execute(contact, "Approach and scan")
	flight.execute("ore", "Extract ore sample")
	flight.execute("parts_a", "Recover spare part")
	flight.execute("parts_b", "Recover spare part")
	flight.execute("miner", "Repair mining drone")
	var initial_rock := flight.miner_rock
	var total_elapsed := 0.0
	for frame in range(27000):
		flight.tick_miner(1.0 / 30.0)
		total_elapsed += 1.0 / 30.0
		if flight.deliveries >= 5:
			break
	assert(flight.deliveries >= 5, "Autonomous miner cannot complete five actual flight cycles")
	assert(flight.salvage_insight_ready, "Five actual flights did not mark Salvage milestone")
	assert(flight.stock_ore == flight.stock_fe + flight.stock_cu + flight.stock_si,
		"Real flight material delivery did not conserve the mineral mixture")
	assert(flight.miner_rock != initial_rock or flight.rock_remaining(initial_rock) > 0,
		"Worker stalled at a depleted asteroid")
	assert(total_elapsed > 5.0 * (State.MINER_EXTRACTION_TIME + State.MINER_UNLOAD_TIME),
		"Mining timings unexpectedly accelerated")

	print("PASS: VNM Pass 2 autonomy, physical asteroid sites, 89/34/14 chemistry, range and cap")
	quit(0)
