extends SceneTree

# Godot --headless --path . --script res://tests/autonomous_worker_smoke.gd
const State = preload("res://reboot_state.gd")

func _initialize() -> void:
	var game := State.new()
	game.begin("HAL")
	game.set_phase(State.Phase.CONTACTS)
	for contact in State.PRIMARY:
		game.execute(contact, "Approach and scan")
	game.execute("ore", "Extract ore sample")
	game.execute("parts_a", "Recover spare part")
	game.execute("parts_b", "Recover spare part")
	game.execute("miner", "Repair mining drone")
	assert(game.active_drones == 1 and not game.salvage_insight_unlocked)
	assert(game.pick_autonomous_task(31, 44, game.player) == "ore",
		"Workers must mine when Salvage isn't researched")
	assert(game.command_for("wreck").is_empty(), "Ship salvage available before second Insight")
	assert(game.hull_extracted == 0)
	game.salvage_insight_ready = true
	game.unlock_salvage()
	assert(game.command_for("wreck") == "Salvage refinery access plating",
		"Player cannot personally cut authorized hull area")
	assert(State.HULL_RESERVE == State.REFINERY_EXPOSURE and State.REFINERY_EXPOSURE == 12,
		"Refinery Insight opened more than its small hull sector")

	# With both materials available, the default generation must select both
	# tasks across a representative deterministic series of independent jobs.
	var mine_choices := 0
	var salvage_choices := 0
	for identity in range(30, 35):
		for assignment in range(1, 101):
			var choice := game.pick_autonomous_task(identity, assignment, game.player)
			if choice == "ore":
				mine_choices += 1
			elif choice == "hull":
				salvage_choices += 1
	assert(mine_choices > 180 and salvage_choices > 180,
		"Shared 50/50 generation default is not choosing both task types")

	# Manual interaction actually starts a timed cut at the accessible hull
	# section, adds matter to HAL's hold, and changes only that site's mask.
	game.player = State.WRECK
	game.velocity = Vector2.ZERO
	game.issue("wreck")
	assert(game.work_action == "Salvage refinery access plating",
		"Right-click didn't start local manual salvage")
	var site := game.manual_hull_site
	assert(site >= 0)
	game.tick_work(State.HULL_CUT_TIME + 0.01)
	assert(game.hull_cargo == 3 and game.hull_extracted == 3,
		"HAL did not collect 3 physical hull units")
	assert(game.hull_site_units[site] == 3, "HAL wasn't cutting at the selected worksite")
	assert(game.controller_load() == 3, "Hull load did not occupy controller hold")
	assert(game.hull_site_visual_units(site) >= 0.75, "Manual excavation not visible")
	assert(game.command_for("stockpile") == "Unload hull feedstock",
		"HAL cannot unload recovered hull at intake")
	game.execute("stockpile", "Unload hull feedstock")
	assert(game.hull_stock == 3 and game.hull_cargo == 0,
		"Manual salvage did not conserve stockpile matter")

	# The entire mothership cannot be scraped just because one sector is
	# researched. Once the 12 units are cut, the rest of the hull is locked.
	for i in range(State.SALVAGE_SITES.size()):
		while game.hull_site_units[i] < State.SALVAGE_SITE_QUOTA:
			var taken := game.extract_hull(i, State.SALVAGE_SITE_QUOTA)
			assert(taken > 0)
	assert(game.hull_extracted == State.REFINERY_EXPOSURE and game.refinery_exposed)
	assert(game.extract_hull(0, 3) == 0, "Hull excavation bypassed Insight boundary")
	assert(game.command_for("wreck").is_empty(), "Unexplored ship hull is still available")
	assert(game.pick_autonomous_task(42, 2, game.player) == "ore",
		"Restored workers do not switch to mining when salvage is exhausted")
	print("PASS: shared 50/50 autonomous workers, player salvage and refinery-only Insight boundary")
	quit(0)
