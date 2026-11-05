# unity-cli-skill

Agent skills for driving Unity from a terminal.

| Skill | Tool it targets | Where |
|---|---|---|
| `unity-dots` | the `unity-cli exec` / `unity-cli list` tool, with BovineLabs DOTS rules | `SKILL.md`, `ScriptStructure.md` (repo root) |
| `unity-cli-field-notes` | Unity's official `unity` CLI (`unity status`, `unity pipeline`, `unity command`) and its Pipeline package | `skills/unity-cli-field-notes/` |

`unity-cli-field-notes` is a companion to Unity's own `unity-cli` skill, not a fork: it holds only observations from a real session and quotes none of the official text.

- `SKILL.md` — connect sequence, command shapes, domain-reload traps, scene/SubScene setup, ECS probing.
- `references/corrections.md` — where the official skill was stale, with evidence, plus dead ends and open questions.
- `scripts/wait-ready.sh` — wait for a ready Editor and a finished recompile; exits 2 on a compile failure.

Tested on Unity CLI 1.0.0-beta.15, `com.unity.pipeline` 0.10.0-exp.1 and 0.9.1-exp.1, Unity 7000.0.0a12, Linux (Hyprland). Other platforms are untested and flagged as such in the notes.

## Install

Copy or symlink a skill folder into your agent's skills directory, for Claude Code:

```sh
ln -s "$PWD/skills/unity-cli-field-notes" ~/.claude/skills/unity-cli-field-notes
```

License: to be decided by the repository owner.
