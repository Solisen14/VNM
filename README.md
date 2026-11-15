# The First Five

A short, single-system Godot 4 prototype about five surviving autonomous mining drones.

## Run

1. On GitHub, choose **Code → Download ZIP**, then extract it.
2. Open the standard Godot 4 editor. In Project Manager, click **Import** and select `project.godot` inside the extracted folder.
3. Press **F5** to run the main scene.

## Opening

Watch 256 autonomous drones haul ore to the human mining ship. The ship initiates a recall before departure, then its reactor explodes. Five survivors pick up their mining orders from their positions at the blast. **Skip intro** goes directly to the aftermath, and **Restart** replays the opening.

Amber fragments are destroyed drones with salvage potential. Violet drone hulls are disabled units that slowly drift and may be repairable. Click either to inspect it. The game tracks both types as individual contacts. Recovering materials and reactivating disabled drones are future mechanics.

## Play

- Drag the map to pan. Scroll to zoom toward the cursor. Click a drone to inspect its current order, cargo, wear and inherited priorities.
- When all five holds fill, claim the Insight to salvage the refinery. Ore is processed at the wreck.
- Place a drone factory when you have 10 metal. Adjust the priorities and click **Apply template**. Drones carry refined metal from the wreck, and the factory keeps building drones while it has enough metal. Each new drone costs 6 metal.
- Place a sensor relay near the right edge of the wreck’s coverage circle to discover the outer ore field. You can move the relay. Take it offline to see the last known location with no current ore count.
- Use **1×** to cycle simulation speed, **Pause** to stop time, or **Restart** to replay the opening.

The sliders are relative decision weights. New drones inherit the current values when fabricated. Applying a different template starts a new generation. The sidebar shows the active priorities while you edit the next template. Cargo and wear affect choices, and a full hold or critical wear can trigger an order directly.

## Files

- `opening.gd` handles fleet traffic, recall, the blast and the persistent aftermath.
- `simulation.gd` handles drone decisions, ore, fabrication and sensor coverage.
- `system_map.gd` handles map drawing, zoom, pan and selection.
- `main.gd` handles player controls and telemetry.

This playtest stops at one system. The relay demonstrates stale telemetry. Behaviour drift and probe launches are future mechanics.
