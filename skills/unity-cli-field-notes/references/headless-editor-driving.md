# Driving editor windows, menus and Timeline from a headless Editor (verified, Linux, newest Unity 7, Unity CLI beta 15, pipeline 1.0.0)

How to rehearse what a person clicks, without a window, and the traps found doing it.

## Resident batchmode Editor

- Launch `Unity -batchmode -force-vulkan -projectPath <p> -logFile <log>` under the Unity lock (no `-quit`), with `com.unity.pipeline` in the manifest (`unity pipeline install --project-path <p>`). Graphics (no `-nographics`) is needed for offscreen previews (`PreviewRenderUtility`), which then render on Vulkan.
- Run C# with `unity command --project-path <p> --result-only --timeout 300 script eval --file probe.cs` (pipeline 1.0.0; the older `script eval_file` is gone). `using` lines are allowed at the top of the file; extension methods (`SetSourcePlayable`, `SetTime`) need their namespace imported. `--internals true` does not open a package's `internal` types (CS0122): use reflection.
- Recompile after editing a `file:` package: `script recompile`, then poll `script recompile_status` until `completed`/`up_to_date`.
- Stop it with an eval of `EditorApplication.delayCall += () => EditorApplication.Exit(0);`, then check the pid is gone.

## Clicks without a mouse

- `EditorApplication.ExecuteMenuItem("<Menu/Path>")` runs real `[MenuItem]`s in batchmode and returns false for a path that is not a `MenuItem`. Hierarchy right-click entries are `GenericMenu` items, not menu items: "New Sub Scene > From Selection" is internal `Unity.Scenes.Editor.SubSceneContextMenu.CreateSubSceneAndAddSelection(GameObject, InteractionMode)`; package code builds a SubScene with public API instead (`NewScene(Additive)`, `SaveScene`, `CloseScene`, `ImportAsset`, then `AddComponent<SubScene>()` with `SceneAsset` and `AutoLoadScene = true`).
- An `EditorWindow` opened by a menu item (`GetWindow`) exists in batchmode, and its `OnGUI` does run (state set inside `OnGUI` changed between evals). `Resources.FindObjectsOfTypeAll<MyWindow>()[0]` finds it. Give each button a named public handler and call those; keep state changes that matter (a finished job's message) in an `EditorApplication.update` handler, not only in `OnGUI`.
- `EditorUtility.DisplayDialog` returns at once in batchmode, so menu items that end in a dialog complete.
- The Timeline window opens through `ExecuteMenuItem("Window/Sequencing/Timeline")` and `TimelineEditor.inspectedAsset` is set when a director's object is selected, but `TimelineEditor.inspectedDirector` stays null: never rely on it alone to find the director (fall back to the one `PlayableDirector` in the open scenes whose `playableAsset` is the timeline).

## Play mode and what you can judge in it

- Projects from the 7000.0.0a16 URP template have Enter Play Mode Options on with domain and scene reload off (`EditorSettings.asset` `m_EnterPlayModeOptions: 3`), so `EditorApplication.isPlaying = true` from an eval, or `yield return new EnterPlayMode()` in an EditMode `[UnityTest]`, keeps statics and locals; SubScenes still bake and the ECS world runs.
- No renderer is visible in batchmode, so an `Animator` with the default culling of imported models (`CullUpdateTransforms`) advances its state but never moves bones. Set `cullingMode = AlwaysAnimate` on the object (Play-mode copy) before judging "it does not move".
- Batchmode frames are about 1 ms: sampling a looping clip between evals aliases. For deterministic values evaluate a manual `PlayableGraph` (`AnimationPlayableOutput` + `AnimationClipPlayable`, `SetTime`, `graph.Evaluate(0)`) or a copied `PlayableDirector` (`DirectorUpdateMode.Manual`, `RebuildGraph`, `time`, `Evaluate`) on a copy in `EditorSceneManager.NewPreviewScene()`; the open scene stays clean.

## Asset traps found while rehearsing

- A Humanoid `AnimationClip` built from code with default settings keeps vertical body motion as root motion (`keepOriginalPositionY = true`, `loopBlendPositionY = false`). Played by an Animator with `applyRootMotion = false` the body stays at the first frame's height, so a landing floats. Set `loopBlendPositionY = true` (Bake Into Pose, based upon Original) with `AnimationUtility.SetAnimationClipSettings`.
- `EditorUtility.CopySerialized(fresh, existing)` also copies `m_Name`: an existing asset takes the fresh object's empty name and every path built from `asset.name` loses it (files named `.anim`, and a dot-file `.fbx` Unity never imports). Set `fresh.name` first.
- `NewScene`/`OpenScene` in Single mode unloads unused assets: C# references to assets loaded before the swap become destroyed objects. Load them again by path after the swap.
- Timeline: `TimelineAsset.DeleteClip` recomputes the clip holds of the clips that are left (one clip alone gets infinite pre- and post-Hold). Clips created again with the same times leave the track's items hash unchanged, so the stale holds stay and that clip plays (held) under the others, summing humanoid body positions. Reuse clips in place and recompute after edits with internal `UnityEngine.Timeline.Extrapolation.CalculateExtrapolationTimes(track)` (reflection; Timeline 6.7.0). Check `clip.extrapolatedStart`/`extrapolatedDuration`.
- Copying asset files back over loaded ScriptableObjects (a backup restore) does not reload them, even with `AssetDatabase.ImportAsset(path, ForceUpdate)`: the loaded object keeps its old fields and a missing reference. Delete the folder with `AssetDatabase.DeleteAsset` first (destroys the loaded objects), copy the files with their `.meta` back (same GUIDs), touch them, `Refresh`, then import non-YAML files before `.asset`/`.playable` and scenes last.
- NUnit `Assert.IsNotNull(unityObject)` passes for a destroyed or missing Unity object (not C#-null). Assert `obj != null` with Unity's operator.
- Never wait on an `AsyncOperation` (`SceneManager.UnloadSceneAsync`, a load) with a loop inside a `finally` or any non-yielding code in a PlayMode `[UnityTest]`: the operation only advances between frames, so the loop spins forever and the batch run hangs until killed. Start the unload in `finally` and do not wait for it.

