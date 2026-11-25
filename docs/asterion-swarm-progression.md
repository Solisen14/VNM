# VNM — Asterion salvage, swarm autonomy and industrial progression

Status: **Living design specification. Pass 3 includes manual ore mining, a second Salvage Insight, three more repairable general-purpose workers, and a refinery-access hull zone. All repaired drones follow a shared 50/50 Mining/Salvage default when both tasks are available; HAL can help salvage. Physical structure relocation, refinery operation, coordination upgrades, factories and drone replication remain future work.**
Recorded 2026-11-24. Preserve the current playable tutorial, the measured pace of HAL and Miner 031, and the pixel-disassembly prototype. Do not treat this file as a request to change code.

## Core fantasy and world scale

VNM begins with one damaged controller and an enormous mining mothership, the MCV Asterion. A small autonomous industrial workforce visibly dismantles wrecks and asteroids, moves matter through refineries, printers and factories, and eventually enables self-replication. Material is conserved in aggregate: pixels are a destructible *visual representation* of recoverable material rather than separately simulated atoms.

Scale targets: Asterion approximately 5 km, initial HAL controller approximately 25 m (blue-whale scale), initial worker drones approximately 4 m (large-horse scale). The controller grows by installing **physical modules** (engines, cargo, processing, computation). At strategic zoom, workers are luminous white dots; up close they can have minimal directional detail. Movement should be gentle, purposeful and organic. Swarm steering should eventually include local separation, clustering and varied worksite selection without wasting time.

The controller alone charts the map initially. Ordinary workers travel through fog but do not discover/chart new terrain.

## Retain the opening exactly in spirit

1. Safe-mode reboot, designation choice and sequential systems restoration.
2. Sensors, zoom, manual flight and waypoint/autopilot tutorial.
3. Three initial signals: asteroid field, damaged Miner 031 and Asterion wreck.
4. First Insight pop-up, **Field Repair** (press **I** for Insight Tree).
5. Player collects three units of ore and one spare part each from two wrecks.
6. Player repairs Miner 031. Mine/scan/salvage and movement should retain their recently approved measured pace.
7. Miner 031 starts mining automatically, no individual work order. Its first delivery and subsequent deliveries demonstrate an autonomous loop.
8. Subsequent Insights expand from this loop rather than replacing it.

**Pass 2 status:** Miner 031 now autonomously selects an asteroid surface when repaired, and right-click mining assignments have been removed. The source's pixel-by-pixel workface and material deliveries are implemented; later autonomous fleets and complex job scheduling remain to be built.

## Worker autonomy and limits

- A repaired or newly built worker starts seeking viable raw material **automatically**.
- Choose an accessible asteroid/surface reasonably near the stockpile (normally the closest productive site), with modest stochastic variation so the swarm does not behave as a perfect queue.
- Drones approach the closest useful *surface* rather than the middle of a field. Remove actual material pixels from the local workface; the workface migrates inward, and a partially mined asteroid is revisited.
- When cargo is full, return to an appropriate reachable stockpile, unload at a deliberate pace, and resume at the same productive asteroid or choose a new one. A source is finite.
- Workers select jobs subject to generation-level settings, research, local material availability and network limitations. **The player should not micromanage individual worker routes**.
- Starting coordination limit: **10 active workers per controller**. This fixed cap applies throughout the early tutorial; being able to increase capacity is **not** part of the initial communications/range implementation. Do not unlock or introduce a Coordination Core in Pass 2. Much later, a distinct **Insight** will reveal the need for additional coordination/computing capacity and enable a *Coordination Core* (or potentially renamed *Swarm Control Node*) to raise the cap. The name and exact late-game trigger are not yet final.
- Workers operate only within communications range of their controller or connected relays. Range extends through sensors/comms research and relay networks. When disconnected, workers should seek reconnection/return; an eventual autonomy upgrade might allow independent operation.
- Early research may improve worker engine speed, cargo size, extraction efficiency, navigation and eventually network range. **Increasing coordination capacity is reserved for the later Coordination Core Insight**, not a generic early research upgrade.
- **Starting Generation 01 default: 50% Mining / 50% Salvage**, shared by Miner 031 and all repaired drones. These are weighted task-choice preferences, **not** mandatory time budgets, classes, or per-drone work orders. Before the Salvage Insight, only mining is eligible. At each completed delivery, a worker picks another job. If one category is unavailable or depleted, it automatically chooses the other. Workers still transport their own cargo to the intake between assignments.
- Future generation templates may tune relative priorities such as mining, salvage, hauling, maintenance and repair. They guide decisions rather than impose rigid time quotas.
- During certain discoveries and infrastructure moves, the system can temporarily prioritize available workers for a major operation without requiring the player to click each worker.
- No full boids/flocking or 1,000-worker economy is implemented yet; the Pass 1 flight lab only tests movement/rendering.

## Insight sequence: tentative gates, to balance in playtests

1. **Field Repair:** after the three scans. Collect 3 ore + 2 spare parts; repair Miner 031.
2. **Salvage:** after **5 successful ore deliveries** by Miner 031 (15 ore at 3 each). Insight motivation: **“Why is the ore stockpiling here?”** HAL discovers a former refinery intake, authorizes cutting **only the refinery-access hull sector (12 extractable units in three work zones)**, and detects **3 additional damaged general-purpose workers** for possible repair. HAL can cut that same access zone personally, carry hull feedstock, and unload at the intake. Restored workers follow shared task priorities immediately. The rest of the Asterion remains non-salvageable until its specific later Insight.
3. **Refining & Logistics:** after roughly **12 units of hull feedstock** have been salvaged and a refinery subsystem revealed. Insight voice: **“I can use the refiner to process these materials.”** Unlock the physical recovery, placement, restoration and use of the refinery plus automated hauling between processing sites. Reveal/ping **2 more damaged workers**. The six repaired workers plus future factory-built workers remain under the 10-unit initial cap.
4. **Component Manufacturing:** after roughly **36 total hull units salvaged** (more than Insight 3) **and 18 units processed** through the refinery. Insight voice: **“I can use the autofactory to build parts.”** Reveal, recover, place, restore and bring the autofactory online; unlock part recipes.
5. **Drone Construction:** after producing the necessary manufactured components, Insight voice: **“I can construct additional worker drones.”** Build the first genuinely new worker: first self-replication milestone. A new drone automatically receives a generation template and begins work within range/capacity.

The values 5 deliveries, 12 hull, 36 hull and 18 processed are **proposed starting thresholds**, not final balancing. Expand current hull reserves to support them. Repairs and manufacturing require their own material costs.

**Critical distinction:** mining drones currently haul their own ore. The Refining & Logistics Insight introduces **general-purpose logistics** that transports supplies between stockpiles, refineries, printers and build sites when needed. It does not simply unlock cargo movement that has already been demonstrated.

## Structures must be physically recovered, moved and placed

A major buried subsystem is **not** instantly unlocked or teleported into operation. The ordered sequence is:

1. Drones strip outer hull pixels until a recognizable component (refinery, autofactory, reactor, CPU, later sensors/scanners/research equipment) is exposed.
2. A structure-recovery task is queued: disconnect it, carefully dismantle restraints and remove it **intact as a relocatable building-sized structure**, with individual sections if required. Distinguish sensitive structural recovery from bulk smelting/salvage.
3. The player selects a **new placement location**, with a Satisfactory-like ghost/placement preview. The player chooses infrastructure sites, not individual hauling paths.
4. Available drones temporarily suspend ordinary mining as necessary, haul the recovered structure to the chosen location, and position/reassemble/anchor it. This must be visible and take time. Respect range, capacity, navigable space and workload.
5. Only after placement and any required repairs or supply hookups can the structure operate.

**After the first refinery is placed**, prompt the player to **choose the location of the first permanent mining stockpile**. Until then, the Asterion wreck stockpile can act as a provisional delivery/cache site so the original tutorial remains coherent. Do not silently auto-place the permanent stockpile.

This placement sequence should teach base construction before players are expected to site dozens of facilities. Infrastructure location remains a meaningful player decision even though drone behaviour is autonomous.

## First asteroid field: iron-heavy composition

Provisional *target* mix remains approximately 65/25/10; actual playable depleted deposit has **137 raw units**:
- **Iron (Fe): 89 units (65.0%)**
- **Copper (Cu): 34 units (24.8%)**
- **Silicon (Si): 14 units (10.2%)**

These are **game-balancing targets**, not realistic asteroid chemistry. The field is made of physically distinct asteroids; composition may later vary by asteroid or pixel neighborhood. The deposit's mix is recovered when mined and the stockpile/refinery keeps track of that mix.

Visualize with an unobtrusive sci-fi sensor HUD **at suitable zoom levels or on hover over the POI**, ideally showing material bars/percentages, total remaining recoverable matter, and later sensor-accuracy upgrades. Avoid permanent UI clutter. **Silicon** is the semiconductor ingredient, not silicone (sealant).

### Material pipeline and recipes (prototype abstraction)

Raw asteroid material / mixed hull feedstock → refinery sorting → Fe, Cu, Si (and other elements where sourced) → autofactory prints parts → assembly builds new workers.

Possible initial parts:
- Structural frame: **iron + carbon**, where carbon must come from *another explicit source* since the first asteroid field contains only Fe/Cu/Si. Decide whether carbon is recovered from the Asterion, its cargo, another deposit, or a revised frame recipe before implementing.
- Electrical/propulsion assembly: iron + copper.
- Control module: silicon + copper.
- A basic mining worker uses one of each assembly, subject to a sensible energy/propulsion abstraction and subsequent balancing.

Do not confuse the printer's material stock with the availability of a fabricated part, and do not conjure matter into existence during cargo or building transfer.

## Later discovery: Asterion cargo hold

When deeper disassembly uncovers the mothership's cargo hold, it should contain mixed **processed and unprocessed ores/materials** and possibly finished components. This is planned for a later chapter, not the immediate next update. Discovering that cache should accelerate industry without replacing extraction or refining.

## Long tutorial arc, not for the next small update

Eventually recover the other **four founding controllers** and outfit them with interstellar engines, compact bootstrapping refinery and autofactory, CPU/coordination core, and a design library covering research, sensors/scanners and further facilities. Controllers physically grow as modules are added. Near the tutorial's conclusion, four refurbished controller seeds depart to found independent machine civilizations. The player remains to grow HAL's lineage.

## Build priorities and guardrails

- **Pass 2 implemented:** site-specific asteroid selection and local erosion; autonomous first miner; 65/25/10 Fe/Cu/Si field and hover/zoom HUD; a fixed cap of 10 workers and basic communications range, **with no Coordination Cores or early capacity upgrades**. Five deliveries now set the Salvage-ready flag, but do not unlock salvage yet. Approved flight handling and mining pace remain.
- **Pass 3 implemented:** five ore deliveries open the second Salvage Insight; three damaged general-purpose workers can be repaired with 2 Fe + 1 Cu supplies each. Every repaired worker follows the Generation 01 50/50 mining/salvage task preferences when both jobs exist and automatically finds other work once the refinery access section is exhausted. HAL can mine ore and cut only the Insight-authorized refinery-access hull sector personally. Exactly 12 hull units expose the refinery; other mothership structures remain locked. The provisional intake cache sits above the Asterion hull.
- **Next (Pass 4):** recover/disconnect/place the exposed refinery, allow HAL to choose a permanent stockpile location, introduce general-purpose hauling and elemental refining, and ping two additional repairable workers.
- **Then:** general-purpose hauling, refining, autofactory recovery, part recipes and first newly manufactured worker.
- Later: true multi-worker swarm behaviour, more structures, and a **separate future Coordination Core Insight** that unlocks capacity upgrades once progression warrants it; planetary-scale resource abstraction and faction evolution.
- No immediate rewrite to microscopic atom simulation. Keep visual pixels and resource units consistent.
- Maintain and extend Godot 4.7.2 compile, scene-boot and progression tests before shipping code.

Decisions still open: precise hull extraction yields, stockpile placement constraints, first carbon source, structure transport capacities, what happens when all ten drone slots are occupied, and how long a temporarily interrupted mining task retains its worksite.
