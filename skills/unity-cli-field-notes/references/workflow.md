# Workflow detail for managers and agents

1. Finish locally first: implement, run the full local Unity tests (SKILL.md section 2), then push. CI is the last check, never the debugger. Do not work on CI or runner setup unless the owner asks.
2. Right-size the model. Strongest model: performance and benchmark analysis, diagnosing a failure of unknown cause, ECS/Burst/job design, any gate. Smaller model: porting scripts between OSes, CI wiring, adding tests, restacking branches, doc and skill updates. Never give the small one a gate to judge.
3. One brief per agent, no overlap. Each agent owns different files and its own worktree (`git worktree add <dir> origin/main --detach`). The brief starts with the rule to pull this skill repo, read it, and push what was learned back before finishing. It names the files the agent must not touch, the goal and "done" check, exact tools and paths on this machine, issue numbers to read, and the report format (short: numbers and commit hashes, no logs).
4. One Unity at a time per machine: take the lock directory before any Unity process, remove it when that process exits.
5. Look it up before asking or guessing: this skill and the linked issues first.
6. Reports: what works (commands), counts, commit hashes, what is not verified, what the owner must decide.
7. Pushes: direct pushes to `main` are authorized in IAFahim repos: `git pull --rebase origin main`, then `git push origin HEAD:main`, never `--force`. Elsewhere do not push, comment or merge unless asked.
