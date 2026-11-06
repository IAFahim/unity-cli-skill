# Baking and editor gotchas

- A baking system sees every entity on every incremental bake. Data that only the baking system should see per baker run belongs in `[TemporaryBakingType]`. Its query needs `IncludePrefab | IncludeDisabledEntities`, or prefabs and inactive GameObjects skip it.
- A baker that reads a file must `DependsOn(AssetDatabase.LoadAssetAtPath<Object>(path))`, or editing the file never rebakes.
- Generated system queries usually require every column of the system. Validate an entity against the query, not against what one feature uses.
- Change filters: `chunk.DidChange(ref handle, LastSystemVersion)`, checked before taking a read-write accessor (that marks the chunk changed). The system's own writes don't retrigger it.
- `World.All` includes the Editor's conversion, shadow and staging worlds. Skip `WorldFlags.Conversion | Shadow | Staging` in tools.
- Editor hooks: never call `AssetDatabase.Refresh` inside `OnPostprocessAllAssets`; defer with `EditorApplication.delayCall` (never fires in batch mode). `[InitializeOnLoad]` also runs in asset import workers, so guard with `AssetDatabase.IsAssetImportWorkerProcess()`.
- External processes from the Editor: use `ProcessStartInfo.ArgumentList`, read stderr asynchronously while reading stdout, and `WaitForExit(timeout)`.
- Benchmarks in batch mode: the first run in a fresh Editor is cold (2-3x slower). Run twice, take the later run or a median, and treat ±0.5 ns/entity as noise unless repeated.
- Editor Burst safety checks dominate idle-row benchmarks (1.9 ns with them, 1.3-1.4 without). A job with many type handles pays about 54 ns per chunk in safety checking, so keep rarely used handles out of it. Judge a Unity gate against the .NET number measured on the same machine that day.
- A disturbed run shows in the empty-world step time (13.9 µs against a normal 4.7-9.4): discard runs where it jumps.
- A .NET tool that reflects over a Unity-compiled dll needs its references next to it: copy `Library/ScriptAssemblies/*.dll` and `<Editor>/Data/Managed/UnityEngine/*.dll` into one folder with the dll.
- Test asmdefs compile against a netstandard profile: `MethodImplOptions.AggressiveOptimization` (CS0117) and `System.Runtime.JitInfo` (CS0234) are missing there. Use `(MethodImplOptions)512`, and reflect `JitInfo.GetCompiledMethodCount` off `typeof(object).Assembly`.
- `DOTNET_*` runtime knobs such as `DOTNET_TieredCompilation=0` reach the editor (JIT method counts change), so JIT experiments need no code change.
