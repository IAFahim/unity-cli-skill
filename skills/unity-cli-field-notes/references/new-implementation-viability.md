# Making a new implementation viable (and deciding when it replaces the old one)

Written from the tl 5.0 rewrite (issues IAFahim/tl#591, PR #592, IAFahim/tl.unity#29). The plan was sound; the first implementation was 1.3x to 3.7x slower than the old one at millions of entities. Small, boring developer fixes closed most of the gap. Do these before you redesign anything.

## 1. Profile first, then fix the small things

Show where the time goes (counters, a trace, a stopwatch per phase) before you change code. In 5.0 the answer was never the architecture:

- **Bounds checks in the inner loop** cost 1.1 to 2.2 ns per visit (4.5 ns to 1.9 ns after pointer access). Hoist the checks out of the loop or use pointers/`Span` over a pinned range.
- **Per-tick copies** of whole arrays (`acc` to `applied`, capacity-sized copies) when only active rows change. Apply from the accumulator; copy only active rows.
- **Per-tick allocation** from parallel dispatch (`Parallel.For` leaked about 2 KB per tick). Warm path means 0 B, with workers too. Cache the dispatcher.
- **Rebuilding on every tick what changes only on membership change** (run descriptors rebuilt by walking every playback). Build when membership changes, reuse in between. The cost of a tick must follow active visits, not playbacks or capacity.
- **Indirect loads** (`order[pos]` then three arrays at that index) and phase-grouped scatter. Lay data out so the hot loop reads sequentially by row; rows are also what threads split on.
- **Managed arrays on the runtime path** (the repo rule: unmanaged only). At 16M playbacks the managed buffers (hundreds of MB) caused large-object GC pressure and a setup 1.7x slower than the old engine. Use native buffers.
- **JIT tier-up**: the first pass is 2x slower than the third. Warm up, discard the first rounds, and say so.
- **Quadratic setup** (a linear scan per start). Use a hash or a sort; test setup at the largest size you claim.

## 2. A fair A/B, or it does not count

- Same shape, same machine, same worker count on both sides, hash-exact outputs on both arms.
- Median of at least 5 runs on a quiet machine. An outlier is explained by a rerun, not by the word "contention".
- Give the old engine's baseline two ways: the lean inner loop and the full generated path. A speedup quoted against the heavier one only is not a speedup.
- Measure the host the owner ships on (Unity with Burst, N workers), not only .NET. Hash parity is not speed. A micro-kernel number is not a system number.
- Measure at the owner's scale: millions of entities with 1 to 4 active timelines each, and up to 1000 timelines per player with 40 to 150 active. Report ms per tick and ns per active visit; a per-capacity-row figure hides cost.

## 3. The viability gate: when a new implementation may replace the old one

All of these, in the same harness, or it stays a branch:

1. At least 2x faster than the old implementation at the target shapes in Unity (Burst) and on .NET.
2. Setup time and memory no worse than the old one.
3. 0 B warm allocation, including with workers.
4. Hashes and pinned goldens bit-exact; every suite green; no test loosened to pass (replace a timing threshold with a count-based assertion, or put the data that justifies the new number on the issue).
5. The source budget does not grow. The change that makes the new path the only path deletes the old one in the same change; adding a second live engine is not a budget waiver.
6. A fresh clone of the pushed branch compiles and passes. A branch that needs uncommitted files is not a checkpoint.
7. A second agent reran the headline numbers and the repro.

Kill rule: if the gate is still missed after the profile-driven fixes, stop and report it. Port only the parts that won (threads, kernels, test oracle) onto the old layout.

## 4. Report like a developer

- Failed goals are not ticked. A todo whose result is "does not hold" is not done. Negative results go first.
- Label every number measured or projected, with machine, shape, worker count and run count.
- Time-box and record: what was tried, what it cost, what it gave.

## 5. Decide, do not ask

The owner is not a relay and not a tie-breaker for things a developer would simply do. A decision that is reversible, in scope, and keeps public API and pinned hashes unchanged is yours: pick the safer option, write one line on the issue, continue. Ask only for: tags, releases, visibility, deletes of data you did not create, force pushes, public API or pinned-hash changes, budget waivers, licence. Everything else, act and report.

## 6. Silent differences between hosts are bugs

- If one host ignores a feature, it must warn. tl.unity (pin before #584) silently ignores a kind's `Idle` method: the flag stays true after its clip while the .NET host resets it. Document the portable form (an explicit "off" clip to the end of the timeline) until the Unity generator catches up.
- Every example in a README runs on every host before it is published; code from a doc that was only read is unverified (the Hello README's added line did not compile in Unity because the sample's `foreach` has no braces, and the scene's `y` is 0.5, not 0).
- Recycling a player row on the plain .NET host: `StopAll` fires the interrupted End pulse of a mid-clip playback on the next tick, so reset and restart the row one step later (or ignore `Interrupted` ends). Tested with 100 players. In Unity a new entity is a new row.
