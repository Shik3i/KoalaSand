# Steam and gases

Steam is material ID `17`, a finite gas phase in the Water family. World Steam uses the generic `uint8` amount plane and shared deterministic mobile-matter activity. It rises first, spreads laterally, crosses chunk boundaries, sleeps when settled, and condenses from enthalpy into ordinary Water.

## World behavior

- Every transfer preserves amount and apportions enthalpy.
- Equal-temperature splits account for integer remainder in `thermal_rounding_reservoir`.
- Provenance and mineral signature travel with matter and survive Water/Ice/Steam transitions.
- Stable gas regions perform no full-world scan.
- A breach emits into adjacent world cells in gas order: up, left, right, down.

## Enclosed Steam

Existing spatial `PipeSegment` records transport Water or Steam. Each segment remains exactly `16 bytes`; it stores local fluid type, mass, temperature, pressure contribution, flow, health, connections, flags, type, and orientation. Latent Pipe progress is sparse and reports `16 bytes/entry` of key/value backing data (`uint64 + int64`), excluding container overhead.

Pipe/world transfer carries proportional enthalpy. Pipe contents exchange heat with adjacent physical matter. Heating Water inside a Pipe can produce Steam; cooling Steam can condense it. The total Water-family amount across world cells and all Pipes is conserved.

Pressure is a deterministic local gameplay approximation:

```text
pressure = fill contribution + pump/local pressure + Steam temperature contribution
Steam contribution = 16000 + max(0, temperature - 1492) * 12
```

It is deliberately not a scientific equation of state. A local segment above the rated pressure or reaction-temperature limit takes local damage. When health reaches zero, only that segment breaches. Its contained Water or Steam leaks into real neighboring world cells and continues through normal liquid/gas/thermal simulation. Cutting a Pipe with content uses the same local physical consequence.

Pipe throughput and Steam Pipe throughput are separate rolling production-statistics flows. Pipe temperature and Pipe pressure sensors expose local integer state to automation. Pressure/fill alerts identify the affected structure instead of scanning or mutating a global network.

## Scope boundary

Steam transport and pressure failure do not imply power generation. Steam turbines, electrical networks, generators, nuclear heat, advanced gas mixtures, combustion chemistry, corrosion, and scientific compressible-flow simulation remain outside Phase 9.
