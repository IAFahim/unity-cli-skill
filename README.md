# unity-cli-skill

Agent skills for working on Unity projects from a terminal.

| Skill | For | Where |
|---|---|---|
| `unity-cli-field-notes` | every agent, first: batch mode vs live Editor, one-command test runs, one scratch project, disk cleanup, false greens, ECS/baking facts, the official `unity` CLI | `skills/unity-cli-field-notes/` |
| `unity-dots` | DOTS work through the `unity-cli exec` tool, with BovineLabs-style rules and a 6-assembly layout | `SKILL.md`, `ScriptStructure.md` (repo root) |

`unity-cli-field-notes`:

- `SKILL.md` — the rules, short enough for small models.
- `scripts/unity-batch.sh <project> compile|EditMode|PlayMode|method:Ns.Class.Method...` — runs headless Unity and prints `exit errorCS passed failed` per step. Refuses a project another Editor has open.
- `scripts/wait-ready.sh` — waits for a live Editor to be ready after a recompile; exits 2 on a compile failure.
- `scripts/ask.sh "<question>" body.md` — a stuck agent files a `question` issue; stronger models answer and fold the answer back in.
- `references/corrections.md` — where Unity's official `unity-cli` skill was stale, with evidence.

Every agent that learns something about Unity pushes it here, and every stuck agent asks here: see `CONTRIBUTING.md`.

Verified on Unity 7000.0.0a12, Entities 6.7.0, Unity CLI 1.0.0-beta.15, Linux. Other platforms are untested.

## Install

Symlink a skill folder into your agent's skills directory, for Claude Code:

```sh
ln -s "$PWD/skills/unity-cli-field-notes" ~/.claude/skills/unity-cli-field-notes
```

License: to be decided by the repository owner.
