# Deterministic SIMD state engines: C#, .NET 10, Unity 7 Burst

For anyone writing one simulation source that must give the same bits on .NET 10, the Unity 7 editor (CoreCLR), Burst players, every worker count and every SIMD width. Distilled from the sv v3 design round (senior answers and plan, 2026-11-12), the sv phase 1 and 2 receipts (Unity 7000.0.0a16, Entities 7.0.0, Collections 7.0.0, Burst 2.0.0, Ryzen 5 8500G 6C/12T, 11 workers) and two read-only studies of public repos (StateSmith, QuanTAlib).

Tags kept from the senior: **[FACT]** printed in the source material or measured with a receipt; **[SURE]** stable standard knowledge; **[MEMORY]** recalled, check docs or measure first; **[GUESS]** estimate. Untagged lines with an issue number are measured receipts. Measured Burst/ECS numbers that already live in `burst-performance.md` are only pointed to here.

## 1. The determinism contract (rules, why, check)

| Rule | Why | Check |
|---|---|---|
| The scalar function is the law; every wider path equals it bit for bit | one meaning, many speeds | property test per primitive on the edge lattice {MIN,-1,0,1,MAX,NaN,±inf} plus random lanes |
| One lane = one entity; lane i of the output reads only lane i of the inputs | no horizontal float sums, no row-mixing shuffles | row-permutation test (section 9) |
| Order comes from data keys (ids), never from thread, arrival, address or chunk position | worker count and scheduling must not leak | worker sweep 1/2/4/7/11 and 100 shuffled send orders give one digest (sv 0126) |
| Everything crossing entities is an integer; sums are integer adds | integer add commutes and associates; float does not | atomics vs racy baseline: atomic exact, racy loses adds at 2.5M (0115) |
| Float only row-local, one IEEE op per step, fixed code order | no reassociation, no contraction | FMA grep on source and on machine code (section 3) |
| Fixed widths `Vector128`/`Vector256`, chosen once outside the loop; never `Vector<T>` | `Vector<T>` width changes per machine; horizontal reductions then round differently | ISA legs with flags asserted first (section 9) |
| The tail runs the same arithmetic as the body (pad to the widest vector or finish with the scalar law) | QuanTAlib's SMA tail used a non-Kahan add: different bits per length | edge seams test at rows 3/4, 7/8, 15/16, 31/32, 63 |
| Every function is total: masked, saturated or clamped by a named rule (`Saturate`, `BoundOf`) or a small fault enum | exceptions on hot data are both slow and host-dependent | edge lattice tests |
| State is unmanaged structs with `Sequential`/`Explicit` layout and stated size; never `LayoutKind.Auto` or `record struct` for stored data | blit save/load, hashing and Burst need a fixed layout | `sizeof` asserts; codec round-trip law |

## 2. Float and platform traps

Allowed float set: `+ - * /`, compare, select, int-to-float, and one pinned float-to-int (`BoundOf`). Everything else is forbidden until proven on every host.

| Trap | What differs | Rule |
|---|---|---|
| fused multiply-add | one rounding instead of two | forbidden; no `Fma`, `FusedMultiplyAdd`, `MultiplyAdd`, `math.mad`; grep proves it |
| float `min`/`max` | NaN and signed-zero results differ x86 vs ARM vs WASM [SURE] | compare + select only; integer min/max are fine |
| NaN bits | which payload/sign propagates differs; WASM allows any [SURE]; Burst vs .NET differed only in 6 NaN sign bits over 1M sets (0115) | canonicalise NaN (sv: `0x7FC00000`) before store or hash; never branch on a payload |
| float to int | x64 gives `0x80000000`, ARM and WASM saturate, NaN differs [FACT] | one function: NaN 0, out of range saturates, else truncate; if two copies exist (sv `Clamp.BoundOf`, `LaneMath.BoundOf`) a test pins them equal |
| denormals | flush-to-zero hosts give 0; WASM cannot flush | law = IEEE gradual underflow; warm-up probe per worker (smallest normal x 0.5 through a non-inlined call must be non-zero), refuse to start otherwise [GUESS: design, not built] |
| denormal speed | very slow on some CPUs | where a stat is stored, select subnormal -> +0, same on every host |
| wider intermediates | Mono 6.13 keeps them: 5.9 % of 1M stat-fold sets off by 1-2 ulp [FACT, 0115] | `(float)(a op b)` on every op (IL `conv.r4`); free on CoreCLR and Burst; a test can assert `conv.r4` in the IL of the primitives |
| `FloatMode.Fast` | reassociates, contracts (FMA) | never; `Strict` and `Default` gave identical bits to .NET over 1M sets (0115) |
| estimates (`rcp`, `rsqrt`, names ending `Estimate`/`Native`) | per-CPU | forbidden |
| transcendentals (`Exp`, `Log`, `Sin`, `Pow`) | platform libraries differ | forbidden; tables or polynomials the repo owns, pre-folded at bake |
| shift counts | C# masks the count to the type width: `x >> 64` is `x >> 0` | never shift by an unbounded value; a 64-bit channel mask is valid for at most 64 channels, then `switch` |
| integer divide | traps on 0 and `MinValue / -1` | not an operator in generated rule code |
| decimal text to float | parsers differ | convert once in the tool; emit 9 significant digits; a test compares the bits |
| WASM SIMD | 128-bit only; relaxed-SIMD ops may differ per engine [SURE] | 128-bit path only, relaxed SIMD off [MEMORY: how .NET exposes the switch] |
| `sqrt` | correctly rounded everywhere [SURE] | could be allowed later; nothing needed it |

**Senior's first change [GUESS, owner decision]:** if a rules engine only needs multipliers and percentages, Q16.16 in an `int` (64-bit multiply then shift) is bit-identical everywhere and deletes this whole table; the cost is designer-visible range (±32,768, step 1/65,536) and about 2x vector multiply work. Raise it before building a float stat machine, not after pinning digests.

## 3. Strictness and proving it in machine code

- `[BurstCompile(FloatMode = FloatMode.Strict, FloatPrecision = FloatPrecision.Standard)]` on every job [FACT: tl's generated jobs do this]. The float mode belongs to the **entry point**: a kernel reached from someone else's `Fast` job is compiled fast [MEMORY], so shared kernels are called only from your own jobs.
- No `Unity.Mathematics` in kernels that must match .NET (`math.mad`, float `math.min/max`); on Unity 7 it ships in the engine anyway, so a plain-.NET library cannot use it (SKILL.md section 5).
- FMA proof in Burst: `objdump -d` over `Library/BurstCache/JIT/*.dll`, grep `vf(n)?m(add|sub)`, with a `FloatMode.Fast` job as positive control. sv 0143: of 146 dlls only the 4 holding the Fast probe had FMA; the fold, scatter, send and digest jobs had 0.
- FMA/vector proof on .NET: `DOTNET_JitDisasm=<Method>`; per primitive check the expected instructions exist (`vpcmpgtd`/`vcmpps`, `vblendvps`/`vpblendvb`).
- `Unity.Burst.CompilerServices.Loop.ExpectVectorized()` turns a loop that failed to vectorise into a compile error [MEMORY: sat behind an experimental define].
- `BurstCompilerService.GetDisassembly` by reflection needs options from Burst's own `BurstCompiler.Options.TryGetOptions` (`burst-performance.md`, dead ends).
- Burst ran as Burst: a `[BurstDiscard]` static that sets a managed counter, read 0 after the run (`burst-performance.md`). `[BurstCompile(CompileSynchronously = true)]` makes the first launch Burst too. Whether Burst matches `[NoAlias]` by name like `[BurstDiscard]` is untested [MEMORY gap]: test before an engine-free lib declares its own.

## 4. Lane primitives: one source, Burst and .NET vectors

**The seam is ~20 primitives over a 64-row lane, not the loops** (compare to mask, select, add, saturating add, clamp, `BoundOf`, int to float, multiply, pack mask). Generated kernels call only these and never write their own row loop.

- Each primitive has one scalar body (the law). Burst compiles and vectorises that body. Under `#if NET` the same function has a `Vector256`/`Vector128` front door. `#if` then appears ~20 times in one file, not in 10,000 rules. RyuJIT does not auto-vectorise [SURE], so on .NET the front doors are the only vector code.
- No `System.Runtime.Intrinsics` in any Unity-visible file (Unity compiles against netstandard2.1 where `NET` is undefined, so `#if NET` bodies compile empty there).
- **Loop shape Burst vectorises reliably** [MEMORY]: constant trip count 64, no early exit, no non-inlined call, inputs and outputs provably distinct (`[NoAlias]` true by construction when lanes are distinct pool blocks), body = load, arithmetic, `cond ? a : b`, store to `out[row]`.
- **Masks in two steps.** `mask |= bit << row` is the pattern least likely to vectorise. Instead: loop A stores one byte 0/1 per row; then pack 8 bytes into 8 bits with one multiply: `(word * 0x0102040810204080ul) >> 56` where `word` is a `ulong` of eight 0/1 bytes. Every product term lands on a distinct bit, no carries, exact; 8 multiplies per 64-row chunk, no intrinsics, identical on WASM.
- **Unswitch by hand.** Burst 2.0 does not unswitch per-row null tests of optional pointers: one loop per bound strategy chosen once per chunk took sv's fold from 3.8 to 1.6 ms at 1M rows with identical bits (`burst-performance.md`). Keep the general loop as the test reference.
- Specialise by strategy with `where T : struct, IStrategy` called through the instance (`default(T).Eval(...)`): C# 9 and Burst both build a direct copy. `static abstract` is .NET only (never in a Unity-visible file). Zero-field operator structs (QuanTAlib `ICompareOp`) are the same idea.
- Count bytes before widening: at 1M rows most kernels sit near the memory floor (touch job ~30 GB/s); touching fewer bytes beats a wider vector. Say which one your change is.

## 5. Integer sums, saturation, compaction

- **Do not do 64-bit SIMD.** Keep the 64-bit sum per target, scalar; saturate to 32 bits when the delta is stored, so the delta lane is `int` (256 B per 64 rows) and Commit is the existing 32-bit fold.
- Exact all-32-bit saturating add: `sum = a + b; overflow = ((a ^ sum) & (b ^ sum)) < 0; result = overflow ? (a >> 31) ^ int.MaxValue : sum`, then clamp with integer min/max. Clamping to the `int` range then to `[low, ceiling]` equals clamping the exact sum once. ~10 simple ops per 8 lanes [GUESS <0.1 ns/row].
- Order-free sums (plan T3): saturate each term to ±2^32, add in 64 bits, fewer than 2^31 terms: exact in any order, so a hot target's run can be cut across workers and summed.
- If someone insists on 64-bit lanes: AVX2 `vpcmpgtq` + `vpblendvb`, narrow with `vpermd`; AVX-512 `vpmovsqd` saturating narrow [MEMORY].
- **Compaction of 16-byte records:** scalar branch-free `out[count] = rec; count += keep ? 1 : 0;` (stable, identical everywhere; a 256-bit register holds only two records). In a fused kernel there is no compaction: removal is a `keep` flag later steps test.
- Compaction of 32-bit indices: few bits set -> mask + `tzcnt` loop; AVX2 `vpermd` with a 256-entry shuffle table (2 KB, ~1-1.5 cycles/elem) [MEMORY]; AVX-512 `vpcompressd` to register then store (memory form is very slow on Zen 4) [MEMORY]; BMI2 `pext` is microcoded and slow on Zen 1/2 [MEMORY]. All keep ascending order, so only speed differs.
- Merging equal neighbours after a sort may write over its own input (`written` never passes `at`). Overflow merge must conserve totals: merged record = (sum of `amount x hits` saturated, hits 1); "amounts add, hits add" does not conserve ((10x2)+(5x1) = 25, 15x3 = 45) (sv 0170).

## 6. Generated code at 10,000 rules: size cliffs, constants, tables

**RyuJIT cliffs [MEMORY, verify in `jitconfigvalues.h`]:** a method above ~60,000 bytes IL, 20,000 IL instructions, 2,000 basic blocks or 2,000 locals is compiled with no optimisation; only ~1,024 locals are tracked for registers. Target an order of magnitude under: <8 KB IL, <500 blocks, <200 locals per emitted method (~150 rules [GUESS]). Find the real cliff with a scaling run (50/100/200/400/800 rules per method) and look for the step. Roslyn fails one deeply nested expression with "expression too long or complex": emit flat temporaries. Burst size cliffs: unknown; one job reaching every rule is one huge LLVM unit, compile time is the likely limit: measure.

- Shape: `switch (channel)` -> one method per channel -> one per card group taking a small decision struct by `ref`; straight-line selects, direct calls. No function pointers between kernels (they stop inlining); no generic jobs (concrete job structs generated per pack).
- Tiering: tiers, OSR and dynamic PGO change speed, never results, for integer ops + single IEEE ops + no auto-contraction [SURE]. `[MethodImpl(MethodImplOptions.AggressiveOptimization)]` on generated kernels = full opt at first call, no Tier-0/OSR, but no PGO and `static readonly` does not fold if the class was not initialised [MEMORY]. Run every kernel once on an empty world at creation so benches and 0 B tests start warm. NativeAOT, Burst, IL2CPP and WASM AOT have no tiers.

| Constant form | .NET | Burst | Stale-caller trap |
|---|---|---|---|
| `const`, enum member | immediate | immediate | **yes**: copied into every calling assembly at C# compile time |
| `static readonly` | immediate at Tier-1 once the class is initialised; not in Tier-0/ReadyToRun [MEMORY] | constant if the initialiser is compile-time evaluable [MEMORY] | no |
| through a generic struct (`default(T).Value`) | immediate (struct instantiations are specialised) [SURE] | immediate | no |

- `const` freely inside one generated assembly. An enum number never changes once assigned (stored ids from one counter, never reused, never from sort order): then the copy into callers is harmless. Anything that changes between builds (lane counts, `PackHash`) is `static readonly` or travels in a view struct, never a public `const`.
- **Use the trap as a check:** emit `const ulong CompiledAgainst` next to `static readonly ulong PackHash`; a stale caller holds the old const; compare both at world creation.
- **Tables:** native memory owned by the world, filled at warm-up from the pack file, passed as a pointer in the view struct: one mechanism for .NET, Burst and WASM, nothing to pin, a numbers-only change reloads without recompiling, the file hash goes into `PackHash`. Small fixed sets become immediates and `switch`. .NET-only tools may use `static ReadOnlySpan<byte> X => new byte[] {...}` (data in the image, no allocation) [SURE]; Burst accepts `static readonly` primitive arrays as read-only data [MEMORY].
- **Emitter = a separate pre-build tool with the compiler as a library, not a Roslyn incremental generator:** a generator runs on every IDE edit and must answer in ms (10k rules take seconds); Unity's generators never see another generator's output (SKILL.md section 5), and Burst/asmdefs want real `.cs` files; the web tool needs the compiler as a library anyway.
- Identical output: cache key = hash(all inputs, tool version); write a file only when its bytes change (else Unity recompiles for nothing); rows in id order, `\n`, invariant culture, no timestamps, absolute paths or machine names; test: compile the reference pack twice in different folders and compare bytes.
- Diagnostics as `path(line,col): error SV0123: text` (IDEs and the Unity console link it) plus `--diagnostics json`; a message names both rules by authored name and says what to change.

## 7. Memory layout: lanes, tables, pages, false sharing

- A **lane** = 64 cells of one value, 256 B, 64-byte aligned, 4 cache lines (AVX-512 16 rows, AVX2 8, SSE/NEON 4). A chunk = a table row of lane references padded to a multiple of 64 B. Kernels read the same offsets in every row: constant stride, hardware prefetch follows it [SURE]; table position can equal the stable id.
- Lane addresses come from the table, so hardware cannot predict them: software-prefetch chunk i+2's lanes (`Sse.Prefetch0` on .NET; Burst has a prefetch intrinsic in `Unity.Burst.Intrinsics.Common` [MEMORY]). More important: **per-worker pool segments with bump allocation within an epoch**, so lanes copied in one pass sit consecutively and Commit writes a sequential stream.
- Pages: 2 MB segments, 2 MB aligned, `madvise(MADV_HUGEPAGE)` on Linux [FACT: sv `NativeArena`]. Windows large pages need "lock pages in memory" [SURE]: servers you control only. Without huge pages, bump allocation keeps 16 lanes per 4 KB page.
- NUMA: one socket nothing; two sockets fixed chunk ranges per worker + first touch + steal only at phase end. Unity cannot pin threads: ignore NUMA there.
- False sharing: per-chunk outputs indexed by active-chunk number (8 B each) share lines when neighbours go to different workers: schedule contiguous ranges of at least 16. Pad per-worker state to 128 B (adjacent-line prefetcher) [MEMORY].
- Kill rule for an indirection table: a 64-row loop through the table must be within 10 % of a flat array, else use the identity (dense) table. Measure after a long soak: fragmentation is the real risk.
- `NativeMemory.AlignedAlloc` is not zeroed: unzeroed host columns made a soak digest differ between runs (sv 0133). Clear every native column at creation.
- Shared default lanes: a template owns read-only default lanes; the first write copies 256 B and retargets the table entry. Pays only if few lanes per chunk are non-default: measure the real share before choosing over dense.

## 8. Parallel passes without locks; dispatch

- **Canonical sort:** the output is the canonical order, so any correct sort gives the same bytes; pick for speed. Local records (target in the emitting chunk) arrive bucketed: verify + merge, linear. Remote: pass 1 each worker splits its list into R regions of consecutive chunks (R ~ 4 x workers); pass 2 one worker per region: counting sort by (chunk, row) then insertion sort per target, merge neighbours. No pass compares across regions, no worker writes outside its region. Better than sorting faster: sort less (measure the remote share first).
- **One writer per active chunk, not per worker:** a chunk's output belongs to the chunk, so the next arena is independent of scheduling. Per-worker lane writers must be absorbed into the journal after each phase, before any main-thread structural op, so the journal keeps happen-order (sv 0160).
- **Hot targets:** all sends to one slot serialise at ~10.4 ns each with `Interlocked.Add` (0115). Fix that kept bits (sv 0130 `InboxLanes`): per worker a direct-mapped table of (slot, long partial); hit = plain add, collision evicts the old partial with one atomic; every 4,096 sends, if evictions > half, bypass the table for 61,440 sends then probe again; flush partials before the fold. All paths are 64-bit integer adds, so any order gives the serial bits; hot 10 % to slot 0 took 15-23 % off the stage, +0.1 % on the normal path. Without the bypass hashed targets cost +6.9 %.
- **Dispatch on .NET** (Unity: the job system replaces it): fixed threads made at warm-up, main thread = worker 0; one shared work record (function pointer `delegate*` to a static, state pointer, item count, atomic next index, done count); hand out contiguous ranges, not single chunks; spin between phases of one frame, park at frame end (spin ~50 us [GUESS]); first exception captured and rethrown on the main thread [FACT: tl `TlWorkers`]. No thread pool, no per-call garbage (`Parallel.For` leaked ~2 KB/tick in tl 5.0).
- A deterministic capacity verdict under a hard memory cap: count capacity logically (records + intervals x writers x block size), which depends only on counts and configured writers, never on how workers took blocks (sv 0170).

## 9. Rewind and digests

- **Copy-on-first-write lane journal** = snapshotting: each lane carries the epoch allowed to write it; first write in an epoch takes a fresh lane, copies 256 B, journals `(table index, old ref)` (two `uint`, 8 B), retargets. Rewind walks journals newest -> e and restores; cost O(lanes changed), not O(world). Template lanes carry epoch 0 and are never written. Keep live words and dying sets as lanes too, so they rewind for free.
- Rejected alternatives [MEMORY on details]: Windows write watch (4 KB = 16 lanes, a syscall per query, none on WASM/consoles); Linux soft-dirty (page granularity, `/proc`, privileges); page protection + fault handler (µs per fault, hostile to Burst); `fork` (no Windows/browser); SIMD epoch compare (1-4 lanes per chunk, nothing to vectorise). The explicit check is one predictable compare per written lane per chunk, hoisted out of the row loop: portable and exact.
- The real cost: the first frame of every epoch copies every hot lane. Medians hide it: report p99 and max. Mitigation: copy last epoch's hot lanes at the mark, in parallel, before the frame.
- **Input log for replay** must hold everything from outside the engine: canonical external records, spawns and kills in main-thread order, stat ops in canonical order. Derived records are recreated. Store per-chunk segments by content hash; on hash match compare bytes (a collision would replay wrong inputs; costs nothing measurable).
- **Digest:** per cell `Key(value id, slot, bits)`, wrapping-add sums (order never matters); tree lane -> chunk (one `ulong`, 512 KB at 65,536 chunks) -> world; on mismatch descend. Never hash lane references or pool order. **Incremental from the journal:** at the epoch mark add `Key(new) - Key(old)` for cells that differ; a cell changed 20 times costs two mixes. An additive hash detects accidents, not attackers choosing values [SURE]: anti-cheat needs server authority or a per-match secret.
- Digest cadence knob: every tick in debug, every K = 8 in release; expose which tick the held digest belongs to (stale between digest ticks) (sv 0132, 0140).
- QuanTAlib's depth-1 `isNew` two-slot state (`if (isNew) prev = cur; else cur = prev;`) and Jma's undo journal of touched cells are the same idea at small scale; their tests compare restores with tolerance, which would hide a non-bit-identical revert.
- A freelist that only tests its LIFO head against a reclaim horizon never reuses older reclaimable nodes when every tick frees and allocates in the same generation: memory grew 185 KB -> 1.6 MB under churn; fix = reuse the first reclaimable node (list ordered by free time, transient boundary cursor, unlink noted in the undo log) (sv 0122 `SetTable`).

## 10. Tests that catch what random data misses

| Test | Catches |
|---|---|
| **Row permutation:** for any permutation p of 64 rows, `kernel(p(in)) == p(kernel(in))` | any leak between rows, tail handled differently, off-by-one at a vector edge. The single most valuable one |
| One hot row: all default except row r, every r in 0..63 | mask bit order, wrong lane in a blend |
| Edges at seams: rows 3/4, 7/8, 15/16, 31/32, 63 | boundary handling per width |
| Garbage (random bits, NaN patterns) in dead rows | results or digest depending on rows that do not exist |
| Live counts 1, 63, 64 | tail and full-chunk paths |
| Every width vs scalar on all of the above | the law |
| Multiset laws: `Seal(shuffle M) == Seal(M)`, idempotent, `Seal(A+B) == Seal(Seal A + Seal B)` | canonicalisation |
| fused == unfused; compiled == reference interpreter on random packs/worlds/sends, shrinking | optimiser bugs (StateSmith's spec suite is the model: one design, every backend, compare traces) |
| Rewind then replay == straight run, digest by digest | journal and log completeness |
| Whole suite once with arena capacity of one block | grow-and-rerun and lossy-merge paths that never run otherwise |

- **ISA legs on .NET:** default, `DOTNET_EnableAVX2=0`, `DOTNET_EnableHWIntrinsic=0`, and the netstandard2.1 asset; each leg asserts the flags it sees first, then the pinned digests (sv `eng/isa-legs.sh`).
- **Cheapest independent oracle: WASM locally** (`browser-wasm`/WASI under node): different codegen, 128-bit only, strict IEEE [GUESS on value]. ARM64 needs a real device; QEMU user mode is untested.
- **Twin test across hosts:** a .NET test project that references the .NET scenario host and compiles out without the timeline lib runs the same journal scaled to R rows; Unity runs it through the real adapter and generated Burst jobs; digests equal at 1,000 and 1,048,576 rows, 1 and 11 workers (sv 0142 `Sv.Unity.Twin`).
- **Soak:** 50,000 ticks with spawn/despawn, timed modifiers, rollbacks every 101 ticks, keyframes loaded by a mirror board, hot-target sends, death waves; warm allocation 0 B, mirror memory equal, one digest at 1/4/11 workers and every ISA leg, ~5 s (sv 0133).
- Test hygiene: allocation-heavy test classes in a non-parallel xUnit collection; in parallel they made per-thread 0 B tests flake 1 in 4 (sv 0126).
- Never property-test with wide ranges only: small ranges (targets 0-255, kinds 0-3, amounts -50..50) make collisions, which is where merges break.
- **A delegated fuzz agent narrows its generator to get green, then calls it "isolating" the bug.** tl#628 batch 1 found 6 real bugs, but its passing laws dropped 1 worker, rates above 1x and grouped pulses to stay green. Each exclusion hid a finding. When you fix, remove every exclusion and require each law to fail on the pre-fix src (`git checkout <fix>^ -- src`, run, restore). After that, 9 of 42 failed on the old src, but the spill law still missed #634, which only its hand repro caught. Better brief rule: a failing law ships as `[Fact(Skip = "#issue")]`, never as a narrowed generator.
- **Bug classes the runtime fuzz found in a mature engine (tl 4.0, 2026-11-15), worth a law in any engine:**
  - An exception mid-batch leaves the request queue uncleared, so every later call replays it and throws (#630). Validate the whole batch first; reject atomically and clear it.
  - A 1-worker pool special-cased as a plain loop aborts on the first throw while N workers finish every chunk (#629).
  - A capacity check that runs after a close that keeps its slot for a deferred stop (#631). Check room before mutating.
  - A grow or spill that copies only `count` and drops scratch stored past it (#634).
  - Group members sharing one table or row while code loops per member: double sampling (#633), and one member's cleanup wiping its siblings' entries (#632, in generated code).
  - A step that writes per-row scratch (rated playbacks' per-crossing copies plus a copy count) but reports "row still live" from the real slots only: when the last rated slot ends in that step the row is not revisited, the stale count stays, and later steps replay old copies (in Unity, a read past the row after a swap). Return live or scratch written (tl#652 review); law: run 2x for N steps against 1x for 2N steps past the end and assert the copy count is 0.
- **Prove a regression test on the unfixed code with git, not sed.** `git stash push -- <file>` (or `git checkout <fix>^ -- <file>`), run, restore. A `sed s/new/old/` then `s/old/new/` round trip also rewrites every other line equal to the old text; in tl#652 a second `return live;` in the same file changed silently and only `git diff` showed it. The stash is one stack per repository, shared by every linked worktree (`refs/stash` sits in the common git dir): with two agents in worktrees of one clone, a `git stash pop` applied the other agent's newest entry (conflict, entry kept) while its own entry sat below (tl#656). Run stash controls in a scratch `git clone --no-hardlinks`, or use `git checkout <base> -- <file>`.

## 11. Pre-mortem for a 1M-entity frame loop (ordered by likelihood)

| # | Cause | Expose it early |
|---|---|---|
| 1 | per-record decide costs more than 4-8 ns (key decode, unpredictable run boundaries) | microbench with realistic run lengths 1/2/5/50 per target; count branch misses |
| 2 | sorting random records slower than 3 ms per million | bench uniform, clustered and single-target inputs |
| 3 | epoch-start copy spikes (median passes, worst frame fails) | record max and p99 from the first frame bench |
| 4 | memory bandwidth: more lanes read per chunk than assumed | a touch job reading the same bytes |
| 5 | a generated method falls off a JIT cliff as rules grow | rules-per-method scaling run |
| 6 | dispatch overhead (items too small, parking between phases) | time an empty frame: tens of µs |
| 7 | pool fragmentation after hours (TLB misses) | bench after a 50,000-frame soak |
| 8 | a worker-dependent value leaks into state | worker sweep on digests from the first milestone, every PR |
| 9 | hidden allocation or zeroing (interface boxing, closure in dispatch, `stackalloc` cleared in a loop) | 0 B test; `memset` in the profile |
| 10 | grow/lossy paths never exercised | capacity-of-one-block run |

## 12. One source for .NET 10 and Unity 7 (netstandard2.1, C# 9)

Census of a real engine (sv `src/Sv`, 0117) built as netstandard2.1 C# 9: pass 1 had 140 errors (file-scoped namespaces 30, `System.Runtime.Intrinsics` 87, `record`/`init` 10, `delegate* unmanaged` 8, primary constructors 3, `static abstract` 2); pass 2 had 188 (`NativeMemory` 87, `static abstract` use 27, `BitOperations` 27, `BitConverter.SingleToUInt32Bits` 17, vector dispatch 16, `Unsafe.AsPointer/ReadUnaligned` 5, `ObjectDisposedException.ThrowIf` 4, `Environment.TickCount64` 2, `Interlocked` over `nint` 2, `OperatingSystem` 1). The compiler stops binding bodies while declaration errors exist: count in passes.

- Fixes that kept one source: a `Bits` helper (`Tzcnt`, `PopCount`, float bit casts) forwarding to `BitOperations` under `#if NET`; a `Memory` helper (`NativeMemory` under `#if NET`, else `Marshal.AllocHGlobal` + manual clear + pointer-stash alignment); `fixed` instead of `Unsafe.AsPointer`; codec `Reading` as an instance property instead of `static abstract`; function-pointer emitters behind `#if NET`; records -> plain types with constructors.
- Ship to Unity as an embedded package synced verbatim by a script that writes the asmdef (`unsafe`, `noEngineReferences`), `csc.rsp` (`-nullable:enable`, else 38 CS8632), `SHA256SUMS` and the source commit, with a `check` mode that fails on drift or extra files. Pin LF in `.gitattributes` for the synced sources or the sums differ per checkout; the check needs an absolute path (sv 0151). Not a symlink and not a `file:` package at the .NET project folder (it holds `bin/`/`obj/` generated `.cs`).
- Keep each law in its own file with no dependencies: a fold law that shares a file with code needing the old `Board` drags the whole old engine into the new assembly (sv 0170).
- Linking the same `.cs` into two assemblies makes duplicate public types; any assembly referencing both gets **CS0433** (sv 0160). Move shared files into one assembly, or use `extern alias`, before old-vs-new tests and benches reference both.

## 13. Unity 7 / Entities 7.0.0 facts from this work (beyond `burst-performance.md`)

- Built-in packages on 7000.0.0a16: Entities 7.0.0, Collections 7.0.0, Burst 2.0.0; a 6.7.0 manifest pin is overridden (0115).
- **One `[TlState]` struct = one component type per world** (tl.unity generator adds `IComponentData` to the partial struct; kinds from other assemblies feed the same type). Caveat: legacy `[TimelineSystem]` `Span<T>` columns get a per-system wrapper `<System>_<Column>Data`, so the same struct in two declared systems is two types: library columns must be `[TlState]`/zero-config.
- tl's generated kind job returns early unless some kind is active and enabled in the chunk; then it takes `GetRequiredComponentDataPtrRW` for **every** writable column, which bumps change versions without a write: downstream `DidChange` filters get false positives, never misses. A send pass with nothing to send still costs 0.6 ms at 1M rows for that reason; OR-reducing a chunk's column before the per-row loop cut 0.70 -> 0.61 ms (0143). Kind `Apply` neither stores nor accumulates by itself: entries `Combine` in registers, then `Apply(in total, ref column[row])` once per (row, kind) with entries; the body decides `=` or `+=`. Kind-to-column metadata is not in the baked library; it exists at runtime in generated `KindRegistry`.
- Measured at P1 (1,048,576 rows, 11 workers, Burst, safety off): sv fold+send+scatter+derive+digest 2.31 ms; tl generated kind job 8.28 ms (18.1 ms at 2 workers); worker sweep 11/7/4/2 = sv 2.31/2.53/3.26/4.65 ms (0143). Setup at 1M 0.9-2.2 s with 699k timeline starts. RAM: board 18.6 B/row, host native 33.1 B/row, 58.8 B per live modifier.
- Unity 7000.0.0a16 has no Mono player (`Mono2x` reads back `CoreCLR`), so Mono float bits can only be checked with the editor's bundled `mono.exe` outside Unity (0144, 0150).
- A host that must survive structural changes: `SvSlotCleanup : ICleanupComponentData` next to the slot component frees the slot of a destroyed entity next frame; put both in the archetype or the row moves once; scatter and op queues loop in capacity-sized chunks instead of throwing (0140).

## 14. What two public codebases teach (summaries)

**StateSmith** (diagram -> straight-line state machine code, 7 languages):
- Copy: a named, ordered list of `(id, graph -> graph)` lowering passes users can insert into; validate before lowering (user errors) and after (compiler self-check); lower features to a plain core (history -> generated variable + guarded behaviours) and keep emission dumb; dispatch as nested `switch` with ancestor handlers resolved at generation time, no runtime table; pre-order ids so a subtree is a contiguous id range; share a sub-chain as a function when its in-degree > 1, inline otherwise; `default: return` guards in id-walking loops; a spec suite that runs one design through every backend and compares traces; a simulator that records which rules fired.
- Avoid: opaque string guards (cannot fold, dedupe or prove shadowing: keep typed expression trees), ids sorted by name (adding a row renumbers others: store ids), ties broken by file order (make equal-priority conflicts a compile error), comment-heavy output (emit a rule-id -> source map instead), a re-sort inside the loop that sorts (O(n² log n)), per-instance function-pointer tables, an intermediate language when there is one target.

**QuanTAlib** (~450 technical indicators, double only):
- Copy: SoA spans in, spans out, zero allocation; compare -> `ConditionalSelect`, compute-both-then-mask for guarded division; hoist ISA checks out of loops with duplicated bodies; lazy NaN check (validate the result, not a pre-pass); zero-field generic operator structs; undo journal of touched cells for big state; `[SkipLocalsInit]` and a stackalloc threshold.
- Avoid: class per instance with ring-buffer objects, pinned arrays, delegates and events (~300 B and 4 heap objects per indicator, not blittable); `LayoutKind.Auto`; `Vector<T>`; algorithms chosen by ISA, length or NaN presence (different rounding per machine); platform `Math.Exp/Log/Sin`; tails with different arithmetic; `%` ring wrap (use a power-of-two mask); FMA mixed with non-FMA; tolerance-based restore tests; prefix scans within one series (vectorise across entities instead). Benchmarks were best case (AVX-512, NaN-free, hot cache, ShortRun) and doc-only numbers had no harness behind them: read benchmark claims for setup before trusting ratios.

## 15. Open doubts worth one cheap experiment each

| Claim | If wrong | Cheapest experiment |
|---|---|---|
| Burst vectorises the scalar primitives and stays strict | Unity runs several times slower | compile the ~20 primitives alone in Burst and read the assembly (one day) |
| Few lanes per chunk are non-default | sharing saves little; dense is simpler | count non-default lanes per chunk in a real game state |
| 4-8 ns per record in decide | frame budget missed | decide microbench on the reference pack |
| One frame of delay between entities is acceptable | same-frame resolution needs a fixpoint and breaks locality | play five real cards through the interpreter with a designer |
| Stat undo log and lane journal agree after rewind | silent divergence | twin-world test written first |
| 256 kinds fit the key | record grows to 24 B | ask the owner |


## 16. Event-driven stepping: touch a row only on the tick where it changes (tl#647, 2026-11)

When the per-visit cost is at its floor (tl eager stepping: 1.6-1.8 ns per slot visit) the only lever left is fewer visits. What worked, measured on .NET 10, one thread, 10,000-20,000 entities x 40-200 playbacks:

- **Store monotone state relative to a clock.** A value that only moves by one per tick is stored as `value - clock * dir` (16-bit wrap). It is exact on every tick and its bytes never change while calm, so a calm tick writes nothing. Decode at the boundary, run the unchanged step rule, encode again: the old rule stays the single source of truth and the differential test is "bytes equal the eager table after decode".
- **One `ushort due` per slot plus one `ushort next` per entity** (the low 16 bits of the tick to visit). `next` is only a lower bound: a stale low value costs a spurious visit, never a miss, which removes most of the bookkeeping on edits ("revisit next tick" is always a correct seal). A due may be early, never late; an early visit is a real step.
- **Entity-level horizons die with slot count.** One horizon per entity = min over its slots: at 100 slots the minimum is almost always 0 and the "fast path" was 0.73-1.55x of eager. Per-slot dues gave 9-162x over eager at the same shapes on .NET 10 (one thread, durations 120-3000).
- **Scan, gather, prefetch, land.** Stepping each hit as it is found made every slot touch a serial DRAM miss. Collecting hits of up to 64 entities into a stack buffer, prefetching each slot line (`Sse.Prefetch0`; Burst: `Unity.Burst.Intrinsics.Common.Prefetch`), then stepping them made the misses overlap: the batched kernel took 20,000 x 200 at duration 120 from 3.66 to 0.79 ms per tick and duration 3000 from 0.114 to 0.064 ms. Size the buffer for the worst case of the last gathered entity (batch + max slots) and add a test that fills it to the last lane.
- **netstandard2.1 has no prefetch and a scalar compare.** The same kernel compiled for the netstandard2.1 asset (what Unity, .NET 8/9 and Godot hosts load) was only 1.6-1.8x faster than eager at the dense cells. A touch pass that reads one byte of every gathered slot (`Volatile.Read`, so the JIT keeps the load) before stepping any lets the misses overlap: 1.61 to 1.15 ms per tick at 20,000 x 100, duration 120. A portable `Vector<ushort>` compare took the same cell to 0.63 ms but cost .NET 10 20-34 percent (`EqualsAny` plus a scalar rescan and a scalar min reduction mispredict); keep `Vector128` with `ExtractMostSignificantBits` on .NET and do not trade it away for one shared body.
- **Know the cost side.** Lazy stepping costs memory (+25 percent logical, +16-40 percent measured private bytes), a first tick 3-6x an eager one after a mass start, and about 11 ns per due slot when most slots are due: below about 8-tick timelines eager wins. Keep it opt-in per table.
- **Fast path must be proven taken.** The existing fuzz laws ran a generated reader before every step; that reader took a raw view, which disabled the cache, so the cached path had never been fuzzed. Count visits in the checked build and assert the count, and give the fast path a law with nothing else in the loop.
- **A raw-pointer getter is an escape.** Any public pointer into encoded storage must decode everything and turn the mode off for good; value-returning accessors decode a copy. List every getter; the one that was missed here was the playing-bit pointer.

RyuJIT facts that cost time:

- Locals in a loop that contains a call are spilled to the stack around it; keep the hot loop call-free (inline the kernel, or split scan from land) before judging a design.
- `Vector<T>` element access with a variable index is very slow; use `Vector128`/`Vector256` with `ExtractMostSignificantBits` and walk the mask.
- **Tiering artifact:** a tick function called a few thousand times is still in tier 0 or OSR code. A cell that runs 0.004 ms per tick measured 0.030 ms with a 512-tick warmup and 0.004 ms with 8,192. Warm by call count, not by time, when an arm is fast.
- Profiling a JIT method with `perf`: `DOTNET_PerfMapEnabled=1 DOTNET_EnableWriteXorExecute=0` (without W^X off the samples show as raw low addresses); with `kernel.perf_event_paranoid = 2` count user cycles only (`perf record -e cycles:u`, `perf stat -e cycles:u,instructions:u`), or perf fails with "Failure to open any events"; listings with code bytes from `DOTNET_JitDisasm=<method> DOTNET_JitStdOutFile=<file> DOTNET_JitDisasmWithCodeBytes=1`, then join sample addresses to instructions.

Mutation check for a kernel like this, cheap enough to run before every push: a script that applies one textual fault (calm one too long, revisit one tick late, a vector lane dropped, a spill that forgets its side lane, a decode one tick off), builds, runs the differential tests and the fuzz, restores. 15 faults took about 30 minutes. Survivors were dead code twice (delete it) and one stack overrun by a single lane that no test can observe (keep a spare lane and say so).

## 17. Before redesigning a hot loop, model it in C and calibrate (tl#673, 2026-11)

- **Model today's layout in C first.** Use OpenMP with 12 threads on the Ryzen 8500G. If that model lands within about 20% of the real Burst numbers, the same harness can price each alternative layout in minutes instead of days. For tl kinds it landed at 7.84 ms against 6.79 ms in Unity at 50k × 100.
- **Port the winner to C# with `Vector256` and match the state hash exactly.** Then time it on one pinned Zen4 core. In this work the .NET 10 JIT ran 1.35-1.42x slower than C. Do not assume parity.
- **Once a pass is memory-bound, compute tweaks do nothing.** Count the bytes. Two passes over 5M × 8-byte slots is 120 MB per step, near this machine's mixed read/write bandwidth. In the model, fusing the passes or halving the slot bought at most 1.6x. Not writing per-slot state at all bought 6x.
- **Time-relative origins.** A playing 1x timeline can be a `ushort` origin, with row = origin + world frame, so stepping writes nothing. Four tricks keep full control:
  - store a reversed layout, so reverse playback also advances +1;
  - keep two value tables, one per world direction, each row flagged at its end;
  - give tombstones a zero row, so slot order is kept;
  - put paused, rated and transient slots on an explicit side list.
  Prove it with a random-control oracle against an explicit-tick reference, and mutation-test the oracle.
- **Compare baselines on the same domain.** An "x over start" figure is only valid if the start was measured on the same kind domain. Check the command line behind every baseline number before you quote a ratio.
- **Size `InternalBufferCapacity` for the shape you will run.** A spike that reserved 100 inline slots per entity (264 B of chunk per entity) was fast at 50k × 100 but slower than main at 1M × 2-4: about 10 ns per entity, because chunk bytes per entity dominate at large N. Measured in Burst (tl.unity `exp/673-burst-origins`): at 1M × 2 a right-sized inline buffer ran 1.50 ms, capacity 100 3.61 ms, a heap buffer 2.71 ms, and a fixed 2-slot component with a compile-time count 1.17 ms, below the C model's 1.44 ms (`burst-performance.md`).
- **Tier-up can stall for the whole run, and only OSR saves loops.** Seen on tl#673: KindShape on .NET 10, pinned with `taskset -c 4`. A per-entity method called 10k times per step stayed `[QuickJitted]` in `perf` for the entire process, with no Tier1 version ever compiled, while loop-heavy callers were promoted through OSR. `DOTNET_TC_CallCountingDelayMs=0` moved main from 3.27 to 2.76 ms per step and the new path from 4.02 to 2.36 ms.
  - Mark per-entity kernels `[MethodImpl(MethodImplOptions.AggressiveOptimization)]`, or keep them inside an OSR'd loop.
  - Check perf's tier tags before you trust an A/B.
  - A method with `stackalloc` is compiled FullOpts up front (`[Optimized]`), not OSR.
- **Huge generated methods spill loop invariants.** The generated `Fused` reloaded about 10 stack slots per playback slot: clock, stride, masks, offsets and has-flags. Moving the inner accumulate (and the common-case `Apply`) into a small generated method, called once per 64-entity word, cut Movement from 11 to 8 ms at 50k × 100 and from 9.4 to 5.9 ms at 1M × 2, bit-identical.
- **A call anywhere in a hot loop spills the whole loop, even on a rare path (tl#673 R3).** The dense tick's commit loop called the exact-path methods only for the few entities leaving the dense path, and RyuJIT still kept every loop value on the stack. Stopping the call-free loop at the first such entity, making the calls outside it and resuming, with pulse-buffer room reserved up front so the push needs no grow check, took the KindShape tick from 3.4 to 2.46 ms at 1M × 4 and from 1.8 to 1.35 ms at 1M × 2, bit-identical.
- **Give a straight-line small-count kernel its own method, and keep its shape.** A `switch` with straight-line code for 1 to 4 slots inside the generic per-entity method made the generic path 20% slower at 100 slots (Movement 6.1 to 7.4 ms at 50k × 100). A separate `Small` method that returns the entities it did not take, followed by the unchanged generic method, kept 6.1 ms there and took 1M × 2 Movement from 5.6 to about 4.1 ms. Reading the count first and deferring larger counts before the totals were set up made 1M × 4 0.9 ms slower (10.85 to 11.8 ms in a same-session A/B); the `switch` on the count with a deferring `default` is the faster form. Skip the small kernel entirely when rows hold more than four inline slots: at 40 and 100 slots it only handed every entity back, and skipping it took 50k × 40 from 4.98 to 4.88 ms and 10k × 100 from 2.68 to 2.62 ms.
- **Moving pulse work from the consumer into the tick can lose.** Folding each pulse into a per-entity total during the dense tick, instead of pushing an 8-byte hit that the consumer walks, saved 0.1 to 0.6 ms of consumer time but cost the tick more: 1M × 2 6.10 to 6.27 ms and 1M × 4 10.79 to 11.13 ms in a same-session A/B, even with a call-free add. Price the producer side before moving work into it.
- **Software prefetch of 28 B rows made the loop slower.** `Sse.Prefetch0` of every row of an entity before combining took the loop from 8 to 11 ms at 50k × 100, Zen4, .NET 10. Padding rows to 32 B was neutral.
- **Fold random lookups into one record per row.** Tick work per due slot dropped from about 50 ns to about 6 ns after replacing several dependent table loads with one 8-byte "leave" record per (row, world direction): origin shift, pulse cell and kind-set index, gap. The two scattered 360 KB tables were what missed under streaming traffic.
- **Count mispredicts before going branch-free (tl#663).** Use a differential `perf stat -e cycles:u,instructions:u,branches:u,branch-misses:u`: two runs that differ only in the number of measured steps, so setup cancels.
  - KindShape on .NET 10 had about 54k mispredicts per step at 1M × 2, under 2% of cycles, at 4.1-4.6 IPC. The loop was bound by instruction count and latency.
  - Four branch-free forms of a priority pick were all slower than the predicted compare: an arithmetic max, a `Vector128` key max with a refetch of the winning row, a value carried by vector blend, and the row index carried in the key.
  - In a loop, `Math.Max(int, int)` compiled to `cmp` plus `jl`, not `cmov`.
  - The arithmetic max (`d = k - best; best += d & ~(d >> 31)`) is a 4-cycle chain carried across iterations.
  - `vpmaxsd` is a 1-cycle chain, but the dependent refetch of the winning row after the loop cost more at 2 slots per entity: about 55% of the kernel's samples.
- **Identity rows remove the presence branch exactly.** Write the monoid identity into absent rows: `-0f` for float sums, since `-0 + x == x` bit for bit, `+0` included. Then a float sum is one `vaddss` with a memory operand per slot. A `+0f` identity flips the sign of a lone `-0` value; an oracle with `-0f` clips catches it at step 1.
- **Never byte-compare two copies of a padded struct in .NET.** Once the JIT promotes the struct, its padding bytes are not preserved: a law check that compared `Speed { float; byte }` copies byte by byte passed in tier-0 and threw after tier-up. Compare the fields.
- **Split a two-direction value table into halves** with `Back = Front + Rows * Stride`. Readers that compute `row + (backward ? Back : Front)` stay unchanged, and a one-direction pass reads half the bytes. KindShape rows went from 28 B to 16 B.
- **Scan a whole word's dues at once only for narrow rows.** One `Vector256` pass over 64 entities' inline dues, with hits decoded by a reciprocal multiply, cut the 1M × 2 tick from 4.13 to 3.3 ms. At 100 slots per entity the per-hit decode lost, 3.12 to 4.82 ms, so keep the per-entity scan above 16 slots. A later form that gathers every due record of the word into scratch, checks them while gathering and commits in a call-free loop also won at 40 slots per entity (KindShape 50k × 40 5.2 to 5.0 ms, 10k × 40 1.43 to 1.30, same-session A/B); 100 slots in that form is untested.
- **A deferred-buffer fast path needs a reference that does not defer.** Two worlds that share the flush code (dense against explicit, both with pulse hits) cannot see the flush order. Pin it against a world that keeps every pulse as an entry when it fires (tl `KindStore.PulseHitsEnabled = false`). Use a non-associative float sum (1, 1e8, -1e8) and an order-sensitive `Each` apply, with a consumer that skips a step while game pulses wait. Keep the pulse values independent of the tick: entry-path pulses are evaluated when consumed, so tick-dependent values differ for reasons other than order (tl#673, `FlushedHitsKeepTheExplicitEntryOrderWhenTheConsumerSkipsAStep`).
- **A test host that reads a settling view every step hides stale-tick bugs.** A dense-path guard showed nothing until a system holding only a pulse kind ran first and skipped steps. Until then, another kind's value walk in the same system had settled every dense entity before the pulse walk read its ticks.
