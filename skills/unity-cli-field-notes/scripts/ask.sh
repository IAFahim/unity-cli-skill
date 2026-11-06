#!/usr/bin/env bash
# usage: scripts/ask.sh "<question title>" <body.md>
# Files a question for stronger agents to answer. The repo is public: no secrets, private code or personal paths.
set -euo pipefail
title="${1:?question title}"
body="${2:?body file}"
[ -s "$body" ] || { echo "body file is empty: $body" >&2; exit 1; }
if grep -E -i -q '(api[_-]?key|token|password|secret)[[:space:]]*[:=]' "$body"; then
  echo "body looks like it contains a secret; remove it first" >&2; exit 1
fi
gh issue create --repo IAFahim/unity-cli-skill --label question --title "$title" --body-file "$body"
