---
name: unity-cli-field-notes
description: Field-tested rules for AI agents working on Unity projects from a terminal - pick batch mode or the live Editor, run tests and builds headless with one script, reuse one scratch project, clean up disk, avoid false greens, and the ECS/baking facts agents get wrong. Use before compiling, testing, building or probing any Unity project, with the official unity-cli skill for live-Editor commands. Verified on the newest Unity 7 editor (Linux and Windows 11), Entities 6.7.0 and 7.0.0, Unity CLI 1.0.0-beta.13 to 15.
---

# Unity field notes for agents

Read once, top to bottom. Every line cost someone hours.

## Owner rules (every agent, every brief starts with rule 1)

1. **Before any work** pull this repo (`git -C <clone of IAFahim/unity-cli-skill> pull --ff-only`, clone it if missing; see `references/new-pc-setup.md`) and read this file. **Before you finish**, push what you learned back to `main` here (one verified line in the right section; `CONTRIBUTING.md`).
2. **Newest Unity 7 editor only.** Install a newer one by name with the CLI (`unity install 7 --yes --accept-eula`); never test, pin or mention older versions. Scripts pick the newest installed editor.
3. **Finish and test locally first.** CI is not a priority; do not work on CI or runners unless asked.
4. **Direct pushes to `main` are authorized** in IAFahim repos (`git pull --rebase origin main`, `git push origin HEAD:main`, never `--force`).
5. **Manage, delegate, right-size**: strongest model for performance and diagnosis, a small one for mechanical work. One brief per agent with file ownership, own worktree. Detail: `references/workflow.md`.
6. **One Unity process at a time**: take the lock directory (`mkdir _work/unity.lock` fails if held), remove it when Unity exits.
7. **Short reports** (commands, counts, shas, what is unverified). **No code comments** in these repos.
8. **Never hand-write or hand-edit Unity-serialized files** (`.asset`, `.unity`, `.prefab`, `.mat`, `.meta`, ProjectSettings YAML): it silently corrupts references (`fileID: 0`) and causes slow reimport loops. Create them through Unity: an editor script in the scratch project's `Assets/Editor` (never the package) run with `-batchmode -nographics -quit -executeMethod`, or a headless Editor driven by `unity command eval`. Verified recipes: `references/headless-assets.md`.
9. **Unity ECS: `ISystem`, `IJobEntity`/`IJobChunk`, Burst, unmanaged data only.** Never `SystemBase`, managed components, GameObject lookups or other managed or hard-coded workarounds. The whole Tl hot path and every lib we use is unmanaged; managed code only in editor tooling, authoring and bakers. Needing a workaround means Tl or the lib lacks something: stop, `gh issue create` in that repo (minimal repro, missing API), tell the owner. Detail: `references/unity-ecs-rules.md`.
10. **Designers wire references in the Inspector** (drag and drop on authoring components and ScriptableObjects). Never by name or path in runtime or authoring flow: no `AssetDatabase.Load*`, `Resources.Load`, Find-by-name. Only tests and editor-only tooling may.
11. **Any Unity task**: make sure the project's own `AGENTS.md`/`CLAUDE.md` has a "Start here" pointing to this skill plus these hard rules; add it if missing, commit, push.
12. Stuck after two honest attempts: `scripts/ask.sh "<question>" body.md` files a `question` issue (versions, repro, exact error, what you tried). The repo is public: no secrets or personal paths.
13. **Cross-machine work goes through GitHub issues, never the owner as relay.** Before starting, check open issues labelled with your OS (`gh issue list --repo IAFahim/<repo> --label <windows|linux>`). On a cross-machine problem open or comment on one with repro, expected vs actual, logs and the command that proves it; claim by commenting; post root cause and commit shas when fixed; the other machine verifies and comments the result. Example: IAFahim/tl#576 (Linux demo step 10).

## 1. First minute: look before you launch

```bash
pgrep -af '[U]nity/Hub/Editor|Editor/Unity' | cut -c1-200   # who is running, on which -projectPath
ls <project>/Temp/UnityLockfile 2>/dev/null                 # exists = that project is open
```

- **One Editor per project path, ever.** A second launch on the same path aborts ("another Unity instance is running"). Never kill an Editor you did not start; it is the person's.
- **Never open a windowed Editor yourself.** You cannot see it and it waits for focus. Run headless: batch mode (section 2), or a resident `-batchmode` Editor you drive with the CLI (section 7).
- Drive an Editor the person already has open (`unity command ...`) only when the task is about that Editor: its scene, its Inspector, Play mode they watch.

## 2. Batch mode: compile, test, build, run code

`scripts/unity-batch.sh <project> <op>...` wraps this and prints one line per op: `exit errorCS passed/failed`.

```bash
U=<newest ~/Unity/Hub/Editor/*/Editor/Unity>
$U -batchmode -nographics -projectPath /abs/p -runTests -testPlatform EditMode -testResults /abs/r.xml -logFile /abs/r.log   # NO -quit with -runTests
$U -batchmode -nographics -quit -projectPath /abs/p -executeMethod Ns.Class.Method -logFile /abs/m.log                     # -quit for executeMethod
$U -batchmode -nographics -quit -projectPath /abs/p -logFile /abs/c.log                                                  # compile only
```

- Exit codes: 0 ok, 2 tests failed, 1 error (compile error, exception, license). Read them directly; **`| tail` eats the exit code.**
- **Always absolute paths** for `-testResults` and `-logFile`. A relative `-testResults` is resolved against the project, writes elsewhere, and you read a stale XML.
- Proof = `grep -c 'error CS' log` is 0 **and** the XML `<test-run total passed failed>` counts are what you expect. "exit 0" alone is not proof.
- First import of a fresh project takes minutes; later runs take ~1 min. Run long ops in the background and do other work; don't poll in a loop.
- PlayMode tests run in the same batch Editor. Frames are ~1 ms there: **wait on wall-clock time** (`Time.realtimeSinceStartup`), never on a frame count, for subscene streaming or FixedStep ticks.
- CoreCLR player (Unity 7): `PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.CoreCLR)` (enum values on 7000.0.0a16: `Mono2x, IL2CPP, WinRTDotNET, CoreCLR`); the build folder has `Managed/` and `CoreCLR/`, an IL2CPP one has `GameAssembly.dll`. Both Windows variations ship with the editor. SubScenes bake at build time with no extra step (Force demo verified on both backends).
- IL2CPP player: `BuildPipeline.BuildPlayer` from an `-executeMethod`, then run `./Game.x86_64 -batchmode -nographics -logFile /abs/p.log` and grep your own result line; call `Application.Quit(code)` in the player.
- CLI form: `unity test <project> --editor-path <Editor/Unity> --mode EditMode --filter Class.Method --output /abs/r.xml -- -logFile /abs/l.log` (exit codes in `references/windows-and-ci.md`).

Windows, CI and runner notes: `references/windows-and-ci.md`. How releases publish: `references/release.md`.

## 3. One scratch project, reused, cleaned

- Make **one** test project per Unity version, and reuse it. Point it at the package you are changing with `"com.x": "file:/abs/path/to/checkout/com.x"` plus `"testables": ["com.x"]` in `Packages/manifest.json`. **Never copy the package** into the project: copies drift and you test old code.
- Switch branches by repointing the `file:` path; the warm `Library/` makes the next run fast.
- Scratch helper scripts go in the scratch project's `Assets/`, never in the package. Delete them when done.
- **Test the package the way a user installs it**: a fresh project whose only dependency is the package. If it compiles only because something sits in your scratch `Assets/`, the package is broken. Ship what it needs, for example a vendored assembly with an asmdef and a sync script that has a `--check` mode.
- A vendored dll's `--check` must not compare rebuilt bytes: the same sources give different bytes per SDK, OS and checkout line endings (`core.autocrlf`). Commit a stamp of the pinned submodule commit, a CR-stripped `git hash-object --stdin` hash of the sources and the dll hashes, and compare that.
- A new git worktree has **empty submodules**: `git submodule update --init --reference <local clone> <path>`.
- **Clean up before you finish**: delete `Builds/`, scratch projects you created, stale copies, and IL2CPP output (`Library/Bee`, `Library/Il2cppBuildCache`). Check `df -h /tmp ~` first and last. A test project is ~3 GB; an IL2CPP build adds 1-2 GB.

## 4. False greens (each one has fooled an agent)

- **Stale domain**: one compile error anywhere keeps the old assemblies loaded, so old code runs and old test counts appear. Check `error CS` = 0 before trusting anything.
- **Console is not the log**: `console get` can be empty while `Editor.log` (or your `-logFile`) has the errors. Read the log.
- **Stale bakes**: subscenes serve old baked data. After changing a baker or authoring asset, force reimport (`AssetDatabase.ImportAsset(p, ForceUpdate | ForceSynchronousImport)`) and check one baked component exists in the live world.
- **Hand-built worlds prove little**: a test that builds a `World` and calls `system.Update()` by hand skips auto-created systems, group order and singletons. Prove the default world at least once (a PlayMode test that loads a scene with a SubScene).
- **Ask the Editor, not the YAML**: inherited prefab components and overrides are invisible in files. Cross-prefab references serialize to `{fileID: 0}` without a warning.
- Never delete scene or prefab content to silence an error.
- Restoring a file with `mv file.bak file` (or `cp -p`) keeps the backup's older mtime, so the next incremental `dotnet build` skips it and the tests run the stale dll; `touch` the file after restoring it. Take the Unity lock with `mkdir lock && <unity ...>`, never `mkdir lock; <unity ...>` (the `;` launches Unity even when the lock is held).
- Two tl.unity samples in one project interfere: with the EcsDemo (old `TimelineLibraryBootstrap` path) and the Force demo (zero-config path) both imported, the Force PlayMode test ends at X 4.9889 instead of 4.0333 and a combined run logs `this world already has a timeline library`; moving `Assets/EcsDemo` away makes it 4.0333 again. Test one sample per project.
- A Universal 3D (URP) project without the Editor UI: `<Editor>/Unity -batchmode -nographics -quit -createProject <dir> -cloneFromTemplate <Editor>/Data/Resources/PackageManager/ProjectTemplates/com.unity.template.urp-blank-*.tgz` (no CLI needed), or `unity projects create <name> --path <dir> --editor-version <v> --template com.unity.template.urp-blank --no-cloud` (`--template 3d` is "Unknown template" on 7000.0.0a16). `-createProject` alone makes a Built-in project, where Entities Graphics draws nothing from a SubScene. Import a package sample headless from an `-executeMethod`: `UnityEditor.PackageManager.UI.Sample.FindByPackage(id, null).First(s => s.displayName == ...).Import(Sample.ImportOptions.OverridePreviousImports)`, then compile again.
- A project whose `Packages/manifest.json` lists a package under `testables` also compiles and runs that package's own test assemblies in every `-runTests`; their generated types can collide with your scene's (e.g. a kind registered twice throws in a system, the run prints no result, exit 2 with 0 `error CS`). Read the XML `<test-suite type="Assembly">` names, and remove the package from `testables` for scene/demo runs.
- Linux shell quirk: `dotnet --list-sdks` can print nothing when `DOTNET_ROOT` points at an empty dir (e.g. a mise `dotnet-root`) while the SDK sits in `~/.dotnet`; export `DOTNET_ROOT=$HOME/.dotnet` and prepend it to `PATH`.
- Unity 7: the editor runs CoreCLR (NUnit XML `clr-version` 10.0.x) and `GC.GetAllocatedBytesForCurrentThread()` is exact, so `Assert.AreEqual(0, GC.GetAllocatedBytesForCurrentThread()-before)` reads 48 B even for allocation-free code (it boxes its arguments before the second read). Compute the delta into a local first, then assert: that reads 0 B.
- `[Licensing::Client] Error: HandshakeResponse` and `Failed to handshake to channel` appear in the Editor log of passing batch runs too (it then connects to its own licensing client). Judge by the NUnit XML counts and the exit code, not by those lines.

## 5. ECS and baking facts agents get wrong

- Every `SystemBase`/`ISystem` in every loaded assembly is **auto-created in the default world** unless `[DisableAutoCreation]`. A system that calls `GetSingleton<T>()` must `RequireForUpdate<T>()` in `OnCreate`, or it throws every frame once its query matches.
- Broad queries catch your entities too. To exclude an **enableable** component use `Absent` (`WithAbsent<T>()`); `None` also matches entities where it is present but disabled.
- Order your systems explicitly (`[UpdateInGroup]`, `[UpdateAfter]`); group membership is not order.
- Authoring `MonoBehaviour`s must live in a **runtime** assembly (Editor-assembly scripts cannot be added to GameObjects). `Baker<T>` needs a reference to `Unity.Entities.Hybrid`. Bakers may live in Editor assemblies.
- Unity's standard `.gitignore` line `**/Library/` also ignores a package folder named `Library` (for example `Runtime/Library/`); add `!/<path>/Library/` or new files never reach git.
- Folders ending in `~` (`Tools~`, `Samples~`, `Documentation~`) are **never compiled** by Unity.
- Baker has only the generic `SetComponentEnabled<T>`; for runtime `ComponentType`s set enable bits in a `[WorldSystemFilter(WorldSystemFilterFlags.BakingSystem)]` system, which also sees every baker's output (good for validation).
- `[BakingType]` components are stripped from the game world; runtime subscene entities have **no names** (`GetName` returns ""). Find entities by components, not names.
- Subscene loading is asynchronous. Baking in an EditMode test without scenes: reflect `Unity.Entities.BakingUtility.BakeGameObjects(world, roots, settings)` (internal; `BakingSettings(flags, blobAssetStore)`).
- On 7000.0.0a16 `Unity.Mathematics` (`float3` and the rest) ships in the engine (`Editor/Data/Managed/UnityEngine/UnityEngine.MathematicsModule.dll`), not as a package: code meant to also build in plain .NET cannot use it; give such libraries their own unmanaged math types.
- On Unity 7, core Entities types (`EntityArchetype`, `EntityQuery`) live in the engine. Their source is not in the package cache, so check the API by compiling.
- Inside a namespace like `Tl.Unity`, the name `Unity.X` binds to `Tl.Unity.X`. Write `global::Unity.Entities...` (source generators hit this too).
- Unity 7 analyzers want cleanup semantics on statics (UAL0010/UAL0013). With domain reload off, statics survive between Play sessions: reset or dispose them in `[RuntimeInitializeOnLoadMethod(SubsystemRegistration)]`, mark the type `[NoAutoStaticsCleanup]` under `#if UNITY_7000_0_OR_NEWER`, and silence the analyzers only for vendored pure-.NET code via its `csc.rsp` (`-nowarn:`).

- Entities 7.0.0 API gaps: `EntityManager` has no `GetComponentLookup`/`GetBufferLookup` (take them from `ref World.Unmanaged.ResolveSystemStateRef(handle)`); `ArchetypeChunk` has `GetEnableableBits` but no public setter (copy a mask per entity through `EnabledMask[i]`); an `IJobParallelForDefer` job struct must itself hold the deferred `NativeList` (as `AsDeferredJobArray()`) or it throws at schedule time.

- Source-generated `ScriptableObject`/`TrackAsset`/`PlayableAsset` types (7000.0.0a16) show in `TypeCache` and menus but save with `m_Script: {fileID: 0}` and load as `null` after restart. Keep the Unity object class in a real file and put generated data in a plain `[Serializable]` class behind `[SerializeReference]` (survives restart). A generated never-saved `TrackAsset` stub plus a `TrackEditor.OnCreate` that swaps it for the real track puts a per-type entry in the Timeline `+` menu. The stub must be a real `.cs` file named after its class (Timeline logs "appears to be invalid" and "No script asset" otherwise; a hint-name file per class from the generator does not help): details in `references/ecs-baking-gotchas.md`.
- An analyzer dll (label `RoslynAnalyzer`, no platforms) inside a runtime asmdef's folder runs on that assembly, every assembly referencing it and `Assembly-CSharp`; no marker asmdef needed. `csc.rsp` next to an asmdef can raise `-langversion` (Unity passes 9.0 first; records need an `IsExternalInit` polyfill). Editor code compiles against `unity-4.8-api` + `BCLExtensions/netstandard2.1` (has `System.Text.Json`, no `System.Runtime.Intrinsics`, no `System.Threading.Lock`); check vendored .NET code offline with Unity's `DotNetSdk` `csc` and the references from a `Library/Bee/artifacts/*/<asm>.rsp`. A missing namespace hides method-body errors, so recount after fixing it (Tl.Gen.Tlb: 13 became 24: `Utf8.IsValid`, `Rune`, `Stopwatch.GetElapsedTime`, `SHA256.HashData`, `Convert.ToHexString`, `CreateDelegate<T>`, `BitOperations`, `OperatingSystem`). 7000.0.0a16 does not define `NET`: guard .NET-only code with `#if NET`.
- Prove a baker's `DependsOn` headless: reflect `Unity.Scenes.EntityScenesPaths.GetSubSceneArtifactHash(sceneGuid, default, true, ImportMode.Synchronous)` before and after editing the dependency.

- Your own Roslyn generator can add `IComponentData` to a user's `partial struct` (plus a `TypeManagerV2` registration called from an ILPP): an `IJobChunk` with `ComponentTypeHandle<T>` and `SystemAPI.Query<RefRW<T>>` work in the same assembly, and `IJobEntity` works in a referencing assembly, all in Burst. An `IJobEntity` over that type in the same assembly fails `SGJE0010 ... is not supported` (Unity's generators never see another generator's output) (verified 7000.0.0a16, IAFahim/tl.unity#22).
- A UPM package folder can also be a .NET project: put `BaseIntermediateOutputPath` `obj~\` and `BaseOutputPath` `bin~\` in a `Directory.Build.props` (above the package folder) so Unity never imports build output; Unity ignores the `.csproj` for compiling but imports it as an asset (commit its `.meta`), and it does not read `<Nullable>`: add `-nullable:enable` to a `csc.rsp` next to the asmdef or every `?` warns CS8632.
- A plain-field `float3` (own struct, per-component operators) is bit-identical to `Unity.Mathematics.float3` and as fast in Burst over 100k entities (3.9 vs 3.8 ns/entity single-thread, 0.88 vs 0.85 parallel). One run right after a recompile was 4x slower for one job in every round and did not repeat: rerun before trusting a Burst micro-bench.

More baking, editor and benchmark gotchas: `references/ecs-baking-gotchas.md`.

- Live baking is testable headless: an EditMode `[UnityTest]` that calls `SubSceneUtility.EditScene(subScene)` then `yield return new EnterPlayMode()` gets a running default world; editing an asset through `SerializedObject` patches the runtime entity within 10-40 ms. The patch rewrites only components and buffers whose baked value changed (a rebaked buffer arrives whole, with your runtime-written fields reset); enable bits and components that bake the same keep their runtime values (verified 7000.0.0a16, IAFahim/tl.unity#22).
- `DefaultWorldInitialization.GetAllSystemTypeIndices(flags, bool)`: the bool is `requireExecuteAlways`; pass `true` and you get only a handful of systems. Use `type.GetCustomAttributes(typeof(UpdateInGroupAttribute), true)` to walk group ancestry; `AddSystemsToRootLevelSystemGroups` needs the parent groups (`SimulationSystemGroup`, `FixedStepSimulationSystemGroup`) in the list or it logs "group was not created".
- Timeline Edit-mode preview from a test: `director.time = t; director.Evaluate();` runs every track mixer's `ProcessFrame` in batch Edit mode. Write scene values only inside `AnimationMode.StartAnimationMode()`, register each property first with `AnimationMode.AddPropertyModification(binding, modification, true)` (what `TrackAsset.GatherProperties` + `driver.AddFromName` do in the window); `StopAnimationMode()` restores them and the scene stays clean.
- `Camera.Render()` in Edit mode does not draw the GameObjects of an open SubScene (Entities gives that scene a Scene-view-only culling mask; `Camera.overrideSceneMask` does not exist on 7000.0.0a16). For a picture, set `EditorSceneManager.SetSceneCullingMask(subScene, EditorSceneManager.DefaultSceneCullingMask)` around the render and put the old mask back.
- Tl (com.tl.unity, read from source on main 9328184): `TlClipData.TimelineOf(asset)` only works in the Editor (its resolver is set by editor code), so a runtime UI cannot turn a `TimelineAsset` into a `TlTimeline`; bake the refs and names into a SubScene buffer and let the UI send indices. Rewind (`TimelineStep.Forward`) and speed (time scale) apply to the whole world, there is no per-playback request for them, and a held (`Ended`) or paused playback does not move in either direction.
- A `MonoBehaviour` whose class name differs from its file name can still be added by a builder (`AddComponent<T>()`), but the saved scene points at no script: SubScene baking in the import worker logs `[Worker0] The referenced script is missing on <GameObject>` (a warning) and its baker never runs. One authoring class per file, named after it.
- A `MonoBehaviour` reading ECS data through `EntityQuery.GetSingleton<T>()` does not complete running jobs (`EntityManager.GetComponentData` does): call `query.CompleteDependency()` first, or PlayMode tests fail with "must call JobHandle.Complete() on LocalToWorldSystem...". A `RefRW` from `SystemAPI.GetSingletonRW` is invalid after `EntityManager.Instantiate`/`DestroyEntity` in the same `OnUpdate`: copy the value, change it, `SystemAPI.SetSingleton` after. `IJobEntity.ScheduleParallel(query)` throws unless the query has every component `Execute` takes (verified 7000.0.0a16).
- In an editor builder, a `TimelineAsset` made with `AssetDatabase.CreateAsset` earlier in the same method can read as `null` after `EditorSceneManager.NewScene(..., NewSceneMode.Single)` when a prefab was saved in between; assigning it then saves `m_PlayableAsset: {fileID: 0}` with no warning and the director bakes nothing. Reload every asset by path after `NewScene`, before wiring it into the scene (7000.0.0a16).
- See what a Roslyn source generator emitted in a Unity assembly: copy `Library/Bee/artifacts/<dag>/<Asm>.rsp`, drop its `-out:`/`-refout:`, add `-out:<tmp>/x.dll` and `-generatedfilesout:<tmp>`, and run `<Editor>/Data/DotNetSdk/dotnet.exe <Editor>/Data/DotNetSdk/sdk/<v>/Roslyn/bincore/csc.dll @x.rsp` from the project folder.
- Iterate on a package's `Samples~/<Name>` without copies: a directory junction (`mklink /J <scratch>/Assets/TlSamples/<Name> <checkout>/com.x/Samples~/<Name>`) compiles it like an imported sample; Unity writes `.meta` files and builder output (scenes) back into the checkout, so ignore the output folders in git.
- Tl zero-config (com.tl.unity, verified main be6d0b3): `Events<T>` raised in `OnClipStart` of an `ITlTrack` are never dispatched (IAFahim/tl.unity#25). A `[Pulse(typeof(K), On = ClipEvent.Start)]` into a `[TlKind(Accepts = KindEntries.Pulses, Mode = KindMode.Each)]` kind whose `Apply` fills a mailbox component works the same tick; game damage to another entity goes through `<Kind>Kind.Pulses(sender.Writer).To(entity, value)` with the sender from `TimelineKindTick.BeginPulses(chunkCount)` (query it with `EntityQueryOptions.IncludeSystems`), `Writer.Begin/End` per chunk in `IJobEntityChunkBeginEnd`, and `AddPulseWriter(handle)`; a target no timeline feeds needs the kind's buffers from its own baker (`<Kind>Kind.Types`, Active disabled). Every auto kind lists all auto-system columns, so Tl adds them all to any entity it reaches (IAFahim/tl.unity#26): keep a starting value in a component no kind writes.
- Tl (verified tl f731c1de, tl.unity 1a375ff): pair and marker keys hash the full type name (namespace, name, `+` for nested) without the assembly name, so `tlb library --assembly` against any dll with the same types gives the same bytes; two types with one full name in a bake or kind catalog fail with both assembly names. One `Tl.LibraryAssembler` (Tl.Core) writes every `game.tlib`, from per-timeline `LibraryPart`s and `Tl.Gen.Tlb.LibraryBake.KindPayload`. `Tl.Gen.Unity` skips any assembly that already contains a `TlUnity.*.g.cs` file (checked-in snapshots such as `Tests/Kinds/Generated`); regenerate those with `Tools~/Tl.Gen.Unity.Snapshot` (`dotnet <dll> Core Tests/Kinds <out> Tl.Unity.Kinds`; `KindTypes.g.cs` is the committed `Kinds.g.cs`).
- Run a package sample's own Editor/PlayMode tests (asmdef `defineConstraints: UNITY_INCLUDE_TESTS`) without `testables`: junction the sample into `Assets/`, drop `testables` from the manifest (the package's own test assemblies would register the same kind twice, `Kind 'ForceKind' is registered twice`) and set the define once with a scratch `-executeMethod` (`PlayerSettings.SetScriptingDefineSymbols(NamedBuildTarget.Standalone, "UNITY_INCLUDE_TESTS")`); delete the junction with `rmdir` (never `rm -r`) before switching back to a `testables` gate run. A cold project's first EditMode run can fail a "ran as Burst code" assertion (Burst not compiled yet): rerun before debugging (verified 7000.0.0a16).
- Tl preview/sim loops that stop at `playback.Tick >= target` mis-handle the end of a timeline: Tl hands over to the `Next` timeline in the step where `Tick + 1 >= Duration`, so Tick never reaches Duration, the new timeline's tick 0 is already applied in that step, and the loop runs on into it (Force Push at 3.0 s previewed x 0.89 instead of 4.0333). Stop when the playback's `Timeline` changes and keep the previous step's state (IAFahim/tl.unity b841389).
- A package sample whose asmdef references one of the package's test assemblies breaks compile (CS0246) when a user imports it without `testables`: the missing reference is dropped, the sample still compiles. Gate such samples with an extra `defineConstraints` symbol that only test projects set.

- Two assemblies whose generated code both declares `public static partial class` in one shared namespace (e.g. `Tl.Generated.TimelineJobs`) give `warning CS0436` in the one that references the other; make per-assembly generated helpers `internal` (verified 7000.0.0a16).
- The `unity.lock` directory can vanish while you work (another agent's cleanup removes it): check it still exists before a benchmark. A K bench that overlapped another Unity run read A 10.5 / B 2.4 ns; the same code with the lock held read 8.2 / 2.0, equal to the baseline.

## 6. Small tools that save hours

- `unity-cli exec` (if used) caches compiled payloads: keep each payload short and check the output is yours.
- Read `Packages/manifest.json` and asmdef references before guessing a type's assembly. If a guessed API fails to compile once, open the source or compile a probe; don't guess twice.

## 7. Live Editor (official CLI), condensed

- Connect: `unity --no-banner status --json`, then `unity --no-banner pipeline editors`. No package: `unity pipeline install --project-path <p>`, then the **window must be focused** before it connects (Linux: minutes of silence otherwise).
- Call: `unity --no-banner command --caller plugin --skill <skill> <group> <verb> --flag v`; discover with `unity command` and `unity command <group>`. Use `--result-only` for JSON.
- Recompiles drop the connection mid-call (`Invalid response format`, `No Pipeline instance`). Verify the effect, wait with `scripts/wait-ready.sh` (exit 2 = compile failure), retry only if it did not apply. Add packages one at a time.
- `script eval --code '...; return x;'` with fully qualified names; `script eval_file --file f.cs` for longer probes.
- Headless Editor to drive (verified): `unity pipeline install`, launch the editor with `-batchmode -nographics` and no `-quit`, then `unity command eval ... --project-path <p>`; commands in `references/headless-assets.md`.
- Simulate editor clicks without a window: against a resident `-batchmode` Editor, `unity command eval --project-path <p> --result-only "$(cat probe.cs)"` runs multi-statement C#; `Undo.IncrementCurrentGroup()` around a change then `Undo.PerformUndo()/PerformRedo()` reproduces Ctrl+Z/Ctrl+Y, and Timeline's internal `TrackExtensions.Duplicate` (reflection, args `track,null,null,null`) is Ctrl+D. Ready check is `unity status --json` (`state: ready`); this CLI has no `unity list`.
- Drag the Timeline playhead without a mouse: `TimelineEditor.GetWindow()`, reflect its internal `state` (`WindowState`), set `previewMode = true`, set `editSequence.time = t`, then call `Evaluate()` and `EvaluateImmediate()`; read `TimelineEditor.inspectedDirector.transform`. On Wayland (Hyprland) `hyprctl dispatch focuswindow address:<addr>` focuses the Editor so the Pipeline server loads, and `grim` captures it; there is no click tool without `ydotool`.
- Unity CLI beta 15 prints `unity editors --installed --json` rows under `data.items` (older builds: `data` was the list); scripts must accept both. A self-hosted runner on a public repo runs fork PRs on your machine: guard the job with `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` and set `PUT repos/<o>/<r>/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors`.
- Details and evidence: `references/corrections.md`.

## Done means

You ran it, you read the counts, the person's own walk works (open the scene, press Play, see it), nothing of yours is left in their scenes or disk, and you said plainly what you did not verify.
