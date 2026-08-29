# Organic Physics

Phase 12 keeps organic matter inside the same authoritative cell simulation as geology, fluids, heat and factory logistics. Trees are world matter, not resource nodes; Wood, Leaves, Charcoal, Ash, Smoke and Food remain spatial materials after interaction.

## Research findings

- [Noita: Exploring the Tech and Design](https://www.gdcvault.com/play/1025695/Exploring-the-Tech-and-Design) demonstrates a continuous falling-sand world combined with compact destructible rigid-body representations. KoalaSand adopts the separation between grid matter and a temporary detached shape, but uses deterministic fixed-point cluster motion.
- [The Powder Toy](https://github.com/The-Powder-Toy/The-Powder-Toy) documents coupled pressure, velocity, heat, gravity and interacting substances. The applicable lesson is that fire products must remain simulated matter rather than visual particles.
- The Powder Toy's [double-buffer/update-order discussion](https://github.com/The-Powder-Toy/The-Powder-Toy/issues/668) reinforces explicit stable ordering and buffered local updates for deterministic cellular behavior.

No source code was copied.

## World generation

`basic_tree.v1` and `mushroom.v1` are canonical `WorldFeatureTemplate` records. WorldGen V2 derives placement from seed, surface slope, available space, regional feature density and aquifer tendency. `abs(x) < 160` is protected spawn/build clearance. Mode never enters generation; Factory, Character and Creative therefore receive identical Trees for a given identity.

Generated Trees have deterministic height, trunk thickness, branches, canopy and `uint8` moisture. Standing geometry is ordinary Wood/Leaves cells and requires zero separate simulation records.

## FellableCluster

A Cut flood-fills the connected Wood/Leaves component, removes those cells atomically and creates one compact native cluster:

- stable `uint64` ID;
- `int16` local cell coordinates;
- material, amount, temperature and moisture per cluster cell;
- Q10 position/velocity;
- Q16 quarter-turn angle/angular velocity;
- deterministic fall direction and collision count.

Clusters advance in stable ID order. Integer sine lookup rasterizes each pose against terrain and solid structures. Gravity accelerates the angle, collisions are strongly damped, and a quarter turn or two contacts settles the cluster. Settlement atomically finds nearby free cells, restores exact material/amount/temperature/moisture, marks it loose, and wakes only local simulation regions. There are no Godot bodies or collision shapes per Tree/cell.

Felling conserves normalized organic mass exactly. Settled Wood becomes normal granular/transportable physical matter, so Conveyors, heat and combustion use it directly.

## Material definitions

Temperature values are authoritative quarter-kelvin integers. Yields use `0..255` fixed-point fractions; combustion products enforce exact simplified mass balance with consumed oxidizer.

| Material | Density | Conductivity | Specific heat | Ignition | Pyrolysis | Energy/mass | Flammability | Moisture cap. | Char | Ash | Smoke | Burn rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Wood | 700 | 18 | 72 | 2092 | 1892 | 12000 | 190 | 96 | 96 | 16 | 159 | 4 |
| Leaves | 180 | 10 | 36 | 1760 | 1680 | 5200 | 255 | 48 | 16 | 48 | 207 | 8 |
| Charcoal | 420 | 12 | 44 | 2692 | disabled | 24000 | 150 | 8 | 0 | 24 | 0 | 2 |
| Smoke | 2 | 8 | 24 | disabled | disabled | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Ash | 900 | 9 | 36 | disabled | disabled | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Charcoal therefore stores twice Wood's combustion energy per mass and burns at half its rate. Smoke uses the existing Phase-9 generic gas solver and renderer pages.

## Optional state and cost

Base storage remains `9 B/cell`. A 64×64 chunk allocates only when needed:

- moisture: `4096 B` (`uint8`);
- oxidizer: `4096 B` (`uint8`);
- reaction progress: `8192 B` (`uint16`);
- reaction state: `4096 B` (`uint8`).

Standing Tree metadata is `0 B`; a detached cluster exists only during a fall. Untouched ambient air and 100,000 idle standing Trees execute zero explicit organic records. Rendering queries only visible clusters and effects and batches them in one `OrganicRenderer` node.
