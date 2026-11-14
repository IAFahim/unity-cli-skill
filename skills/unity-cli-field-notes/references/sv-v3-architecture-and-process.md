# sv v3: a compiled, layered, rewindable state engine, and how the work was run

Two halves. Part A is the architecture of sv v3 (the plan of 2026-11-12, corrected by the senior's answers and by what broke when agents built it); reuse it for any deterministic, rewindable, million-entity state engine on .NET + Unity 7. Part B is the process: what cost the owner a day, and the manager patterns that worked. Low-level SIMD, float and test recipes are in `deterministic-simd-state-engines.md`.

Plan tags kept where they matter: [DECISION] design choice, [ASSUMED], [DERIVED] arithmetic on layouts, [PROJECTED] estimate (±50 % until measured), [TARGET] gate, [FACT] measured or printed.

# Part A: architecture

## A1. The whole system in one line

A frame is `Step(State, Inputs) -> (State', Inputs', Events)`. Inputs are **stored, not applied**: everything aimed at an entity in frame n is a record consumed at the start of frame n+1. Nothing else exists.

## A2. Axioms and the theorems they buy

| Axiom | Statement |
|---|---|
| A1 Cell | a value is one 4-byte cell at (slot, value id); ids are generated enums; `slot = chunk * 64 + row` |
| A2 Lane | storage is lanes: the 64 cells of one value in one chunk (256 B) |
| A3 Record | an input is `(key, amount, hits)`; a frame's inputs are a multiset |
| A4 Frozen | a layer reads only what an earlier layer finished; persistent cells change only in Commit |
| A5 Own row | work for target t writes only t's cells; anything for another entity is a record for next frame |
| A6 Fold | a cell changes at most once per frame: `after = clamp(before + saturate32(sum))` |
| A7 Static rules | the rule set is fixed per content pack; what varies at run time is data |

| Theorem | Why | Buys |
|---|---|---|
| T1 Canonical: `Seal(M)` depends only on the multiset | total-order sort, merge equal neighbours | any arrival order, any worker count |
| T2 Locality: chunk c's result depends on frozen state + records targeting c | A4 + A5 | no locks, no atomics in the frame |
| T3 Order-free sums | terms saturated to ±2^32, 64-bit sums, < 2^31 terms | a hot target's run can be split over workers |
| T4 Termination: one root causes at most `F + F² + F³` records | strata are a DAG checked at compile time, depth <= 3 | bounded work per frame |
| T5 Fusion: two layers may fuse per chunk iff the later reads no other-chunk cell the earlier writes | both orders read identical values | compiled code faster than the layer picture, same meaning |
| T6 Rewind: restoring lane refs of epoch e + replaying the log reproduces every digest | journal holds each replaced ref once; Step is a function | lag compensation |
| T7 Width/host: any SIMD width, worker count, host gives the same bits | vertical ops only; each an integer op, one IEEE binary32 op + select, or pinned `BoundOf` | cross-host identity |

Write each theorem as a property test (T1 shuffle/idempotence/merge, T2 worker splits 1/2/4/7/11, T3 random cut points, T5 fused == unfused, T6 rewind+replay == straight run, T7 ISA legs + Burst).

## A3. Data model

| Value class | Cell | Kept | Written by |
|---|---|---|---|
| Stat | float | yes | stat machine (modifiers), main thread, edge-driven |
| Intrinsic | int | yes | Commit (the fold) |
| Channel (a damage/heal "type") | int | no, frame scratch | Decide |
| Event | 1 level bit, edge derived | yes | Commit |

- Kind, owner, link references, card/item counts, immunity masks are ordinary intrinsics: no second mechanism. "Immune" is a number or bit mask a rule reads (owner: immunity is not a feature).
- The generated enum **is** the lane index, drawn from one counter stored in the pack and never reused, so adding a value moves nothing and old saves stay readable. The first plan derived intrinsic ids as `StatCount + id` (adding a stat moved every intrinsic): wrong, corrected.
- **Shared default lanes** [DECISION]: each template owns read-only default lanes; a chunk's table points at them until a row differs; first write copies 256 B. Dense (identity table) is the special case with the same kernels. Sizes for 100 stats + 100 intrinsics + 100 events [DERIVED]: dense 812.5 B/entity (812 MB at 1M); shared table only 12.75 B; table + 16 touched lanes/chunk 76.75 B. Which wins depends on how many lanes stay default in a real game: count it before choosing.
- Chunk image for save/load/unload = live word + materialised map + materialised lanes in id order: one sequential write, canonical (independent of pool addresses).
- Slots: `Free -> Live -> Dying -> Free`. A dead slot is not reused until the snapshot ring has passed its death, so rewind never needs thrown-away data and a record naming it as source stays meaningful. Slot `2^22 - 1` is the "no source" key value and is never handed out.

## A4. The stored-input record (16 bytes)

`ulong Key | int Amount | int Hits`, key bits: target slot 22 | source slot 22 | source kind 8 | channel 8 | origin 2 (Direct, Timeline, Reflected, Triggered) | depth 2.

- Sorting by `Key` = sorting by (target, source, kind, channel, origin, depth); `Key >> 48` is the chunk; one `ulong` compare orders two records. 1,000 identical hits are one record with `Hits = 1000`.
- Source kind is copied in at send time (the source may be dead next frame; a lookup is a cache miss per record). "Consumed" is computed (`Taken`, `NotTaken = Amount - Taken`), not stored.
- Limits 256 kinds, 256 channels, 4,194,304 slots; past them the record grows to 24 B. Senior: start with a 24-byte plain-fields record, prove the laws, then pack to 16 B as a measured optimisation with the plain form as oracle (sv kept `EffectFields` + its own compare as that oracle).
- **Seal** (raw -> canonical): route (forwarding rows rewrite the target) -> counting-sort partition by chunk -> sort each chunk segment by (Key, Amount) (a segment already in order is only verified) -> merge equal neighbours (hits add in 64 bits, saturate once) -> checked build asserts strictly ascending, no zero amount, depth <= limit. Records a row sends to itself arrive bucketed: linear.
- **Overflow** [DECISION]: raw arena full -> layers are pure, so grow once (a cold, logged event) and rerun the layer; canonical over capacity -> lossy merge in three levels (equal key; across sources; across kinds), totals per (target, channel) conserved, an `Overflow` event names the level; the decision depends only on the multiset. Implementation corrections in A9.

## A5. Frame order

```
1 Seal     raw arena n -> canonical
2 Stats    expire -> stat ops in canonical order -> recalculate -> changed stats into lanes
3 Decide   per active chunk, read-only on persistent lanes: Gate -> Remove -> Emit (to others: next arena) -> Flow (channel totals, self triggers -> deltas)
4 Commit   per active chunk, own row only: Fold -> Events (level bits by hysteresis; edges -> messages, on-edge emits)
5 Publish  outward events sorted by slot, digest, epoch mark
6 rest of the frame: timelines, game systems read frozen state and Send into raw arena n+1
```

- Grouping "by type" and "by source" is not a pass: it is the canonical sort order plus channel totals. Gates run before totals (a gate decides what counts); reflection runs after Gate (it reads offered and taken).
- An active chunk has a record, a changed stat or a pending event re-check; nothing else is visited, so an idle world costs the Seal check.
- 3a-3d fuse per chunk; 4a-4b fuse per chunk; one barrier between 3 and 4 only if some rule reads another entity's cell. An `unfused` mode runs every sub-layer over the whole world (the reference meaning and what the web simulator shows).

## A6. Rules: gates, emits, flows, events

- **Gate** = `priority, when, then` on two decision cells. Admit (`Deny`/`Allow`): the highest-priority applicable rule decides, none -> Allow; **equal priority with different verdicts on overlapping conditions is a compile error**, never a silent tie-break. Shape (`Added`, `Additive`, `Multi`, `Cap`) reuses the stat modifier algebra and applies only if admitted; exclusive groups take only their top member.
- "Immune to snipers" gates on the record's kind, so it also drops the poison the bullet carried. Immunity as a count is `Absorb(budget, per = Hit|Amount)`, the only order-dependent effect, and its order is canonical (source slot, kind, channel, amount), never arrival.
- **Cards** are possession counts (intrinsics); every rule a card owns is compiled in with `self.card > 0` and-ed in; per chunk a card mask of zero skips the whole rule group with one test. Packs not compiled in run on the reference interpreter (mods, web tool, hot reload).
- **Emit** `on <cond> emit(to, channel, amount, per)`: `to` Self/Source/Owner/reference intrinsic; `amount` constant/Offered/Taken/NotTaken (scaled by a stat); `per` Record/Hit/Source/Frame. Reflection = `emit(to = Source, same channel, Taken, per = Record)`. To another entity -> a next-frame record with depth + 1; to self -> a same-frame delta, self rules stratified, a cycle is a compile error unless an edge is marked next-frame.
- **Termination:** a rule fires iff `depth <= depthLimit` (reflection default 0: never reflects a reflected record), world maximum 3. Mutual reflection ends in two frames, mutual immunity in one (denied -> `Taken = 0` -> zero records are not stored). The owner's "remove pass" is a compaction of survivors; no pass adds to the list it reads.
- **Flow and Fold:** channel total `sum Term(Taken, Hits)`; a flow is a designer row (`Health += Healing - Physical - Poison`); fold once: `clamp(before + saturate32(delta), min(floor, ceiling), ceiling)`. **Sum, then clamp once** [DECISION]: no entity dies at 0 mid-frame in a frame that also healed it; "heal first, then hit" is only expressible through `Absorb`.
- **Events are values:** one kept level bit, `next = (~state & enter) | (state & stay)`, edge = `state ^ next`; an edge becomes an outward message (ascending slot, per-channel cap, one Dense record above the cap) and fires on-edge emits at most once per (entity, event) per frame. Event conditions read only the entity's own row.
- Checks between layers are two things: designer chains (named acyclic boolean expressions; a chain reading only the target's row becomes one 64-bit mask per chunk) and engine checks in checked builds (ascending seal output, conservation `Offered = Taken + NotTaken`, no persistent lane written in Decide, delta scratch zero after Commit).
- **Compiler:** three IRs (pack: typed hash-consed expression trees over id types; layer: decision cells in final order, chains inlined, strata, each expression split into a row part and a record part; kernel: a straight vector program per chunk + a per-record scalar block behind `switch (channel)`), and a named ordered pass list a project can insert into: Bind, Validate-1 (designer errors), Lower (sugar -> core), Stratify, Order (priority desc then id; shadowed-rule warnings), Split, Optimise (fold, CSE, dispatch on channel then kind, group by card mask), Partition (cap method size), Emit (values, kernels, glue, job structs, rule id -> source map, no comments), Validate-2 (every rule emitted or reported, ids stable vs previous pack). Expressions are total: no division operator, NaN compares false.
- Senior's order of work: **write the reference interpreter and scenarios before any storage**; the meaning of a pack is the product, lanes and journals are optimisations of something already running and agreed with a designer.

## A7. Entity to entity, timelines, rewind, hosts

- Any entity sends to any entity by slot; no targeting system. Hand and shield are separate entities with an `Owner` intrinsic; a per-template forwarding row (`forward Healing -> Owner`, at most 4 hops, cycles dropped and counted) rewrites the target in Seal, so it lands the same frame. Reads of another entity are frozen (pre-Commit) reads. Latency: A->B one frame, A->B->A two, forwarding zero.
- **Timelines without depending on tl:** core knows only that something calls `Send`. The pack compiler emits glue into the game assembly: a row-local outbox `[TlState]` column, a `[TlKind]` whose `Apply` adds into it, a clip/track pair; **Collect** after the timeline step visits changed chunks, sends every non-zero cell as a record (origin Timeline) and zeroes it (consumer clears). tl has no per-playback source and a kind sums playbacks, so a sourced effect (a sniper's poison) is a small **status entity** (`Owner` = sniper, `Kind` = Sniper, target = victim) that plays the timeline and dies with it; then "immune to snipers" drops the ticks too.
- **Rewind:** a snapshot is an epoch mark, nothing is copied; copy-on-first-write lanes + a journal (A9 for the implementation rules); ring of 32 epochs (2 frames per epoch at 30 Hz = 2.1 s) [DECISION]. Journal at 1M entities [DERIVED]: 10 % of chunks x 3 intrinsics per epoch = 1.24 MB/epoch, 40 MB for 32; every chunk = 396 MB. A stat machine with its own undo log must agree with the lane journal bit for bit: write that twin test first.
- **Lag compensation:** collect a server tick's late inputs, rewind to the newest epoch at or before the oldest, insert them into the log, step forward; outward events of replayed frames diff into `Retracted`/`Added` for the game. Cost `(now - e) x frame` once per server tick (6-8 frames for 200 ms at 30 Hz). Default replays only the engine; re-running AI and timelines needs the host's own snapshot.
- **Hosts:** core `netstandard2.1` + `net10.0`, C# 9, unsafe, references nothing (World.Create, Acquire, Kill, Send, Step, Read, Events, Requests, Digest, Rewind, Replay, Save/LoadChunk, Dispose); rules/compiler/interpreter as a library; a CLI pack tool; a .NET host with worker pool and `Vector256` front doors; a WASM build for a browser designer + simulator; the Unity adapter owns its memory (not ECS chunk data), entities carry only a slot component, concrete generated `[BurstCompile(FloatMode = Strict)]` job structs with a `[BurstDiscard]` probe.

## A8. Budgets: projected vs measured

| Item | Plan [PROJECTED] | Measured [FACT] |
|---|---|---|
| fold of 1M rows, 2 intrinsics + condition lane | 1.6 ms | 2.06-2.24 ms (1.60 without conditions; 3.8 ms before per-strategy loops) |
| sv frame at 1M rows, 11 workers (v2 fold path) | - | 2.31-2.53 ms |
| tl generated kind job at 1M rows | - | 8.28-8.45 ms, alone over the 8.3 ms (25 % of 30 Hz) gate |
| random atomic send | 1.6 ns | 0.7 ns wall; one hot target 10.4 ns serial |
| v3 frame, 1M records, every entity ticking | 4.2 ms | not built yet |

Lesson: every projection was off by 30-50 % in one direction or the other; plans must carry kill rules (revert or downgrade, never tune more than a day) and agents must measure a touch job (memory floor) before believing a projection.

## A9. What broke when agents built the plan (readings now in code)

| Finding | Rule for next time |
|---|---|
| Table stride is pack lanes + 2 meta lanes (live, dying/template), not the pack's lane count | generated code indexes through the runtime view struct, never a pack constant |
| A table index can be journaled twice in one epoch (retarget to template, then write) | rewind walks each epoch backwards; worker writers are absorbed after every phase, before any main-thread acquire/release/write/load |
| Journal entry printed as `long + uint` (16 B) but costed at 8 B | two `uint` (a table index fits 32 bits) |
| `Rewind(e)` numbering ambiguous | define it as "state at the start of epoch e" in the contract |
| Linking shared files into the new core duplicated public types | CS0433 for any assembly referencing old and new; move shared code into one assembly first |
| The fold law shared a file with code needing the old engine | one law per dependency-free file |
| Overflow merge "amounts add, hits add" does not conserve totals | merged = (saturate32 sum of amount x hits, hits 1); deepest depth and highest origin kept, so termination holds; a fourth cut rule counts drops |
| Hard-cap raw arena verdict depended on worker block-taking | count capacity logically from record counts and configured writers |
| Shape `Multi` formula (`x Multi`) vs stat algebra (`x (1 + Multi)`) | one algebra wins (the stat machine's); "heals twice" is `multi: 1.0` |
| Depth limit "does not fire at its limit" vs reflection default 0 | fires iff `depth <= limit`; compiler rejects `limit + 1 > 3` for sends to others |
| "Fold once per changed cell" vs code folding every touched row | fold iff delta != 0 or a bounding stat changed |
| "Pending event re-check" undefined | re-check iff spawned, intrinsic folded to a new value, stat changed, or a channel total non-zero this or last frame |
| Card field named a card row in one section and an intrinsic in another | reader accepts card name first, then intrinsic |
| A `per: Frame/Source` emit guard intersected the channel sets of `and(taken(A) > 0, offered(B) > 0)`: disjoint sets gave mask 0 and the emit never fired (sv 0401, found by fuzzing 21,000 packs, not by any hand test) | a presence pre-guard is a necessary condition: AND one mask per aggregate conjunct; intersecting is right only when every conjunct constrains the same record's field |

Plans written without opening code contradict themselves in small places; the implementing agent records each reading in an issue with the chosen interpretation and keeps code following it until the owner or senior confirms.

Earlier generation (v2 adapter, sv phases 1-2) sharp edges that were fixed and are worth avoiding in any ECS host: rows existing before `Install` were never scattered (adopt them and fill sinks at install); `Unbind` did not cancel a same-frame `Bind`; destroying an entity leaked its slot (cleanup component); fixed 65,536 op/write capacities threw (grow or chunk); two hosts per world silently (throw); a fixed digest cadence with a stale digest (configurable, expose the digest's tick); docs described a send API a `[TlKind]` cannot call (a kind cannot address another row: ship a send pass over an effect column + target column instead).

# Part B: process lessons

## B1. What cost the owner a day

| Mistake | What to do (field-notes rule) |
|---|---|
| Managed agents on sv without knowing what it stores (intrinsics lived in host columns) or what the owner wanted it to be; phases 1-2 built a correct plan for the wrong product | know the project first (rule 18): say in your own words what it is for, what it stores where, how data moves, what the owner builds with it; if `AGENTS.md` does not say, stop and get the owner's statement |
| Filed nine issues from guesses after the owner described an idea (one was an "immunity" feature when immunity is just a number) | talk first (rule 17): reply with your understanding in the owner's words and the few questions that matter; no files, no issues, no code examples until the model is agreed |
| Showed code that guessed the owner's model | no code in design talk unless asked |
| Asked the owner to open, close or check issues | own the lifecycle: close with sha + receipts after a second run, reopen when touched |
| Brief said one commit trailer, agents used another | put the exact trailer in every brief; cosmetic, but it is a tell of briefs not being read |

## B2. A one-file senior brief that works

The senior (strongest model, no tools, one pass) produced a 1,190-line plan with axioms, code and kill rules from one file. What that file had:

1. **How to read it**, with source tags: OWNER (intent, the owner's own examples), FACT (from code/docs in the appendices), READING (the writer's interpretation, "do not trust these"), ILLUSTRATION (invented numbers). Say plainly that the writer does not fully understand the problem.
2. **The owner's intent in one paragraph**, then **numbered requirements** (R1..R18) so answers can cite them, including the constraints already held (determinism, no FMA, 0 B warm, C# 9 on the Unity side, no backward compatibility, pinned digests).
3. **One worked example** with a table of inputs and the expected layer-by-layer result.
4. **What exists today**: a table of piece / what it does / gap against the requirements, plus measured numbers and pins.
5. **What the writer could not resolve**, as explicit questions.
6. **What the deliverable must contain**, numbered (data model, record, passes, rules, entity-to-entity, boundary, rewind, hosts, migration, verification, code examples, risks and owner decisions separately, "say when you are guessing").
7. **Appendices verbatim**: AGENTS.md, contracts, docs, the relevant source files, prior plan, research notes, these field notes. Nothing to browse.

The answer format to ask for: tags ([FACT]/[SURE]/[MEMORY]/[GUESS] or [DECISION]/[ASSUMED]/[DERIVED]/[PROJECTED]/[TARGET]), a gaps-and-contradictions table, owner decisions with a recommendation each, a "not verified" list, milestones with gate and kill rule each, and corrections applied back to the plan when follow-up questions find errors (the senior found five of its own: lane ids, unbounded shift, input log missing spawns/kills/stat ops, false sharing between workers, medians hiding epoch-start spikes).

## B3. The standing code brief (what every coding agent gets)

- Audience: the owner reads the code top to bottom and hands it to other agents; no comments; names carry the domain; one source runs on .NET 10 and Unity 7 Burst at 1M entities with identical bits.
- Data is plain unmanaged structs with a stated layout; behaviour is static functions over it; a function's result depends only on its arguments (writes only through visible pointer/`ref`/`Span` parameters); every function total; few primitives each with a law written as a property test; order from data keys; deleting a piece shrinks the system.
- A feature table: struct-generic strategies (everywhere), `static abstract` (.NET only), pointers in the core and `Span` at .NET edges (no `Span` as a job field), `stackalloc` for small fixed sizes, `Sequential`/`Explicit` layouts, build-time generation emitting C# 9, one `Bits` helper. Forbidden on simulation paths: LINQ, lambdas, `async`, reflection, `dynamic`, exceptions as control flow, `record` for hot data, `Vector<T>`, FMA, platform math, `Dictionary` iteration, raw float-to-int casts.
- The SIMD rules in `deterministic-simd-state-engines.md` section 1.
- When the agent cannot run anything: whole files in dependency order, only APIs it is sure of (others listed as unverified), compile in its head (precedence of `& | == ?:`, overflow in every multiply and shift, language version), never claim it works, give the commands that would prove or break it.
- Hand back: 3-6 lines of decisions with reasons; complete files with paths; the public surface one line each; the laws and their tests; unverified items; the first commands to run. A last block per task: goal, what to build on, targets, what must not change, scale and budget, may it run things, deliver plan/code/both.

## B4. Manager patterns that worked

- **One worktree per agent** (`git worktree add <dir> origin/<base> --detach`) and **file ownership** in the brief: each agent owns named files and must not touch others; no two agents edit one file.
- **Skeleton commit before parallel work:** the manager commits the shared skeleton (projects, asmdefs, shared types, folder layout, empty contract file) on the integration branch first; agents fork from it, so nobody invents a parallel copy of a shared type.
- **Link kept files, but watch duplicate types:** linking old `.cs` files into a new assembly keeps one source but declares the same public types twice; any test or bench referencing both assemblies hits CS0433. Decide at skeleton time which assembly owns each shared file.
- **Locks:** take `bench.lock` then `unity.lock` (directories, `mkdir` fails if held) for every timed or Unity run, log the times, release on exit.
- **Independent verifier:** a separate agent clones fresh, rebuilds, reruns every gate, and writes a per-item PASS/FAIL table with evidence plus a "not run" row and a risks list; only then are issues closed. A verifier found docs that promised an API the host cannot call, and test deletions an issue had not listed.
- **Receipts format:** commit, settings line (editor, runtime, workers, Burst/safety/debugger/leak flags, processes, warm-up, rounds), counts, digests, numbers with ranges; "3 processes, not 5" said out loud when budgets cut it.
- **Kill rules per step**, written before the work: e.g. lanes as default only if the normal path costs < 3 % more; a step that trips one is reverted or downgraded, not tuned for days.
- **Waves:** core (.NET) agents, Unity agent, bench agent, verifier; a wave may be "no tests by owner order" (pure scaffolding); merge into an integration branch, then verify from a fresh clone of that branch.
- **Probes before plans:** a phase-0 probe agent (no engine change) measured the facts the plan leaned on (change versions, atomics cost, lookup writes, float bits per host) and tripped a kill rule (one hot target) and a stop-and-report (Mono float bits) early, which saved building on wrong numbers.
- **Senior questions get context files**, not summaries: when a plan left a layer unanswered (designer authoring), the next lookup attached the real authoring docs and code of the neighbour library.
