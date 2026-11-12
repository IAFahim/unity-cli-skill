# Libraries, their jobs, and building in layers

Why this file exists: the owner wants every tool to have one stated job, every system built as separate layers that can be tested alone and
previewed by reading, and nothing that only adds ceremony. Read it before adding a library, a project or a layer. Every project's
`AGENTS.md` carries its own layer table in the shape of section 3 (rule 18).

## 1. The libraries and what each one owns

| Library | Owns (job) | Does not own |
|---|---|---|
| tl | time: designer-authored timelines (tracks, clips, markers, next, channel) baked to a library, kinds with `Combine` and `Apply`, pulses, playback per entity | game state storage, rules about who may do what, space |
| tl.unity (`com.tl.unity`) | the Unity host for tl: Core, Runtime, Authoring, generated Burst kind jobs, SubScene baking | anything tl itself does not do |
| sv | state: stats, intrinsics, events (storage at fixed offsets) and, in v3, the rule layers over them (stored inputs, gates, shaping, absorb, reflection and triggers, flow, fold, rewind) | time (timers and ticks), space (areas, auras), AI, movement |
| grid-influence (Gi) | space: influence fields; sources deposit, readers sample at entity positions | state rules, timelines |
| ecs-kernels | derived math kernels | rules, storage |
| Weave (proposed glue) | coordination between the libraries inside a host | any logic the libraries own |
| unity-cli-skill | knowledge and the tools agents use to drive Unity | game code |

Hard rules: libraries never reference each other; glue lives in the host (sv v3: generated glue only, the core references nothing);
a library that needs another's data takes it as plain columns or records through an interface the host fills; hosts (Unity, plain .NET,
WASM) adapt, they never decide.

## 2. sv v3 as layers (the template for any new system)

| Layer | Job | Input to output (plain data) | Alone-test | Preview |
|---|---|---|---|---|
| 0 storage | hold every value at its enum offset, default-shared lanes, chunk image | lane table to cells | codec round trip, address function, digest keyed by slot and lane | dump a chunk as rows |
| 1 inputs | store what happened as records, seal to canonical order | raw arena to canonical records | output depends only on the multiset (permutation test) | list records per target |
| 2 stats | modifier sets to stat values | stat ops to lane writes | integer law on edge values, scalar equals vector | per stat: terms in order, result |
| 3 rules | gate, remove, emit, flow, events | records and cells to deltas, next-frame records | compiled equals the reference interpreter | trace: which rule fired, what it changed, why a hit was denied |
| 4 commit | fold, events, epoch mark | deltas to values | fold law, hysteresis | before and after per changed cell |
| 5 time travel | journal, input log, replay | epochs to restored state | replay digest equals the straight run | which lanes an epoch touched |
| 6 tools | pack read and validate, compile, run, trace | pack rows to generated code or a trace | byte-identical generated output | `sv trace`, the web simulator |
| 7 hosts | frame loop, workers, Unity adapter, tl glue, web | layers 0 to 6 to a running game | same digests at 1 and 11 workers | the host's own debug display |

## 3. What makes a layer legitimate (all five, or it is not a layer)

1. One job, one sentence.
2. A named input type and a named output type, both plain data (no hidden receiver, no shared mutable state).
3. A law or invariant that can be tested without the layers above or below it.
4. A preview: the layer's output can be dumped as text or JSON the owner can read top to bottom. Previewing is a requirement, not a nicety.
5. A reference form: a slow, obviously correct version of the layer (or of the stack) that the fast version is diffed against.

Order of data flow only; a layer never reaches up. Layers may be fused by the compiler into one pass when the result is bit-identical (sv: plan
theorem T5); the layered picture stays the model, an `unfused` mode runs the layers one after another and gives the same bits, and the preview
tools show the unfused view.

## 4. The trap (and how to avoid it)

- A layer that only forwards, an interface with one implementation, an option nobody asked for: delete it (agent-code-brief: deleting a piece
  must shrink the system). If a layer fails any of the five tests it is ceremony.
- Layers can become a way to hide cost: every layer boundary must state its cost in the benchmark phase; a boundary that costs more than the
  budget is fused, not removed from the model.
- Many tiny layers make previews unreadable. Prefer about eight, each with a meaningful dump.
- Do not build layers speculatively for a host that does not exist (Unity adapter before the core is proven); add them in order of data flow.
- A layer table that is not kept true is worse than none: update it in the same commit as the change; the manager checks it when merging.

## 5. How to apply

- New library or project: write its job sentence and layer table in its `AGENTS.md` before code (rule 18), with the five tests per layer.
- New agent brief: give the layer it owns, its input and output types, its alone-test and its preview; forbid touching other layers' files.
- Testing order: each layer alone, then adjacent pairs against the reference form, then the whole stack across hosts and worker counts.
- The owner previews by reading dumps layer by layer; if a layer has no readable dump, it is not finished.
