# New PC setup (verified on Windows 11; Linux notes where they differ)

1. Install `git`, `gh` (`gh auth login`, account IAFahim) and the .NET 10 SDK (`dotnet --version` prints 10.x).
2. Clone this skill next to your other repos and keep it fresh: `git clone https://github.com/IAFahim/unity-cli-skill <GitHub root>/unity-cli-skill`. Here the root is `D:\GitHub`. Before any work run `git -C <GitHub root>/unity-cli-skill pull --ff-only` and read `skills/unity-cli-field-notes/SKILL.md`; before you finish, push what you learned to `main`.
3. Unity CLI: `irm https://unity.com/install.ps1 | iex` (Windows) or `curl -fsSL https://unity.com/install.sh | bash` (Linux). It lands in `%LOCALAPPDATA%\Unity\bin\unity.exe` or `~/.local/bin/unity`; open a new shell, then `unity --version`.
4. Editor: install the newest Unity 7 by name, never by version: `unity --no-banner install 7 --yes --accept-eula --module windows-il2cpp` (`linux-il2cpp` on Linux). `--dry-run` prints the plan. `install latest` does not give Unity 7: use `install 7`. Check with `unity --no-banner editors --installed --json` (it lists the install path).
5. Editors live in `C:\Program Files\Unity\Hub\Editor\<version>\Editor\Unity.exe` (Linux `~/Unity/Hub/Editor/<version>/Editor/Unity`). Scripts pick the newest installed one; set the `UNITY` env var only to force a specific binary.
6. tlb for the kinds capacity test: in a checkout of `IAFahim/tl` run `dotnet build tools/Tl.Bake -c Release`, then set `TL_TLB=<checkout>/tools/Tl.Bake/bin/Release/net10.0/Tl.Bake.dll`.
7. Submodules in a new worktree: `git submodule update --init --reference <main clone>/.git/modules/<path> <path>`, once per submodule, in the background.
8. One Unity process at a time: `New-Item -ItemType Directory D:\GitHub\_work\unity.lock` (or `mkdir`) fails when held; wait 30 s and retry; remove it when Unity exits.
9. Run `.sh` scripts on Windows with `& "C:\Program Files\Git\bin\bash.exe" script.sh`.
10. New Unity project with Tl in one command: `bash eng/tl-init.sh <path>` from IAFahim/tl.unity (or `curl -fsSL https://raw.githubusercontent.com/IAFahim/tl.unity/main/eng/tl-init.sh | bash -s -- <path>`); it finds or installs Unity 7, builds tlb, adds the package and `Assets/Game/Game.asmdef`, and compiles.
