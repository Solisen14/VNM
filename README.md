# VNM

A Godot 4 prototype about five surviving control drones. The project opens at the controller’s safe-mode reboot.

## Run

1. On GitHub, choose **Code → Download ZIP** and extract the project.
2. Open Godot 4. In Project Manager, click **Import** and select `project.godot`.
3. Press **F5** to play.

## Reboot and Field Repair

Choose your designation and follow the systems as they come online. Use **Q / E** or the mouse wheel to zoom, **A / D** to turn, and **W / S** for forward and reverse thrust. **Left-click** a waypoint to fly there under autopilot. **Right-click** a contact to approach and carry out its available action. Use **Frame signals** to see the search area again and **Follow controller** to return the camera to your ship.

The controller charts the space along its flight path. Miner 031 can work through the fog and report its cargo without charting terrain.

Scan the ore field, damaged miner and wreck of the MCV Asterion. **Field Repair** appears in a first-Insight pop-up. Press **I** or use the pop-up button to open the Insights panel. Collect 3 ore from the field and one spare part from each of the two wrecked drones, then return to the miner and repair it. **Miner 031 automatically selects a worksite and starts mining as soon as it is repaired.** You do not assign individual ore jobs.

## Pass 1: Physical scale and luminous worker movement

This update **preserves the existing reboot and Field Repair tutorial**. Only the visual size, camera zoom and Miner 031 flight behaviour change.

- **Physical proportions:** Asterion ~5 km, original control craft ~25 m, mining workers ~4 m. The existing 2020-world-unit hull is treated as the 5 km reference, so a worker really is tiny beside it. On-screen reticles and labels remain readable.
- **Worker rendering:** Miner 031 is a bright white point with a subtle halo and a slightly altered cargo glow. At extreme close-up zoom, a minimal directional crossbar becomes visible. A disabled worker is a dim point, not a full triangular ship sprite.
- **Flight behaviour:** Miner 031 follows a shared destination-seeking steering model. It turns and accelerates gradually, drifts in small deterministic lateral curves, slows for mining/unloading and retains the original finite material / delivery accounting. It still cannot reveal fog.
- **Camera:** Scroll or Q/E can now zoom from 0.18× to 8×. A metre scale bar sits in the lower-right of the map. **Frame signals** continues to show the broader tutorial area.
- **Separate flight lab:** In Godot, open `swarm_lab.tscn` and press **F6** to preview **1, 10, 100 or 1,000** luminous workers moving using exactly the same motion helper (`worker_motion.gd`). This scene tests rendering and steering only; it is not part of the tutorial's production economy and does not chart terrain.

For repeatable headless tests, run `godot --headless --path . --script res://tests/pass1_smoke.gd` and `godot --headless --path . --script res://tests/pass2_smoke.gd`. They cover the first Insight, Field Repair, autonomous deliveries, site selection, material conservation, controller coordination and range, and player-only map charting.

This is **Pass 1**, not full flocking. Neighbour separation/cohesion, site-specific cutting positions, and large-scale worker aggregation belong to later passes. The player ship still uses its original procedural silhouette at the corrected physical scale; its modular sprite system is planned for Pass 3.

## Pass 2: Autonomous surface mining

- **No individual mining orders:** After being repaired, Miner 031 heads automatically toward the nearest viable asteroid *surface* on the stockpile-facing side. Small consistent scoring variations prevent identical routes. It returns with up to three units, unloads, then resumes the same rock until empty. Drones never chart the fog.
- **Discrete field:** The field now consists of 26 finite asteroids containing exactly **100 raw units**. Each individual asteroid has its own remaining yield and transparent sprite mask, consumed in a jagged line from the worker's near-side cutting face, not as a growing circle around the POI.
- **Mineral accounting:** The initial deposit yields **65 iron (Fe), 25 copper (Cu), 10 silicon (Si)** raw units. Extraction removes these from the field; cargo carries the mixture; the provisional Asterion stockpile stores each raw element separately. These are still raw/unrefined units. The player uses three initial ore samples to repair Miner 031.
- **Sensor UI:** Hover over a scanned asteroid or zoom in enough for an overlay showing the initial Fe/Cu/Si composition and how much raw matter remains.
- **Controller constraints:** HAL starts with a hard maximum of **10 supported worker drones** and a **1,450-world-unit communications radius**. Miner 031 cannot operate beyond that radius and heads back toward HAL if contact is lost. The UI shows network status and drone count. **Coordination Cores are NOT available:** their upgrade is reserved for a later Insight.
- **Next milestone is not implemented yet:** After the fifth ore delivery, the simulation records that the *Salvage Insight* threshold has been met, but hull disassembly and the three additional repairable drones belong to Pass 3. No manual hull assignment is available during Pass 2.
- **Unchanged:** HAL's flight controls, slow miner acceleration, eight-second extraction time, five-second unloading time, Field Repair, and the tutorial's first pop-up.

**Play note:** When HAL flies far enough away, the miner may stop extraction or follow HAL to restore communications. Returning within the working area allows it to resume. No Coordination Core upgrade is possible in this version.

## Asterion disassembly preview (currently locked)

The mothership art still contains the earlier prototype's destructible hull mask and buried refinery visualization. **The working mining-drone assignment that used to unlock it after one delivery is deliberately disabled.** Salvage will instead unlock through a later Insight after five deliveries, with additional repairable drones and physically relocated infrastructure.

The refinery, hauling networks, component manufacturing, and drone replication are not operational in the reboot scene yet. Those belong to subsequent passes.

## Earlier Dock 03 mission

Open `dock_03.tscn` and press **F6** to run the earlier Dock 03 mission.

After the fleet recall, watch the local network reboot or choose **Skip opening**. Move with **WASD** or right-click a point on the map. Left-click a contact, fly within reach, and use the action in the sidebar. Middle-drag pans and the mouse wheel zooms. **Follow drone** recenters the camera.

Inspect Worker 031, recover a repair kit from the service locker, and take it to the wreck stockpile. The control module stays reserved until you authorize its use. Bring it back to Worker 031 and fit it. Then select the scrap cache as its pickup and the wreck stockpile as its drop-off. The worker keeps hauling on its own while you explore. The sidebar shows your cargo, stock on hand, and cargo in transit separately.

## Earlier factory prototype

Open `main.tscn` and press **F6** to run the earlier single-system sandbox and its original mining-drone opening.

### From wreck to factory

1. Watch the fleet recall and blast, or choose **Skip intro**. The five survivors resume their original mining orders.
2. When their holds fill, select **Insight · Coordinate the Five**. This brings the refinery online and unlocks separate priorities for each founder.
3. Select a founder and raise **Salvage** to 100. They recover frames or control modules from amber debris and carry them to the wreck. Spend one control module to restore the maintenance fabricator.
4. The refinery separates ore into iron, carbon, copper, and silicon according to the field’s composition. The fabricator makes frames from 3 iron and 1 carbon, and control modules from 2 copper and 2 silicon. The wreck holds the element and component inventories.
5. With **Restore** enabled, a founder can collect a control module and carry it to a disabled violet drone. The restored miner follows its original orders. Lower **Restore** if you want to reserve modules for construction.
6. Spend **3 frames and 2 control modules** to place the drone factory. Apply a template once. Haulers stock the factory’s internal inventory, and it assembles drones continuously using one frame and one module each. Apply different priorities to start a new generation.

Founders are individually programmable. A mine-only founder caches ore at the field so a haul-only founder can collect it. Fabricated drones inherit the active template. Use **Service** for routine wear and **Restore** for disabled miners.

## Map and controls

- Drag to pan, scroll to zoom, and click drones or wreckage to inspect them.
- Spend one frame on a relay near the right edge of the cyan sensor circle. The outer field is richer in copper and silicon. Choose a mining preference once it is charted.
- Use **1×** to cycle speed, **Pause** to stop time, or **Restart** to replay the opening.

`opening.gd` runs the fleet recall and blast. `simulation.gd` runs drone decisions and production. `system_map.gd` draws the map. `main.gd` handles the interface.
