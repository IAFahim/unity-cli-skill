# Where the official unity-cli skill was stale or wrong

Compared against the Unity plugin `0.1.6-beta` skill `unity-cli` while running Unity CLI `1.0.0-beta.15` with `com.unity.pipeline 0.10.0-exp.1` on Linux. Each item says what was observed. Worth reporting upstream; none of it quotes the official text beyond command names.

| # | Official skill says | Observed | Evidence |
|---|---|---|---|
| 1 | Safe Mode recovery starts with `unity pipeline list` (and reads `data.summary.instancesInSafeMode`, `data.instances[].safeMode.detected`) | `unity pipeline list` fails: `unknown command 'list' (Did you mean unity pipeline editors?)`. Subcommands in beta.15: `install`, `upgrade`, `editors`, `list-versions`, `cloud-build`, `automation`. `pipeline editors` prints a `safeMode` column. | `unity pipeline --help` |
| 2 | Quick start runs `unity command editor_play` and `unity command eval --code ...` | Neither name is in the Editor's command listing. Real names: `editor.playmode start`, `script eval`. Groups are dotted and verbs are separate words. | `unity command` and `unity command <group>` listings |
| 3 | CLI "latest: 1.0.0-beta.9" | Installed CLI reports `1.0.0-beta.15`. | `unity --version` |
| 4 | After `unity pipeline install` the Editor connects | On an unfocused Linux Editor nothing happened for 10+ minutes (`hasPipelinePackage=true`, `serverReachable=false`, no log writes) until the window was focused. Not mentioned anywhere; easy to misread as a crash. | Editor log silent; `hyprctl dispatch focuswindow` then `status` -> `starting` -> `ready` |
| 5 | `package add ... --wait` "blocks until added" | When the add triggers a domain reload the call can fail with `Invalid response format from Pipeline server` although the manifest was updated. A second `package add` sent while the first reloads fails the same way. | manifest contained the package after the error |
| 6 | Poll `script recompile_status` until done | After a compile error it never returned `completed` (printed a value starting `c…`, truncated), so a poll loop runs to its timeout. `console status` -> `groundTruth.compilationFailed` is the direct signal and flips immediately. Exact status text on failure was not captured. | loop ended by timeout with `compilationFailed: true` and two `CS0214` errors |
| 7 | "Never hand-edit scene YAML while a live Editor is reachable" | Sound advice, but a scene object hand-written while the Editor was unfocused loaded cleanly once the Editor was focused. The failure the advice prevents is real; the claim that it always fails is not. | `scene get_hierarchy` listed the hand-added object, console clean |

## Things that were a waste of time (so nobody repeats them)

- Treating `*** stack smashing detected ***: terminated` in the Editor log as the cause of the stall. The UPM server was alive; the Editor was only unfocused.
- `unity connect` (no such command), `unity pipeline list`, bare `eval` / `editor_play`.
- Waiting on `package add --wait` to confirm success instead of checking the manifest.
- Polling `recompile_status` alone: on failure it never reaches `completed`, so the loop only times out.
- Setting a new default in a component's source and expecting already-added components to pick it up.

## Open questions (not verified here)

- Whether an Editor restart clears the Entities Graphics `OnPerformCulling` NRE spam after adding the package to a running Editor.
- Whether the focus requirement is Linux/Wayland-specific; not tested on macOS or Windows.
- Whether `pipeline editors` populates `safeMode` for a Safe Mode Editor (column exists, was empty for a healthy one).
