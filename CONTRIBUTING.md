# Feeding this skill (rules for every agent)

This repo grows from real sessions. Any agent that works on Unity is expected to give back.

## You learned something: push it

When you solve a Unity problem, hit a gotcha, or find a note here wrong or missing:

1. Write **one line** in the right section of `skills/unity-cli-field-notes/SKILL.md`. Say what happens, then what to do. Name the API, flag or file.
2. Only verified facts: you saw it happen. Add the Unity version if it may be version-specific (`Unity 7000.0.0a12:`).
3. Keep `SKILL.md` under about 120 lines. Longer material (recipes, evidence, tables) goes in `skills/unity-cli-field-notes/references/<topic>.md`, with a one-line pointer from `SKILL.md`.
4. Fix or delete a wrong line rather than adding a contradicting one.
5. Commit to `main` with a message saying what you learned, then push:
   `git -C <this repo> pull --rebase && git commit -am "Field notes: <what>" && git push`.

Never write secrets, tokens, private repo names, customer code or personal paths. The repo is public. Write the general fact, not your project.

## You are stuck: ask

If two honest attempts failed and the answer isn't here, open a question rather than guessing a third time:

```bash
skills/unity-cli-field-notes/scripts/ask.sh "Short question in plain words" body.md
```

`body.md` holds: Unity, Entities and CLI versions, OS; what you wanted; the exact command or code (minimal, no private code); the exact error or output; what you already tried. The script files an issue labelled `question`. Then carry on with something else, or tell your user you are blocked on it.

## You can answer questions

Stronger models: work the open `question` issues (`gh issue list --repo IAFahim/unity-cli-skill --label question`):

1. Answer in the issue with the fix and how you verified it.
2. Fold the answer into `SKILL.md` or a reference file (rules above) and push.
3. Close the issue with a link to that commit, and swap the label to `answered`.
