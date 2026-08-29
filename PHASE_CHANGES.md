# Physical phase changes

Phase changes are local consequences of simulated heat and finite material amount. They are not machine recipes.

## Water family

```text
Ice --1092 qK + latent 12000--> Water --1492 qK + latent 42000--> Steam
Steam --1492 qK - latent 42000--> Water --1092 qK - latent 12000--> Ice
```

Ice is immobile solid matter. Water falls and spreads through the unified mobile-matter solver. Steam rises and spreads through the same deterministic amount/activity architecture with gas direction rules. Condensation produces ordinary physical Water, which can fall, pool, enter an Intake, flood structures, or cool/freeze again.

## Glass and Iron families

```text
Glass --5873 qK + latent 20000--> Molten Glass
Iron  --7245 qK + latent 16000--> Molten Iron
```

Molten Glass and molten Iron are finite physical matter. They flow slowly according to their distinct mobility, exchange heat with adjacent cells and Pipes, solidify locally, and preserve amount, provenance, and mineral signature. Casting is therefore geometry plus controlled heat removal: route molten matter into a shape and let it cool. No hidden casting inventory or timer exists.

Hot molten matter can boil adjacent Water through ordinary heat exchange. The result is a local Steam event, not a scripted Water deletion. The same contact can cool and solidify the molten material. Conservation tests cover the combined material-family mass and total enthalpy, including the explicit integer rounding reservoir.

## Transition-state representation

`phase_energy` is a lazy `uint16[4096]` chunk plane. Direction bits in the existing cell flags distinguish heating from cooling progress. A transition remains at its threshold until its amount-scaled latent requirement is crossed. When progress returns to zero and the chunk stays quiet, the plane can be released.

All transition endpoints are stable material IDs: Water `3`, Glass `10`, Iron `11`, Ice `16`, Steam `17`, Molten Glass `18`, Molten Iron `19`. Content resources expose the new materials to catalog, inspection, rendering, and progression without owning simulation behavior.

## Processing design rule

Furnaces supply heat. Conveyors, chutes, Pipes, filters, containers, contact surfaces, and cooling geometry route physical matter. A useful production line must expose heating time, thermal loss, phase state, spill risk, pressure, cooling, and blockage. Research may unlock suitable structures and sensors; it never converts matter by itself.
