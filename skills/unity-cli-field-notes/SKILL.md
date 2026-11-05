---
name: unity-cli-field-notes
description: Field-tested notes for driving a live, already-open Unity Editor from the Unity CLI (unity status / pipeline / command). Use alongside the official unity-cli skill when connecting to an Editor, adding the Pipeline package, waiting out domain reloads, setting up scenes and SubScenes, probing ECS worlds with script eval, or when a unity command fails with "No Pipeline instance" or "Invalid response format". Verified on Unity CLI 1.0.0-beta.15, com.unity.pipeline 0.10.0-exp.1 and 0.9.1-exp.1, Unity 7000.0.0a12, Linux.
---

# Unity CLI field notes

Companion to the official `unity-cli` skill, not a replacement. Everything here was observed on a real session; `references/corrections.md` lists where the official text was stale. Run `unity --version` first: names below are for 1.0.0-beta.15.

## Connect (in this order)

1. `unity --no-banner status --json` — `data.instances` empty means no reachable Pipeline server.
2. `unity --no-banner pipeline editors` — one row per Editor, with `hasPipelinePackage`, `serverReachable`, `safeMode`. There is no `pipeline list` in beta.15.
3. No package: `unity pipeline install --project-path <p>`. It only edits `Packages/manifest.json`.
4. **The Editor will not act on it until its window is focused.** An unfocused Editor stays idle for many minutes (log silent, `hasPipelinePackage=true`, `serverReachable=false`). Focus it (Hyprland: `hyprctl dispatch focuswindow address:<addr>`, found via `hyprctl clients -j` and the title `Unity - <project> - ...`; X11: `xdotool windowactivate`), then wait for state `ready`. Do not diagnose a crash or Safe Mode from the log alone — check `pgrep` and that the UPM server process is alive first.
5. Use `scripts/wait-ready.sh` for every wait. It polls `status` until `ready` and `script recompile_status` until `idle`/`completed`/`up_to_date` (`idle` is the steady state of a quiet Editor).

`isRunning=true` with an empty `pid` and no process in `pgrep` means the Editor is gone (closed by the user). Don't relaunch it unasked.

## Calling commands

Always `unity --no-banner command --caller plugin --skill <skill-name> <group> <verb> --flag value`.

- Names are `group verb`, dotted groups: `editor.playmode start`, `script eval`, `gameobject create_many`, `scene get_hierarchy`, `component set_field`, `package add`, `console get`, `capture game_view`. Discover with `unity command` (groups) then `unity command <group>` (verbs, flags). Use the dotted names: bare `editor_play` fails with a rename hint, and bare `eval` is an unlisted alias of `script eval`.
- Add `--result-only` (before or after `<group> <verb>`) to print only the result as JSON. Without it, output is a header plus a tab-separated row with the result in the third field: `... | tail -1 | python3 -c "import sys,json;print(json.loads(sys.stdin.read().split('\t')[2]))"`.
- Array flags take JSON: `--positions '[[-3,1,0],[-3,1,2]]'`. Object references take `--value '{"path":"Assets/Scenes/X.unity"}'`.
- Run `console clear` before a step you want to judge by error count.

## Domain reloads lie

Anything that recompiles (`package add --wait`, `script recompile`, editing a `.cs`) can drop the connection mid-call. Seen with `package add --wait`; three `script recompile` calls on a focused windowed Editor returned cleanly, so it is not every reload:

- Symptoms: `Invalid response format from Pipeline server`, or `No Pipeline instance found ... domain reload is in progress`, even though the operation worked.
- Do: verify the effect (`grep Packages/manifest.json`, `script recompile_status`), run `wait-ready.sh`, retry only if it did not apply.
- Add packages one at a time, waiting for ready between them. A second `package add` fired during the first's reload fails.
- After a failed compile `recompile_status` prints `completed, 1 error: <file>(line,col): error CSxxxx: ...`, so a loop that matches the first word as `completed` reports success on a broken build. Check `console status` -> `groundTruth.compilationFailed` instead, and read errors with `console get --tail 20 --level error`, deduped by message. `wait-ready.sh` exits 2 on a compile failure.

## Scenes and components

- `scene create --path X --additive true` makes the new scene active. It fails with `Cannot create a new scene additively with an untitled scene unsaved` when the open scene is the unsaved untitled default; `scene open --path X --additive true` an existing scene instead (it does not become active). `scene set_active` needs the scene already open. There is no scene close verb. New objects land in the active scene, so `scene set_active` back to the main scene before creating the host object. Read a non-active scene with `scene get_hierarchy --path X`. `scene save --path X` each scene you touched.
- `component add --target <instanceId> --type Ns.Type` works with namespaced types, but the type must already be compiled.
- `component add` serializes the compiled type's field defaults at add time. Changing a default in source afterwards does not update existing components; use `component set_field`.
- SubScene host: `component add --type Unity.Scenes.SubScene` then `set_field --field _SceneAsset --value '{"path":"..."}'`.
- Hand-editing `.unity` YAML worked once on an unfocused, clean Editor (it loaded without errors on focus). Treat that as luck; use the commands.

## Probing at runtime

`editor.playmode start`, wait 8–10 s (SubScene load and baking), then `script eval_file --file probe.cs` as many times as needed, then `editor.playmode stop`. `script eval --code '...'` is the inline form. Both need statement-terminated code ending in `return ...;` (a bare `1+1` fails with `; expected`) and fully qualified names (`using` lines fail). They see the project's own types and `Unity.Entities`, so an ECS probe is one file:

```csharp
var em = Unity.Entities.World.DefaultGameObjectInjectionWorld.EntityManager;
var q = em.CreateEntityQuery(typeof(MyData));
var a = q.ToComponentDataArray<MyData>(Unity.Collections.Allocator.Temp);
return "count=" + q.CalculateEntityCount() + " first=" + a[0].Value;
```

Compare against a closed-form expectation in the same eval and report the max error. `capture game_view --save_path Assets/<x>.png --width 960 --height 540` works in Play mode and the PNG can be read back. `--save_path` must be under the project root (delete the PNG and its `.meta` afterwards); without it the image comes back inline as base64.

## Entities Graphics note

After adding `com.unity.entities.graphics` 6.7.0 the console filled with `NullReferenceException` in `EntitiesGraphicsSystem.OnPerformCulling` (and earlier "Compute shader ... was not found!" assertions). Entities rendered correctly anyway. The compute shaders load fine once imported, so the stale object is the Editor-mode world created before they were. A forced reload did not clear it; an Editor restart is the untested remedy.

## A second Editor for verification

If no Pipeline connection is possible, a headless Editor on a **copy** of the project (`Assets`, `Packages`, `ProjectSettings`, no `Library`) runs while the live one holds the lock: `Unity -batchmode -nographics -projectPath <copy> -executeMethod X.Run -logFile log` with no `-quit`, ending in `EditorApplication.Exit(code)`. First import takes minutes. Say so when you do it; `.meta` files it generates can be copied back. Never point it at the live project path.
