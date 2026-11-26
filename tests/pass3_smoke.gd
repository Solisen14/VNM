extends SceneTree

# Godot --headless --path . --script res://tests/pass3_smoke.gd
const State = preload("res://reboot_state.gd")
const OreField = preload("res://ore_field.gd")

func _initialize() -> void:
	var game := State.new()
	assert(game.begin("HAL"))
	game.set_phase(State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		game.execute(contact, "Approach and scan")
	assert(game.contact_name("ore") == "Depleted Ore Field")
	game.execute("ore", "Extract ore sample")
	game.execute("parts_a", "Recover spare part")
	game.execute("parts_b", "Recover spare part")
	game.execute("miner", "Repair mining drone")
	assert(game.phase == State.Phase.HAULING and game.active_drones == 1)
	assert(game.command_for("ore") == "Extract ore sample", "HAL should be allowed to mine after worker repair")
	assert(game.command_for("wreck").is_empty(), "Salvage available prematurely")
	assert(State.STOCKPILE.y < 45.0 and State.STOCKPILE.distance_to(State.REFINERY_INTAKE) < 150.0,
		"Provisional stockpile should be off the upper Asterion hull at its intake")

	# HAL can personally extract raw matter and carry it to the intake.
	var extracted_before := game.field_extracted
	game.execute("ore", "Extract ore sample")
	assert(game.ore > 0 and game.field_extracted > extracted_before, "Manual extraction after Field Repair failed")
	assert(game.ore == game.cargo_fe + game.cargo_cu + game.cargo_si, "HAL raw cargo chemistry out of balance")
	var loaded := game.ore
	game.execute("stockpile", "Unload raw ore")
	assert(game.ore == 0 and game.stock_ore == loaded, "HAL failed to unload into stockpile")
	assert(game.stock_ore == game.stock_fe + game.stock_cu + game.stock_si, "Manual ore deposit lost elements")

	# First automatic worker fills the intake cache five times, triggering a
	# SECOND Insight rather than automatically exposing ship internals.
	game.player = Vector2(850, 130)
	for trip in range(5):
		if game.miner_rock < 0:
			assert(game.choose_mining_site())
		game.miner_position = game.miner_worksite
		game.tick_miner(State.MINER_EXTRACTION_TIME + 0.01)
		assert(game.miner_cargo > 0, "Miner stopped extracting")
		game.miner_position = State.STOCKPILE
		game.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
	assert(game.deliveries == 5 and game.salvage_insight_ready, "Salvage Insight threshold failed")
	assert(not game.salvage_insight_unlocked, "Salvage auto-unlocked without player acknowledging it")
	for contact in State.SALVAGE_CONTACTS:
		assert(not game.is_visible(contact), "Future salvagers pinged before Salvage insight")
	game.unlock_salvage()
	assert(game.salvage_insight_unlocked, "Salvage Insight didn't unlock")
	for contact in State.SALVAGE_CONTACTS:
		assert(game.is_visible(contact), "New repairable salvager missing")

	# The player collects finite supplies at the intake and takes them to each
	# broken salvager. 2 Fe and 1 Cu are consumed per restored worker.
	var fe_before := game.stock_fe
	var cu_before := game.stock_cu
	var total_stock_before := game.stock_ore
	for i in range(3):
		assert(game.can_collect_repair_supplies(), "Not enough repair supplies for salvager %d" % i)
		game.execute("stockpile", "Collect repair supplies")
		assert(game.repair_kits == 1, "HAL did not load one repair supply package")
		var contact: String = State.SALVAGE_CONTACTS[i]
		assert(game.command_for(contact) == "Repair salvage drone", "Repair command unavailable")
		game.execute(contact, "Repair salvage drone")
		assert(game.salvage_worker_active(contact), "Salvager did not boot")
		assert(game.repair_kits == 0, "Repair supplies were not consumed")
	assert(game.active_drones == 4 and game.has_worker_capacity(), "Restored workers exceeded coordination slots")
	assert(game.stock_fe == fe_before - 6 and game.stock_cu == cu_before - 3, "Restoring workers conjured materials")
	assert(game.stock_ore == total_stock_before - 9, "Intake raw stock wasn't debited for repairs")

	# Simulate whole flights using steering and actual 12-second cutting,
	# without teleporting any of the three salvagers to destinations.
	var charted_before := game.chart.size()
	for frame in range(21000):
		game.tick_salvage_workers(1.0 / 30.0)
		if game.refinery_exposed and game.hull_stock == game.hull_extracted:
			break
	assert(game.refinery_exposed, "12 units of hull salvage failed to expose refinery")
	assert(game.hull_extracted == State.REFINERY_EXPOSURE, "Cutting overshot the protected refinery")
	for site in range(State.SALVAGE_SITES.size()):
		assert(game.hull_site_units[site] == State.SALVAGE_SITE_QUOTA,
			"Salvager cuts did not physically expose each hull zone")
	assert(game.hull_stock == game.hull_extracted, "Hull feedstock vanished while hauling")
	assert(game.salvage_deliveries >= 4, "Salvage workers were not transporting cargo")
	assert(game.chart.size() == charted_before, "Salvagers are not supposed to chart space")
	for frame in range(1000):
		game.tick_salvage_workers(1.0 / 30.0)
	assert(game.hull_extracted == State.REFINERY_EXPOSURE, "Salvagers damaged exposed machinery")
	assert(game.active_drones == 4 and game.active_drones < State.DRONE_CAPACITY,
		"Initial 10-drone limit changed")
	verify_refinery_recovery(game)
	print("PASS: VNM mining, salvage, intact refinery extraction, tow and placement")
	quit(0)

func verify_refinery_recovery(game: State) -> void:
	assert(game.refinery_phase == State.RefineryPhase.EXPOSED)
	assert(not game.place_refinery(State.REFINERY_STAGING), "Placement skipped disconnection")
	assert(game.begin_refinery_recovery())
	assert(not game.begin_refinery_recovery(), "Recovery queued twice")
	var hull_stock := game.hull_stock
	var charted_before := game.chart.size()
	for frame in range(3000):
		game.tick(1.0 / 30.0, 0.0, 0.0)
		if game.refinery_phase == State.RefineryPhase.EXTRACTING:
			break
	assert(game.refinery_phase == State.RefineryPhase.EXTRACTING, "Crew never reached and disconnected the refinery")
	assert(game.refinery_position == State.REFINERY_BAY and game.refinery_crew.size() == 3)
	game.tick(1.0, 0.0, 0.0)
	assert(game.refinery_position.distance_to(State.REFINERY_BAY) > 0.0
		and game.refinery_position != State.REFINERY_STAGING, "Refinery extraction skipped visible travel")
	for frame in range(1000):
		game.tick(1.0 / 30.0, 0.0, 0.0)
		if game.refinery_phase == State.RefineryPhase.STAGED:
			break
	assert(game.refinery_phase == State.RefineryPhase.STAGED)
	assert(game.refinery_position == State.REFINERY_STAGING and game.chart.size() == charted_before)
	assert(not game.place_refinery(State.REFINERY_BAY), "Accepted a site in the hull")
	var site := State.REFINERY_STAGING + Vector2(230, -135)
	assert(not game.place_refinery(site), "Accepted an unsurveyed site")
	game.player = site + Vector2(50, 15)
	game.chart_position()
	assert(game.place_refinery(site), game.refinery_placement_error(site))
	var position := game.refinery_position
	game.player = State.WORLD.position + Vector2.ONE
	game.tick(1.0, 0.0, 0.0)
	assert(game.refinery_link_paused and game.refinery_position == position, "Tow kept moving outside the link")
	game.player = site + Vector2(50, 15)
	game.tick(1.0, 0.0, 0.0)
	assert(not game.refinery_link_paused and game.refinery_position != position and game.refinery_position != site)
	for frame in range(1000):
		game.tick(1.0 / 30.0, 0.0, 0.0)
		if game.refinery_phase == State.RefineryPhase.ANCHORING:
			break
	assert(game.refinery_phase == State.RefineryPhase.ANCHORING and game.refinery_position == site)
	game.tick(State.REFINERY_ANCHOR_TIME * 0.5, 0.0, 0.0)
	assert(game.refinery_phase == State.RefineryPhase.ANCHORING, "Anchoring completed early")
	game.tick(State.REFINERY_ANCHOR_TIME * 0.5, 0.0, 0.0)
	assert(game.refinery_phase == State.RefineryPhase.PLACED and game.refinery_crew.is_empty())
	assert(game.hull_stock == hull_stock and game.hull_extracted == hull_stock, "Recovery changed bulk feedstock")
	assert(not game.place_refinery(site + Vector2(200, 0)), "Placed refinery can be placed again")
