---
name: unity-cli-field-notes
description: Field-tested rules for AI agents working on Unity projects from a terminal - pick batch mode or the live Editor, run tests and builds headless with one script, reuse one scratch project, clean up disk, avoid false greens, and the ECS/baking facts agents get wrong. Use before compiling, testing, building or probing any Unity project, with the official unity-cli skill for live-Editor commands. Verified on Unity 7000.0.0a12 (Linux) and 7000.0.0a16 (Windows 11), Entities 6.7.0 and 7.0.0, Unity CLI 1.0.0-beta.13 to 15.
---

# Unity field notes for agents

Read once, top to bottom. Every line cost someone hours.

## 0. Give back (every agent, every time)

- **You learned or solved something about Unity, the CLI, ECS or its tooling?** Add one verified line to the right section here and push to `main` before you finish. Find the repo with `git -C "$(dirname "$(readlink -f <this SKILL.md>)")" rev-parse --show-toplevel`, or clone `IAFahim/unity-cli-skill`. Rules: `CONTRIBUTING.md`.
- **Stuck after two honest attempts?** Don't guess a third time: `scripts/ask.sh "<question>" body.md` files a `question` issue (versions, minimal repro, exact error, what you tried). Stronger models answer those and fold the answers back in here.
- The repo is public: no secrets, private code, customer names or personal paths.

## 0b. Workflow (mandatory, it saves tokens)

1. **Finish locally first.** Implement everything the task needs, run the full local Unity tests (section 2), and only then push and wait for CI. CI is the last check, never the debugger, and not the priority: do not work on CI or runner setup unless the owner asks, solve the current local task only.
2. **Right-size the model.** Hard work goes to the strongest model: performance and benchmark analysis, diagnosing a failure whose cause is unknown, ECS/Burst/job design, anything a plan calls a gate. Mechanical work goes to a smaller or cheaper one: porting scripts between OSes, CI and workflow wiring, adding tests, restacking branches, doc and skill updates. Do not spend the strong model on mechanical work, and do not give the small one a gate to judge.
3. **One brief per agent, no overlap.** Each agent owns different files and its own branch or worktree. Name the files it must not touch. Every brief carries: the goal and the "done" check, the exact tools and paths on this machine, the issue numbers to read, and the report format (short, numbers and commit hashes, not logs).
4. **One Unity at a time per machine.** Two batch Editors at once make every benchmark noise and fight over CPU. Take a lock (create a directory such as `_work/unity.lock`; it fails if held) before any Unity process and remove it the moment that process exits.
5. **Look it up before asking or guessing.** Read this file and the linked issues first. Many failures here are already solved (for example the 48 B allocation test, section 4).
6. **Report short.** Final reports give: what works (commands), counts, commit hashes, what is not verified, what the owner must decide. No pasted logs.
7. **Do not push, comment or merge** unless the owner asked in this task. Commit on a local branch and say so.

## 1. First minute: look before you launch

```bash
pgrep -af '[U]nity/Hub/Editor|Editor/Unity' | cut -c1-200   # who is running, on which -projectPath
ls <project>/Temp/UnityLockfile 2>/dev/null                 # exists = that project is open
```

- **One Editor per project path, ever.** A second launch on the same path aborts ("another Unity instance is running"). Never kill an Editor you did not start; it is the person's.
- **Never open an interactive (windowed) Editor to compile or test.** You cannot see it, it waits for focus, and you will wait for hours. Use batch mode (section 2).
- Use the live Editor (official `unity-cli` skill, `unity command ...`) only when the person has it open and the task is about that Editor: its scene, its Inspector, Play mode they watch.

## 2. Batch mode: compile, test, build, run code

`scripts/unity-batch.sh <project> <op>...` wraps this and prints one line per op: `exit errorCS passed/failed`.

```bash
U=~/Unity/Hub/Editor/<version>/Editor/Unity
$U -batchmode -nographics -projectPath /abs/p -runTests -testPlatform EditMode -testResults /abs/r.xml -logFile /abs/r.log   # NO -quit with -runTests
$U -batchmode -nographics -quit -projectPath /abs/p -executeMethod Ns.Class.Method -logFile /abs/m.log                     # -quit for executeMethod
$U -batchmode -nographics -quit -projectPath /abs/p -logFile /abs/c.log                                                  # compile only
```

- Exit codes: 0 ok, 2 tests failed, 1 error (compile error, exception, license). Read them directly; **`| tail` eats the exit code.**
- **Always absolute paths** for `-testResults` and `-logFile`. A relative `-testResults` is resolved against the project, writes elsewhere, and you read a stale XML.
- Proof = `grep -c 'error CS' log` is 0 **and** the XML `<test-run total passed failed>` counts are what you expect. "exit 0" alone is not proof.
- First import of a fresh project takes minutes; later runs take ~1 min. Run long ops in the background and do other work; don't poll in a loop.
- PlayMode tests run in the same batch Editor. Frames are ~1 ms there: **wait on wall-clock time** (`Time.realtimeSinceStartup`), never on a frame count, for subscene streaming or FixedStep ticks.
- IL2CPP player: `BuildPipeline.BuildPlayer` from an `-executeMethod`, then run `./Game.x86_64 -batchmode -nographics -logFile /abs/p.log` and grep your own result line; call `Application.Quit(code)` in the player.
- `unity test <project> --editor-path <Editor/Unity> --mode EditMode --filter Class.Method --output /abs/r.xml -- -logFile /abs/l.log` is the CLI form. Unity exit 2 (tests failed) returns CLI exit 8; CLI exit 6 "Test run did not complete" means Unity exited 1 before results, so `grep 'error CS'` the log. With a warm `Library/`, `--filter` reruns one test in about a minute. Unity 7000.0.0a12 ran a project pinned to 6000.7.0a6 this way.

### CI on a self-hosted runner

- A runner started from a desktop session has a minimal `PATH` (no `~/.local/bin`), so `unity` fails with exit 127. Resolve the CLI explicitly (env override, then `PATH`, then its install dir) and pass `--editor-path`.
- Never hardcode an editor version in a CI script; the path rots when editors are swapped. Pick the project's pinned editor if installed, else the newest. The editor bundles Mono at `<Editor>/Data/MonoBleedingEdge/bin/mono` (6.13 on 7000.0.0a12), which runs `dotnet build` netstandard2.1 dlls, so CI needs no system Mono.
- The runner reuses one workspace: the next queued job overwrites `-logFile` and results files while you read them. Compare timestamps to your job's, or `gh run download` the artifact of your exact run.

### Windows and Unity 7000.0.0a16 (verified)

- Run shell scripts through Git Bash (`& "C:\Program Files\Git\bin\bash.exe" script.sh`); `bash` is not on the PowerShell PATH. Convert paths with `cygpath -m` before giving them to Unity or a manifest `file:` entry. `python3` is a Windows Store stub: use `python`, or parse XML with sed.
- Git Bash with autocrlf gives CRLF working trees. Scripts still run; compare files with `diff --strip-trailing-cr`.
- a16 ships built-in Entities 7.0.0, Collections 7.0.0, Burst 2.0.0, test-framework 1.9.0 and performance 7.0.0; the older manifest pins are overridden. Burst 2.0 turns some old patterns into errors (BC1064).
- `Baker.GetComponents<T>()` (array overload) throws "Unknown Type" for a `MonoBehaviour` not registered with the TypeManager; the `List<T>` overload works.
- A fresh project plus the first EditMode run takes a few minutes on a 6-core machine.

## 3. One scratch project, reused, cleaned

- Make **one** test project per Unity version, and reuse it. Point it at the package you are changing with `"com.x": "file:/abs/path/to/checkout/com.x"` plus `"testables": ["com.x"]` in `Packages/manifest.json`. **Never copy the package** into the project: copies drift and you test old code.
- Switch branches by repointing the `file:` path; the warm `Library/` makes the next run fast.
- Scratch helper scripts go in the scratch project's `Assets/`, never in the package. Delete them when done.
- **Test the package the way a user installs it**: a fresh project whose only dependency is the package. If it compiles only because something sits in your scratch `Assets/`, the package is broken. Ship what it needs, for example a vendored assembly with an asmdef and a sync script that has a `--check` mode.
- A new git worktree has **empty submodules**: `git submodule update --init --reference <local clone> <path>`.
- **Clean up before you finish**: delete `Builds/`, scratch projects you created, stale copies, and IL2CPP output (`Library/Bee`, `Library/Il2cppBuildCache`). Check `df -h /tmp ~` first and last. A test project is ~3 GB; an IL2CPP build adds 1-2 GB.

## 4. False greens (each one has fooled an agent)

- **Stale domain**: one compile error anywhere keeps the old assemblies loaded, so old code runs and old test counts appear. Check `error CS` = 0 before trusting anything.
- **Console is not the log**: `console get` can be empty while `Editor.log` (or your `-logFile`) has the errors. Read the log.
- **Stale bakes**: subscenes serve old baked data. After changing a baker or authoring asset, force reimport (`AssetDatabase.ImportAsset(p, ForceUpdate | ForceSynchronousImport)`) and check one baked component exists in the live world.
- **Hand-built worlds prove little**: a test that builds a `World` and calls `system.Update()` by hand skips auto-created systems, group order and singletons. Prove the default world at least once (a PlayMode test that loads a scene with a SubScene).
- **Ask the Editor, not the YAML**: inherited prefab components and overrides are invisible in files. Cross-prefab references serialize to `{fileID: 0}` without a warning.
- Never delete scene or prefab content to silence an error.
- Unity 7000.0.0a12: the editor runs CoreCLR (NUnit XML `clr-version` 10.0.x) and `GC.GetAllocatedBytesForCurrentThread()` is exact, so `Assert.AreEqual(0, GC.GetAllocatedBytesForCurrentThread()-before)` reads 48 B even for allocation-free code (it boxes its arguments before the second read; `Assert.That(.., Is.EqualTo(0))` reads 24). Compute the delta into a local first, then assert.
- Unity 7000.0.0a16 gives the same 48 B: probe loop reads 48 B with the inline form, 0 B with the delta stored in a local first.
- `[Licensing::Client] Error: HandshakeResponse` and `Failed to handshake to channel` appear in the Editor log of passing batch runs too (it then connects to its own licensing client). Judge by the NUnit XML counts and the exit code, not by those lines.

## 5. ECS and baking facts agents get wrong

- Every `SystemBase`/`ISystem` in every loaded assembly is **auto-created in the default world** unless `[DisableAutoCreation]`. A system that calls `GetSingleton<T>()` must `RequireForUpdate<T>()` in `OnCreate`, or it throws every frame once its query matches.
- Broad queries catch your entities too. To exclude an **enableable** component use `Absent` (`WithAbsent<T>()`); `None` also matches entities where it is present but disabled.
- Order your systems explicitly (`[UpdateInGroup]`, `[UpdateAfter]`); group membership is not order.
- Authoring `MonoBehaviour`s must live in a **runtime** assembly (Editor-assembly scripts cannot be added to GameObjects). `Baker<T>` needs a reference to `Unity.Entities.Hybrid`. Bakers may live in Editor assemblies.
- Folders ending in `~` (`Tools~`, `Samples~`, `Documentation~`) are **never compiled** by Unity.
- Baker has only the generic `SetComponentEnabled<T>`; for runtime `ComponentType`s set enable bits in a `[WorldSystemFilter(WorldSystemFilterFlags.BakingSystem)]` system, which also sees every baker's output (good for validation).
- `[BakingType]` components are stripped from the game world; runtime subscene entities have **no names** (`GetName` returns ""). Find entities by components, not names.
- Subscene loading is asynchronous. Baking in an EditMode test without scenes: reflect `Unity.Entities.BakingUtility.BakeGameObjects(world, roots, settings)` (internal; `BakingSettings(flags, blobAssetStore)`).
- On Unity 7, core Entities types (`EntityArchetype`, `EntityQuery`) live in the engine. Their source is not in the package cache, so check the API by compiling.
- Inside a namespace like `Tl.Unity`, the name `Unity.X` binds to `Tl.Unity.X`. Write `global::Unity.Entities...` (source generators hit this too).
- Unity 7 analyzers want cleanup semantics on statics (UAL0010/UAL0013). With domain reload off, statics survive between Play sessions: reset or dispose them in `[RuntimeInitializeOnLoadMethod(SubsystemRegistration)]`, mark the type `[NoAutoStaticsCleanup]` under `#if UNITY_7000_0_OR_NEWER`, and silence the analyzers only for vendored pure-.NET code via its `csc.rsp` (`-nowarn:`).

### Baking and editor gotchas

- A baking system sees every entity on every incremental bake. Data that only the baking system should see per baker run belongs in `[TemporaryBakingType]` (it exists only in the pass where that baker ran). Its query needs `IncludePrefab | IncludeDisabledEntities`, or prefabs and inactive GameObjects skip it.
- A baker that reads a file must `DependsOn(AssetDatabase.LoadAssetAtPath<Object>(path))`, or editing the file never rebakes.
- Generated system queries usually require **every** column of the system. Validate an entity against the query, not against what one feature uses.
- Change filters: `chunk.DidChange(ref handle, LastSystemVersion)`, checked **before** taking a read-write accessor (that marks the chunk changed). The system's own writes don't retrigger it.
- `World.All` includes the Editor's conversion, shadow and staging worlds. Skip `WorldFlags.Conversion | Shadow | Staging` in tools.
- Editor hooks: never call `AssetDatabase.Refresh` inside `OnPostprocessAllAssets`; defer with `EditorApplication.delayCall` (which never fires in batch mode). `[InitializeOnLoad]` also runs in asset import workers, so guard with `AssetDatabase.IsAssetImportWorkerProcess()`.
- External processes from the Editor: use `ProcessStartInfo.ArgumentList`, not a hand-quoted string. Read stderr asynchronously while reading stdout, and `WaitForExit(timeout)`. Otherwise a chatty or hung tool freezes the Editor.
- Benchmarks in batch mode: the first run in a fresh Editor is cold (2-3x slower). Run twice, take the later run or a median of several, and treat ±0.5 ns/entity as noise unless repeated.
- Editor Burst safety checks dominate idle-row benchmarks (a16: B 1.9 ns with them, 1.3-1.4 without). A job with many type handles pays about 54 ns per chunk in safety checking, so keep rarely used handles out of it. Judge a Unity gate against the .NET number measured on the same machine that day, not a number from another machine.
- A disturbed run shows in the empty-world step time (13.9 µs against a normal 4.7-9.4): discard runs where it jumps.

## 6. Small tools that save hours

- A .NET tool that reflects over a Unity-compiled dll needs its references next to it. Copy `Library/ScriptAssemblies/*.dll` and `<Editor>/Data/Managed/UnityEngine/*.dll` into one folder with the dll, then load from there.
- `unity-cli exec` (if used) caches compiled payloads: keep each payload short and check the output is yours.
- Read `Packages/manifest.json` and asmdef references before guessing a type's assembly. If a guessed API fails to compile once, open the source or compile a probe; don't guess twice.
- Test asmdefs compile against a netstandard profile: `MethodImplOptions.AggressiveOptimization` (CS0117) and `System.Runtime.JitInfo` (CS0234) are missing there. Use `(MethodImplOptions)512`, and reflect `JitInfo.GetCompiledMethodCount` off `typeof(object).Assembly` (Unity 7000.0.0a12 has it at runtime).
- Unity 7000.0.0a12: `DOTNET_*` runtime knobs such as `DOTNET_TieredCompilation=0` reach the editor (JIT method counts changed), so JIT-behavior experiments need no code change.

## 7. Live Editor (official CLI), condensed

- Connect: `unity --no-banner status --json`, then `unity --no-banner pipeline editors`. No package: `unity pipeline install --project-path <p>`, then the **window must be focused** before it connects (Linux: minutes of silence otherwise).
- Call: `unity --no-banner command --caller plugin --skill <skill> <group> <verb> --flag v`; discover with `unity command` and `unity command <group>`. Use `--result-only` for JSON.
- Recompiles drop the connection mid-call (`Invalid response format`, `No Pipeline instance`). Verify the effect, wait with `scripts/wait-ready.sh` (exit 2 = compile failure), retry only if it did not apply. Add packages one at a time.
- `script eval --code '...; return x;'` with fully qualified names; `script eval_file --file f.cs` for longer probes.
- Details and evidence: `references/corrections.md`.

## Done means

You ran it, you read the counts, the person's own walk works (open the scene, press Play, see it), nothing of yours is left in their scenes or disk, and you said plainly what you did not verify.
