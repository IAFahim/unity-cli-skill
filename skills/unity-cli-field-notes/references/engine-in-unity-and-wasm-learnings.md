# Learned bringing a deterministic C# engine into Unity 7 and the browser (all verified, Unity 7000.0.0a16 on Linux, .NET 10.0.403)

## Unity batch on Linux
- `-projectPath` needs an `Assets` folder: a project dir with only `Packages/` and `ProjectSettings/` aborts with "Couldn't set project path to: ..." (the message shows the path doubled when the path is absolute). `mkdir Assets` fixes it. A hand-made project (`ProjectSettings/ProjectVersion.txt` with `m_EditorVersion`, `Packages/manifest.json`, empty `Assets`) is enough; first import takes about a minute.
- A test assembly with `"includePlatforms": []` is a PlayMode assembly; `-testPlatform EditMode` runs 0 of its tests and says nothing. Use `"includePlatforms": ["Editor"]`.
- NUnit `[TestCaseSource]` cannot be combined with `[Values]` on the same test (runs with "Not enough arguments"); put every parameter in the `TestCaseData`.
- `BurstCompiler.Options.EnableBurstCompilation = false` set after a job type was first scheduled does not make it run managed (compiled state is cached per job type) and `--burst-disable-compilation` is not accepted by this editor (exit 2, no XML). Prove a Burst probe can fail by calling the probe method from managed test code and expecting the managed value.
- Engine code that uses `Buffer.MemoryCopy` and `Span<T>.Clear` (netstandard2.1 `Memory.Copy`/`Clear` helpers) compiled and ran inside `[BurstCompile]` jobs with 0 `error BC` and probe = Burst, so no `UnsafeUtility.MemCpy` fallback is needed.
- Unity does not read `<Nullable>`; a `csc.rsp` with `-nullable:enable` next to every asmdef (runtime, editor, tests) removes the CS8632 warnings.
- A copy of the working tree plus a new project with no `Library` is a quick stand-in for the fresh-clone gate; confirm once with a real `git clone` at the end.

## Cross-platform generated output
- A generated file that records character offsets into an authored text file (here a rule map) changes with CRLF vs LF checkouts. Pin the authored files with `.gitattributes` (`*.sv.json text eol=lf`) and regenerate the committed output.
- A checksum list built with `sort` depends on the locale (`en_US` vs the Windows run that wrote it): `export LC_ALL=C` in the sync script.

## WASM (browser-wasm) from .NET 10
- `Microsoft.NET.Sdk.WebAssembly` refuses to build without the `wasm-tools` workload (NETSDK1147) even with AOT and native relink off. When the system SDK's workload state is root-owned (`dotnet workload restore` says access denied), install a user-local SDK of the same version: `dotnet-install.sh --version <sdk> --install-dir <dir>`, put it first on `PATH` with `DOTNET_ROOT`, then `dotnet workload install wasm-tools` there.
- A browser-wasm app cannot reference a console/exe project (NETSDK1150); link the few needed source files with `<Compile Include=... Link=...>` or move them to a library.
- `InvariantGlobalization=true` requires `WasmBuildNative` to be left at its default (setting it false is an error). `[JSExport]` call sites need `[assembly: SupportedOSPlatform("browser")]` or CA1416 fails a warnings-as-errors build.
- Trimmed, non-AOT publish of a compiler plus reference interpreter was 5.8 MB; first simulate of a small scenario took 54 ms in the built-in browser. Serve `bin/.../wwwroot` with `python3 -m http.server` (it serves `.wasm` correctly).
- Content files from outside the project can be published under `wwwroot` with `<Content Include="..\x.json" Link="wwwroot\samples\x.json" />`.

## Shell
- `pkill -f 'http.server 8123'` matches the shell running the command and kills it (exit 144); stop a server by pid from `ss -ltnp`.
- A pack tool that skips regeneration when its input key is unchanged ignores changes in the emitter code: delete the output folder when you change the emitter.

## Profiling and measuring .NET hot loops on Linux
- `perf` shows no managed symbols unless the process runs with `DOTNET_EnableWriteXorExecute=0`; add `DOTNET_PerfMapEnabled=1` for symbols, or jitdump (`DOTNET_PerfMapEnabled=1` plus `perf record -k 1`, then `perf inject --jit`) for per-instruction annotation.
- A phase that is memory-bandwidth-bound moves its cache misses to the next phase when you skip a pass (seal -0.12 ms, decide +0.11 ms): only keep a change when the whole-frame median improves.
- Compare old and new builds interleaved in one session, median of several processes, under the bench lock; a run-to-run drift of 5-10% on this box is bigger than most micro-wins. Under 3% total: revert it.
- A script that pipes the bench into `head` can be killed before its `rmdir` and leave a stale lock; trap the unlock.
- Saturating 64-bit products over lanes that provably fit in 2^31 are cheaper as plain `long` multiplies (measured B commit 1.41 -> 0.67 ms); background on 64-bit vector multiply: dotnet/runtime PR 103555.

## tl in Unity (plain host)
- `Tl.Gen.Plain.dll` (plain-host generator, tl-kinds a15ea149) emits nothing for an assembly that declares no `[TimelineSystem]` struct, so zero-config-only code (`[TlState]`, `[TlKind]`, `ITlTrack`, e.g. sv `--glue tl`) gets no `Tl.Generated.TlAuto_<Asm>`. Add one empty `[TimelineSystem] public ref partial struct` and it emits `TlAuto_<Asm>` byte-identical to tl's .NET generator output.
- A baked library records the clip type's assembly name in its metadata: name the Unity glue assembly like the host's (sv `Sv.NorthStar3`) or the bytes differ.
- Keep `com.tl.unity` a plain manifest dependency, not under `testables`, so its own test assemblies (a kind registered twice) never compile; gate your tl assemblies with `versionDefines` on the package so a project without tl still builds.
- `.gitattributes` `text eol=lf` rules on a package folder rewrite bytes inside committed `*.dll` and `*.bytes`: add `binary` lines for them.

## Worker pools and software prefetch
- A `Workers` pool whose threads read the generation counter on their own thread can miss the first `Run` when a worker starts late, and `Run` then spins forever (seen as an 11-minute hang under `DOTNET_EnableHWIntrinsic=0`; a memory dump confirmed it). Read the counter in the constructor (sv 03edc9e, issue 0372).
- In a scalar Decide kernel, software prefetch loops (source rows, next chunk's table entries, two chunks ahead in Seal order) each cost more than they saved; a small per-frame table (24 B per chunk, one parallel build phase of 0.17 ms) that replaces three dependent loads with one won 11 percent. Measure a prefetch against the replacement-by-table before writing it.

## Benchmarks and tests on stale generated kernels
- A test or bench project that generates its kernels at build time (`build/Sv.Pack.targets`, output `obj/SvPack`) can run the previous emitter's kernels under a new host: the incremental target listed only the tool's `sv.dll` as input, not `Sv.Rules.dll` (the emitter), and the tool itself skips an unchanged pack. Symptom: digests identical, suites green, but a phase gets slower (B commit 0.2 -> 1.2 ms) and a claimed gain does not reproduce. Check `stat` of `obj/SvPack/Kernels.g.cs` against the emitter dll, delete `obj/SvPack/.svpack.key`, rebuild. sv now lists every dll of the tool folder as input.
- When an agent's number does not reproduce, bisect with detached worktrees of its commits built in scratch before blaming the code: here its tip was fine and my checkout was stale.

## Checking an outside perf recommendation on this box (Ryzen 5 8500G, Linux, THP always, defrag madvise)
- With THP `always` and `defrag=madvise`, a 1 GB .NET process had only 30 percent huge pages; `madvise(MADV_HUGEPAGE)` after `NativeMemory.Alloc` of big blocks barely raised it (glibc's mmap'd chunks are not 2 MB aligned and are often touched before the advice), and frame time did not move. Measure `AnonHugePages` in `/proc/<pid>/smaps_rollup` before believing a huge-page gain.
- Fewer workers (6 of 11) for "bandwidth-bound" phases made those phases slower on this 2 x Zen 4 + 4 x Zen 4c part; test the claim, do not assume SMT is useless for streaming passes.
- `perf stat -e instructions,cycles,branch-misses,branches` works in user mode (paranoid 2) and settles "is it speculation?" in one run (here IPC 1.8, misses 2 percent of branches).

## "Allocates nothing on any thread" tests under xunit
- `GC.GetTotalAllocatedBytes(true)` inside an xunit test counts the test host's own threads (message bus, vstest result channel); an EventPipe trace with `Microsoft-Windows-DotNETRuntime:0x280001:5` (GCSampledObjectAllocationHigh + Type + GC, via `DOTNET_EnableEventPipe=1`, `DOTNET_EventPipeOutputPath=...{pid}.nettrace`) shows them. Tiered compilation was not the cause (`DOTNET_TieredCompilation=0` still flaked). Measure the engine's own threads instead: each worker stores `GC.GetAllocatedBytesForCurrentThread()` at the end of its share of a Run, and the test sums main + workers (sv e022a9d, issue 0371). Prove it with a negative control (a worker-only allocation must fail the test).
- A warm check that takes one sample flakes on a loaded box; take the minimum of three measured runs: a real warm leak allocates every run.

## Release hygiene learned on sv v3 (2026-11-14)
- Check what CI actually builds before calling it green: sv's `determinism` workflow ran `dotnet test sv.slnx`, and the solution held only the old engine, so "green on six hosts" said nothing about v3. List the solution's projects against `find . -name '*.csproj'` and check a sibling repo the tests need (tl) is checked out in CI at a pinned commit.
- Struct padding is not zeroed in C#: a `byte` field before a `float`/`long` leaves bytes holding stack garbage, and any raw `memcpy`/hash/save of such structs is nondeterministic. It showed only on contended or ARM64 runners; `taskset -c 0,1 dotnet test` reproduced it locally; `MALLOC_PERTURB_` does not (it is stack, not heap). Fix with explicit zeroed padding fields and a guard test that the field sizes add up to `Unsafe.SizeOf<T>()`.
- `-p:DefineConstants=X` on the command line replaces the SDK's constants (`NET`, `NET10_0` ...), so code silently builds its netstandard fallbacks; append instead with a property in `Directory.Build.props` (`<DefineConstants>$(DefineConstants);X</DefineConstants>` under a condition).
- A build-time code generator target must run after `ResolveProjectReferences` (not at `BeforeBuild`), or a parallel solution build can run a stale or missing tool; and its own skip key must include the generator's build id (MVID), or generator changes never regenerate.
- Unity installs a package from a subfolder of a private git repo with `https://github.com/<o>/<r>.git?path=/packages/<name>#<tag>` using the local git credential helper; the project manifest entry overrides the version dependency another package declares. Prove it with `packages-lock.json` (`source: git`, hash).
- A generated enum named `Event` collides with `UnityEngine.Event` in MonoBehaviours (CS0104); use an alias `using Event = <ns>.Event;`. Inside `namespace Hello`, a generated `Hello.Sv` namespace also shadows a top-level `Sv` namespace: put `using` directives at file top.
