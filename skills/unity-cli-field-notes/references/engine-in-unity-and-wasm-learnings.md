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
