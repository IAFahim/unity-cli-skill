# Create assets and scenes through Unity, headless (verified, Windows 11, newest Unity 7)

Never write `.asset`, `.unity`, `.prefab`, `.mat` or `.meta` by hand. Both routes below ran with no window and produced correct files (a reference from one asset to another serialized with the target's guid, not `fileID: 0`). Take the Unity lock first.

## A. Batch `-executeMethod` (default; no extra package)

Put the ScriptableObject type in a runtime folder of the scratch project and the maker in `Assets/Editor` (never in the package). Delete both when done.

```csharp
using UnityEngine;
public class ProbeData : ScriptableObject { public int count; public ProbeData other; }
```

```csharp
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
public static class MakeProbe
{
    public static void Run()
    {
        if (!AssetDatabase.IsValidFolder("Assets/Generated")) AssetDatabase.CreateFolder("Assets", "Generated");
        var a = ScriptableObject.CreateInstance<ProbeData>();
        a.count = 7;
        AssetDatabase.CreateAsset(a, "Assets/Generated/A.asset");
        var b = ScriptableObject.CreateInstance<ProbeData>();
        b.other = a;
        AssetDatabase.CreateAsset(b, "Assets/Generated/B.asset");
        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        new GameObject("Probe");
        EditorSceneManager.SaveScene(scene, "Assets/Generated/Probe.unity");
        AssetDatabase.SaveAssets();
    }
}
```

```bash
"C:/Program Files/Unity/Hub/Editor/<newest>/Editor/Unity.exe" -batchmode -nographics -quit -projectPath D:/abs/scratch -executeMethod MakeProbe.Run -logFile D:/abs/make.log
grep -c 'error CS' D:/abs/make.log
```

Result: exit 0, 0 compile errors, `A.asset`, `B.asset`, `Probe.unity` and their `.meta` files exist. Prefabs: `PrefabUtility.SaveAsPrefabAsset(go, path)` in the same method.

## B. Unity CLI against a headless resident Editor

```bash
unity --no-banner pipeline install --project-path D:/abs/scratch
"<Editor>/Unity.exe" -batchmode -nographics -projectPath D:/abs/scratch -logFile D:/abs/resident.log &
unity --no-banner list --project-path D:/abs/scratch
unity --no-banner command eval 'var so = UnityEngine.ScriptableObject.CreateInstance<ProbeData>(); so.count = 9; UnityEditor.AssetDatabase.CreateAsset(so, "Assets/Generated/C.asset"); UnityEditor.AssetDatabase.SaveAssets(); return UnityEditor.AssetDatabase.AssetPathToGUID("Assets/Generated/C.asset");' --project-path D:/abs/scratch
unity --no-banner command eval 'var s = UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.DefaultGameObjects, UnityEditor.SceneManagement.NewSceneMode.Single); new UnityEngine.GameObject("ProbeC"); UnityEditor.SceneManagement.EditorSceneManager.SaveScene(s, "Assets/Generated/C.unity"); return s.path;' --project-path D:/abs/scratch
```

- No `-quit`, or the Editor exits after import. `pipeline install` adds `com.unity.pipeline` (0.10.0-exp.1) to `Packages/manifest.json` and exits 0; run it before the first open. A script that rewrites `manifest.json` (such as `eng/test-com-tl-unity.sh`) drops it: install again or add the dependency there.
- `unity list --project-path` answered about 20 s after launch on a warm project. `eval` returned `{"success":true,"result":...}` for the unity version (`7000.0.0a16`), the new asset's GUID and the scene path; both files existed afterwards, and project types (`ProbeData`) resolve by name.
- Stop the Editor by killing the process you started (`unity close <project>` reported `Closed false, method none` for a batch Editor, and `unity close` takes the project as an argument, not `--project-path`). Check no `Unity.exe` with your project path remains.
- Use A for repeatable generation in a script; use B when many small steps need each result read back.
