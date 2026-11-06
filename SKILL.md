---
name: unity-dots
version: 4.0.0
description: |
  Unity DOTS/ECS work through the `unity-cli exec` / `unity-cli list` tool, with BovineLabs-style
  strict Data-Oriented Design and a 6-assembly layout. Inspect first, mutate second, verify before
  claiming success. For batch mode, test runs, disk hygiene and ECS/baking facts read
  skills/unity-cli-field-notes/SKILL.md first.
---

# unity-dots

## Rules that never bend

1. **Inspect before you mutate.** Before touching a scene object, report the active scene path, the root objects, and whether the target lives in the parent scene or in a referenced subscene asset. Reuse what exists; create only after absence is confirmed.
2. **Measure, don't assume.** Done = compile clean (`error CS` = 0) + the requested state read back directly (object at its path, component on it, entity query count > 0). A count of 0 is a failure, whatever the tests say.
3. **One fix per cycle.** One change, compile, verify. After two failures from quoting, escaping or context confusion, stop writing code and only inspect until you find the mistake.
4. **No guessed APIs.** Probe a type or namespace with a minimal compile-safe query. If a guess fails once, read the asmdef or the source.
5. **No helper scaffolding to dodge a failed query.** Simplify the query instead. Editor scripts, menu items and converters only when the person asked for permanent code. Remove anything temporary.
6. **Never delete scene or prefab content to silence an error.** Diagnose and report.
7. **Honest report**: inspected, changed, compile result, direct verification, what is still unverified.

## `unity-cli exec`

- Non-trivial C# (quotes, generics, lambdas, several statements) goes through stdin:
  `echo 'var s = UnityEditor.SceneManagement.EditorSceneManager.GetActiveScene(); return s.path;' | unity-cli exec`
- After editing `.cs`: `unity-cli editor refresh --compile` before Play mode or the next `exec`.
- After text-editing `.prefab/.unity/.asset/.mat`: `unity-cli reserialize <path>` at once.
- `exec` caches compiled payloads: keep each short, one concern, and check the output is yours.
- `unity-cli console` can return `[]` while `Logs/Editor.log` holds the errors. Read the log.

## SubScenes

- The parent-scene GameObject with `Unity.Scenes.SubScene` and the referenced `.unity` asset are two things. Verify the parent scene from the parent scene.
- Don't open the subscene asset with `OpenSceneMode.Single` unless editing it is the task. If it is: note the previous scene, edit, save, restore, re-verify from the parent.
- The type is `Unity.Scenes.SubScene` (not `Unity.Entities.SubScene`). Reuse the existing container; never add a second one.
- Manually created entities do not prove authoring + baker + subscene works. Only a query on the loaded world does.

## Traps that cost hours

- **Stale bakes**: force reimport (`ImportAsset(p, ForceUpdate | ForceSynchronousImport)`) touched assets, then confirm one baked component exists in the live world before trusting a play test.
- **Stale domain**: one compile error anywhere keeps old assemblies running. Prove new types with `Type.GetType`.
- **Ask the Editor, not the YAML**: inherited prefab components and variants are invisible in files. Cross-prefab references serialize to `{fileID: 0}` silently.
- **`SaveAsPrefabAsset`** can write a stale in-memory copy. Force-reimport first; afterwards diff the file and read the deletions.
- **Prefab overrides address base arrays by index**: deleting rows at the front of a base array rebinds every override after it. Array-size overrides hide appended rows.
- **Filter worlds by name** (`ServerWorld`, `ClientWorld`): flags also match the Editor's conversion worlds, which hold stale data.
- `EditorApplication.delayCall` never fires headless; registrars that rely on it need a direct call.
- Entities baked with `TransformUsageFlags.None` have no parent chain at runtime; resolve owners in the Baker from the authoring hierarchy.

## Code standards

- `OnUpdate` stays trivial; logic lives in stateless pure functions with tests.
- Zero allocation in hot paths, Burst and jobs, native collections only.
- Components are normalized pure data; utilities are stateless extensions; engine glue is never mixed with logic in one file.
- No comments: name and extract instead. Small single-purpose files. Constants for magic numbers.
- UI Toolkit for UI. No drive-by refactors.

## Six assemblies per feature

`Scripts.Data` (unmanaged components, no logic), `Scripts` (systems, pure functions), `Scripts.Authoring` (MonoBehaviours and Bakers, runtime assembly referencing `Unity.Entities.Hybrid`), `Scripts.Debug` (gizmos, dev diagnostics), `Scripts.Editor` (editor-only tools), `Scripts.Tests` (tests first). Templates: `ScriptStructure.md`. Change asmdef references one at a time and compile after each.
