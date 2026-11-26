extends SceneTree

# Godot --headless --path . --script res://tests/pass3_smoke.gd
const State = preload("res://reboot_state.gd")
const Industry = State.Industry

func _initialize() -> void:
	var game := State.new()
	assert(game.begin("HAL"))
	wait_until(game, func() -> bool: return game.phase == State.Phase.SENSORS)
	game.mark_zoom(1.0, 0.8)
	game.mark_zoom(0.8, 1.0)
	game.tick(0.1, 1.0, 1.0)
	assert(game.phase == State.Phase.WAYFINDING)
	game.plot_move(Vector2(120, 80))
	wait_until(game, func() -> bool: return game.phase == State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		use_contact(game, contact, "Approach and scan")
	assert(game.contact_name("ore") == "Depleted Ore Field")
	use_contact(game, "ore", "Extract ore sample")
	assert(game.command_for("ore").is_empty(), "Early repeat mining could still crowd out repair parts")
	use_contact(game, "parts_a", "Recover spare part")
	use_contact(game, "parts_b", "Recover spare part")
	use_contact(game, "miner", "Repair mining drone")
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
	assert(game.ore == 0 and game.stock_ore == loaded and game.ore_collected == loaded, "HAL delivery did not count")
	assert(not game.salvage_insight_ready)
	assert(game.stock_ore == game.stock_fe + game.stock_cu + game.stock_si, "Manual ore deposit lost elements")

	# Both HAL and worker deposits satisfy the same ten-unit threshold.
	game.player = Vector2(850, 130)
	for trip in range(5):
		if game.miner_rock < 0:
			assert(game.choose_mining_site())
		game.miner_position = game.miner_worksite
		game.tick_miner(State.MINER_EXTRACTION_TIME + 0.01)
		assert(game.miner_cargo > 0, "Miner stopped extracting")
		game.miner_position = State.STOCKPILE
		game.tick_miner(State.MINER_UNLOAD_TIME + 0.01)
		assert(game.salvage_insight_ready == (game.ore_collected >= State.ORE_COLLECTION_GOAL))
	assert(game.deliveries == 5 and game.salvage_insight_ready, "Salvage Insight threshold failed")
	assert(game.ore_collected == game.stock_ore, "Worker deliveries did not count")
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
		assert(game.command_for(contact) == "Repair worker", "Repair command unavailable")
		game.execute(contact, "Repair worker")
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
	verify_commissioning(game)
	print("PASS: VNM mining through refinery placement, power and Controller 2 commissioning")
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
	assert(game.refinery_position == State.REFINERY_BAY and not game.refinery_crew.is_empty())
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

func verify_commissioning(game: State) -> void:
	var industry := game.industry
	assert(industry.stage == Industry.Stage.REPAIR and industry.refinery.status() == "DAMAGED / OFFLINE")
	assert(game.command_for("refinery").is_empty(), "An empty refinery could be repaired")
	assert(game.command_for("reactor_bay").is_empty(), "Reactor salvage opened before the refinery was repaired")
	game.issue("repair_cache")
	assert(game.has_destination, "Service locker did not plot a physical approach")
	wait_until(game, func() -> bool: return industry.service_cargo > 0 or industry.service_delivered == 3)
	if industry.service_cargo > 0:
		use_contact(game, "refinery", "Deliver service components")
	wait_until(game, func() -> bool: return industry.service_delivered == 3)
	use_contact(game, "refinery", "Repair refinery")
	assert(industry.service_spent["refinery"] == 3 and industry.service_delivered == 0)
	assert(industry.refinery.status() == "RESTORED / UNPOWERED" and not industry.refinery.can_operate())
	assert(game.command_for("wreck").is_empty(), "Recovery reopened the old hull sector")
	wait_until(game, func() -> bool: return industry.stage == Industry.Stage.REACTOR_SITE)
	assert(industry.reactor_position == Industry.REACTOR_STAGING and industry.reactor_hull_stock == Industry.CUT_REQUIRED)
	assert(not industry.place_reactor(game, industry.refinery.position).is_empty(), "Allowed overlapping reactor site")
	var reactor_site := Industry.REACTOR_STAGING + Vector2(140, -135)
	game.plot_move(reactor_site)
	wait_until(game, func() -> bool: return not game.has_destination)
	assert(industry.place_reactor(game, reactor_site).is_empty(), industry.reactor_site_error(game, reactor_site))
	assert(industry.reactor_position != reactor_site, "Reactor was teleported")
	wait_until(game, func() -> bool: return industry.stage == Industry.Stage.REACTOR_RESTORE and industry.service_delivered == 2)
	assert(industry.reactor_position == reactor_site and not industry.reactor_ready)
	use_contact(game, "reactor", "Restore auxiliary reactor")
	assert(industry.service_spent["reactor"] == 2 and industry.reactor_ready)
	var waypoint := reactor_site.lerp(industry.refinery.position, 0.5) + Vector2(0, -54)
	assert(not industry.install_cable(game, waypoint).is_empty(), "Cable was free")
	wait_until(game, func() -> bool: return industry.conduit_stock >= industry.route_cost(waypoint))
	assert(industry.install_cable(game, waypoint).is_empty(), industry.cable_error(game, waypoint))
	assert(not industry.refinery.powered and industry.conduit_installed == 0)
	wait_until(game, func() -> bool: return industry.stage == Industry.Stage.SEARCH)
	assert(industry.conduit_installed == industry.route_cost(waypoint))
	assert(industry.conduit_remaining + industry.conduit_stock + industry.conduit_installed == Industry.CONDUIT_RESERVE)
	assert(industry.refinery.status() == "POWERED / CONTROL UNAVAILABLE" and not industry.refinery.can_operate())
	var chart_cells := game.chart.size()
	for i in range(240):
		game.tick(1.0 / 30.0, 0.0, 0.0)
	assert(game.chart.size() == chart_cells and not game.is_visible("controller_2"), "Workers resolved the anomaly")
	game.plot_move(Industry.RICH_FIELD)
	wait_until(game, func() -> bool: return game.is_visible("controller_2") and game.is_visible("rich_ore"))
	game.plot_move(game.player)
	wait_until(game, func() -> bool: return not game.has_destination)
	use_contact(game, "rich_ore", "Extract rich ore")
	assert(industry.rich_total > 0 and game.ore == industry.rich_total and game.ore == game.cargo_fe + game.cargo_cu + game.cargo_si)
	use_contact(game, "stockpile", "Unload raw ore")
	use_contact(game, "controller_2", "Scan Controller 2")
	use_contact(game, "repair_cache", "Recover service components")
	use_contact(game, "controller_2", "Deliver service components")
	use_contact(game, "controller_2", "Restore Controller 2")
	assert(industry.service_spent["controller"] == 2 and industry.refinery.controller_id == 0)
	wait_until(game, func() -> bool: return industry.stage == Industry.Stage.SPECIALIZE)
	assert(industry.founder_position == industry.dock_port() and industry.refinery.controller_id == 2)
	assert(not industry.select_material("carbon") and industry.select_material("Cu") and not industry.select_material("Fe"))
	assert(industry.refinery.accepts_material("Cu") and not industry.refinery.accepts_material("Si"))
	# Power loss must pause commissioning even after docking.
	industry.reactor_ready = false
	game.tick(1.0, 0.0, 0.0)
	assert(not industry.refinery.can_operate() and not industry.logistics_unlocked and industry.elapsed == 0.0)
	industry.reactor_ready = true
	wait_until(game, func() -> bool: return industry.stage == Industry.Stage.ONLINE)
	assert(industry.refinery.status() == "ONLINE / IDLE" and industry.logistics_unlocked)
	assert(industry.refinery.raw_input == 0 and industry.refinery.refined_output == 0)
	assert(industry.energy < Industry.STARTER_ENERGY and industry.energy > 0.0)
	var independent := Industry.Refinery.new()
	assert(independent.select_material("Si"))
	assert(independent.receive_raw("Cu", 10) == 0)
	assert(independent.receive_raw("Si", Industry.Refinery.BUFFER_CAPACITY + 1) == Industry.Refinery.BUFFER_CAPACITY)
	assert(industry.refinery.specialization == "Cu" and industry.refinery.raw_input == 0)
	industry.energy = 0.001
	game.tick(1.0, 0.0, 0.0)
	assert(industry.energy == 0.0 and not industry.refinery.can_operate())

func wait_until(game: State, predicate: Callable) -> void:
	for frame in range(5400):
		if predicate.call():
			return
		game.tick(1.0 / 30.0, 0.0, 0.0)
	assert(false, "Timed out in stage %d, player %s, action %s, notice %s" % [
		game.industry.stage, game.player, game.work_action, game.notice])

func use_contact(game: State, contact: String, action: String) -> void:
	assert(game.command_for(contact) == action, "Unexpected action at %s: %s" % [contact, game.command_for(contact)])
	game.issue(contact)
	wait_until(game, func() -> bool: return game.pending_contact.is_empty() and game.work_action.is_empty())
