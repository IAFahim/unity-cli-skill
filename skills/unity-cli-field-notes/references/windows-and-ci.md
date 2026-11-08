# Windows and CI notes

## Windows (verified on Unity 7, Windows 11)

- Run shell scripts through Git Bash (`& "C:\Program Files\Git\bin\bash.exe" script.sh`); `bash` is not on the PowerShell PATH. Convert paths with `cygpath -m` before giving them to Unity or a manifest `file:` entry.
- Git Bash with autocrlf gives CRLF working trees. Scripts still run; compare files with `diff --strip-trailing-cr`.
- The editor ships built-in Entities 7.0.0, Collections 7.0.0, Burst 2.0.0, test-framework 1.9.0 and performance 7.0.0; older manifest pins are overridden. Burst 2.0 turns some old patterns into errors (BC1064).
- `Baker.GetComponents<T>()` (array overload) throws "Unknown Type" for a `MonoBehaviour` not registered with the TypeManager; the `List<T>` overload works.
- A fresh project plus the first EditMode run takes a few minutes on a 6-core machine.
- `unity install latest` does not give Unity 7. Use `unity install 7`.

## Self-hosted runner

- A runner started from a desktop session has a minimal `PATH` (no `~/.local/bin`), so `unity` fails with exit 127. Resolve the CLI explicitly (env override, then `PATH`, then its install dir) and pass `--editor-path`.
- Never pin an editor version in a CI script. Use the newest installed editor, else run `unity install 7 --yes --accept-eula` first. The editor bundles Mono at `<Editor>/Data/MonoBleedingEdge/bin/mono`, which runs `dotnet build` netstandard2.1 dlls, so CI needs no system Mono.
- The runner reuses one workspace: the next queued job overwrites `-logFile` and results files while you read them. Compare timestamps to your job's, or `gh run download` the artifact of your exact run.
- `unity test <project> --editor-path <Editor/Unity> --mode EditMode --filter Class.Method --output /abs/r.xml -- -logFile /abs/l.log`: Unity exit 2 (tests failed) returns CLI exit 8; CLI exit 6 "Test run did not complete" means Unity exited 1 before results, so `grep 'error CS'` the log. With a warm `Library/`, `--filter` reruns one test in about a minute.
- Passing a complex quoted `bash -c "..."` through Windows PowerShell can split the arguments and run only the first command (e.g. only `mkdir lock`) with exit 0. Put chained Unity commands in a real `.sh` file and run `bash file.sh`; then check the XML and log exist. To wait for the shared lock: `until mkdir lock 2>/dev/null; do sleep 30; done` inside that file.
- Inline Python heredocs sent through an agent's Bash tool can turn `\0` or `\1` inside string literals into raw control bytes (git then shows the file as binary, a sed backreference becomes empty). Write such helper scripts to a file first and run them with arguments.
